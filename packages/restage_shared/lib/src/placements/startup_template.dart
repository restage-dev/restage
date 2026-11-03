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
String? startupTemplateJson(
  Uri url,
  String apiKey,
  PlacementBatchRequestV1 request, {
  bool identityTokens = false,
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
      final metering = request.meteringKey;
      if (metering != null) {
        swap('"meteringKey":"$metering"', '"meteringKey":"$_meteringToken"');
      }
      final anonymous = request.analyticsAnonymousId;
      if (anonymous != null) {
        swap(
          '"analyticsAnonymousId":"$anonymous"',
          '"analyticsAnonymousId":"$_anonymousToken"',
        );
      }
    }
    final registration = request.registration;
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
    if (request.localClock case final clock?) {
      swap(
        '"utcOffsetMinutes":${clock.utcOffsetMinutes}}',
        '"utcOffsetMinutes":$_offsetToken}',
      );
    }
    for (final (key, carrier, token) in [
      (
        'sdkBuiltInsCanonicalBase64',
        request.sdkBuiltInsCanonicalBase64,
        _builtInsToken,
      ),
      (
        'sdkInstalledLibraries',
        request.sdkInstalledLibraries,
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
  final builtIns = tree(request.sdkBuiltInsCanonicalBase64);
  final libraries = tree(request.sdkInstalledLibraries);
  return jsonEncode({
    'url': url.toString(),
    'authorization': 'Bearer $apiKey',
    'appBuildContractHash': request.appBuildContractHash,
    if (tokenizesOrdinal) 'contract': contractTokenized,
    'body': body,
    'fullBody': full,
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
