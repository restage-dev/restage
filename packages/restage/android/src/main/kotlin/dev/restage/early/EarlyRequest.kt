package dev.restage.early

import android.content.Context
import android.os.Process
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** One buffered startup request, sent from process start and handed to Dart once. */
object EarlyRequest {
    class Result(
        val status: Int,
        val body: ByteArray,
        val headers: Map<String, String>,
        val sentAtMicros: Long,
        val answeredAtMicros: Long,
    )

    private const val TAG = "RestageEarly"
    private const val BUILD_CONTRACT_REQUIRED = 409
    private val done = CountDownLatch(1)
    private val configured = CountDownLatch(1)
    @Volatile private var result: Result? = null
    @Volatile private var sent: ByteArray? = null
    @Volatile private var templateJson: String? = null
    @Volatile private var target: String? = null
    @Volatile private var sentAtMicros = 0L
    private var taken = false

    private fun since() = SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()

    fun start(context: Context) {
        Log.i(TAG, "start at ${since()} ms")
        Thread { run(context) }.apply { name = "restage-early"; start() }
    }

    private fun readTemplate(context: Context): EarlyTemplate? {
        val text = try {
            val file = lastFile(context)
            val last = if (file.exists()) file.readText() else null
            // A kept template describes the build that wrote it.
            if (last != null && JSONObject(last).optString("builtFor") == EarlyFacts.buildStamp(context)) {
                Log.i(TAG, "template from the last launch")
                last
            } else {
                val built = context.assets.open(ASSET).bufferedReader().readText()
                Log.i(TAG, "template from the build")
                built
            }
        } catch (e: Exception) {
            Log.i(TAG, "no template is built into this app: ${e.javaClass.simpleName}")
            return null
        }
        templateJson = text
        return EarlyTemplate.parse(text)
    }

    private fun run(context: Context) {
        try {
            EarlyFacts.registration(context)
            val template = readTemplate(context) ?: return
            val facts = EarlyFacts.read(context) +
                ("mountedSince" to EarlyFacts.mountedSince(context, template.authorization))
            val body = template.body(facts, full = false) ?: return
            sent = body
            target = template.url + "\n" + template.authorization
            configured.countDown()
            sentAtMicros = System.currentTimeMillis() * 1000
            var (status, bytes, headers) = post(template, body)
            if (status == BUILD_CONTRACT_REQUIRED) {
                val full = template.body(facts, full = true)
                if (full != null) {
                    Log.i(TAG, "contract required at ${since()} ms; resending in full")
                    val again = post(template, full)
                    status = again.first
                    bytes = again.second
                    headers = again.third
                }
            }
            Log.i(TAG, "answer at ${since()} ms status=$status bytes=${bytes.size} edge-timing=${headers["restage-edge-timing"]}")
            result = Result(status, bytes, headers, sentAtMicros, System.currentTimeMillis() * 1000)
        } catch (e: Exception) {
            Log.i(TAG, "failed at ${since()} ms: $e")
        } finally {
            configured.countDown()
            done.countDown()
        }
    }

    private fun post(template: EarlyTemplate, body: ByteArray): Triple<Int, ByteArray, Map<String, String>> {
        val phases = EarlyPhases()
        phases.resolve(URL(template.url).host)
        val connection = URL(template.url).openConnection() as HttpURLConnection
        (connection as? javax.net.ssl.HttpsURLConnection)?.let {
            it.sslSocketFactory = phases.factory(it.sslSocketFactory)
        }
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.connectTimeout = 8000
        connection.readTimeout = 8000
        connection.setRequestProperty("Authorization", template.authorization)
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setFixedLengthStreamingMode(body.size)
        Log.i(TAG, "send at ${since()} ms")
        connection.outputStream.use { it.write(body) }
        phases.wrote()
        val status = connection.responseCode
        phases.gotFirstByte()
        val bytes = (if (status < 400) connection.inputStream else connection.errorStream)?.use { it.readBytes() }
            ?: ByteArray(0)
        // Header names lowercased, repeated values joined, as an HTTP client reports them.
        val headers = connection.headerFields.filterKeys { it != null }
            .mapKeys { it.key.lowercase() }.mapValues { it.value.joinToString(", ") }
        phases.finished()
        Log.i(TAG, phases.line())
        return Triple(status, bytes, headers)
    }

    /** The buffered answer to exactly [request] sent to [url]; once. */
    @Synchronized
    fun take(request: ByteArray, url: String, authorization: String, timeoutMs: Long): Result? {
        if (taken) return null
        configured.await(timeoutMs, TimeUnit.MILLISECONDS)
        val early = sent ?: return null
        if (!request.contentEquals(early) || target != url + "\n" + authorization) {
            Log.i(TAG, "mismatch sent=${digest(early)}/${early.size} dart=${digest(request)}/${request.size} differing=${differingKeys(early, request)}")
            return null
        }
        taken = true
        done.await(timeoutMs, TimeUnit.MILLISECONDS)
        Log.i(TAG, "handed to Dart at ${since()} ms status=${result?.status}")
        return result
    }

    /**
     * The request the platform sent and its answer, whether or not it equals
     * Dart's: waits for the request to finish, and marks the answer taken.
     */
    @Synchronized
    fun inFlight(timeoutMs: Long): Pair<ByteArray, Result?>? {
        if (taken) return null
        configured.await(timeoutMs, TimeUnit.MILLISECONDS)
        val early = sent ?: return null
        taken = true
        done.await(timeoutMs, TimeUnit.MILLISECONDS)
        Log.i(TAG, "in flight taken at ${since()} ms status=${result?.status}")
        return early to result
    }

    /** The template text in use, for a debug comparison. */
    fun templateText(): String? {
        configured.await(2, TimeUnit.SECONDS)
        return templateJson
    }

    /** The request the platform sent, for a debug comparison. */
    fun sentBytes(): ByteArray? = sent

    /** Keeps Dart's startup template for the next launch. */
    fun remember(context: Context, template: String) {
        val file = lastFile(context)
        val temp = File(context.filesDir, "$LAST.tmp")
        temp.writeText(JSONObject(template).put("builtFor", EarlyFacts.buildStamp(context)).toString())
        temp.renameTo(file)
    }

    private fun lastFile(context: Context) = File(context.filesDir, LAST)

    // Names of the top-level members that differ, never their values.
    private fun differingKeys(sent: ByteArray, request: ByteArray): String = try {
        val a = JSONObject(String(sent, Charsets.UTF_8))
        val b = JSONObject(String(request, Charsets.UTF_8))
        (a.keys().asSequence() + b.keys().asSequence()).toSortedSet()
            .filter { a.opt(it)?.toString() != b.opt(it)?.toString() }
            .joinToString(",")
    } catch (e: Exception) {
        "unreadable"
    }

    private fun digest(bytes: ByteArray) =
        MessageDigest.getInstance("SHA-256").digest(bytes).take(6).joinToString("") { "%02x".format(it) }

    private const val ASSET = "restage_early.json"
    private const val LAST = "restage_early_last.json"
}
