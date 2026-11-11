import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart'
    show PlacementBatchRefusalReasonV1;

import '../measurement/measurement_sdk_runtime_session.dart'
    show measurementReportedSdkVersion;
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/generated_surface_need.dart';
import 'delivery_input_budget.dart';

final Set<(String, PlacementBatchRefusalReasonV1, String?)> _logged = {};

const _docs = 'https://docs.restage.dev';
const _libraryDocs =
    '$_docs/authoring/custom-widgets#3-declare-exact-library-ownership';
const _catalogDocs =
    '$_docs/delivery/app-size#when-a-surface-uses-a-widget-you-dont-have';
const _fallbackDocs =
    '$_docs/delivery/hosted-delivery#when-a-version-cant-be-shown';
const _configDocs = '$_docs/delivery/hosted-delivery#configure-delivery';
const _hostingDocs =
    '$_docs/delivery/placements#present-a-placement-as-a-route';
const _flowModeDocs =
    '$_docs/flows/overview#what-you-can-change-without-an-app-release';
const _hostDataDocs =
    '$_docs/authoring/host-data#declare-the-data-as-constructor-parameters';
const _eventDocs = '$_docs/flows/overview#screens-and-events';
const _actionDocs = '$_docs/flows/host-actions#when-an-action-doesnt-match';

/// The published surface a fallback is about, as far as it is known.
@internal
final class PublishedSurfaceLabel {
  const PublishedSurfaceLabel({this.type, this.slug, this.version});

  /// The surface type, such as `message`.
  final String? type;

  /// The surface slug.
  final String? slug;

  /// The published version or screen revision.
  final int? version;

  PublishedSurfaceLabel _withVersion(int? version) => version == null
      ? this
      : PublishedSurfaceLabel(type: type, slug: slug, version: version);

  String get _phrase {
    final name = slug == null
        ? 'version'
        : '${type == null || type == 'general' ? '' : '$type '}`$slug`';
    return 'the published $name${version == null ? '' : ' r$version'}';
  }
}

/// Prints one debug-build line the first time [placement] falls back for
/// [reason]; release builds print nothing.
@internal
void debugLogPlacementFallback(
    PlacementKeyV1 placement, PlacementBatchRefusalReasonV1 reason,
    {String? detail, PublishedSurfaceLabel? published}) {
  if (!kDebugMode || !_logged.add((placement.value, reason, detail))) return;
  debugPrint('[restage] placement ${placement.value} shows its fallback '
      '(${placementFallbackReason(reason, detail)}): '
      '${_hint(reason, detail, published ?? const PublishedSurfaceLabel())}');
}

/// Why a placement request brought no decision.
@internal
sealed class PlacementNoAnswerCause {
  const PlacementNoAnswerCause();

  /// The cause of [error], thrown while the request to [endpoint] was in
  /// flight.
  factory PlacementNoAnswerCause.of(Object error, Uri endpoint) =>
      switch (error) {
        TimeoutException(:final duration) =>
          PlacementNoAnswerTimeout(duration, host: endpoint.host),
        http.ClientException() => PlacementNoAnswerUnreachable(
            endpoint.host, error,
            port: endpoint.port),
        _ => PlacementNoAnswerError(error, host: endpoint.host),
      };

  /// What happened, for a developer reading the debug log.
  String describe();
}

const _retried = "It's retried on the next mount.";

/// The service did not answer within [duration].
@internal
final class PlacementNoAnswerTimeout extends PlacementNoAnswerCause {
  const PlacementNoAnswerTimeout(this.duration, {this.host});
  final Duration? duration;
  final String? host;
  @override
  String describe() => '${_service(host)} didn\'t answer '
      '${duration == null ? 'in time' : 'within ${_seconds(duration!)}'}. '
      "Check the device's network and `baseUrl`. $_retried";
}

/// The device could not connect to [host].
@internal
final class PlacementNoAnswerUnreachable extends PlacementNoAnswerCause {
  const PlacementNoAnswerUnreachable(this.host, this.error, {this.port});
  final String host;
  final Object error;

