package dev.restage.early

import android.util.Base64
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

/**
 * The startup request as data: canonical body strings with value tokens, plus the
 * facts native fills in. The Dart side writes the same format after each startup.
 */
class EarlyTemplate(private val json: JSONObject) {
    val url: String = json.getString("url")
    val authorization: String = json.getString("authorization")
    private val fills: Set<String> =
        json.optJSONArray("fills")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()

    fun body(facts: Map<String, Any?>, full: Boolean): ByteArray? {
        val text = json.optString(if (full) "fullBody" else "body", "").ifEmpty { return null }
        return fill(text, facts).toByteArray(Charsets.UTF_8)
    }

    private fun fill(text: String, facts: Map<String, Any?>): String {
        var out = text
        if (out.contains(CONTRACT) || out.contains(HASH)) {
            val ordinal = facts["appBuildOrdinal"]?.toString() ?: "null"
            val contract = (json.optString("contract").takeIf { it.isNotEmpty() } ?: "").replace(ORDINAL, ordinal)
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(("restage.placement-build-contract.v1\u0000" + contract).toByteArray(Charsets.UTF_8))
            out = out.replace(CONTRACT, contract)
                .replace(HASH, "sha256:" + digest.joinToString("") { "%02x".format(it) })
        }
        out = out.replace(METERING, (facts["meteringKey"] ?: "").toString())
            .replace(ANONYMOUS, (facts["analyticsAnonymousId"] ?: "").toString())
        if (out.contains(OFFSET)) out = out.replace(OFFSET, (facts["utcOffsetMinutes"] ?: 0).toString())
        out = out.replace(MOUNTED, (facts["mountedSince"] ?: "").toString())
        out = out.replace(NONCE, (facts["registrationNonce"] ?: "").toString())
            .replace(CREATED, (facts["registrationCreatedAtMicros"] ?: 0).toString())
        if (out.contains(BUILT_INS)) out = out.replace(BUILT_INS, carrier("builtIns", facts))
        if (out.contains(LIBRARIES)) out = out.replace(LIBRARIES, carrier("installedLibraries", facts))
        return out
    }

    private fun carrier(name: String, facts: Map<String, Any?>): String {
        val tree = json.optJSONObject(name) ?: JSONObject()
        for (key in fills) {
            if (key == "utcOffsetMinutes" || key == "buildOrdinal" || (key == "appVersion") != (name == "installedLibraries")) continue
            val value = facts[key]
            if (value == null) tree.remove(key) else tree.put(key, value)
        }
        val bytes = Canonical.encode(tree).toByteArray(Charsets.UTF_8)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    companion object {
        private const val ORDINAL = "@@buildOrdinal@@"
        private const val CONTRACT = "@@buildContract@@"
        private const val HASH = "@@appBuildContractHash@@"
        private const val METERING = "@@meteringKey@@"
        private const val ANONYMOUS = "@@analyticsAnonymousId@@"
        private const val MOUNTED = "@@mountedSince@@"
        private const val NONCE = "@@registrationNonce@@"
        private const val CREATED = "@@registrationCreatedAtMicros@@"
        private const val OFFSET = "@@utcOffsetMinutes@@"
        private const val BUILT_INS = "@@sdkBuiltIns@@"
        private const val LIBRARIES = "@@sdkInstalledLibraries@@"

        fun parse(text: String): EarlyTemplate? = try {
            EarlyTemplate(JSONObject(text))
        } catch (e: Exception) {
            null
        }
    }
}

/** Canonical JSON: keys sorted, no whitespace, integers only. */
object Canonical {
    fun encode(value: Any?): String = StringBuilder().also { write(it, value) }.toString()

    private fun write(out: StringBuilder, value: Any?) {
        when (value) {
            null, JSONObject.NULL -> out.append("null")
            is Boolean -> out.append(value)
            is Int, is Long -> out.append(value)
            is String -> string(out, value)
            is JSONArray -> {
                out.append('[')
                for (i in 0 until value.length()) {
                    if (i > 0) out.append(',')
                    write(out, value.get(i))
                }
                out.append(']')
            }
            is JSONObject -> {
                out.append('{')
                val keys = value.keys().asSequence().toList().sorted()
                keys.forEachIndexed { i, key ->
                    if (i > 0) out.append(',')
                    string(out, key)
                    out.append(':')
                    write(out, value.get(key))
                }
                out.append('}')
            }
            else -> throw IllegalArgumentException("unsupported ${value::class}")
        }
    }

    private fun string(out: StringBuilder, value: String) {
        out.append('"')
        for (c in value) {
            when {
                c == '"' -> out.append("\\\"")
                c == '\\' -> out.append("\\\\")
                c == '\b' -> out.append("\\b")
                c == '\t' -> out.append("\\t")
                c == '\n' -> out.append("\\n")
                c == '\u000C' -> out.append("\\f")
                c == '\r' -> out.append("\\r")
                c < ' ' -> out.append("\\u00").append(Integer.toHexString(c.code).padStart(2, '0'))
                else -> out.append(c)
            }
        }
        out.append('"')
    }
}
