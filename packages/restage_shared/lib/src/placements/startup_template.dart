import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';
import 'package:restage_shared/src/capability/surface_fit.dart'
    show SurfaceHostContractV1;
import 'package:restage_shared/src/capability/widget_vocabulary.dart';
import 'package:restage_shared/src/placements/placement_delivery.dart';
import 'package:restage_shared/src/surface_delivery/surface_registration.dart';

/// The version this SDK reports; kept equal to the `restage` package version.
const String kRestageSdkVersion = '2.0.0';

/// The assignment API level this SDK speaks.
const int kAssignmentSdkApiLevel = 4;

/// [url] with surrounding whitespace and trailing slashes removed: the one
/// form a service URL takes in build output, configuration and requests.
String canonicalServiceUrl(String url) =>
    url.trim().replaceFirst(RegExp(r'/+$'), '');

/// The placement-resolve endpoint of the service at [baseUrl].
Uri placementResolveUrl(String baseUrl) =>
    Uri.parse('${canonicalServiceUrl(baseUrl)}/sdk/v1/placements/resolve');

/// The capability a build presents, from its built-in catalog version, its
/// registered libraries and the widgets and icons it installs.
///
/// Icon families with no code point are left out.
InstalledCapability computeInstalledCapability({
  required int builtInCatalogVersion,
  required Iterable<InstalledLibrary> installedLibraries,
  Set<String> widgetNames = const {},
  Map<String, Set<int>> iconCodePoints = const {},
}) =>
    InstalledCapability(
      builtInCatalogVersion: builtInCatalogVersion,
      installedLibraries: installedLibraries.toList(),
      vocabulary: WidgetVocabulary(
        widgetNames: widgetNames,
        iconCodePoints: {
          for (final family in iconCodePoints.entries)
            if (family.value.isNotEmpty) family.key: family.value,
        },
      ),
    );

/// The base64url `sdkInstalledLibraries` report, or null past its bounds.
String? installedLibrariesCarrierOf(
  InstalledCapability capability, {
  String? appVersion,
}) {
  final report = SdkInstalledLibrariesV1(
    builtInCatalogVersion: capability.builtInCatalogVersion,
    appVersion: appVersion,
    libraries: [
      for (final library in capability.installedLibraries)
        SdkInstalledLibraryV1(
          namespace: library.namespace,
          version: library.version,
          compatibleSince: library.compatibleSince,
          generated: library.generated,
        ),
    ],
  );
  final carrier = base64UrlEncode(report.canonicalBytes).replaceAll('=', '');
  return carrier.length <= sdkInstalledLibrariesMaximumCarrierCharacters
      ? carrier
      : null;
}

/// The base64url `sdkSupportedPolicyRevisions` report for [platform].
String supportedPolicyRevisionsCarrierOf(String platform) => base64UrlEncode(
      SdkSupportedPolicyRevisionsV1(
        sdkVersion: kRestageSdkVersion,
        assignmentApiLevel: kAssignmentSdkApiLevel,
        platform: platform,
        privacyPolicyFloor: collectionPrivacyPolicyFloor,
        collectionBudgetFloor: collectionBudgetPolicyFloor,
      ).canonicalBytes,
    ).replaceAll('=', '');

/// The base64url built-in facts carrier for [facts]; keys sort canonically.
String builtInsCarrierOf(Map<String, Object> facts) =>
    base64UrlEncode(CanonicalJsonCodec.encode(facts)).replaceAll('=', '');

