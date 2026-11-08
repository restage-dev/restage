import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:restage_shared/restage_shared.dart';

/// The startup request the platform sent at process start.
final class EarlyRequest {
  static const _channel = MethodChannel('restage/early_request');
  static var _attempts = 0;

  /// When the platform sent its request and when the answer completed, in
  /// microseconds since the epoch; set when a request was taken.
  static int? sentAtMicros;
  static int? answeredAtMicros;

  /// The response headers (lowercase names) of the answer taken last.
  static Map<String, String> responseHeaders = const {};

  /// Receives each startup template instead of the platform; a build step's hook.
  @visibleForTesting
  static Future<void> Function(
      Uri url, String apiKey, PlacementBatchRequestV1 request)? recorder;

  // Under `flutter test` there is no platform; a channel call would wait on
  // the test clock.
  static bool get _underTest {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } on Object {
      return false;
    }
  }

  static bool get _supported =>
      !kIsWeb &&
      !_underTest &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The platform's answer when it sent exactly [request] to [url]; once.
  static Future<http.StreamedResponse?> take(
    Uint8List request,
    Uri url,
    String apiKey, {
    PlacementBuildContractV1? contract,
  }) async {
    if (_attempts >= 3 || !_supported) return null;
    _attempts += 1;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('take', {
        'request': request,
        'url': url.toString(),
        'authorization': 'Bearer $apiKey',
        'timeoutMs': 20000,
      });
      if (result == null && kDebugMode) {
        await _reportMismatch(request, contract);
      }
      if (result == null || result['status'] != 200) return null;
      sentAtMicros = result['sentAtMicros'] as int?;
      answeredAtMicros = result['answeredAtMicros'] as int?;
      final body = result['body']! as Uint8List;
      final headers = {
        for (final entry
            in ((result['headers'] as Map<Object?, Object?>?) ?? const {})
                .entries)
          '${entry.key}': '${entry.value}',
      };
      responseHeaders = Map.unmodifiable(headers);
      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: body.length,
        headers: headers,
      );
    } on Object {
      return null;
    }
  }

  /// The request the platform sent and its answer, whether or not it equals
  /// Dart's; waits for the platform's request to finish and marks its answer
  /// taken, so only one request leaves the device. Null when the platform sent
  /// none (or it was taken already); [response] is null when it failed.
  /// Stands in for the platform's request in tests.
  @visibleForTesting
  static Future<({Uint8List sent, EarlyResponse? response})?> Function({
    int timeoutMs,
  })? debugInFlight;

  static Future<({Uint8List sent, EarlyResponse? response})?> inFlight({
    int timeoutMs = 20000,
  }) async {
    if (debugInFlight case final stand?) return stand(timeoutMs: timeoutMs);
    if (!_supported || _underTest) return null;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'inFlight',
        {'timeoutMs': timeoutMs},
      );
      if (result == null) return null;
      final sent = result['sent']! as Uint8List;
      final status = result['status'] as int?;
      final body = result['body'] as Uint8List?;
      if (status == null || body == null) return (sent: sent, response: null);
      final headers = {
        for (final entry
            in ((result['headers'] as Map<Object?, Object?>?) ?? const {})
                .entries)
          '${entry.key}': '${entry.value}',
      };
      responseHeaders = Map.unmodifiable(headers);
      sentAtMicros = result['sentAtMicros'] as int?;
      answeredAtMicros = result['answeredAtMicros'] as int?;
      return (
        sent: sent,
        response: EarlyResponse(status: status, body: body, headers: headers),
      );
    } on Object {
      return null;
    }
  }

  // In debug builds, a request the platform did not match says where they differ.
  static Future<void> _reportMismatch(
    Uint8List request,
    PlacementBuildContractV1? contract,
  ) async {
    try {
      final sent = await _channel.invokeMethod<Uint8List>('sent');
      if (sent == null) {
        debugPrint('[restage] No startup request is built into this app. The '
            'first request is sent from Dart. Set base_url and api_key on the '
            'restage_early_template builder and rebuild.');
        return;
      }
      final mine = jsonDecode(utf8.decode(request)) as Map<String, Object?>;
      final theirs = jsonDecode(utf8.decode(sent)) as Map<String, Object?>;
      // Only the launch's startup batch has a template to compare with.
      if (mine['mode'] != 'prefetch') return;
      final differing = [
        for (final key in {...mine.keys, ...theirs.keys})
          if (jsonEncode(mine[key]) != jsonEncode(theirs[key])) key,
      ];
      if (differing.isEmpty) return;
      for (final key in differing) {
        final a = mine[key];
        final b = theirs[key];
        if (a is String && b is String && key.startsWith('sdk')) {
          String decode(String v) =>
              utf8.decode(base64Url.decode(base64Url.normalize(v)));
          try {
            debugPrint(
                '[restage] $key\n  runtime: ${decode(a)}\n  built:   ${decode(b)}');
          } on Object {
            // Not a JSON carrier.
          }
        }
      }
      if (differing.contains('appBuildContractHash') && contract != null) {
        debugPrint(await _contractDifference(contract));
      }
      final message =
          'The startup request built into this app differs from the one the '
          'SDK built at runtime in: ${differing.join(', ')}. Rebuild with '
          '`dart run build_runner build`, and make sure the builder options '
          '(channel) and the catalog selection match Restage.configure.';
      debugPrint('[restage] $message');
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError(message),
        library: 'restage',
      ));
    } on Object catch (error) {
      debugPrint('[restage] early request check failed: $error');
    }
  }

  // Which parts of the build contract differ from the one built into the app.
  static Future<String> _contractDifference(
    PlacementBuildContractV1 contract,
  ) async {
    final text = await _channel.invokeMethod<String>('template');
    if (text == null) return '';
    final full =
        (jsonDecode(text) as Map<String, Object?>)['fullBody']! as String;
    final built = (jsonDecode(
      full.replaceAll(RegExp('@@[A-Za-z]+@@'), '0').replaceAll('"0"', '"0"'),
    ) as Map<String, Object?>)['buildContract']! as Map<String, Object?>;
    final runtime =
        jsonDecode(jsonEncode(contract.toJson())) as Map<String, Object?>;
    final lines = <String>['[restage] The build contract differs in:'];
    for (final key in {...built.keys, ...runtime.keys}) {
      if (jsonEncode(built[key]) == jsonEncode(runtime[key])) continue;
      if (key == 'installedCapability') {
        final b = built[key]! as Map<String, Object?>;
        final r = runtime[key]! as Map<String, Object?>;
        for (final part in {...b.keys, ...r.keys}) {
          if (jsonEncode(b[part]) == jsonEncode(r[part])) continue;
          if (part == 'vocabulary') {
            final bn = ((b[part] as Map?)?['widgetNames'] as List?)
                    ?.cast<String>()
                    .toSet() ??
                {};
            final rn = ((r[part] as Map?)?['widgetNames'] as List?)
                    ?.cast<String>()
                    .toSet() ??
                {};
            lines.add('  installedCapability.vocabulary: only built in '
                '${bn.difference(rn)}, only at runtime ${rn.difference(bn)}; icons '
                'built ${jsonEncode((b[part] as Map?)?['iconCodePoints']).length} '
                'runtime ${jsonEncode((r[part] as Map?)?['iconCodePoints']).length}');
          } else {
            lines.add(
                '  installedCapability.$part: built ${jsonEncode(b[part])} runtime ${jsonEncode(r[part])}');
          }
        }
      } else {
        lines.add(
            '  $key: built ${jsonEncode(built[key]).length} chars, runtime ${jsonEncode(runtime[key]).length} chars'
            '${key == 'platform' || key == 'buildOrdinal' ? ' (${built[key]} vs ${runtime[key]})' : ''}');
      }
    }
    return lines.join('\n');
  }

  /// In debug builds, says which of the service URL and key the startup
  /// request template was built for differs from what the app configures.
  static Future<void> debugCheckConfiguration(
    String baseUrl,
    String apiKey,
  ) async {
    if (!kDebugMode || !_supported || _underTest) return;
    try {
      final text = await _channel.invokeMethod<String>('template');
      if (text == null) {
        debugPrint(
          '[restage] No startup request is built into this app. The first '
          'request is sent from Dart. Set base_url and api_key on the '
          'restage_early_template builder and rebuild.',
        );
        return;
      }
      final template = jsonDecode(text) as Map<String, Object?>;
      final builtUrl = Uri.parse(template['url']! as String);
      final configured = Uri.parse(baseUrl);
      final problems = <String>[
        if (builtUrl.origin != configured.origin)
          'the service URL: built for ${builtUrl.origin}, configured '
              '${configured.origin}',
        if (template['authorization'] != 'Bearer $apiKey')
          'the api key: the api_key in build.yaml is not the apiKey passed to '
              'Restage.configure',
      ];
      if (problems.isEmpty) return;
      final message = 'The startup request built into this app differs from '
          'Restage.configure in ${problems.join('; ')}. Update the '
          'restage_codegen:restage_early_template options in build.yaml and '
          'rebuild. Until then the startup request is sent from Dart.';
      debugPrint('[restage] $message');
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError(message), library: 'restage'),
      );
    } on Object {
      // The check is a debug aid only.
    }
  }

  /// Keeps the startup request for the platform to send at the next launch.
  static Future<void> remember(
    Uri url,
    String apiKey,
    PlacementBatchRequestV1 request,
  ) async {
    if (request.mode != PlacementBatchModeV1.prefetch) return;
    if (recorder case final record?) return record(url, apiKey, request);
    if (!_supported) return;
    try {
      final template = startupTemplateJson(url, apiKey, request);
      if (template == null) return;
      await _channel.invokeMethod<void>('remember', {'template': template});
    } on Object {
      // The next launch sends from Dart.
    }
  }

  /// Gives the platform the report text it splices into its early request for
  /// the API key named by [scope]: `,"mountedSince":[...]`, or empty for none.
  static Future<void> setMountedSince(String scope, String fragment) async {
    if (!_supported || _underTest) return;
    try {
      await _channel.invokeMethod<void>('setMountedSince', {
        'scope': scope,
        'fragment': fragment,
      });
    } on Object {
      // The platform's request then reports nothing; Dart's carries it.
    }
  }

  /// A test's stand-in for the platform's identity rewrite.
  @visibleForTesting
  static Future<bool> Function(String meteringKey, String analyticsAnonymousId)?
      identitySetter;

  /// A test's acknowledgement of clearing native startup authority.
  @visibleForTesting
  static Future<bool> Function()? startupInvalidator;

  /// Whether native startup identity must participate in local erasure.
  static bool get hasBootstrapPlatform =>
      _supported || identitySetter != null || startupInvalidator != null;

  /// Disables the persisted startup request until fresh authority replaces it.
  static Future<bool> invalidateStartup() async {
    if (startupInvalidator case final invalidate?) return invalidate();
    if (!_supported) return true;
    try {
      await _channel.invokeMethod<void>('invalidateStartup');
      return true;
    } on Object {
      return false;
    }
  }

  /// Replaces the identity the platform fills into its early request, after
  /// the app reset its own. Both must be UUIDs; false when the platform
  /// refuses or is absent.
  static Future<bool> setIdentity({
    required String meteringKey,
    required String analyticsAnonymousId,
  }) async {
    if (identitySetter case final set?) {
      return set(meteringKey, analyticsAnonymousId);
    }
    if (!_supported || _underTest) return false;
    try {
      await _channel.invokeMethod<void>('setIdentity', {
        'meteringKey': meteringKey,
        'analyticsAnonymousId': analyticsAnonymousId,
      });
      return true;
    } on Object {
      return false;
    }
  }

  /// The platform's device facts, read at process start; null where it has none.
  static Future<Map<String, Object?>?> facts() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMapMethod<String, Object?>('facts');
    } on Object {
      return null;
    }
  }

  /// Replaces the install's registration identity with a new one, after the
  /// service refused the old one.
  static Future<({String nonce, int createdAtMicros})?> resetRegistration({
    bool propagateErrors = false,
  }) =>
      _registration('resetRegistration', propagateErrors: propagateErrors);

  /// The install's registration nonce and creation time, made by the platform
  /// before its first request and kept until a credential is confirmed.
  /// With [propagateErrors], native failure cannot acknowledge durable erasure.
  /// An unsupported platform still has no native identity.
  static Future<({String nonce, int createdAtMicros})?> registration({
    bool propagateErrors = false,
  }) =>
      _registration('registration', propagateErrors: propagateErrors);

  static Future<({String nonce, int createdAtMicros})?> _registration(
    String method, {
    required bool propagateErrors,
  }) async {
    if (!_supported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(method);
      if (result == null) {
        if (propagateErrors) {
          throw StateError('Native registration unavailable');
        }
        return null;
      }
      return (
        nonce: result['registrationNonce']! as String,
        createdAtMicros: result['registrationCreatedAtMicros']! as int,
      );
    } on Object {
      if (propagateErrors) rethrow;
      return null;
    }
  }
}

/// The answer to the platform's early request.
final class EarlyResponse {
  /// Creates the answer.
  const EarlyResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  /// The HTTP status.
  final int status;

  /// The response bytes.
  final Uint8List body;

  /// The response headers, with lowercase names.
  final Map<String, String> headers;
}