  /// The port the request went to.
  final int? port;
  @override
  String describe() {
    final emulator = defaultTargetPlatform == TargetPlatform.android &&
            port != null &&
            const {'localhost', '127.0.0.1', '::1'}.contains(host)
        ? ' On Android, run `adb reverse tcp:$port tcp:$port` to let the '
            'device or emulator reach localhost on this computer.'
        : '';
    return "couldn't connect to $host (${_message(error)}). Check `baseUrl` "
        "and the device's network.$emulator $_retried See $_configDocs";
  }
}

/// The service answered with HTTP [status].
@internal
final class PlacementNoAnswerStatus extends PlacementNoAnswerCause {
  const PlacementNoAnswerStatus(this.status,
      {this.retryAfter, this.endpoint, this.location, this.error});
  final int status;

  /// The wait the service asked for in seconds, when it named one.
  final Duration? retryAfter;

  /// Where the request went.
  final Uri? endpoint;

  /// The `Location` header of a redirect.
  final String? location;

  /// The error code the answer's body named, if any.
  final String? error;

  @override
  String describe() {
    final service = _service(endpoint?.host);
    final code = error == null ? '' : ', `$error`';
    return switch (status) {
      429 => '$service is rate limiting this app (HTTP 429).'
          '${retryAfter == null ? '' : ' Retry after ${retryAfter!.inSeconds} s.'}',
      200 when error == 'want_not_met' => '$service answered before it had '
          'read the content a live update announced, so the shown content '
          'stays until the next update.',
      >= 300 && < 400 => _redirect(service),
      401 => '$service refused the API key (HTTP 401$code). Set `apiKey` to '
          'the public SDK key (rs_pk_...) for this environment. '
          'See $_configDocs',
      403 when error == 'edge_required' => '$service accepts SDK requests '
          'only at its public API address (HTTP 403$code). Set `baseUrl` to '
          "your environment's API URL. See $_configDocs",
      403 => '$service refused the request (HTTP 403$code). Check `baseUrl`, '
          'and any proxy, firewall or access policy in front of it. '
          'See $_configDocs',
      404 => '$service has no placement route at '
          '${endpoint == null ? _route : _bare(endpoint!)} (HTTP 404$code). Set '
          '`baseUrl` to the API URL alone, with no path. See $_configDocs',
      >= 400 && < 500 => '$service rejected the request (HTTP $status$code) '
          'without a placement answer. Check that the restage package '
          '($measurementReportedSdkVersion) and the service are current.',
      >= 500 => '$service returned a server error (HTTP $status$code). '
          '$_retried',
      _ => '$service answered HTTP $status instead of a placement decision. '
          '$_retried',
    };
  }

  String _redirect(String service) {
    Uri? target;
    try {
      target = location == null
          ? null
          : (endpoint?.resolve(location!) ?? Uri.parse(location!));
    } on FormatException {
      target = null;
    }
    final text = target == null ? null : _bare(target);
    final base = text != null && text.endsWith(_route)
        ? text.substring(0, text.length - _route.length)
        : null;
    return '$service redirected the request (HTTP $status'
        '${text == null ? '' : ' to $text'}), and the SDK doesn\'t follow '
        'redirects. '
        '${base == null ? 'Set `baseUrl` to the address it redirects to.' : 'Set `baseUrl` to $base.'}'
        ' See $_configDocs';
  }
}

/// The answer arrived, but this build cannot render it.
@internal
final class PlacementNoAnswerUnrenderable extends PlacementNoAnswerCause {
  const PlacementNoAnswerUnrenderable(this.tokens,
      {this.published = const PublishedSurfaceLabel()});

  /// Fit failure tokens, as the service names them.
  final List<String> tokens;

  /// The delivered surface.
  final PublishedSurfaceLabel published;
  @override
  String describe() => tokens.isEmpty
      ? "this mount couldn't use ${published._phrase}. $_retried"
      : describeFitTokens(tokens, published: published);
}