/// The first startup batch of a fresh install, with placeholder device facts.
PlacementBatchRequestV1 startupRequestFor({
  required String platform,
  required List<PlacementMountRequestV1> mounts,
  required Map<String, SurfaceHostContractV1> contractsByHash,
  required InstalledCapability capability,
  required Map<String, Object> builtIns,
  bool registers = true,
  bool identities = true,
  int? buildOrdinal,
  String appVersion = _placeholderVersion,
}) {
  final build = PlacementBuildContractV1(
    platform: platform,
    buildOrdinal: buildOrdinal,
    mounts: mounts,
    contractsByHash: contractsByHash,
    installedCapability: capability,
    installedCapabilityHash: capability.contentHash,
  );
  return PlacementBatchRequestV1(
    mounts: mounts,
    buildContract: build,
    appBuildContractHash: build.appBuildContractHash,
    mode: PlacementBatchModeV1.prefetch,
    localClock: DeliveryLocalClockV1(0),
    sdkInstalledLibraries: installedLibrariesCarrierOf(
      capability,
      appVersion: appVersion,
    ),
    sdkBuiltInsCanonicalBase64: builtInsCarrierOf(builtIns),
    sdkSupportedPolicyRevisions: supportedPolicyRevisionsCarrierOf(platform),
    registration: registers
        ? SurfaceRegistrationTupleV1(
            registrationNonce: _placeholderNonce,
            registrationCreatedAtMicros: 1,
          )
        : null,
    meteringKey: identities ? _placeholderUuid : null,
    analyticsAnonymousId: identities ? _placeholderUuid : null,
    inlineMounts: [for (var i = 0; i < mounts.length; i++) i],
    startup: true,
  );
}

const _placeholderVersion = '0';
const _placeholderUuid = '00000000-0000-4000-8000-000000000000';

// 32 zero bytes, unpadded base64url.
final String _placeholderNonce =
    base64UrlEncode(List.filled(32, 0)).replaceAll('=', '');

const _meteringToken = '@@meteringKey@@';
const _anonymousToken = '@@analyticsAnonymousId@@';
const _contractToken = '@@buildContract@@';
const _hashToken = '@@appBuildContractHash@@';
const _nonceToken = '@@registrationNonce@@';
const _createdToken = '@@registrationCreatedAtMicros@@';
const _offsetToken = '@@utcOffsetMinutes@@';
const _builtInsToken = '@@sdkBuiltIns@@';
const _librariesToken = '@@sdkInstalledLibraries@@';
const _mountedToken = '@@mountedSince@@';

// The facts the platform reads itself, by the carrier that holds them.
const _nativeBuiltIns = {
  'country',
  'language',
  'platform',
  'osVersion',
  'deviceClass',
  'appBuildOrdinal',
  'daysSinceInstall',
};

