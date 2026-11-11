import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:restage_shared/restage_shared.dart';

/// The startup request the platform sent at process start.
final class EarlyRequest {
  static const _channel = MethodChannel('restage/early_request');

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

  /// Stands in for the request the platform sent, given the SDK's own, in
  /// tests.
  @visibleForTesting
  static Uint8List? Function(PlacementBatchRequestV1 mine)? debugSent;

  static var _consulted = false;

  /// Forgets that the platform was consulted, as a new process would.
  @internal
  static void debugForget() {
    _consulted = false;
    _defaults = (analytics: true, measurement: true);
  }

  /// The request the platform sent at launch, decoded, for the SDK's own
  /// startup request [mine] to judge; null when it sent none, the platform
  /// was consulted already, or the request went to another endpoint.
  static Future<PlacementBatchRequestV1?> sentRequest(
    PlacementBatchRequestV1 mine,
    Uri url,
    String apiKey,
  ) async {
    if (_consulted) return null;
    _consulted = true;
    final Uint8List? bytes;
    if (debugSent case final stand?) {
      bytes = stand(mine);
    } else {
      if (!_supported) return null;
      try {
        bytes = await _channel.invokeMethod<Uint8List>('sent');
      } on Object {
        return null;
      }
    }
    if (bytes == null) return null;
    try {
      final template = await _builtTemplate();
      final json = template == null
          ? null
          : jsonDecode(template) as Map<String, Object?>;
      // The platform sends the template's endpoint; another is not this one.
      if (json != null &&
          (json['url'] != url.toString() ||
              json['authorization'] != 'Bearer $apiKey')) {
        return null;
      }
      final built = _contract(json, mine.buildContract.buildOrdinal);
      return PlacementBatchRequestV1.fromCanonicalBytes(
        bytes,
        verifiedBuildContract: (hash) => hash == mine.appBuildContractHash
            ? mine.buildContract
            : built != null && built.appBuildContractHash == hash
                ? built
                : null,
      );
    } on Object {
      // A request the template cannot spell is for another build.
      debugReportUnadopted(StartupAnswerMismatch.build);
      return null;
    }
  }

  // The build contract the template spells, with the device's build ordinal.
  static PlacementBuildContractV1? _contract(
    Map<String, Object?>? template,
    int? ordinal,
  ) {
    if (template?['contract'] case final String text) {
      try {
        return PlacementBuildContractV1.fromCanonicalBytes(
          utf8.encode(text.replaceAll('@@buildOrdinal@@', '$ordinal')),
        );
      } on Object {
        return null;
      }
    }
    return null;
  }