/// The answer needs what only the paywall's generated widget provides.
@internal
final class PlacementNoAnswerNeedsGeneratedSurface
    extends PlacementNoAnswerCause {
  const PlacementNoAnswerNeedsGeneratedSurface(this.paywallId);

  /// The paywall the mount shows.
  final String paywallId;
  @override
  String describe() => generatedSurfaceRequiredMessage(paywallId);
}

/// The answer could not be read.
@internal
final class PlacementNoAnswerUndecodable extends PlacementNoAnswerCause {
  const PlacementNoAnswerUndecodable([this.error]);
  final Object? error;
  @override
  String describe() => "the delivered content couldn't be read by restage "
      '$measurementReportedSdkVersion'
      '${error == null ? '' : ' (${_message(error!)})'}. '
      'Update the restage package, and check that the service is current.';
}

/// The delivered version's content could not be fetched or verified.
@internal
final class PlacementNoAnswerContentUnavailable extends PlacementNoAnswerCause {
  const PlacementNoAnswerContentUnavailable();
  @override
  String describe() =>
      "the delivered version's content couldn't be downloaded or verified. "
      '$_retried';
}

/// What changed while a request was in flight.
@internal
enum PlacementStaleChange {
  /// The installed widgets or libraries.
  installedWidgets,

  /// The configuration, identity or consent the request was made under.
  configuration,

  /// A built-in device fact the decision was routed on.
  deviceFacts,

  /// The time zone a delivered version's local time window is set in.
  timeZone,

  /// The delivered version's lifetime or local time window ended.
  expired,

  /// The delivered version's local time window has not started.
  notYetStarted,

  /// The device clock moved back past the request.
  clockMovedBack,

  /// The service no longer holds the device's experiment registration.
  registrationRetired,
}

/// The request's inputs changed before its answer could be used. It was
/// dropped.
@internal
final class PlacementNoAnswerStale extends PlacementNoAnswerCause {
  const PlacementNoAnswerStale(this.change, {this.facts = const []});
  final PlacementStaleChange change;

  /// The built-in facts that changed, by wire name, for
  /// [PlacementStaleChange.deviceFacts].
  final List<String> facts;
  @override
  String describe() => switch (change) {
        PlacementStaleChange.installedWidgets =>
          'a widget library was registered while the request was being made. '
              'The request was dropped. Register libraries before the first '
              'mount. $_retried',
        PlacementStaleChange.deviceFacts =>
          "the device's ${_factNames(facts)} changed after this decision was "
              "made. The decision wasn't shown. $_retried",
        PlacementStaleChange.timeZone =>
          "the device's time zone changed after the request was sent. The "
              "delivered version's time window is set in the old time zone. "
              'The answer was dropped. $_retried',
        PlacementStaleChange.expired =>
          "the delivered version's time window or experiment assignment ended "
              'before it could be shown. The answer was dropped. $_retried',
        PlacementStaleChange.notYetStarted =>
          "the delivered version's time window hasn't started by this "
              "device's clock. The answer was dropped. $_retried",
        PlacementStaleChange.clockMovedBack =>
          'the device clock moved back while the request was in flight. The '
              'answer was dropped. $_retried',
        PlacementStaleChange.registrationRetired =>
          "the service no longer holds this device's experiment "
              'registration. The answer was dropped. The next mount registers '
              'this device again.',
        PlacementStaleChange.configuration =>
          "Restage's configuration, user identity or consent changed while "
              'the request was being made. The request was dropped. $_retried',
      };
}

const _factLabels = {
  'appBuildOrdinal': 'app build',
  'channel': 'channel',
  'country': 'country',
  'daysSinceInstall': 'install age',
  'deviceClass': 'device class',
  'language': 'language',
  'osVersion': 'OS version',
  'platform': 'platform',
  'sdkApiLevel': 'SDK level',
};

