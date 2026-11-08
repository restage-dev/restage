package dev.restage.early

import android.content.Context
import android.content.res.Resources
import android.os.Build
import android.util.Base64
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.SecureRandom
import java.util.TimeZone

/** Device facts native knows at process start, in the forms the Dart client sends. */
object EarlyFacts {
    fun read(context: Context): Map<String, Any?> {
        val locale = Resources.getSystem().configuration.locales.get(0)
        val metrics = Resources.getSystem().displayMetrics
        val shortest = minOf(metrics.widthPixels, metrics.heightPixels) / metrics.density
        val info = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "country" to twoLetter(locale.country)?.lowercase(),
            "language" to twoLetter(locale.language)?.lowercase(),
            "platform" to "android",
            "osVersion" to Build.VERSION.SDK_INT,
            "deviceClass" to if (shortest > 0) (if (shortest < 600) "phone" else "tablet") else null,
            "appBuildOrdinal" to info?.let { buildNumber(it) }?.takeIf { it in 0..MAX_PORTABLE },
            "appVersion" to info?.versionName?.trim()?.takeIf { validVersion(it) },
            "daysSinceInstall" to daysSinceInstall(context),
            "firstLaunchMicros" to firstLaunchMicros(context),
            "meteringKey" to identity(context).first,
            "analyticsAnonymousId" to identity(context).second,
            "registrationNonce" to registration(context).first,
            "registrationCreatedAtMicros" to registration(context).second,
            "utcOffsetMinutes" to TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60000,
        )
    }

    /** Names the installed build, so a template kept by an older one is not reused. */
    fun buildStamp(context: Context): String {
        val info = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (e: Exception) {
            null
        }
        return "${info?.let { buildNumber(it) }}:${info?.versionName}:${info?.lastUpdateTime}"
    }

    @Suppress("DEPRECATION")
    private fun buildNumber(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun twoLetter(value: String?): String? =
        value?.trim()?.takeIf { it.length == 2 && it.all { c -> c in 'a'..'z' || c in 'A'..'Z' } }

    private fun validVersion(v: String) =
        v.isNotEmpty() && v.length <= 64 && v.none { it.code < 0x20 || it.code == 0x7f }

    /** The install's registration identity: made once before the first request, kept in app storage. */
    @Synchronized
    fun registration(context: Context): Pair<String, Long> {
        val file = File(context.filesDir, "restage_install_registration")
        runCatching {
            val (nonce, created) = file.readText().trim().split(":")
            if (nonce.length == 43) return nonce to created.toLong()
        }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val nonce = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val created = System.currentTimeMillis() * 1000
        val temp = File(context.filesDir, "restage_install_registration.tmp")
        FileOutputStream(temp).use { output ->
            output.write("$nonce:$created".toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        if (!temp.renameTo(file)) throw IOException("Registration unavailable")
        return nonce to created
    }

    /** When the first launch happened, made once and kept in app storage. */
    @Synchronized
    fun firstLaunchMicros(context: Context): Long {
        val file = File(context.filesDir, "restage_first_launch")
        runCatching { return file.readText().trim().toLong() }
        val now = System.currentTimeMillis() * 1000
        file.writeText(now.toString())
        return now
    }

    /** Whole elapsed UTC days since the first launch. */
    fun daysSinceInstall(context: Context): Long =
        maxOf(0L, (System.currentTimeMillis() * 1000 - firstLaunchMicros(context)) / 86_400_000_000L)

    /** Starts a new registration identity, after the service refused the old one. */
    @Synchronized
    fun resetRegistration(context: Context): Pair<String, Long> {
        val file = File(context.filesDir, "restage_install_registration")
        if (file.exists() && !file.delete()) throw IOException("Registration unavailable")
        return registration(context)
    }

    /** Replaces the stored identity, after the app reset its own. Refuses anything but two UUIDs. */
    @Synchronized
    fun setIdentity(context: Context, metering: String, anonymous: String): Boolean {
        if (!UUID_FORM.matches(metering) || !UUID_FORM.matches(anonymous)) return false
        val file = File(context.filesDir, "restage_install_identity")
        val temp = File(context.filesDir, "restage_install_identity.tmp")
        temp.writeText("$metering:$anonymous")
        return temp.renameTo(file)
    }

    /** The metering key and anonymous id, made once at the first launch and kept in app storage. */
    @Synchronized
    fun identity(context: Context): Pair<String, String> {
        val file = File(context.filesDir, "restage_install_identity")
        runCatching {
            val (metering, anonymous) = file.readText().trim().split(":")
            if (metering.length == 36 && anonymous.length == 36) return metering to anonymous
        }
        val metering = java.util.UUID.randomUUID().toString()
        val anonymous = java.util.UUID.randomUUID().toString()
        val temp = File(context.filesDir, "restage_install_identity.tmp")
        temp.writeText("$metering:$anonymous")
        temp.renameTo(file)
        return metering to anonymous
    }

    /** Names the API key a report belongs to: the start of the key's SHA-256. */
    fun reportScope(authorization: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(authorization.removePrefix("Bearer ").toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }

    /**
     * The report text Dart keeps for the early request: empty, or `,"mountedSince":[...]`.
     * The file holds the key scope on its first line, and a report of another key is not sent.
     */
    @Synchronized
    fun mountedSince(context: Context, authorization: String): String {
        val text = runCatching { File(context.filesDir, "restage_mounted_since").readText() }.getOrDefault("")
        val scope = text.substringBefore('\n', "")
        val fragment = text.substringAfter('\n', "")
        return if (scope == reportScope(authorization) && fragment.startsWith(MOUNTED_PREFIX) && fragment.length <= MOUNTED_MAXIMUM) fragment else ""
    }

    /** Keeps the report text Dart gives for the key [scope]; anything but empty or a report fragment is dropped. */
    @Synchronized
    fun setMountedSince(context: Context, scope: String, fragment: String): Boolean {
        if (!SCOPE_FORM.matches(scope)) return false
        if (fragment.isNotEmpty() && (!fragment.startsWith(MOUNTED_PREFIX) || fragment.length > MOUNTED_MAXIMUM)) return false
        val temp = File(context.filesDir, "restage_mounted_since.tmp")
        temp.writeText("$scope\n$fragment")
        return temp.renameTo(File(context.filesDir, "restage_mounted_since"))
    }

    private const val MOUNTED_PREFIX = ",\"mountedSince\":["
    private const val MOUNTED_MAXIMUM = 32 * 1024

    private val SCOPE_FORM = Regex("[0-9a-f]{16}")

    private val UUID_FORM = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    private const val MAX_PORTABLE = 9007199254740991L
}