  /// In debug builds, says why the platform's answer was not used.
  static void debugReportUnadopted(StartupAnswerMismatch reason) {
    if (!kDebugMode) return;
    final message = unadoptedStartupMessage(reason);
    debugPrint('[restage] $message');
    // A choice that changed this launch is followed from the next one.
    if (reason == StartupAnswerMismatch.analytics ||
        reason == StartupAnswerMismatch.assignment) {
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError(message), library: 'restage'),
    );
  }

  /// Stands in for the platform's built-in template in tests.
  @visibleForTesting
  static Future<String?> Function()? debugTemplate;

  // The built-in template text, or null; only on a platform that has one.
  static Future<String?> _builtTemplate() async {
    if (debugTemplate case final read?) return read();
    if (!_supported) return null;
    return _channel.invokeMethod<String>('template');
  }

  // `configure` usually runs before `runApp` creates the binding a channel
  // needs, so these calls wait for it, for up to [bindingWait].
  static Future<bool> _bindingReady() async {
    var waited = Duration.zero;
    while (!_bindingExists()) {
      if (waited >= bindingWait) return false;
      await Future<void>.delayed(_bindingPoll);
      waited += _bindingPoll;
    }
    return true;
  }

  static bool _bindingExists() {
    if (debugBindingExists case final exists?) return exists();
    try {
      ServicesBinding.instance;
      return true;
    } on Object {
      return false;
    }
  }

  /// Stands in for whether the binding exists yet, in tests.
  @visibleForTesting
  static bool Function()? debugBindingExists;

  /// How long a platform call waits for the binding before it is dropped.
  @visibleForTesting
  static const bindingWait = Duration(seconds: 10);
  static const _bindingPoll = Duration(milliseconds: 50);

  static bool get _canCheck =>
      kDebugMode && (debugTemplate != null || _supported);

  /// In debug builds, reports a first-launch request that is missing or built
  /// for a different service URL or key than [entry] was given.
  ///
  /// [fromBuild] is whether the key came from the app's generated setup;
  /// [declaresPlacements] whether the build has placements to request.
  static Future<void> debugCheckConfiguration(
    String baseUrl,
    String apiKey, {
    required String entry,
    required bool fromBuild,
    required bool Function() declaresPlacements,
  }) async {
    if (!_canCheck) return;
    if (debugTemplate == null && !await _bindingReady()) return;
    try {
      final text = await _builtTemplate();
      if (text == null) {
        // A build with no placements writes no request, and needs none.
        if (!declaresPlacements()) return;
        _reportConfiguration(
          fromBuild
              ? missingBuiltTemplateMessage(
                  ios: defaultTargetPlatform == TargetPlatform.iOS,
                )
              : kMissingEarlyTemplateMessage,
        );
        return;
      }
      final template = jsonDecode(text) as Map<String, Object?>;
      final message = earlyTemplateMismatchMessage(
        builtUrl: template['url']! as String,
        configuredUrl: placementResolveUrl(baseUrl).toString(),
        sameKey: template['authorization'] == 'Bearer $apiKey',
        entry: entry,
      );
      if (message != null) _reportConfiguration(message);
    } on Object {
      // The check is a debug aid only.
    }
  }

  /// In debug builds, reports a first-launch request built into an app whose
  /// [entry] call got no key, so hosted delivery is off. [registered] is
  /// whether the app passed its generated setup.
  static Future<void> debugCheckUnusedTemplate({
    required String entry,
    required bool registered,
  }) async {
    if (!_canCheck) return;
    if (debugTemplate == null && !await _bindingReady()) return;
    try {
      if (await _builtTemplate() != null) {
        _reportConfiguration(
          unusedEarlyTemplateMessage(entry: entry, registered: registered),
        );
      }
    } on Object {
      // The check is a debug aid only.
    }
  }

  static void _reportConfiguration(String message) {
    debugPrint('[restage] $message');
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError(message), library: 'restage'),
    );
  }

  /// Receives each saved choice instead of the platform, in tests.
  @visibleForTesting
  static void Function({
    required bool hosted,
    required bool? analytics,
    required bool measurement,
  })? choiceRecorder;

  static ({bool hosted, bool? analytics, bool measurement})? _pendingChoice;
  static Future<void>? _choiceWriter;

  /// Keeps what the app configured for the platform's request at the next
  /// launch: none when not [hosted], and no analytics id, registration or
  /// assignment when [analytics] is false. A null [analytics] leaves it to
  /// the build's default. Without [measurement], no registration or
  /// assignment. The last call wins.
  static Future<void> saveChoice({
    required bool hosted,
    bool? analytics,
    bool measurement = true,
  }) {
    _pendingChoice =
        (hosted: hosted, analytics: analytics, measurement: measurement);
    return _choiceWriter ??= _writeChoices();
  }

  // One writer sends the latest choice until none is pending, so an earlier
  // configure never lands after a later one.
  static Future<void> _writeChoices() async {
    try {
      if (!await _bindingReady() || (choiceRecorder == null && !_supported)) {
        _pendingChoice = null;
        return;
      }
      for (var choice = _pendingChoice;
          choice != null;
          choice = _pendingChoice) {
        _pendingChoice = null;
        if (choiceRecorder case final record?) {
          record(
            hosted: choice.hosted,
            analytics: choice.analytics,
            measurement: choice.measurement,
          );
          continue;
        }
        try {
          await _channel.invokeMethod<void>('saveChoice', {
            'hosted': choice.hosted,
            'analytics': choice.analytics,
            'measurement': choice.measurement,
          });
        } on Object {
          // The platform keeps the choice it saved last.
        }
      }
    } finally {
      _choiceWriter = null;
    }
  }

  static var _defaults = (analytics: true, measurement: true);

  /// The build's analytics default and the app's measurement setting, which a
  /// kept template carries for a launch with no saved choice.
  static void setStartupDefaults({
    required bool analytics,
    required bool measurement,
  }) =>
      _defaults = (analytics: analytics, measurement: measurement);

  /// The template [remember] keeps for [request].
  @visibleForTesting
  static String? rememberedTemplate(
    Uri url,
    String apiKey,
    PlacementBatchRequestV1 request,
  ) =>
      startupTemplateJson(
        url,
        apiKey,
        request,
        analytics: _defaults.analytics,
        measurement: _defaults.measurement,
      );

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
      final template = rememberedTemplate(url, apiKey, request);
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