String _factNames(List<String> facts) {
  final names = [for (final fact in facts) _factLabels[fact] ?? fact];
  if (names.isEmpty) return 'facts';
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// This device's experiment registration was not ready. The request was not
/// sent.
@internal
final class PlacementNoAnswerUnregistered extends PlacementNoAnswerCause {
  const PlacementNoAnswerUnregistered({this.late = false});

  /// Whether the registration was still being saved at the input deadline.
  final bool late;
  @override
  String describe() => late
      ? "this device's experiment registration wasn't saved within "
          '${_seconds(DeliveryInputBudget.defaultTotal)}. The request wasn\'t '
          'sent. Restage saves the registration with shared_preferences. '
          'Check that it answers quickly on this device. $_retried'
      : "this device's experiment registration couldn't be saved. The request "
          "wasn't sent. Restage saves the registration with shared_preferences. "
          'Check that the plugin works in this app. In tests, call '
          '`SharedPreferences.setMockInitialValues({})`. $_retried';
}

/// Any other failure.
@internal
final class PlacementNoAnswerError extends PlacementNoAnswerCause {
  const PlacementNoAnswerError(this.error, {this.host});
  final Object error;
  final String? host;
  @override
  String describe() => 'the request${host == null ? '' : ' to $host'} failed '
      '(${_message(error)}). $_retried';
}

const _route = '/sdk/v1/placements/resolve';

/// [uri] without credentials, query or fragment.
String _bare(Uri uri) => Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path)
    .toString();

String _service(String? host) =>
    host == null || host.isEmpty ? 'the service' : 'the service at $host';

String _seconds(Duration duration) => duration.inMilliseconds % 1000 == 0
    ? '${duration.inSeconds} s'
    : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';

String _message(Object error) => switch (error) {
      http.ClientException(:final message) => message,
      FormatException(:final message) => message,
      _ => '$error',
    };

final Set<(String, String)> _loggedNoAnswers = {};

/// Prints one debug-build line the first time [placement] gets no answer for
/// [reason]; release builds print nothing.
@internal
void debugLogPlacementNoAnswer(PlacementKeyV1 placement, String reason,
    [PlacementNoAnswerCause? cause]) {
  if (!kDebugMode || !_loggedNoAnswers.add((placement.value, reason))) return;
  if (cause is PlacementNoAnswerNeedsGeneratedSurface) {
    debugPrint('[restage] ${cause.describe()}');
    return;
  }
  final refusal = PlacementBatchRefusalReasonV1.values.asNameMap()[reason];
  final sentence = cause?.describe() ??
      (refusal == null
          ? 'no answer from the service.'
          : _hint(refusal, null, const PublishedSurfaceLabel()));
  debugPrint('[restage] placement ${placement.value} shows its fallback '
      '($reason): $sentence');
}

/// How long the service may refuse the API key before it is reported. A key
/// minted moments ago is refused until the service has published it.
const Duration kRefusedApiKeyGrace = Duration(minutes: 1);

/// The clock the refused-key report reads.
@internal
DateTime Function() refusedApiKeyClock = DateTime.now;

bool _loggedRefusedKey = false;
DateTime? _keyRefusedSince;

/// Notes that the service refused the API key. Once refusals have lasted
/// [kRefusedApiKeyGrace], prints one line in every build mode: a wrong key is
/// a configuration error, not a passing failure.
@internal
void noteRefusedApiKey(Uri endpoint) {
  final now = refusedApiKeyClock();
  final since = _keyRefusedSince ??= now;
  if (_loggedRefusedKey || now.difference(since) < kRefusedApiKeyGrace) return;
  _loggedRefusedKey = true;
  debugPrint(
      '[restage] ${PlacementNoAnswerStatus(401, endpoint: endpoint).describe()}');
}

/// Notes that the service accepted the API key, ending any refusal.
@internal
void noteAcceptedApiKey() {
  _keyRefusedSince = null;
  _acceptedKeyEpoch += 1;
}

int _acceptedKeyEpoch = 0;

/// Grows each time the service accepts the API key.
@internal
int get acceptedApiKeyEpoch => _acceptedKeyEpoch;