/// The template the platform sends at process start: [request] as canonical
/// text with the device facts the platform knows left as tokens, or null when
/// [request] does not hold the fields a template needs.
///
/// With [identityTokens] the request's metering key and anonymous id become
/// tokens the platform fills with the ones it made, for the first launch.
///
/// [analytics] and [measurement] are the build's defaults for the two
/// switches. The template also holds `analyticsOff` and `measurementOff`, the
/// request as the SDK sends it with each switch off.
String? startupTemplateJson(
  Uri url,
  String apiKey,
  PlacementBatchRequestV1 request, {
  bool identityTokens = false,
  bool analytics = true,
  bool measurement = true,
}) {
  final contract = request.buildContract;
  final ordinal = contract.buildOrdinal;
  final contractText = utf8.decode(contract.canonicalBytes);
  final ordinalPrefix = '{"buildOrdinal":$ordinal,';
  final tokenizesOrdinal =
      ordinal != null && contractText.startsWith(ordinalPrefix);
  final contractTokenized = tokenizesOrdinal
      ? '{"buildOrdinal":@@buildOrdinal@@,'
          '${contractText.substring(ordinalPrefix.length)}'
      : contractText;
  String? tokenized(PlacementBatchRequestV1 form) {
    var text = utf8.decode(form.canonicalBytes);
    var ok = true;
    void swap(String from, String to) {
      if (!text.contains(from)) {
        ok = false;
        return;
      }
      text = text.replaceFirst(from, to);
    }

    swap(
      '"appBuildContractHash":"${request.appBuildContractHash}"',
      '"appBuildContractHash":"${tokenizesOrdinal ? _hashToken : request.appBuildContractHash}"',
    );
    if (form.carriesBuildContract) {
      swap(
        '"buildContract":$contractText',
        '"buildContract":${tokenizesOrdinal ? _contractToken : contractText}',
      );
    }
    // The platform splices the install's mounted-surface report here.
    swap('"mode":"prefetch","mounts":',
        '"mode":"prefetch"$_mountedToken,"mounts":');
    if (identityTokens) {
      final metering = form.meteringKey;
      if (metering != null) {
        swap('"meteringKey":"$metering"', '"meteringKey":"$_meteringToken"');
      }
      final anonymous = form.analyticsAnonymousId;
      if (anonymous != null) {
        swap(
          '"analyticsAnonymousId":"$anonymous"',
          '"analyticsAnonymousId":"$_anonymousToken"',
        );
      }
    }
    final registration = form.registration;
    if (registration != null) {
      swap(
        '"registrationNonce":"${registration.registrationNonce}"',
        '"registrationNonce":"$_nonceToken"',
      );
      swap(
        '"registrationCreatedAtMicros":'
            '${registration.registrationCreatedAtMicros}',
        '"registrationCreatedAtMicros":$_createdToken',
      );
    }
    if (form.localClock case final clock?) {
      swap(
        '"utcOffsetMinutes":${clock.utcOffsetMinutes}}',
        '"utcOffsetMinutes":$_offsetToken}',
      );
    }
    for (final (key, carrier, token) in [
      (
        'sdkBuiltInsCanonicalBase64',
        form.sdkBuiltInsCanonicalBase64,
        _builtInsToken,
      ),
      (
        'sdkInstalledLibraries',
        form.sdkInstalledLibraries,
        _librariesToken,
      ),
    ]) {
      if (carrier != null) swap('"$key":"$carrier"', '"$key":"$token"');
    }
    return ok ? text : null;
  }

  Map<String, Object?>? tree(String? carrier) {
    if (carrier == null) return null;
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(carrier))),
    );
    return decoded is Map<String, Object?> ? decoded : null;
  }

  final unreported = request.withMountedSince(const []);
  final body = tokenized(unreported.withBuildContract(carried: false));
  final full = tokenized(unreported.withBuildContract(carried: true));
  if (body == null || full == null) return null;
  final quiet = unreported.withoutAnalytics();
  final quietBody = tokenized(quiet.withBuildContract(carried: false));
  final quietFull = tokenized(quiet.withBuildContract(carried: true));
  if (quietBody == null || quietFull == null) return null;
  final unmeasured = unreported.withoutAssignment();
  final unmeasuredBody =
      tokenized(unmeasured.withBuildContract(carried: false));
  final unmeasuredFull = tokenized(unmeasured.withBuildContract(carried: true));
  if (unmeasuredBody == null || unmeasuredFull == null) return null;
  final builtIns = tree(request.sdkBuiltInsCanonicalBase64);
  final libraries = tree(request.sdkInstalledLibraries);
  return jsonEncode({
    'url': url.toString(),
    'authorization': 'Bearer $apiKey',
    'appBuildContractHash': request.appBuildContractHash,
    if (tokenizesOrdinal) 'contract': contractTokenized,
    'body': body,
    'fullBody': full,
    'analytics': analytics,
    'analyticsOff': {'body': quietBody, 'fullBody': quietFull},
    'measurement': measurement,
    'measurementOff': {'body': unmeasuredBody, 'fullBody': unmeasuredFull},
    if (builtIns != null) 'builtIns': builtIns,
    if (libraries != null) 'installedLibraries': libraries,
    'fills': [
      if (request.localClock != null) 'utcOffsetMinutes',
      if (tokenizesOrdinal) 'buildOrdinal',
      if (builtIns != null)
        for (final key in builtIns.keys)
          if (_nativeBuiltIns.contains(key)) key,
      if (libraries != null && libraries.containsKey('appVersion'))
        'appVersion',
    ],
  });
}

/// Why the platform's startup answer cannot stand for the startup request the
/// SDK would send, by the first condition that failed.
enum StartupAnswerMismatch {
  /// Another platform, build ordinal, mount list or host contract.
  build,

  /// The platform claimed a widget, icon or library the app does not install.
  capability,

