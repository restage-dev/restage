package dev.restage.early

import android.content.Context
import android.os.Process
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
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
            if (last != null && JSONObject(last).optBoolean("disabled", false)) {
                // Startup authority is cleared; the build's text stays readable.
                templateJson = runCatching { context.assets.open(ASSET).bufferedReader().readText() }.getOrNull()
                return null
            }
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
            val template = readTemplate(context) ?: return
            val choice = readChoice(context)
            // An app last configured offline sends nothing.
            if (choice.hosted == false) return
            val analytics = choice.analytics ?: template.analyticsDefault
            // Either the build or the last launch turning measurement off is enough.
            val measurement = template.measurementDefault && choice.measurement != false
            val text = template.text(full = false, analytics = analytics, measurement = measurement) ?: return
            // The registration is made only for a request that carries it.
            if (text.contains(EarlyTemplate.NONCE)) EarlyFacts.registration(context)
            val facts = EarlyFacts.read(context) +
                ("mountedSince" to EarlyFacts.mountedSince(context, template.authorization))
            val body = template.body(text, facts)
            sent = body
            configured.countDown()
            sentAtMicros = System.currentTimeMillis() * 1000
            var (status, bytes, headers) = post(template, body)
            if (status == BUILD_CONTRACT_REQUIRED) {
                val full = template.text(full = true, analytics = analytics, measurement = measurement)
                    ?.let { template.body(it, facts) }
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

    /** The request the platform sent, once it is configured; null when it sent none. */
    fun sentBytes(timeoutMs: Long): ByteArray? {
        configured.await(timeoutMs, TimeUnit.MILLISECONDS)
        return sent
    }

    /** Keeps Dart's startup template for the next launch. */
    fun remember(context: Context, template: String) {
        val file = lastFile(context)
        val temp = File(context.filesDir, "$LAST.tmp")
        temp.writeText(JSONObject(template).put("builtFor", EarlyFacts.buildStamp(context)).toString())
        temp.renameTo(file)
    }

    /** Clears startup authority without falling back to a bundled template. */
    fun invalidateStartup(context: Context) {
        val file = lastFile(context)
        val temp = File(context.filesDir, "$LAST.invalidating")
        val data = JSONObject().put("builtFor", EarlyFacts.buildStamp(context))
            .put("disabled", true).toString().toByteArray(Charsets.UTF_8)
        FileOutputStream(temp).use { output ->
            output.write(data)
            output.fd.sync()
        }
        check(temp.renameTo(file)) { "Startup authority could not be cleared" }
        templateJson = null
    }

    /** What the app last configured; [analytics] is null when it left it to the build. */
    class Choice(val hosted: Boolean?, val analytics: Boolean?, val measurement: Boolean?)

    /** Keeps what the app configured, for the request at the next launch. */
    fun saveChoice(context: Context, hosted: Boolean, analytics: Boolean?, measurement: Boolean) {
        val file = File(context.filesDir, CHOICE)
        val temp = File(context.filesDir, "$CHOICE.tmp")
        val json = JSONObject().put("hosted", hosted).put("measurement", measurement)
        if (analytics != null) json.put("analytics", analytics)
        val data = json.toString()
        if (file.exists() && runCatching { file.readText() }.getOrNull() == data) return
        FileOutputStream(temp).use { output ->
            output.write(data.toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        check(temp.renameTo(file)) { "The choice could not be kept" }
    }

    // No file is no choice; a file that can't be read fails closed: no analytics.
    private fun readChoice(context: Context): Choice {
        val file = File(context.filesDir, CHOICE)
        if (!file.exists()) return Choice(null, null, null)
        return runCatching {
            val json = JSONObject(file.readText())
            fun flag(name: String) = if (json.has(name)) json.getBoolean(name) else null
            Choice(flag("hosted"), flag("analytics"), flag("measurement"))
        }.getOrElse { Choice(null, false, false) }
    }

    private fun lastFile(context: Context) = File(context.filesDir, LAST)

    private const val ASSET = "restage_early.json"
    private const val LAST = "restage_early_last.json"
    private const val CHOICE = "restage_early_choice.json"
}