/// The reported reason: the server's code, then its detail when it sent one.
@internal
String placementFallbackReason(
        PlacementBatchRefusalReasonV1 reason, String? detail) =>
    detail == null ? reason.name : '${reason.name}:$detail';

/// Forgets which fallbacks were logged.
@internal
void resetPlacementFallbackLog() {
  _logged.clear();
  _loggedNoAnswers.clear();
  _loggedRefusedKey = false;
  _keyRefusedSince = null;
  refusedApiKeyClock = DateTime.now;
}

String _hint(PlacementBatchRefusalReasonV1 reason, String? detail,
        PublishedSurfaceLabel published) =>
    switch (reason) {
      PlacementBatchRefusalReasonV1.unavailable =>
        'nothing is published to it yet. Publish a surface to show it here.',
      PlacementBatchRefusalReasonV1.invalidAuthority =>
        'the server refused this key for it. Check that the API key belongs '
            'to the app that owns this placement.',
      PlacementBatchRefusalReasonV1.unknownLocator =>
        'the server does not know this placement. Check its name and that '
            'this build has reported it.',
      PlacementBatchRefusalReasonV1.invalidRequest =>
        'the request did not match this build. Regenerate and rebuild the app.',
      PlacementBatchRefusalReasonV1.incompatible => detail == null
          ? _noDetails(published)
          : describeFitTokens(detail.split(' '), published: published),
      PlacementBatchRefusalReasonV1.artifactUnavailable =>
        'its published content could not be fetched. It is retried on the '
            'next mount.',
      PlacementBatchRefusalReasonV1.localClockUnavailable =>
        'its delivery rule needs the device clock and time zone.',
      PlacementBatchRefusalReasonV1.enrollmentRequired =>
        'an experiment needs an assignment key. Check identity setup.',
      PlacementBatchRefusalReasonV1.assignmentUnavailable =>
        'its experiment assignment expired. The next mount enrolls again.',
      PlacementBatchRefusalReasonV1.decodeFailed =>
        'the server response could not be read. Check that the SDK and the '
            'server are current.',
    };

String _noDetails(PublishedSurfaceLabel published) =>
    "${published._phrase} doesn't fit this build, and the service sent no "
    'details. See $_fallbackDocs';

/// One fit failure: what is wrong, how to fix it, and where to read more.
typedef _Gap = (String problem, List<String> fixes, String? docs);

/// The fit failure [tokens] the service or this build reported, as sentences
/// a developer can act on. A leading `published@N` token names the version.
@internal
String describeFitTokens(List<String> tokens,
    {PublishedSurfaceLabel published = const PublishedSurfaceLabel()}) {
  var label = published;
  final gaps = <_Gap>[];
  for (final token in tokens) {
    if (token.isEmpty) continue;
    final version = _publishedVersion(token);
    if (version != null) {
      label = label._withVersion(version);
      continue;
    }
    gaps.add(_gap(_FitToken.parse(token), label));
  }
  if (gaps.isEmpty) return _noDetails(label);
  final problems = <String>[];
  final fixes = <String>[];
  final docs = <String>[];
  for (final (problem, gapFixes, link) in gaps) {
    if (!problems.contains(problem)) problems.add(problem);
    for (final fix in gapFixes) {
      if (!fixes.contains(fix)) fixes.add(fix);
    }
    if (link != null && !docs.contains(link)) docs.add(link);
  }
  final sentences = [
    ...problems,
    ...fixes,
    if (docs.isNotEmpty) 'See ${docs.join(' and ')}',
  ];
  return [
    for (final (index, sentence) in sentences.indexed)
      index == 0 ? sentence : _capitalized(sentence),
  ].join(' ');
}

String _capitalized(String sentence) => sentence.isEmpty
    ? sentence
    : sentence[0].toUpperCase() + sentence.substring(1);

int? _publishedVersion(String token) => token.startsWith('published@')
    ? int.tryParse(token.substring('published@'.length))
    : null;