/// The debug report when hosted delivery is configured but the build wrote no
/// first-launch request.
@visibleForTesting
const String kMissingEarlyTemplateMessage =
    'This app configures hosted delivery, but no first-launch request is built '
    'into it, so the first request waits for Dart to start. Try setting '
    'api_key and base_url for restage_codegen:user_factories in build.yaml '
    '(`restage init --sdk-key rs_pk_...` writes them), then run '
    '`dart run build_runner build` and rebuild the app.';

/// The debug report when the app's generated setup has a key but the app
/// bundle holds no first-launch request.
@visibleForTesting
String missingBuiltTemplateMessage({required bool ios}) =>
    "This app's generated setup has a publishable key, but no first-launch "
    'request is in the app bundle, so the first request waits for Dart to '
    'start. ${ios ? 'Try listing `ios/Runner/restage_early.json` under '
        '`flutter: assets:` in pubspec.yaml (`restage init` adds it), '
        'then rebuild the app.' : 'Try running '
        '`dart run build_runner build`, then rebuilding the app.'}';

/// The debug report when the build has a key but [entry] got none.
@visibleForTesting
String unusedEarlyTemplateMessage({
  required String entry,
  required bool registered,
}) =>
    registered
        ? 'This app has a first-launch request built in, but its generated setup '
            'has no publishable key, so hosted delivery is off. The request is '
            'from an earlier build. Try rebuilding the app after '
            '`dart run build_runner build`.'
        : 'This app has a first-launch request built in, but $entry got no '
            'publishable key, so hosted delivery is off. Try passing '
            '`registerWidgets: kRestageWidgetRegistration` to `$entry`.';

/// The debug report when the first-launch request was built for another
/// service URL or key than [entry] was given, or null when they match.
@visibleForTesting
String? earlyTemplateMismatchMessage({
  required String builtUrl,
  required String configuredUrl,
  required bool sameKey,
  required String entry,
}) {
  final differences = [
    if (builtUrl != configuredUrl)
      'URL (built for $builtUrl, configured $configuredUrl)',
    if (!sameKey) 'publishable key',
  ];
  if (differences.isEmpty) return null;
  return 'The first-launch request built into this app uses a different '
      '${differences.join(' and ')} than $entry, so the platform\'s request '
      'is discarded and the first request waits for Dart to start. Try '
      'passing `registerWidgets: kRestageWidgetRegistration` without apiKey '
      'and baseUrl, so $entry uses the ones in build.yaml, or setting the '
      'same values in build.yaml, then run `dart run build_runner build` and '
      'rebuild the app.';
}

/// The debug report when the platform's first-launch answer was not used.
@visibleForTesting
String unadoptedStartupMessage(StartupAnswerMismatch reason) =>
    switch (reason) {
      StartupAnswerMismatch.build =>
        "The first-launch request built into this app names other placements "
            "than the app declares, so its answer wasn't used and the first "
            "request waited for Dart to start. Try running "
            "`dart run build_runner build`, then rebuilding the app.",
      StartupAnswerMismatch.capability =>
        "The first-launch request built into this app claims widgets, icons "
            "or libraries the app doesn't install, so its answer wasn't used "
            "and the first request waited for Dart to start. Try keeping "
            "`includeMaterial` and `includeCupertino` at their defaults, or "
            "setting `catalog: derived` under restage_codegen:user_factories.",
      StartupAnswerMismatch.analytics =>
        "The first-launch request was sent with the analytics choice of an "
            "earlier launch, so its answer wasn't used. The next launch "
            "follows this one's choice. Try `analytics: false` under "
            "restage_codegen:user_factories for an app that starts with "
            "analytics off.",
      StartupAnswerMismatch.measurement =>
        "The first-launch request registers this install, but "
            "`measurementEnabled` is false, so its answer isn't used and the "
            "first request waits for Dart to start. Try running "
            "`dart run build_runner build` so the build reads "
            "`measurementEnabled: false`, then rebuilding the app.",
      StartupAnswerMismatch.assignment =>
        "The first-launch request carried another experiment assignment than "
            "this launch, so its answer wasn't used. The next launch's request "
            "follows this one.",
    };
