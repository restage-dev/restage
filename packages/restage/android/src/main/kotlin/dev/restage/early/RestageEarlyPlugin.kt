package dev.restage.early

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class RestageEarlyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "restage/early_request").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val app = context ?: return result.success(null)
        when (call.method) {
            "take" -> {
                val request = call.argument<ByteArray>("request")
                val url = call.argument<String>("url")
                val authorization = call.argument<String>("authorization")
                if (request == null || url == null || authorization == null) return result.success(null)
                val timeout = (call.argument<Number>("timeoutMs") ?: 4000).toLong()
                executor.execute {
                    val early = EarlyRequest.take(request, url, authorization, timeout)
                    main.post { result.success(early?.let { mapOf("status" to it.status, "body" to it.body, "headers" to it.headers, "sentAtMicros" to it.sentAtMicros, "answeredAtMicros" to it.answeredAtMicros) }) }
                }
            }
            "inFlight" -> {
                val timeout = (call.argument<Number>("timeoutMs") ?: 20000).toLong()
                executor.execute {
                    val flight = EarlyRequest.inFlight(timeout)
                    main.post {
                        result.success(
                            flight?.let { (sent, early) ->
                                mapOf(
                                    "sent" to sent,
                                    "status" to early?.status,
                                    "body" to early?.body,
                                    "headers" to early?.headers,
                                    "sentAtMicros" to early?.sentAtMicros,
                                    "answeredAtMicros" to early?.answeredAtMicros,
                                )
                            }
                        )
                    }
                }
            }
            "remember" -> {
                val template = call.argument<String>("template") ?: return result.success(null)
                executor.execute {
                    runCatching { EarlyRequest.remember(app, template) }
                    main.post { result.success(null) }
                }
            }
            "invalidateStartup" -> executor.execute {
                val cleared = runCatching { EarlyRequest.invalidateStartup(app) }.isSuccess
                main.post {
                    if (cleared) result.success(null)
                    else result.error("storage", "Startup authority could not be cleared.", null)
                }
            }
            "setIdentity" -> {
                val metering = call.argument<String>("meteringKey")
                val anonymous = call.argument<String>("analyticsAnonymousId")
                if (metering == null || anonymous == null) return result.error("invalid", "Both ids are required.", null)
                executor.execute {
                    val stored = runCatching { EarlyFacts.setIdentity(app, metering, anonymous) }.getOrDefault(false)
                    main.post {
                        if (stored) result.success(null) else result.error("invalid", "Both ids must be UUIDs.", null)
                    }
                }
            }
            "setMountedSince" -> {
                val fragment = call.argument<String>("fragment") ?: ""
                val scope = call.argument<String>("scope") ?: ""
                executor.execute {
                    val stored = EarlyFacts.setMountedSince(app, scope, fragment)
                    main.post {
                        if (stored) result.success(null) else result.error("invalid", "Not a mounted-surface report.", null)
                    }
                }
            }
            "resetRegistration", "registration" -> executor.execute {
                runCatching {
                    if (call.method == "resetRegistration") EarlyFacts.resetRegistration(app)
                    else EarlyFacts.registration(app)
                }.fold(
                    onSuccess = { (nonce, created) ->
                        main.post { result.success(mapOf("registrationNonce" to nonce, "registrationCreatedAtMicros" to created)) }
                    },
                    onFailure = {
                        main.post { result.error("registration_unavailable", "Registration unavailable.", null) }
                    },
                )
            }
            "template" -> result.success(EarlyRequest.templateText())
            "sent" -> result.success(EarlyRequest.sentBytes())
            "facts" -> runCatching { EarlyFacts.read(app) }.fold(
                onSuccess = { result.success(it) },
                onFailure = { result.error("registration_unavailable", "Registration unavailable.", null) },
            )
            else -> result.notImplemented()
        }
    }
}