/// A token's parts: `code[:subject][@required][;available]`.
final class _FitToken {
  const _FitToken(this.raw, this.code, this.subject, this.required, this.have);

  factory _FitToken.parse(String token) {
    final semicolon = token.indexOf(';');
    final head = semicolon < 0 ? token : token.substring(0, semicolon);
    final have = semicolon < 0 ? null : token.substring(semicolon + 1);
    final at = head.indexOf('@');
    final body = at < 0 ? head : head.substring(0, at);
    final required = at < 0 ? null : head.substring(at + 1);
    final colon = body.indexOf(':');
    return _FitToken(
        token,
        colon < 0 ? body : body.substring(0, colon),
        colon < 0 ? null : _unescape(body.substring(colon + 1)),
        required == null ? null : _unescape(required),
        have == null ? null : _unescape(have));
  }

  final String raw;
  final String code;
  final String? subject;
  final String? required;
  final String? have;
}

String _unescape(String part) {
  try {
    return Uri.decodeComponent(part);
  } on ArgumentError {
    return part;
  } on FormatException {
    return part;
  }
}

String _republish(PublishedSurfaceLabel published) {
  final slug = published.slug;
  return slug == null
      ? 'Push and publish it again from this build.'
      : 'Push and publish it again from this build: `restage surface push '
          '$slug`, then `restage surface publish $slug`.';
}

const _builtInNamespaces = {
  'restage.core',
  'restage.material',
  'restage.cupertino',
};