  /// One request carries an install id and the other does not.
  analytics,

  /// The same install id, but only one request registers: measurement is off.
  measurement,

  /// Another metering key, registration, assignment or held state.
  assignment,
}

/// Why the answer to [sent], the request the platform sent at launch, cannot be
/// used for [mine], the startup request the SDK would send; null when it can.
///
/// Fields the platform fills from the device or that only shape the answer's
/// size (inline artifacts, the mounted-surface report, device facts, the local
/// clock) are not compared.
StartupAnswerMismatch? startupAnswerMismatch({
  required PlacementBatchRequestV1 sent,
  required PlacementBatchRequestV1 mine,
}) {
  final a = sent.buildContract;
  final b = mine.buildContract;
  if (a.platform != b.platform ||
      a.buildOrdinal != b.buildOrdinal ||
      !_sameJson(
        [for (final mount in sent.mounts) mount.toJson()],
        [for (final mount in mine.mounts) mount.toJson()],
      ) ||
      !_sameJson(
        {for (final e in a.contractsByHash.entries) e.key: e.value.toJson()},
        {for (final e in b.contractsByHash.entries) e.key: e.value.toJson()},
      )) {
    return StartupAnswerMismatch.build;
  }
  if (!capabilityCovers(
    installed: b.installedCapability,
    claimed: a.installedCapability,
  )) {
    return StartupAnswerMismatch.capability;
  }
  if (sent.analyticsAnonymousId != mine.analyticsAnonymousId) {
    return StartupAnswerMismatch.analytics;
  }
  if ((sent.registration == null) != (mine.registration == null)) {
    return StartupAnswerMismatch.measurement;
  }
  if (sent.meteringKey != mine.meteringKey ||
      sent.assignmentKey != mine.assignmentKey ||
      !_sameJson(sent.registration?.toJson(), mine.registration?.toJson()) ||
      !_sameJson(
        [for (final held in sent.heldAssignments) held.toJson()],
        [for (final held in mine.heldAssignments) held.toJson()],
      ) ||
      !_sameJson(
        [for (final held in sent.heldDeclines) held.toJson()],
        [for (final held in mine.heldDeclines) held.toJson()],
      )) {
    return StartupAnswerMismatch.assignment;
  }
  return null;
}

/// Whether an app that [installed] this capability renders everything chosen
/// for [claimed]: no newer built-in catalog, no widget, icon or library it
/// lacks.
bool capabilityCovers({
  required InstalledCapability installed,
  required InstalledCapability claimed,
}) {
  if (claimed.builtInCatalogVersion > installed.builtInCatalogVersion) {
    return false;
  }
  for (final library in claimed.installedLibraries) {
    final have = [
      for (final candidate in installed.installedLibraries)
        if (candidate.namespace == library.namespace) candidate,
    ].firstOrNull;
    if (have == null) return false;
    if (have == library) continue;
    final wanted = library.version;
    final version = have.version;
    if (wanted == null ||
        version == null ||
        version < wanted ||
        have.effectiveCompatibleSince > library.effectiveCompatibleSince ||
        have.effectiveGenerated < library.effectiveGenerated) {
      return false;
    }
  }
  final want = claimed.vocabulary;
  final has = installed.vocabulary;
  if (want == null || has == null) return want == has;
  if (!has.widgetNames.containsAll(want.widgetNames)) return false;
  for (final family in want.iconCodePoints.entries) {
    final icons = has.iconCodePoints[family.key] ?? const <int>{};
    if (!icons.containsAll(family.value)) return false;
  }
  return true;
}

bool _sameJson(Object? a, Object? b) => _sorted(a) == _sorted(b);

// JSON text with every map's keys sorted, so key order is never a difference.
String _sorted(Object? value) {
  if (value is List) return '[${value.map(_sorted).join(',')}]';
  if (value is! Map) return jsonEncode(value);
  final keys = [for (final key in value.keys) '$key']..sort();
  final members = [
    for (final key in keys) '${jsonEncode(key)}:${_sorted(value[key])}',
  ];
  return '{${members.join(',')}}';
}
