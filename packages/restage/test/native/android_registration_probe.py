"""Run actual Android registration helper/channel code with JVM environment stubs."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
CACHE = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle'))) / 'caches/modules-2/files-2.1'

def jar(group, artifact, version):
    matches = list((CACHE / group / artifact / version).glob('*/*.jar'))
    if len(matches) != 1:
        raise RuntimeError(f'Missing cached compiler dependency: {artifact} {version}')
    return str(matches[0])

STUBS = {
    'Context.kt': '''package android.content
import java.io.File
class Context(val filesDir: File) {
    val packageManager = android.content.pm.PackageManager()
    val packageName = "test.app"
}
''',
    'PackageInfo.kt': '''package android.content.pm
class PackageInfo {
    val longVersionCode = 1L; val versionCode = 1
    val versionName = "1"; val lastUpdateTime = 1L
}
class PackageManager { fun getPackageInfo(name: String, flags: Int) = PackageInfo() }
''',
    'Resources.kt': '''package android.content.res
class Resources {
    val configuration = Configuration(); val displayMetrics = Metrics()
    companion object { fun getSystem() = Resources() }
}
class Configuration { val locales = Locales() }
class Locales { fun get(index: Int) = java.util.Locale.US }
class Metrics { val widthPixels = 100; val heightPixels = 100; val density = 1f }
''',
    'Os.kt': '''package android.os
object Build { object VERSION { const val SDK_INT = 34 } }
class Looper { companion object { fun getMainLooper() = Looper() } }
class Handler(looper: Looper) { fun post(action: () -> Unit): Boolean { action(); return true } }
''',
    'Base64.kt': '''package android.util
object Base64 {
    const val URL_SAFE = 1; const val NO_PADDING = 2; const val NO_WRAP = 4
    fun encodeToString(bytes: ByteArray, flags: Int) = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}
''',
    'FlutterPlugin.kt': '''package io.flutter.embedding.engine.plugins
interface FlutterPlugin {
    class FlutterPluginBinding(val applicationContext: android.content.Context, val binaryMessenger: Any = Any())
    fun onAttachedToEngine(binding: FlutterPluginBinding)
    fun onDetachedFromEngine(binding: FlutterPluginBinding)
}
''',
    'Channel.kt': '''package io.flutter.plugin.common
class MethodCall(val method: String) { fun <T> argument(name: String): T? = null }
class MethodChannel(messenger: Any, name: String) {
    interface MethodCallHandler { fun onMethodCall(call: MethodCall, result: Result) }
    interface Result {
        fun success(value: Any?); fun error(code: String, message: String?, details: Any?); fun notImplemented()
    }
    fun setMethodCallHandler(handler: MethodCallHandler?) {}
}
''',
    'EarlyRequest.kt': '''package dev.restage.early
import android.content.Context
object EarlyRequest {
    class Result(val status: Int, val body: ByteArray, val headers: Map<String, String>, val sentAtMicros: Long, val answeredAtMicros: Long)
    fun inFlight(timeout: Long): Pair<ByteArray, Result?>? = null
    fun remember(context: Context, template: String) {}
    fun saveChoice(context: Context, hosted: Boolean, analytics: Boolean?, measurement: Boolean) {}
    fun invalidateStartup(context: Context) {}
    fun templateText(): String? = null
    fun sentBytes(timeoutMs: Long): ByteArray? = null
}
''',
    'Probe.kt': '''package dev.restage.early
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.Provider
import java.security.SecureRandomSpi
import java.security.Security
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

class BrokenEntropy : SecureRandomSpi() {
    override fun engineSetSeed(seed: ByteArray) {}
    override fun engineNextBytes(bytes: ByteArray) { throw SecurityException("Entropy unavailable") }
    override fun engineGenerateSeed(count: Int): ByteArray = throw SecurityException("Entropy unavailable")
}
class EntropyProvider : Provider("RegistrationFailure", "1.0", "Test entropy failure") {
    init { put("SecureRandom.RegistrationFailure", BrokenEntropy::class.java.name) }
}
class Reply : MethodChannel.Result {
    val done = CountDownLatch(1)
    var calls = 0; var value: Any? = null; var code: String? = null; var message: String? = null; var details: Any? = null
    override fun success(value: Any?) { calls++; this.value = value; done.countDown() }
    override fun error(code: String, message: String?, details: Any?) {
        calls++; this.code = code; this.message = message; this.details = details; done.countDown()
    }
    override fun notImplemented() { error("unimplemented", null, null) }
}
fun main(args: Array<String>) {
    val name = args.single()
    val root = kotlin.io.path.createTempDirectory("registration-proof-").toFile()
    val context = Context(root)
    val plugin = RestageEarlyPlugin()
    val binding = FlutterPlugin.FlutterPluginBinding(context)
    plugin.onAttachedToEngine(binding)
    val executor = RestageEarlyPlugin::class.java.getDeclaredField("executor").apply { isAccessible = true }.get(plugin) as ExecutorService
    val registration = File(root, "restage_install_registration")
    val temp = File(root, "restage_install_registration.tmp")
    val metering = File(root, "restage_install_identity").apply { writeText("11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222") }
    fun call(method: String): Reply {
        val reply = Reply()
        plugin.onMethodCall(MethodCall(method), reply)
        check(reply.done.await(3, TimeUnit.SECONDS)) { "Registration channel did not complete its callback" }
        check(reply.calls == 1) { "Registration channel completed more than once" }
        return reply
    }
    try {
        if (name == "registration success is persisted and reset preserves metering") {
            val initial = call("registration")
            check(initial.code == null && initial.value is Map<*, *>)
            val initialMap = initial.value as Map<*, *>
            check(registration.readText() == "${initialMap["registrationNonce"]}:${initialMap["registrationCreatedAtMicros"]}")
            val reset = call("resetRegistration")
            check(reset.code == null && reset.value is Map<*, *>)
            val resetMap = reset.value as Map<*, *>
            check(resetMap["registrationNonce"] != initialMap["registrationNonce"])
            check(registration.readText() == "${resetMap["registrationNonce"]}:${resetMap["registrationCreatedAtMicros"]}")
        } else {
            val method = when {
                name.startsWith("facts ") -> "facts"
                name.startsWith("reset ") -> "resetRegistration"
                else -> "registration"
            }
            when {
                name.contains("thrown write") -> temp.mkdir()
                name.contains("false rename") || name.contains("false delete") -> {
                    registration.mkdir(); File(registration, "blocker").writeText("retain")
                }
                name.contains("entropy") -> Security.insertProviderAt(EntropyProvider(), 1)
                else -> error("Unknown named case")
            }
            val reply = call(method)
            check(reply.code == "registration_unavailable" && reply.message == "Registration unavailable." && reply.details == null && reply.value == null) {
                "Native registration failure did not return one coarse error"
            }
        }
        check(metering.readText() == "11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222") { "Registration changed metering identity" }
        println("PASS: $name")
    } finally {
        plugin.onDetachedFromEngine(binding)
        executor.shutdownNow()
        check(executor.awaitTermination(3, TimeUnit.SECONDS))
        Security.removeProvider("RegistrationFailure")
        check(root.deleteRecursively()) { "Probe filesystem cleanup failed" }
        println("CLEANUP: executor stopped; temporary files removed")
    }
}
''',
}

def main():
    output = Path(sys.argv[1]).resolve()
    operation = sys.argv[2]
    output.mkdir(parents=True, exist_ok=True)
    stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.21')
    annotations = jar('org.jetbrains', 'annotations', '13.0')
    compiler = [jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.21'), stdlib,
                jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.2.21'),
                jar('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
                jar('org.jetbrains.kotlin', 'kotlin-daemon-embeddable', '2.2.21'),
                jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'), annotations]
    native = ROOT / 'packages/restage/android/src/main/kotlin/dev/restage/early'
    sources = [native / 'EarlyFacts.kt', native / 'RestageEarlyPlugin.kt']
    if operation == 'compile':
        stubs = output / 'stubs'; stubs.mkdir(exist_ok=True)
        for name, body in STUBS.items(): (stubs / name).write_text(body)
        classes = output / 'classes'; classes.mkdir(exist_ok=True)
        command = ['java', '-cp', os.pathsep.join(compiler), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                   '-no-stdlib', '-no-reflect', '-nowarn', '-classpath', os.pathsep.join([stdlib, annotations]),
                   '-d', str(classes), *map(str, sources), *map(str, stubs.glob('*.kt'))]
        (output / 'source-sha256.json').write_text(json.dumps({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, indent=2)+'\n')
    else:
        command = ['java', '-cp', os.pathsep.join([str(output / 'classes'), stdlib]), 'dev.restage.early.ProbeKt', operation]
    print(repr(command), flush=True)
    raise SystemExit(subprocess.run(command).returncode)

if __name__ == '__main__': main()