// Described from the token alone: the service judged the build it was sent,
// which may differ from this device's registry now.
_Gap _gap(_FitToken token, PublishedSurfaceLabel published) {
  final it = published._phrase;
  final subject = token.subject;
  final have = token.have;
  final republish = [_republish(published)];
  const build = 'run `dart run build_runner build`';
  switch (token.code) {
    case 'missingLibrary':
      if (have == 'unversioned') {
        return (
          '$it needs the widget library `$subject` v${_major(token.required)}, '
              'but this build registers it without a capability version.',
          ['Set `capabilityVersion` on its `@RestageLibrary` and $build.'],
          _libraryDocs,
        );
      }
      return (
        '$it needs the widget library `$subject` v${_major(token.required)}, '
            "which this build doesn't register.",
        ['Add the package that provides it to the app, then $build.'],
        _libraryDocs,
      );
    case 'brokenLibrary':
      final (version, since) = _pair(have, ',');
      return (
        '$it was built against `$subject` v${_major(token.required)}, but '
            "this build's `$subject`"
            '${version == null ? '' : ' v$version'} declares a break'
            '${since == null ? '' : ' (compatibleSince: $since)'}.',
        republish,
        _libraryDocs,
      );
    case 'oldLibrary':
      final (needVersion, needGenerated) = _pair(token.required, '/');
      final (haveVersion, haveGenerated) = _pair(have, '/');
      if (haveVersion == null) {
        return (
          '$it needs `$subject` v$needVersion'
              '${needGenerated == null ? '' : ' with generated code v$needGenerated'}'
              ", newer than this build's.",
          [
            'Update the package that provides `$subject`'
                '${needGenerated == null ? '' : ' and restage_codegen'}, then '
                '$build.'
          ],
          _libraryDocs,
        );
      }
      final versionBehind = needVersion == null ||
          (int.tryParse(haveVersion) ?? 0) < (int.tryParse(needVersion) ?? 0);
      if (versionBehind || needGenerated == null) {
        return (
          '$it needs `$subject` v$needVersion; this build has v$haveVersion.',
          [
            'Update the package that provides `$subject` to the release with '
                'capability version $needVersion, then $build.'
          ],
          _libraryDocs,
        );
      }
      return (
        "$it needs `$subject`'s generated code at v$needGenerated; this "
            "build's is v${haveGenerated ?? 1}.",
        ['Update restage_codegen, then $build.'],
        _libraryDocs,
      );
    case 'missingWidget':
      if (subject == null) {
        return (
          "$it draws a widget this build doesn't have.",
          [
            'Install the full catalog, or draw it once in a `@Screen` and '
                '$build.'
          ],
          _catalogDocs,
        );
      }
      final colon = subject.lastIndexOf(':');
      final namespace = colon < 0 ? null : subject.substring(0, colon);
      final widget = colon < 0 ? subject : subject.substring(colon + 1);
      if (namespace == null || _builtInNamespaces.contains(namespace)) {
        return (
          "$it draws `$widget`, which this build's widget catalog leaves out.",
          [
            'Draw it once in a `@Screen` and $build, or install the full '
                'catalog.'
          ],
          _catalogDocs,
        );
      }
      return (
        "$it draws `$widget` from `$namespace`, which this build's "
            "`$namespace` doesn't include.",
        [
          'Update the package that provides `$namespace`, or annotate '
              '`$widget` with `@RestageWidget`, then $build.'
        ],
        _libraryDocs,
      );
    case 'missingIcon':
      return (
        '$it uses the ${subject ?? 'icon'} glyph '
            "${token.required ?? '(unknown)'}, which this build's icon set "
            'leaves out.',
        [
          "Try removing the icon's key, or include the icon in the app (draw "
              "it in the app's own code, or call "
              '`InstalledIconTable.add(builtInIconTable())` at startup) and '
              'release a build.'
        ],
        _catalogDocs,
      );
    case 'missingInstalledVocabulary':
      return (
        "the service got no list of this build's widgets and icons. It "
            "couldn't check $it against them.",
        [
          'This SDK (restage $measurementReportedSdkVersion) sends one. Check '
              'that the service and the restage package are current.'
        ],
        null,
      );
    case 'hostingMismatch':
      final (needKind, needModes) = _pair(token.required, '/');
      final (haveKind, haveMode) = _pair(have, '/');
      if (needKind == null || haveKind == null) {
        return (
          '$it is a different kind of surface, or presents differently, '
              'than this placement shows.',
          ['Point this placement at a surface of the kind it hosts.'],
          _hostingDocs,
        );
      }
      final shown = _hosting(haveKind, [if (haveMode != null) haveMode]);
      if (needKind == haveKind) {
        final need = _presentations(needModes?.split('+'));
        final placement = _presentations([if (haveMode != null) haveMode]);
        return (
          '$it can only be shown $need, but this placement shows it '
              '$placement.',
          [
            '${haveMode == 'presented' ? 'Mount this placement inline in a '
                    'widget tree' : 'Open this placement with '
                    '`Restage.presentPlacement`'}, or change `presentation:` '
                'on its source annotation, then push and publish it again.'
          ],
          _hostingDocs,
        );
      }
      return (
        '$it is ${_hosting(needKind, needModes?.split('+'))}, but this '
            'placement shows $shown.',
        [
          'Point this placement at $shown, or mount the surface from a '
              'placement that shows ${_kind(needKind)}.'
        ],
        _hostingDocs,
      );
    case 'deliveryModeMismatch':
      return (
        token.required == null || have == null
            ? 'the published flow and this build disagree on whether the '
                'flow is typed or general.'
            : '$it is a ${token.required} flow, but this build declares it '
                '$have.',
        [
          ...republish,
          if (token.required == 'general')
            'Setting `delivery: FlowDeliveryMode.general` on its `@FlowGraph` '
                'and releasing the app fixes the flow mode alone.',
        ],
        _flowModeDocs,
      );
    case 'builtInFloor':
      final action = subject == null ? '' : "'s action `$subject`";
      if (token.required == null) {
        return (
          '$it$action needs a newer restage package than '
              '$measurementReportedSdkVersion.',
          ['Update the restage package.'],
          null,
        );
      }
      return (
        '$it$action needs built-in widgets v${token.required}; this build '
            '(restage $measurementReportedSdkVersion) has '
            'v${have ?? RestageBuiltInCatalogCapabilities.currentVersion}.',
        [
          'Update the restage package to a release with built-in widgets '
              'v${token.required}.'
        ],
        null,
      );
    case 'missingHostField':
      return (
        "$it reads `$subject` from host data, which this placement doesn't "
            'pass.',
        republish,
        _hostDataDocs,
      );
    case 'incompatibleHostField':
      return (
        token.required == null || have == null
            ? "$it reads `$subject` with a type this placement doesn't pass."
            : '$it reads `$subject` as ${token.required}; this placement '
                'passes $have.',
        republish,
        _hostDataDocs,
      );
    case 'unhandledEvent':
      return (
        "$it sends the event `$subject`, which this placement doesn't "
            'handle.',
        republish,
        _eventDocs,
      );
    case 'incompatibleEventShape':
      return (
        '$it sends the event `$subject` with arguments its handler here '
            "doesn't accept.",
        republish,
        _eventDocs,
      );
    case 'actionMismatch':
      final (version, differs) = _pair(have, '/');
      return (
        version == null
            ? "$it calls the host action `$subject`, which this build doesn't "
                'provide.'
            : version != token.required
                ? '$it calls the host action `$subject` v${token.required}; '
                    'this build provides v$version.'
                : '$it calls the host action `$subject` v${token.required}, '
                    'whose ${_actionParts(differs)} from this build\'s '
                    'v$version.',
        republish,
        _actionDocs,
      );
    case 'seedMismatch':
      return (
        'this placement can seed `$subject`'
            '${token.required == null ? '' : ' as ${token.required}'}, but $it '
            '${have == null ? "doesn't take it" : 'takes it as $have'}.',
        republish,
        _flowModeDocs,
      );
    case 'signalMismatch':
      return (
        '$it fires the signal `$subject`, which this build has no handler '
            'for.',
        republish,
        _flowModeDocs,
      );
    case 'resultMismatch':
      return (
        subject == null
            ? "$it's typed result differs from this build's."
            : "$it's typed result differs from this build's in "
                '${subject.split(',').map((key) => '`$key`').join(', ')}.',
        republish,
        _flowModeDocs,
      );
    case 'outboundMismatch':
      return (
        '$it sends `$subject`'
            '${token.required == null ? '' : ' as ${token.required}'}; this '
            "build ${have == null ? "doesn't take it" : 'takes it as $have'}.",
        republish,
        _flowModeDocs,
      );
    case 'missingIsland' || 'changedIsland':
      final widget = token.required ?? 'a widget';
      return (
        token.code == 'missingIsland'
            ? "$it doesn't fit this build: $widget: this build doesn't "
                'include its app code.'
            : "$it doesn't fit this build: $widget: this build changed its "
                'app code.',
        republish,
        null,
      );
    default:
      return ("$it doesn't fit this build (`${token.raw}`).", republish, null);
  }
}

const _actionPartNames = {
  'name': 'name',
  'args': 'arguments',
  'result': 'result',
  'minClient': 'minimum built-in widgets version',
  'idempotent': 'idempotency',
};

/// The differing action parts, `args,idempotent`, as a phrase with its verb.
String _actionParts(String? parts) {
  final names = [
    for (final part in parts?.split(',') ?? const <String>[])
      if (part.isNotEmpty) _actionPartNames[part] ?? part,
  ];
  if (names.isEmpty) return 'contract differs';
  final listed = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return '$listed ${names.length == 1 ? 'differs' : 'differ'}';
}

String? _major(String? required) => required?.split('/').first;

(String?, String?) _pair(String? value, String separator) {
  if (value == null) return (null, null);
  final index = value.indexOf(separator);
  return index < 0
      ? (value, null)
      : (value.substring(0, index), value.substring(index + 1));
}

String _kind(String kind) => kind == 'flow' ? 'a flow' : 'a single screen';

String _presentations(List<String>? modes) => [
      for (final mode in modes ?? const <String>[])
        mode == 'presented' ? 'as a route' : 'inline',
    ].join(' or ');

String _hosting(String kind, List<String>? modes) {
  final shown = _presentations(modes);
  return shown.isEmpty ? _kind(kind) : '${_kind(kind)} $shown';
}
