import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';
import 'package:restage_shared/src/capability/surface_fit.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';
import 'package:restage_shared/src/identity/surface_slug.dart';
import 'package:restage_shared/src/placements/placement_geometry.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_contract/surface_publication_contract.dart';
import 'package:restage_shared/src/surface_delivery/surface_artifact_descriptor.dart';
import 'package:restage_shared/src/surface_delivery/surface_registration.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show WidgetLibrary;

/// Maximum canonical UTF-8 bytes in one placement request or discovery report.
///
/// This is a transport and decoding-work budget, not a limit on the number of
/// placements or builds an application may have.
const int kMaximumPlacementRequestBytes = 512 * 1024;

/// Maximum canonical response UTF-8 bytes after transport decompression.
const int kMaximumPlacementResponseBytes = 32 * 1024 * 1024;

/// Maximum bytes in one base64-decoded content-addressed payload frame.
const int kMaximumPlacementArtifactBytes = 16 * 1024 * 1024;

/// Maximum expanded selected payload bytes across all mounted closures.
const int kMaximumPlacementExpandedClosureBytes = 64 * 1024 * 1024;

/// A target-free surface name and its exact general or screen-contract family.
final class DeliverySurfaceLocatorV1 extends _PlacementValue {
  /// Creates a locator using the shared surface-slug grammar.
  DeliverySurfaceLocatorV1({
    required this.surfaceType,
    required this.slug,
    required this.family,
  }) {
    validateSurfaceSlug(slug);
    if (surfaceSlugPattern.stringMatch(slug) != slug || family.isNone) {
      throw const CanonicalFormatException(
        'A surface locator requires an exact slug and a surface family.',
      );
    }
  }

  /// Decodes one closed locator object.
  factory DeliverySurfaceLocatorV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'surfaceLocator');
    return _construct(
      () => DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId(reader.string('surfaceType')),
        slug: reader.string('slug'),
        family: DeliveryFamilySelectorV1.fromJson(reader.object('family')),
      ),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory DeliverySurfaceLocatorV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, DeliverySurfaceLocatorV1.fromJson);

  static const _keys = {'surfaceType', 'slug', 'family'};

  /// Registered surface category.
  final DeliverySurfaceTypeId surfaceType;

  /// Surface name within [surfaceType].
  final String slug;

  /// Exact requested surface family; never the placement-only `none` branch.
  final DeliveryFamilySelectorV1 family;

  @override
  Map<String, Object?> toJson() => {
        'surfaceType': surfaceType.value,
        'slug': slug,
        'family': family.toJson(),
      };
}

/// A target-free placement declaration sent under authenticated SDK authority.
final class PlacementMountRequestV1 extends _PlacementValue {
  /// Creates a declaration, checking the generated default's exact locator.
  PlacementMountRequestV1({
    required this.key,
    required this.hostContractHash,
    this.defaultSurface,
  }) {
    _requireContentHash(hostContractHash, 'hostContractHash');
    if (key.isGeneratedDefault &&
        (defaultSurface == null ||
            key.surfaceType != defaultSurface!.surfaceType ||
            key.slug != defaultSurface!.slug)) {
      throw const CanonicalFormatException(
        'A generated placement must name its exact default surface locator.',
      );
    }
  }

  /// Decodes one closed mount request with an explicit nullable default.
  factory PlacementMountRequestV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'mountRequest');
    final rawDefault = reader.requiredNullableValue('defaultSurface');
    return PlacementMountRequestV1(
      key: PlacementKeyV1.fromJson(reader.object('key')),
      defaultSurface: rawDefault == null
          ? null
          : DeliverySurfaceLocatorV1.fromJson(rawDefault),
      hostContractHash: reader.string('hostContractHash'),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementMountRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementMountRequestV1.fromJson);

  static const _keys = {'key', 'defaultSurface', 'hostContractHash'};

  /// Namespace-qualified placement name.
  final PlacementKeyV1 key;

  /// Optional remote fallback; absent for a widget-only named placement.
  final DeliverySurfaceLocatorV1? defaultSurface;

  /// Exact content hash of the host contract this mount supplies.
  final String hostContractHash;

  @override
  Map<String, Object?> toJson() => {
        'key': key.toJson(),
        'defaultSurface': defaultSurface?.toJson(),
        'hostContractHash': hostContractHash,
      };
}

/// An authenticated placement and its resolved default surface identity.
final class PlacementMountDescriptorV1 extends _PlacementValue {
  /// Creates a descriptor whose default, when present, has the same target.
  PlacementMountDescriptorV1({
    required this.placement,
    required this.hostContractHash,
    this.defaultSurface,
  }) {
    _requireContentHash(hostContractHash, 'hostContractHash');
    if (defaultSurface != null && defaultSurface!.target != placement.target) {
      throw const CanonicalFormatException(
        'The default surface and placement must have the same exact target.',
      );
    }
  }

  /// Decodes one closed descriptor, optionally checking authenticated target.
  factory PlacementMountDescriptorV1.fromJson(
    Object? value, {
    TargetCoordinate? expectedTarget,
  }) {
    final reader = _reader(value, _keys, 'mountDescriptor');
    final rawDefault = reader.requiredNullableValue('defaultSurface');
    final result = PlacementMountDescriptorV1(
      placement: PlacementIdentityV1.fromJson(reader.object('placement')),
      defaultSurface: rawDefault == null
          ? null
          : DeliverySurfaceReferenceV1.fromJson(
              requireCanonicalObject(rawDefault, 'defaultSurface'),
            ),
      hostContractHash: reader.string('hostContractHash'),
    );
    if (expectedTarget != null) result._requireTarget(expectedTarget);
    return result;
  }

  /// Decodes exact bytes and optionally checks the authenticated target.
  factory PlacementMountDescriptorV1.fromCanonicalBytes(
    List<int> bytes, {
    TargetCoordinate? expectedTarget,
  }) =>
      _decode(
        bytes,
        (value) => PlacementMountDescriptorV1.fromJson(
          value,
          expectedTarget: expectedTarget,
        ),
      );

  static const _keys = {'placement', 'defaultSurface', 'hostContractHash'};

  /// Exact target-qualified placement identity.
  final PlacementIdentityV1 placement;

  /// Resolved default surface; null when none was declared or none is hosted.
  final DeliverySurfaceReferenceV1? defaultSurface;

  /// Exact host contract carried by the request.
  final String hostContractHash;

  /// Checks response correlation under the supplied exact authenticated target.
  ///
  /// Resolving a locator's type/slug to an opaque published surface identity
  /// belongs to the authenticated resolver. This checks the public correlation
  /// facts available in both request and response, including exact family.
  void validateForRequest(
    PlacementMountRequestV1 request, {
    required TargetCoordinate expectedTarget,
  }) {
    _requireTarget(expectedTarget);
    // A declared default may be unresolved; an undeclared one never resolves.
    if (placement.key != request.key ||
        hostContractHash != request.hostContractHash ||
        (defaultSurface != null &&
            defaultSurface!.family != request.defaultSurface?.family)) {
      throw const CanonicalFormatException(
        'The mount descriptor does not agree with the requested declaration.',
      );
    }
  }

  void _requireTarget(TargetCoordinate target) {
    if (placement.target != target) {
      throw const CanonicalFormatException(
        'The mount descriptor has a different authenticated target.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'placement': placement.toJson(),
        'defaultSurface': defaultSurface?.toJson(),
        'hostContractHash': hostContractHash,
      };
}

/// The complete immutable, target-free host and renderer declaration.
final class PlacementBuildContractV1 extends _PlacementValue {
  /// Creates a canonical declaration with no unreachable host contracts.
  ///
  /// Exact repeated key/host/default declarations collapse to one mount. A
  /// repeated key/host pair with a different default refuses. The same key may
  /// have different host contracts, each retained independently.
  factory PlacementBuildContractV1({
    required String platform,
    required List<PlacementMountRequestV1> mounts,
    required Map<String, SurfaceHostContractV1> contractsByHash,
    required InstalledCapability installedCapability,
    required String installedCapabilityHash,
    int? buildOrdinal,
  }) {
    _requirePlatform(platform);
    if (buildOrdinal != null) _requireNonnegative(buildOrdinal, 'buildOrdinal');
    _requireContentHash(installedCapabilityHash, 'installedCapabilityHash');

    // Bound input work before sorting, deduplication, or copying collections.
    final budget = _JsonBudget()
      ..addJson(platform)
      ..addJson(buildOrdinal)
      ..addListFraming(mounts.length);
    for (final mount in mounts) {
      budget.addJson(mount.toJson());
    }
    budget.addObjectFraming(contractsByHash.length);
    for (final entry in contractsByHash.entries) {
      budget
        ..addJson(entry.key)
        ..addJson(entry.value.toJson());
    }
    budget.addCapability(installedCapability);

    final canonicalMounts = _canonicalMounts(mounts);
    final referencedHashes =
        canonicalMounts.map((mount) => mount.hostContractHash).toSet();
    if (referencedHashes.length != contractsByHash.length ||
        !referencedHashes.containsAll(contractsByHash.keys)) {
      throw const CanonicalFormatException(
        'Host contracts must match exactly the hashes referenced by mounts.',
      );
    }
    final contracts = <String, SurfaceHostContractV1>{};
    for (final hash in contractsByHash.keys.toList()..sort()) {
      _requireContentHash(hash, 'contractsByHash');
      final snapshot = SurfaceHostContractV1.fromJson(
        contractsByHash[hash]!.toJson(),
      );
      if (snapshot.contentHash != hash) {
        throw const CanonicalFormatException(
          'A host contract does not match its exact content hash.',
        );
      }
      contracts[hash] = snapshot;
    }
    final capability = _strictCapability(installedCapability.toJson());
    if (capability.contentHash != installedCapabilityHash) {
      throw const CanonicalFormatException(
        'The installed capability does not match its exact content hash.',
      );
    }
    final result = PlacementBuildContractV1._(
      platform: platform,
      buildOrdinal: buildOrdinal,
      mounts: canonicalMounts,
      contractsByHash: Map.unmodifiable(contracts),
      installedCapability: capability,
      installedCapabilityHash: installedCapabilityHash,
    );
    _requireJsonBudget(result.toJson());
    return result;
  }

  PlacementBuildContractV1._({
    required this.platform,
    required this.buildOrdinal,
    required this.mounts,
    required this.contractsByHash,
    required this.installedCapability,
    required this.installedCapabilityHash,
  });

  /// Decodes the complete closed target-free build object.
  factory PlacementBuildContractV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'buildContract');
    final rawOrdinal = reader.requiredNullableValue('buildOrdinal');
    if (rawOrdinal != null && rawOrdinal is! int) {
      throw const CanonicalFormatException('buildOrdinal must be null or int.');
    }
    final rawContracts = reader.object('contractsByHash');
    return _construct(
      () => PlacementBuildContractV1(
        platform: reader.string('platform'),
        buildOrdinal: rawOrdinal as int?,
        mounts: reader
            .list('mounts')
            .map(PlacementMountRequestV1.fromJson)
            .toList(),
        contractsByHash: {
          for (final entry in rawContracts.entries)
            entry.key: SurfaceHostContractV1.fromJson(entry.value),
        },
        installedCapability:
            _strictCapability(reader.object('installedCapability')),
        installedCapabilityHash: reader.string('installedCapabilityHash'),
      ),
    );
  }

  /// Decodes exact canonical bytes and optionally verifies the supplied hash.
  factory PlacementBuildContractV1.fromCanonicalBytes(
    List<int> bytes, {
    String? expectedAppBuildContractHash,
  }) {
    final result = _decode(bytes, PlacementBuildContractV1.fromJson);
    if (expectedAppBuildContractHash != null) {
      result.verifyHash(expectedAppBuildContractHash);
    }
    return result;
  }

  static const _keys = {
    'platform',
    'buildOrdinal',
    'mounts',
    'contractsByHash',
    'installedCapability',
    'installedCapabilityHash',
  };

  /// Runtime platform token.
  final String platform;

  /// Device-asserted build ordinal, explicitly null when unavailable.
  final int? buildOrdinal;

  /// Deduplicated declarations sorted by their unsigned canonical bytes.
  final List<PlacementMountRequestV1> mounts;

  /// Exact immutable host contracts, keyed and ordered by their own hashes.
  final Map<String, SurfaceHostContractV1> contractsByHash;

  /// Complete renderer snapshot, including its exact optional vocabulary.
  final InstalledCapability installedCapability;

  /// Hash produced by [InstalledCapability.contentHash].
  final String installedCapabilityHash;

  /// SHA-256 of UTF-8 `restage.placement-build-contract.v1`, one NUL byte,
  /// then the exact canonical build bytes; written as `sha256:<lowercase hex>`.
  ///
  /// Target, credentials, users, observations and geometry are absent from the
  /// build bytes and therefore absent from this hash's preimage.
  late final String appBuildContractHash = 'sha256:${crypto.sha256.convert(
    <int>[
      ...utf8.encode('restage.placement-build-contract.v1\u0000'),
      ...canonicalBytes,
    ],
  )}';

  /// Refuses a supplied digest that does not identify this exact build.
  void verifyHash(String expectedAppBuildContractHash) {
    _requireContentHash(expectedAppBuildContractHash, 'appBuildContractHash');
    if (appBuildContractHash != expectedAppBuildContractHash) {
      throw const CanonicalFormatException(
        'The app build contract hash does not identify the supplied build.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'platform': platform,
        'buildOrdinal': buildOrdinal,
        'mounts': mounts.map((mount) => mount.toJson()).toList(),
        'contractsByHash': {
          for (final entry in contractsByHash.entries)
            entry.key: entry.value.toJson(),
        },
        'installedCapability': installedCapability.toJson(),
        'installedCapabilityHash': installedCapabilityHash,
      };
}

/// One same-frame observation of a runtime occurrence of a mount declaration.
final class PlacementMountBoundsV1 extends _PlacementValue {
  /// Creates bounded integer geometry with a report-local occurrence index.
  PlacementMountBoundsV1({
    required this.key,
    required this.hostContractHash,
    required this.logicalBounds,
    required this.logicalViewport,
    required this.occurrenceIndex,
  }) {
    _requireContentHash(hostContractHash, 'hostContractHash');
    _requireNonnegative(occurrenceIndex, 'occurrenceIndex');
  }

  /// Decodes only the closed geometry fields; runtime data is never admitted.
  factory PlacementMountBoundsV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'mountBounds');
    return PlacementMountBoundsV1(
      key: PlacementKeyV1.fromJson(reader.object('key')),
      hostContractHash: reader.string('hostContractHash'),
      logicalBounds:
          PlacementLogicalRectV1.fromJson(reader.object('logicalBounds')),
      logicalViewport:
          PlacementLogicalSizeV1.fromJson(reader.object('logicalViewport')),
      occurrenceIndex: reader.integer('occurrenceIndex'),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementMountBoundsV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementMountBoundsV1.fromJson);

  static const _keys = {
    'key',
    'hostContractHash',
    'logicalBounds',
    'logicalViewport',
    'occurrenceIndex',
  };

  /// Namespace-qualified placement name.
  final PlacementKeyV1 key;

  /// Exact host contract observed for this occurrence.
  final String hostContractHash;

  /// Bounds in the same coordinate frame as [logicalViewport].
  final PlacementLogicalRectV1 logicalBounds;

  /// Bounded positive viewport used for this observation.
  final PlacementLogicalSizeV1 logicalViewport;

  /// Distinguishes occurrences of the same key and host within this report.
  final int occurrenceIndex;

  @override
  Map<String, Object?> toJson() => {
        'key': key.toJson(),
        'hostContractHash': hostContractHash,
        'logicalBounds': logicalBounds.toJson(),
        'logicalViewport': logicalViewport.toJson(),
        'occurrenceIndex': occurrenceIndex,
      };
}

/// Target-free discovery declarations and observations for one exact build.
final class PlacementDiscoveryReportV1 extends _PlacementValue {
  /// Creates a report whose locators and bounds are reachable from the build.
  ///
  /// Duplicate declarations follow the build's rules. Every key/host/occurrence
  /// bounds identity must be unique; even an identical repeat refuses.
  factory PlacementDiscoveryReportV1({
    required List<PlacementMountRequestV1> mounts,
    required PlacementBuildContractV1 buildContract,
    required String appBuildContractHash,
    required List<PlacementMountBoundsV1> bounds,
    String? appVersion,
  }) {
    buildContract.verifyHash(appBuildContractHash);
    if (appVersion != null &&
        (appVersion.isEmpty ||
            appVersion.length > 64 ||
            appVersion.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f))) {
      throw const CanonicalFormatException(
        'An app version is 1 to 64 printable characters.',
      );
    }
    final budget = _JsonBudget()
      ..addJson(buildContract.toJson())
      ..addListFraming(mounts.length);
    for (final mount in mounts) {
      budget.addJson(mount.toJson());
    }
    budget.addListFraming(bounds.length);
    for (final bound in bounds) {
      budget.addJson(bound.toJson());
    }
    final canonicalMounts = _canonicalMounts(mounts);
    final buildMounts = buildContract.mounts.toSet();
    if (!buildMounts.containsAll(canonicalMounts)) {
      throw const CanonicalFormatException(
        'Every reported locator must be an exact declaration in the build.',
      );
    }
    final reportedHosts = {
      for (final mount in canonicalMounts) (mount.key, mount.hostContractHash),
    };
    for (final bound in bounds) {
      if (!reportedHosts.contains((bound.key, bound.hostContractHash))) {
        throw const CanonicalFormatException(
          'Bounds must name an exact reported key and host contract.',
        );
      }
    }
    final result = PlacementDiscoveryReportV1._(
      mounts: canonicalMounts,
      buildContract: buildContract,
      appBuildContractHash: appBuildContractHash,
      bounds: _canonicalBounds(bounds),
      appVersion: appVersion,
    );
    _requireJsonBudget(result.toJson());
    return result;
  }

  PlacementDiscoveryReportV1._({
    required this.mounts,
    required this.buildContract,
    required this.appBuildContractHash,
    required this.bounds,
    this.appVersion,
  });

  /// Decodes a closed report and verifies its complete build/hash correlation.
  factory PlacementDiscoveryReportV1.fromJson(Object? value) {
    final json = requireCanonicalObject(value, 'discoveryReport');
    _requireJsonBudget(json);
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: {..._keys, 'appVersion'},
      requiredKeys: _keys,
      path: 'discoveryReport',
    );
    return PlacementDiscoveryReportV1(
      appVersion: reader.optionalString('appVersion'),
      mounts:
          reader.list('mounts').map(PlacementMountRequestV1.fromJson).toList(),
      buildContract:
          PlacementBuildContractV1.fromJson(reader.object('buildContract')),
      appBuildContractHash: reader.string('appBuildContractHash'),
      bounds:
          reader.list('bounds').map(PlacementMountBoundsV1.fromJson).toList(),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementDiscoveryReportV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementDiscoveryReportV1.fromJson);

  static const _keys = {
    'mounts',
    'buildContract',
    'appBuildContractHash',
    'bounds',
  };

  /// Canonical declarations observed in this report, a subset of the build.
  final List<PlacementMountRequestV1> mounts;

  /// Complete immutable declaration for the captured build.
  final PlacementBuildContractV1 buildContract;

  /// Verified digest of [buildContract].
  final String appBuildContractHash;

  /// Canonically sorted observations retaining every distinct occurrence.
  final List<PlacementMountBoundsV1> bounds;

  /// The app's display version, such as `2.4.1`; outside the build hash.
  final String? appVersion;

  @override
  Map<String, Object?> toJson() => {
        'mounts': mounts.map((mount) => mount.toJson()).toList(),
        'buildContract': buildContract.toJson(),
        'appBuildContractHash': appBuildContractHash,
        'bounds': bounds.map((bound) => bound.toJson()).toList(),
        if (appVersion != null) 'appVersion': appVersion,
      };
}

/// Latest aggregate geometry observed by a server for one exact build.
final class PlacementReportedGeometryV1 extends _PlacementValue {
  /// Creates bounded latest geometry with a server-owned observation time.
  factory PlacementReportedGeometryV1({
    required String appBuildContractHash,
    required int serverObservedAtMicros,
    required List<PlacementMountBoundsV1> mounts,
  }) {
    _requireContentHash(appBuildContractHash, 'appBuildContractHash');
    _requireNonnegative(serverObservedAtMicros, 'serverObservedAtMicros');
    final budget = _JsonBudget()..addListFraming(mounts.length);
    for (final mount in mounts) {
      budget.addJson(mount.toJson());
    }
    final result = PlacementReportedGeometryV1._(
      appBuildContractHash: appBuildContractHash,
      serverObservedAtMicros: serverObservedAtMicros,
      mounts: _canonicalBounds(mounts),
    );
    _requireJsonBudget(result.toJson());
    return result;
  }

  PlacementReportedGeometryV1._({
    required this.appBuildContractHash,
    required this.serverObservedAtMicros,
    required this.mounts,
  });

  /// Decodes the closed latest-geometry projection.
  factory PlacementReportedGeometryV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'reportedGeometry');
    return PlacementReportedGeometryV1(
      appBuildContractHash: reader.string('appBuildContractHash'),
      serverObservedAtMicros: reader.integer('serverObservedAtMicros'),
      mounts:
          reader.list('mounts').map(PlacementMountBoundsV1.fromJson).toList(),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementReportedGeometryV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementReportedGeometryV1.fromJson);

  static const _keys = {
    'appBuildContractHash',
    'serverObservedAtMicros',
    'mounts',
  };

  /// Exact build associated with this latest aggregate projection.
  final String appBuildContractHash;

  /// Portable nonnegative UTC epoch microseconds assigned by the server.
  final int serverObservedAtMicros;

  /// Sorted observations with unique key/host/occurrence identities.
  final List<PlacementMountBoundsV1> mounts;

  @override
  Map<String, Object?> toJson() => {
        'appBuildContractHash': appBuildContractHash,
        'serverObservedAtMicros': serverObservedAtMicros,
        'mounts': mounts.map((mount) => mount.toJson()).toList(),
      };
}

/// The exact immutable policy scopes watched by one public delivery.
typedef DeliveryDependencyClosureV1 = Set<DeliveryPolicyScopeV1>;

/// Freezes a sorted scope set, refusing repeated scopes.
DeliveryDependencyClosureV1 freezeDeliveryDependencyClosureV1(
  Iterable<DeliveryPolicyScopeV1> scopes,
) {
  final copied = <DeliveryPolicyScopeV1>[];
  final seen = <DeliveryPolicyScopeV1>{};
  for (final scope in scopes) {
    final snapshot = DeliveryPolicyScopeV1.fromJson(scope.toJson());
    if (!seen.add(snapshot)) {
      throw const CanonicalFormatException('Duplicate dependency scope.');
    }
    copied.add(snapshot);
  }
  _sortCanonical(copied);
  return Set.unmodifiable(copied);
}

/// The closed sorted-set codec for public dependency scopes.
abstract final class DeliveryDependencyClosureV1Codec {
  /// Encodes scopes in canonical byte order.
  static List<Object?> encode(DeliveryDependencyClosureV1 scopes) => [
        for (final scope in freezeDeliveryDependencyClosureV1(scopes))
          scope.toJson(),
      ];

  /// Refuses duplicate scopes and noncanonical set ordering.
  static DeliveryDependencyClosureV1 decode(Object? value) {
    if (value is! List<Object?>) {
      throw const CanonicalFormatException(
        'Dependency closure must be a list.',
      );
    }
    final result = freezeDeliveryDependencyClosureV1([
      for (final scope in value)
        DeliveryPolicyScopeV1.fromJson(
          requireCanonicalObject(scope, 'dependencyClosure[]'),
        ),
    ]);
    if (!_sameJson(value, encode(result))) {
      throw const CanonicalFormatException('Dependency scopes must be sorted.');
    }
    return result;
  }
}

/// Public source spellings for a selected policy step.
enum PublicDeliverySelectionSourceV1 {
  /// The owner's default output.
  ownerDefault,

  /// An admitted rule destination.
  rule,

  /// An admitted percentage destination or remainder.
  percentage,

  /// An admitted experiment selection.
  experiment,
}

/// An allowlisted policy owner, exact family, and selection source.
final class PublicDeliveryDecisionStepV1 extends _DeliveryValue {
  /// Creates a public step without rule, audience, or allocation evidence.
  PublicDeliveryDecisionStepV1({required this.scope, required this.source});

  /// Decodes a closed public step.
  factory PublicDeliveryDecisionStepV1.fromJson(Object? value) {
    final reader =
        _deliveryReader(value, const {'scope', 'source'}, 'decisionStep');
    return _construct(
      () => PublicDeliveryDecisionStepV1(
        scope: DeliveryPolicyScopeV1.fromJson(reader.object('scope')),
        source: PublicDeliverySelectionSourceV1.values.byName(
          reader.string('source'),
        ),
      ),
    );
  }

  /// Decodes byte-exact canonical public step bytes.
  factory PublicDeliveryDecisionStepV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PublicDeliveryDecisionStepV1.fromJson);

  /// Exact selected owner and family.
  final DeliveryPolicyScopeV1 scope;

  /// Bounded selection-source vocabulary.
  final PublicDeliverySelectionSourceV1 source;

  @override
  Map<String, Object?> toJson() => {
        'scope': scope.toJson(),
        'source': source.name,
      };
}

/// The ordered public selections and their exact delivered publication.
final class PublicDeliveryDecisionPathV1 extends _DeliveryValue {
  /// Requires a surface-family step, optionally preceded by a placement.
  PublicDeliveryDecisionPathV1({
    required List<PublicDeliveryDecisionStepV1> steps,
    required this.actualPublication,
  }) : steps = List.unmodifiable([
          for (final step in steps)
            PublicDeliveryDecisionStepV1.fromJson(step.toJson()),
        ]) {
    if (steps.isEmpty ||
        steps.length > 2 ||
        (steps.length == 2 && !steps.first.scope.root.isPlacement) ||
        steps.last.scope.root.isPlacement ||
        steps.first.scope.target != actualPublication.surface.target ||
        steps.last.scope.root.surface !=
            actualPublication.surface.surfaceIdentity ||
        steps.last.scope.family != actualPublication.surface.family) {
      throw const CanonicalFormatException('Public decision steps disagree.');
    }
  }

  /// Decodes a closed public path.
  factory PublicDeliveryDecisionPathV1.fromJson(Object? value) {
    final reader = _deliveryReader(
      value,
      const {'steps', 'actualPublication'},
      'decisionPath',
    );
    return PublicDeliveryDecisionPathV1(
      steps: [
        for (final step in reader.list('steps'))
          PublicDeliveryDecisionStepV1.fromJson(step),
      ],
      actualPublication: DeliveryPublicationReferenceV1.fromJson(
        reader.object('actualPublication'),
      ),
    );
  }

  /// Decodes byte-exact canonical public path bytes.
  factory PublicDeliveryDecisionPathV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PublicDeliveryDecisionPathV1.fromJson);

  /// Optional placement followed by the selected surface-family step.
  final List<PublicDeliveryDecisionStepV1> steps;

  /// Exact delivered output, including any public binding reference.
  final DeliveryPublicationReferenceV1 actualPublication;

  /// The noncyclic digest of selected identities, path, and publication.
  CanonicalDigest get selectionIdentityDigest => _domainDigest(
        'restage.placement-selection-identity.v1',
        {
          'path': toJson(),
          'selectedSurface': actualPublication.surface.toJson(),
          'actualPublication': actualPublication.toJson(),
        },
      );

  @override
  Map<String, Object?> toJson() => {
        'steps': [for (final step in steps) step.toJson()],
        'actualPublication': actualPublication.toJson(),
      };
}

/// A safe immutable delivery projection, with opaque authority carriers.
final class PublicPlacementDeliveryV1 extends _DeliveryValue {
  /// Computes or verifies the allowlisted digest and checks public agreement.
  factory PublicPlacementDeliveryV1({
    required PlacementMountDescriptorV1 mount,
    required PublicDeliveryDecisionPathV1 path,
    required DeliverySurfaceReferenceV1 selectedSurface,
    required DeliveryPublicationReferenceV1 actualPublication,
    required SurfaceFitRequirementV1 fitRequirement,
    required DeliveryCacheValidityV1 cacheValidity,
    required DeliveryDependencyClosureV1 dependencyClosure,
    CanonicalDigest? publicProjectionDigest,
    String? routingSelectionReceipt,
    PresentationAssignmentCarrierV2? assignment,
  }) {
    final dependencies = freezeDeliveryDependencyClosureV1(dependencyClosure);
    if (path.steps.length != 2 ||
        path.steps.first.scope.root.placement != mount.placement ||
        selectedSurface != actualPublication.surface ||
        path.actualPublication != actualPublication ||
        selectedSurface.target != mount.placement.target ||
        cacheValidity.hostContractHash != mount.hostContractHash ||
        cacheValidity.selectionIdentityDigest != path.selectionIdentityDigest ||
        dependencies.any((scope) => scope.target != mount.placement.target) ||
        !dependencies.containsAll(path.steps.map((step) => step.scope))) {
      throw const CanonicalFormatException('Public delivery fields disagree.');
    }
    var previousIndex = -1;
    for (final selection in cacheValidity.policySelections) {
      final index = path.steps.indexWhere(
        (step) => step.scope == selection.policyRevision.scope,
      );
      if (index <= previousIndex) {
        throw const CanonicalFormatException('Cache policy path disagrees.');
      }
      previousIndex = index;
    }
    if (routingSelectionReceipt != null) {
      _requireOpaqueReceipt(routingSelectionReceipt);
    }
    final result = PublicPlacementDeliveryV1._(
      mount: PlacementMountDescriptorV1.fromJson(mount.toJson()),
      path: PublicDeliveryDecisionPathV1.fromJson(path.toJson()),
      selectedSurface: DeliverySurfaceReferenceV1.fromJson(
        selectedSurface.toJson(),
      ),
      actualPublication: DeliveryPublicationReferenceV1.fromJson(
        actualPublication.toJson(),
      ),
      fitRequirement: SurfaceFitRequirementV1.fromJson(fitRequirement.toJson()),
      cacheValidity: DeliveryCacheValidityV1.fromJson(cacheValidity.toJson()),
      dependencyClosure: dependencies,
      routingSelectionReceipt: routingSelectionReceipt,
      assignment: assignment == null
          ? null
          : PresentationAssignmentCarrierV2.fromJson(assignment.toJson()),
    );
    if (publicProjectionDigest != null &&
        publicProjectionDigest != result.publicProjectionDigest) {
      throw const CanonicalFormatException(
        'Public projection digest mismatch.',
      );
    }
    _requireResponseJsonBudget(result.toJson());
    return result;
  }

  PublicPlacementDeliveryV1._({
    required this.mount,
    required this.path,
    required this.selectedSurface,
    required this.actualPublication,
    required this.fitRequirement,
    required this.cacheValidity,
    required this.dependencyClosure,
    required this.routingSelectionReceipt,
    required this.assignment,
  });

  /// Decodes the closed projection and verifies its supplied digest.
  factory PublicPlacementDeliveryV1.fromJson(Object? value) {
    final reader = _deliveryReader(value, _keys, 'publicPlacementDelivery');
    final receipt = reader.requiredNullableValue('routingSelectionReceipt');
    final assignment = reader.requiredNullableValue('assignment');
    return _construct(
      () => PublicPlacementDeliveryV1(
        mount: PlacementMountDescriptorV1.fromJson(reader.object('mount')),
        path: PublicDeliveryDecisionPathV1.fromJson(reader.object('path')),
        selectedSurface: DeliverySurfaceReferenceV1.fromJson(
          reader.object('selectedSurface'),
        ),
        actualPublication: DeliveryPublicationReferenceV1.fromJson(
          reader.object('actualPublication'),
        ),
        fitRequirement: SurfaceFitRequirementV1.fromJson(
          reader.object('fitRequirement'),
        ),
        cacheValidity: DeliveryCacheValidityV1.fromJson(
          reader.object('cacheValidity'),
        ),
        dependencyClosure: DeliveryDependencyClosureV1Codec.decode(
          reader.list('dependencyClosure'),
        ),
        publicProjectionDigest: CanonicalDigest(
          reader.string('publicProjectionDigest'),
        ),
        routingSelectionReceipt: receipt == null
            ? null
            : requireCanonicalString(receipt, 'routingSelectionReceipt'),
        assignment: assignment == null
            ? null
            : PresentationAssignmentCarrierV2.fromJson(
                requireCanonicalObject(assignment, 'assignment'),
              ),
      ),
    );
  }

  /// Decodes byte-exact canonical public delivery bytes.
  factory PublicPlacementDeliveryV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PublicPlacementDeliveryV1.fromJson);

  static const _keys = {
    'mount',
    'path',
    'selectedSurface',
    'actualPublication',
    'fitRequirement',
    'cacheValidity',
    'dependencyClosure',
    'publicProjectionDigest',
    'routingSelectionReceipt',
    'assignment',
  };

  /// Correlated authenticated mount.
  final PlacementMountDescriptorV1 mount;

  /// The safe selected policy path.
  final PublicDeliveryDecisionPathV1 path;

  /// Actual selected surface and its own exact family.
  final DeliverySurfaceReferenceV1 selectedSurface;

  /// Exact delivered publication.
  final DeliveryPublicationReferenceV1 actualPublication;

  /// Complete requirements from the qualified immutable selected publication.
  final SurfaceFitRequirementV1 fitRequirement;

  /// Cache eligibility evidence, evaluated by its consumer.
  final DeliveryCacheValidityV1 cacheValidity;

  /// Complete public policy watch set.
  final DeliveryDependencyClosureV1 dependencyClosure;

  /// Opaque routing token; decoding establishes no signed authority.
  final String? routingSelectionReceipt;

  /// Opaque original assignment handle; authority resolves externally.
  final PresentationAssignmentCarrierV2? assignment;

  /// Digest of the safe pre-mount projection, excluding opaque credentials.
  late final CanonicalDigest publicProjectionDigest = _domainDigest(
    'restage.public-placement-delivery.v1',
    _projection(),
  );

  Map<String, Object?> _projection() => {
        'mount': mount.toJson(),
        'path': path.toJson(),
        'selectedSurface': selectedSurface.toJson(),
        'actualPublication': actualPublication.toJson(),
        'fitRequirement': fitRequirement.toJson(),
        'cacheValidity': cacheValidity.toJson(),
        'dependencyClosure': DeliveryDependencyClosureV1Codec.encode(
          dependencyClosure,
        ),
      };

  @override
  Map<String, Object?> toJson() => {
        ..._projection(),
        'publicProjectionDigest': publicProjectionDigest.hex,
        'routingSelectionReceipt': routingSelectionReceipt,
        'assignment': assignment?.toJson(),
      };
}

/// Content identity within an exact payload-format partition.
final class ArtifactIdentityV1 extends _PlacementValue {
  /// Validates a supported payload format and canonical SHA-256 hash.
  ArtifactIdentityV1({
    required this.payloadFormatVersion,
    required this.contentHash,
  }) {
    if (payloadFormatVersion < 1 ||
        payloadFormatVersion >
            kMaxSupportedSurfaceArtifactPayloadFormatVersion) {
      throw const CanonicalFormatException(
        'Unsupported artifact payload format.',
      );
    }
    _requireContentHash(contentHash, 'contentHash');
  }

  /// Reads the identity of an existing artifact descriptor.
  factory ArtifactIdentityV1.fromDescriptor(SurfaceArtifactDescriptor value) =>
      ArtifactIdentityV1(
        payloadFormatVersion: value.payloadFormatVersion,
        contentHash: value.contentHash,
      );

  /// Decodes a closed artifact identity.
  factory ArtifactIdentityV1.fromJson(Object? value) {
    final reader = _reader(
      value,
      const {'payloadFormatVersion', 'contentHash'},
      'artifactIdentity',
    );
    return ArtifactIdentityV1(
      payloadFormatVersion: reader.integer('payloadFormatVersion'),
      contentHash: reader.string('contentHash'),
    );
  }

  /// Decodes byte-exact canonical identity bytes.
  factory ArtifactIdentityV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, ArtifactIdentityV1.fromJson);

  /// Supported frame encoding partition.
  final int payloadFormatVersion;

  /// Canonical `sha256:` content hash of the entire frame.
  final String contentHash;

  @override
  Map<String, Object?> toJson() => {
        'payloadFormatVersion': payloadFormatVersion,
        'contentHash': contentHash,
      };
}

/// Resolution mode for one ordered placement batch.
enum PlacementBatchModeV1 {
  /// Read-only startup resolution without registration or enrollment.
  prefetch,

  /// Resolution for a real mount with permitted existing credentials.
  mount,

  /// Read-only resolution using existing authority without new registration.
  refresh,
}

/// An opaque retained assignment path handle correlated to one exact mount.
final class PlacementHeldAssignmentV1 extends _PlacementValue {
  /// Validates the existing path handle shape without resolving its authority.
  PlacementHeldAssignmentV1({
    required this.key,
    required this.hostContractHash,
    required this.retainedPathHandle,
  }) {
    _requireContentHash(hostContractHash, 'hostContractHash');
    _construct(
      () => PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier: retainedPathHandle,
      ),
    );
  }

  /// Decodes a closed per-mount proof carrier.
  factory PlacementHeldAssignmentV1.fromJson(Object? value) {
    final reader = _reader(
      value,
      const {'key', 'hostContractHash', 'retainedPathHandle'},
      'heldAssignment',
    );
    return PlacementHeldAssignmentV1(
      key: PlacementKeyV1.fromJson(reader.object('key')),
      hostContractHash: reader.string('hostContractHash'),
      retainedPathHandle: reader.string('retainedPathHandle'),
    );
  }

  /// Decodes exact canonical proof-correlation bytes.
  factory PlacementHeldAssignmentV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementHeldAssignmentV1.fromJson);

  /// Namespace-qualified exact requested placement key.
  final PlacementKeyV1 key;

  /// Exact requested host contract hash.
  final String hostContractHash;

  /// Exact canonical opaque32 handle returned by the assignment path owner.
  final String retainedPathHandle;

  @override
  Map<String, Object?> toJson() => {
        'key': key.toJson(),
        'hostContractHash': hostContractHash,
        'retainedPathHandle': retainedPathHandle,
      };
}

/// One complete target-free startup, mount, or refresh request.
final class PlacementBatchRequestV1 extends _PlacementValue {
  /// Freezes declared ordered mounts, exact build, carriers, and held content.
  factory PlacementBatchRequestV1({
    required List<PlacementMountRequestV1> mounts,
    required PlacementBuildContractV1 buildContract,
    required String appBuildContractHash,
    required PlacementBatchModeV1 mode,
    DeliveryLocalClockV1? localClock,
    Set<ArtifactIdentityV1> heldArtifacts = const {},
    String? sdkInstalledLibraries,
    String? sdkBuiltInsCanonicalBase64,
    String? sdkSupportedPolicyRevisions,
    String? assignmentKey,
    List<PlacementHeldAssignmentV1> heldAssignments = const [],
    SurfaceRegistrationTupleV1? registration,
    String? meteringKey,
    String? analyticsAnonymousId,
  }) {
    _requireJsonBudget({
      'kind': 'placementBatchRequest',
      'schemaVersion': 1,
      'mounts': [for (final mount in mounts) mount.toJson()],
      'buildContract': buildContract.toJson(),
      'appBuildContractHash': appBuildContractHash,
      'mode': mode.name,
      'localClock': localClock?.toJson(),
      'heldAssignments': [for (final proof in heldAssignments) proof.toJson()],
      'heldArtifacts': [
        for (final identity in heldArtifacts) identity.toJson(),
      ],
      if (sdkInstalledLibraries != null)
        'sdkInstalledLibraries': sdkInstalledLibraries,
      if (sdkBuiltInsCanonicalBase64 != null)
        'sdkBuiltInsCanonicalBase64': sdkBuiltInsCanonicalBase64,
      if (sdkSupportedPolicyRevisions != null)
        'sdkSupportedPolicyRevisions': sdkSupportedPolicyRevisions,
      if (assignmentKey != null) 'assignmentKey': assignmentKey,
      if (registration != null) ...registration.toJson(),
      if (meteringKey != null) 'meteringKey': meteringKey,
      if (analyticsAnonymousId != null)
        'analyticsAnonymousId': analyticsAnonymousId,
    });
    buildContract.verifyHash(appBuildContractHash);
    final seen = <String>{};
    for (final mount in mounts) {
      final key = '${utf8.decode(mount.key.canonicalBytes)}\u0000'
          '${mount.hostContractHash}';
      if (!seen.add(key) || !buildContract.mounts.contains(mount)) {
        throw const CanonicalFormatException(
          'Mount is duplicated or undeclared.',
        );
      }
    }
    final proofs = _freezeHeldAssignments(heldAssignments, mounts);
    if (registration != null) {
      SurfaceRegistrationTupleV1.fromJson(registration.toJson());
    }
    if (mode == PlacementBatchModeV1.prefetch &&
        (assignmentKey != null || proofs.isNotEmpty || registration != null)) {
      throw const CanonicalFormatException(
        'Prefetch cannot carry enrollment inputs.',
      );
    }
    if (mode == PlacementBatchModeV1.refresh && registration != null) {
      throw const CanonicalFormatException(
        'Refresh cannot carry registration inputs.',
      );
    }
    if (assignmentKey != null) {
      if (assignmentKey.length > 256 ||
          SurfaceScreenDeliveryRequest.normalizeAssignmentKey(assignmentKey) !=
              assignmentKey) {
        throw const CanonicalFormatException('Invalid assignment key.');
      }
    }
    _validateUuid(meteringKey, 'meteringKey');
    _validateUuid(analyticsAnonymousId, 'analyticsAnonymousId');
    if (sdkInstalledLibraries != null) {
      final bytes = _carrierBytes(
        sdkInstalledLibraries,
        sdkInstalledLibrariesMaximumCarrierCharacters,
        'sdkInstalledLibraries',
      );
      final report = SdkInstalledLibrariesV1.fromCanonicalBytes(bytes);
      final expected = SdkInstalledLibrariesV1(
        libraries: [
          for (final library
              in buildContract.installedCapability.installedLibraries)
            SdkInstalledLibraryV1(
              namespace: library.namespace,
              version: library.version,
              compatibleSince: library.compatibleSince,
            ),
        ],
      );
      if (report != expected) {
        throw const CanonicalFormatException(
          'Library carrier disagrees with build.',
        );
      }
    }
    if (sdkSupportedPolicyRevisions != null) {
      SdkSupportedPolicyRevisionsV1.fromCanonicalBytes(
        _carrierBytes(
          sdkSupportedPolicyRevisions,
          sdkSupportedPolicyRevisionsMaximumCarrierCharacters,
          'sdkSupportedPolicyRevisions',
        ),
      );
    }
    for (final (field, carrier) in [
      ('sdkBuiltInsCanonicalBase64', sdkBuiltInsCanonicalBase64),
    ]) {
      if (carrier != null) {
        // The shared canonical grammar admits bytes without reinterpreting the
        // authority-owned inner built-in or assignment schema.
        requireCanonicalObject(
          CanonicalJsonCodec.decode(
            _carrierBytes(
              carrier,
              kMaximumPlacementRequestBytes,
              field,
            ),
          ),
          field,
        );
      }
    }
    final identities = heldArtifacts.toList();
    _sortCanonical(identities);
    final result = PlacementBatchRequestV1._(
      mounts: List.unmodifiable([
        for (final mount in mounts)
          PlacementMountRequestV1.fromJson(mount.toJson()),
      ]),
      buildContract: PlacementBuildContractV1.fromJson(buildContract.toJson()),
      appBuildContractHash: appBuildContractHash,
      mode: mode,
      localClock: localClock,
      heldArtifacts: Set.unmodifiable(identities),
      sdkInstalledLibraries: sdkInstalledLibraries,
      sdkBuiltInsCanonicalBase64: sdkBuiltInsCanonicalBase64,
      sdkSupportedPolicyRevisions: sdkSupportedPolicyRevisions,
      assignmentKey: assignmentKey,
      heldAssignments: proofs,
      registration: registration,
      meteringKey: meteringKey,
      analyticsAnonymousId: analyticsAnonymousId,
    );
    _requireJsonBudget(result.toJson());
    return result;
  }

  PlacementBatchRequestV1._({
    required this.mounts,
    required this.buildContract,
    required this.appBuildContractHash,
    required this.mode,
    required this.localClock,
    required this.heldArtifacts,
    required this.sdkInstalledLibraries,
    required this.sdkBuiltInsCanonicalBase64,
    required this.sdkSupportedPolicyRevisions,
    required this.assignmentKey,
    required this.heldAssignments,
    required this.registration,
    required this.meteringKey,
    required this.analyticsAnonymousId,
  });

  /// Decodes a closed request without inventing authenticated target authority.
  factory PlacementBatchRequestV1.fromJson(Object? value) {
    _requireJsonBudget(value);
    final reader = _taggedBatchReader(
      value,
      'placementBatchRequest',
      const {
        'mode',
        'mounts',
        'buildContract',
        'appBuildContractHash',
        'localClock',
        'heldArtifacts',
        'heldAssignments',
      },
      optional: const {
        'sdkInstalledLibraries',
        'sdkBuiltInsCanonicalBase64',
        'sdkSupportedPolicyRevisions',
        'assignmentKey',
        'registrationNonce',
        'registrationCreatedAtMicros',
        'meteringKey',
        'analyticsAnonymousId',
      },
    );
    final clock = reader.requiredNullableValue('localClock');
    final rawHeld = reader.list('heldArtifacts');
    final held = <ArtifactIdentityV1>{};
    for (final raw in rawHeld) {
      if (!held.add(ArtifactIdentityV1.fromJson(raw))) {
        throw const CanonicalFormatException(
          'Duplicate held artifact identity.',
        );
      }
    }
    final result = _construct(
      () => PlacementBatchRequestV1(
        mounts: [
          for (final mount in reader.list('mounts'))
            PlacementMountRequestV1.fromJson(mount),
        ],
        buildContract:
            PlacementBuildContractV1.fromJson(reader.object('buildContract')),
        appBuildContractHash: reader.string('appBuildContractHash'),
        mode: PlacementBatchModeV1.values.byName(reader.string('mode')),
        localClock: clock == null
            ? null
            : DeliveryLocalClockV1.fromJson(
                requireCanonicalObject(clock, 'localClock'),
              ),
        heldArtifacts: held,
        sdkInstalledLibraries: reader.optionalString('sdkInstalledLibraries'),
        sdkBuiltInsCanonicalBase64:
            reader.optionalString('sdkBuiltInsCanonicalBase64'),
        sdkSupportedPolicyRevisions:
            reader.optionalString('sdkSupportedPolicyRevisions'),
        assignmentKey: reader.optionalString('assignmentKey'),
        heldAssignments: [
          for (final proof in reader.list('heldAssignments'))
            PlacementHeldAssignmentV1.fromJson(proof),
        ],
        registration: SurfaceRegistrationTupleV1.fromServeBody(
          requireCanonicalObject(value, 'request'),
        ),
        meteringKey: reader.optionalString('meteringKey'),
        analyticsAnonymousId: reader.optionalString('analyticsAnonymousId'),
      ),
    );
    if (!_sameJson(value, result.toJson())) {
      throw const CanonicalFormatException('Batch request is not canonical.');
    }
    return result;
  }

  /// Decodes only the bounded original canonical request bytes.
  factory PlacementBatchRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementBatchRequestV1.fromJson);

  /// Original order of unique declared mounts.
  final List<PlacementMountRequestV1> mounts;

  /// Complete generated and known-dynamic build declaration.
  final PlacementBuildContractV1 buildContract;

  /// Exact build-contract content hash.
  final String appBuildContractHash;

  /// Whether this request may admit mount credential inputs.
  final PlacementBatchModeV1 mode;

  /// Current local offset evidence; absence remains unavailable.
  final DeliveryLocalClockV1? localClock;

  /// Sorted content identities already held by the client.
  final Set<ArtifactIdentityV1> heldArtifacts;

  /// Existing opaque installed-library carrier.
  final String? sdkInstalledLibraries;

  /// Existing opaque canonical built-in observations.
  final String? sdkBuiltInsCanonicalBase64;

  /// Existing canonical policy-support carrier.
  final String? sdkSupportedPolicyRevisions;

  /// Optional current credential handle for a real mount.
  final String? assignmentKey;

  /// Exact per-mount held original assignment proofs.
  final List<PlacementHeldAssignmentV1> heldAssignments;

  /// Optional folded registration tuple for a real mount.
  final SurfaceRegistrationTupleV1? registration;

  /// Existing metering identifier.
  final String? meteringKey;

  /// Existing analytics rollout identifier for a real mount.
  final String? analyticsAnonymousId;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementBatchRequest',
        'schemaVersion': 1,
        'mounts': [for (final mount in mounts) mount.toJson()],
        'buildContract': buildContract.toJson(),
        'appBuildContractHash': appBuildContractHash,
        'mode': mode.name,
        'localClock': localClock?.toJson(),
        'heldArtifacts': [
          for (final identity in heldArtifacts) identity.toJson(),
        ],
        if (sdkInstalledLibraries != null)
          'sdkInstalledLibraries': sdkInstalledLibraries,
        if (sdkBuiltInsCanonicalBase64 != null)
          'sdkBuiltInsCanonicalBase64': sdkBuiltInsCanonicalBase64,
        if (sdkSupportedPolicyRevisions != null)
          'sdkSupportedPolicyRevisions': sdkSupportedPolicyRevisions,
        if (assignmentKey != null) 'assignmentKey': assignmentKey,
        'heldAssignments': [
          for (final proof in heldAssignments) proof.toJson(),
        ],
        if (registration != null) ...registration!.toJson(),
        if (meteringKey != null) 'meteringKey': meteringKey,
        if (analyticsAnonymousId != null)
          'analyticsAnonymousId': analyticsAnonymousId,
      };
}

/// A published root or a retained dependency with its actual descriptor.
final class PlacementArtifactReferenceV1 extends _DeliveryValue {
  /// Checks descriptor format, hash, and version against its public coordinate.
  PlacementArtifactReferenceV1({
    required DeliveryPublicationReferenceV1 publication,
    required this.descriptor,
  }) : publication = publication {
    SurfaceArtifactDescriptorV1Codec.decode(descriptor.toJson());
    if (descriptor.payloadFormatVersion != publication.payloadFormatVersion ||
        descriptor.contentHash != 'sha256:${publication.contentHash.hex}' ||
        descriptor.version != publication.publishedVersion) {
      throw const CanonicalFormatException(
        'Artifact and publication disagree.',
      );
    }
  }

  /// Uses the dependency source version and containing root publication time.
  PlacementArtifactReferenceV1.dependency({required this.descriptor})
      : publication = null {
    SurfaceArtifactDescriptorV1Codec.decode(descriptor.toJson());
  }

  /// Decodes a closed reference with an explicit nullable publication.
  factory PlacementArtifactReferenceV1.fromJson(Object? value) {
    final reader = _deliveryReader(
      value,
      const {'publication', 'descriptor'},
      'artifactReference',
    );
    return _construct(() {
      final publication = reader.requiredNullableValue('publication');
      final descriptor = SurfaceArtifactDescriptorV1Codec.decode(
        reader.object('descriptor'),
      );
      return publication == null
          ? PlacementArtifactReferenceV1.dependency(descriptor: descriptor)
          : PlacementArtifactReferenceV1(
              publication: DeliveryPublicationReferenceV1.fromJson(
                requireCanonicalObject(publication, 'publication'),
              ),
              descriptor: descriptor,
            );
    });
  }

  /// Decodes exact canonical publication/descriptor bytes.
  factory PlacementArtifactReferenceV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementArtifactReferenceV1.fromJson);

  /// Exact root publication, absent for retained artifact dependencies.
  final DeliveryPublicationReferenceV1? publication;

  /// Whole-frame descriptor with root ordinal or dependency source version.
  final SurfaceArtifactDescriptor descriptor;

  /// Content identity, independent of each use's publication metadata.
  ArtifactIdentityV1 get identity =>
      ArtifactIdentityV1.fromDescriptor(descriptor);

  @override
  Map<String, Object?> toJson() => {
        'publication': publication?.toJson(),
        'descriptor': descriptor.toJson(),
      };
}

/// Verified content bytes for one identity, transferred once per response.
final class PlacementBatchArtifactV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Verifies the content hash and the existing strict payload-frame grammar.
  factory PlacementBatchArtifactV1({
    required ArtifactIdentityV1 identity,
    required List<int> bytes,
  }) {
    _requireSize(
      bytes.length,
      kMaximumPlacementArtifactBytes,
      'Artifact decoded bytes',
    );
    final copied = Uint8List.fromList(bytes);
    if ('sha256:${crypto.sha256.convert(copied)}' != identity.contentHash) {
      throw const CanonicalFormatException('Artifact content hash mismatch.');
    }
    final payload = _construct(
      () => SurfacePayload.decode(
        copied,
        requireRequiredLibraries: surfaceArtifactFrameRequiresManifest(
          identity.payloadFormatVersion,
        ),
        allowSections:
            surfaceArtifactFrameAllowsSections(identity.payloadFormatVersion),
      ),
    );
    if (_compareBytes(payload.canonicalBytes, copied) != 0) {
      throw const CanonicalFormatException('Artifact frame is not canonical.');
    }
    return PlacementBatchArtifactV1._(
      identity,
      copied.asUnmodifiableView(),
      payload,
    );
  }

  PlacementBatchArtifactV1._(this.identity, this._bytes, this._payload);

  /// Decodes a closed content object with bounded canonical base64url bytes.
  factory PlacementBatchArtifactV1.fromJson(Object? value) {
    final reader = _unbudgetedReader(
      value,
      const {'identity', 'canonicalBase64Url'},
      'batchArtifact',
    );
    final carrier = reader.string('canonicalBase64Url');
    _requireSize(
      carrier.length,
      (kMaximumPlacementArtifactBytes * 4 + 2) ~/ 3,
      'Artifact encoded characters',
    );
    return _construct(
      () => PlacementBatchArtifactV1(
        identity: ArtifactIdentityV1.fromJson(reader.object('identity')),
        bytes: SurfaceContractJson.decodeCanonicalBase64Url(
          carrier,
          'artifact.canonicalBase64Url',
        ),
      ),
    );
  }

  /// Decodes exact canonical content bytes within the response budget.
  factory PlacementBatchArtifactV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementBatchArtifactV1.fromJson);

  /// Exact frame partition and content hash.
  final ArtifactIdentityV1 identity;
  final Uint8List _bytes;
  final SurfacePayload _payload;

  /// Defensive copy of verified whole-frame bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Actual decoded whole-frame byte count.
  int get decodedByteLength => _bytes.length;

  @override
  Map<String, Object?> toJson() => {
        'identity': identity.toJson(),
        'canonicalBase64Url': SurfaceContractJson.encodeBase64Url(_bytes),
      };
}

/// Safe finite refusal vocabulary for a batch or correlated fallback row.
enum PlacementBatchRefusalReasonV1 {
  /// Authenticated request authority was unavailable.
  invalidAuthority,

  /// A locator could not be admitted under request authority.
  unknownLocator,

  /// A request was malformed or outside its declared build.
  invalidRequest,

  /// No selected remote output was available.
  unavailable,

  /// The selected output was incompatible with this build.
  incompatible,

  /// Required content was unavailable.
  artifactUnavailable,

  /// Current local clock evidence was required and absent.
  localClockUnavailable,

  /// A read-only request would need a new assignment.
  enrollmentRequired,

  /// The held assignment no longer proves; the client forgets it.
  assignmentUnavailable,
}

/// One bounded diagnostic with no private witness fields.
final class PlacementBatchDiagnosticV1 extends _DeliveryValue {
  /// Creates a diagnostic with an optional bounded public explanation.
  PlacementBatchDiagnosticV1({required this.code, this.detail}) {
    if (detail != null) {
      final bytes = CanonicalJsonCodec.encode(detail);
      if (detail!.isEmpty ||
          detail!.contains('\u0000') ||
          bytes.length > 1024) {
        throw const CanonicalFormatException('Invalid diagnostic detail.');
      }
    }
  }

  /// Decodes a closed diagnostic.
  factory PlacementBatchDiagnosticV1.fromJson(Object? value) {
    final reader =
        _deliveryReader(value, const {'code', 'detail'}, 'batchDiagnostic');
    final detail = reader.requiredNullableValue('detail');
    return _construct(
      () => PlacementBatchDiagnosticV1(
        code:
            PlacementBatchRefusalReasonV1.values.byName(reader.string('code')),
        detail:
            detail == null ? null : requireCanonicalString(detail, 'detail'),
      ),
    );
  }

  /// Decodes exact canonical diagnostic bytes.
  factory PlacementBatchDiagnosticV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementBatchDiagnosticV1.fromJson);

  /// Safe refusal code.
  final PlacementBatchRefusalReasonV1 code;

  /// Optional public detail, at most 1024 canonical UTF-8 bytes.
  final String? detail;

  @override
  Map<String, Object?> toJson() => {'code': code.name, 'detail': detail};
}

/// One admitted input's correlated available or fallback result.
sealed class PlacementBatchEntryV1 extends _DeliveryValue {
  PlacementBatchEntryV1._(this.descriptor);

  /// Creates an available result with a complete exact artifact closure.
  factory PlacementBatchEntryV1.available(
    PlacementMountDescriptorV1 descriptor,
    PublicPlacementDeliveryV1 publicDelivery,
    List<PlacementArtifactReferenceV1> artifactClosure, {
    PlacementDeliveryWatchV1? watch,
  }) = PlacementBatchAvailableV1;

  /// Creates a correlated fallback result retaining the admitted descriptor.
  factory PlacementBatchEntryV1.useFallback(
    PlacementMountDescriptorV1 descriptor,
    PlacementBatchRefusalReasonV1 reason,
    List<PlacementBatchDiagnosticV1> diagnostics, {
    PlacementDeliveryWatchV1? watch,
  }) = PlacementBatchUseFallbackV1;

  /// Decodes a closed row union.
  factory PlacementBatchEntryV1.fromJson(Object? value) {
    final json = requireCanonicalObject(value, 'batchEntry');
    final status = requireCanonicalString(json['status'], 'batchEntry.status');
    final result = _construct(() {
      if (status == 'available') {
        final reader = _deliveryReader(
          json,
          const {'status', 'descriptor', 'publicDelivery', 'artifactClosure'},
          'batchEntry',
          optional: const {'watch'},
        );
        final watch = reader.optionalObject('watch');
        return PlacementBatchAvailableV1(
          PlacementMountDescriptorV1.fromJson(reader.object('descriptor')),
          PublicPlacementDeliveryV1.fromJson(reader.object('publicDelivery')),
          [
            for (final reference in reader.list('artifactClosure'))
              PlacementArtifactReferenceV1.fromJson(reference),
          ],
          watch:
              watch == null ? null : PlacementDeliveryWatchV1.fromJson(watch),
        );
      }
      if (status == 'useFallback') {
        final reader = _deliveryReader(
          json,
          const {'status', 'descriptor', 'reason', 'diagnostics'},
          'batchEntry',
          optional: const {'watch'},
        );
        final watch = reader.optionalObject('watch');
        return PlacementBatchUseFallbackV1(
          PlacementMountDescriptorV1.fromJson(reader.object('descriptor')),
          PlacementBatchRefusalReasonV1.values.byName(reader.string('reason')),
          [
            for (final diagnostic in reader.list('diagnostics'))
              PlacementBatchDiagnosticV1.fromJson(diagnostic),
          ],
          watch:
              watch == null ? null : PlacementDeliveryWatchV1.fromJson(watch),
        );
      }
      throw const CanonicalFormatException('Unknown batch entry status.');
    });
    if (!_sameJson(value, result.toJson())) {
      throw const CanonicalFormatException('Batch entry is not canonical.');
    }
    return result;
  }

  /// Decodes exact canonical row bytes.
  factory PlacementBatchEntryV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementBatchEntryV1.fromJson);

  /// Original admitted placement, host hash, and default family.
  final PlacementMountDescriptorV1 descriptor;
}

/// One server-issued watch token associated with its exact policy scope.
final class PlacementDeliveryWatchChannelV1 extends _DeliveryValue {
  /// Copies the scope and validates the existing token's bounded wire shape.
  PlacementDeliveryWatchChannelV1({
    required DeliveryPolicyScopeV1 scope,
    required this.token,
  }) : scope = DeliveryPolicyScopeV1.fromJson(scope.toJson()) {
    _requireWatchToken(token);
    _requireResponseJsonBudget(toJson());
  }

  /// Decodes a closed scope-associated token without authorizing its signature.
  factory PlacementDeliveryWatchChannelV1.fromJson(Object? value) {
    final reader = _deliveryReader(
      value,
      const {'scope', 'token'},
      'deliveryWatchChannel',
    );
    return PlacementDeliveryWatchChannelV1(
      scope: DeliveryPolicyScopeV1.fromJson(reader.object('scope')),
      token: reader.string('token'),
    );
  }

  /// Decodes exact canonical watch channel bytes.
  factory PlacementDeliveryWatchChannelV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementDeliveryWatchChannelV1.fromJson);

  /// Exact policy owner and family supplied by the server.
  final DeliveryPolicyScopeV1 scope;

  /// Opaque existing signed token; authorization remains with its verifier.
  final String token;

  @override
  Map<String, Object?> toJson() => {'scope': scope.toJson(), 'token': token};
}

/// Live watch metadata outside the selected delivery's projection identity.
final class PlacementDeliveryWatchV1 extends _DeliveryValue {
  /// Freezes a scope-sorted token list with one target and no duplicate scopes.
  PlacementDeliveryWatchV1({
    required this.decisionIdentityDigest,
    required List<PlacementDeliveryWatchChannelV1> channels,
  }) : channels = _freezeDeliveryWatchChannels(channels) {
    _requireResponseJsonBudget(toJson());
  }

  /// Decodes a closed watch with exact canonical scope ordering.
  factory PlacementDeliveryWatchV1.fromJson(Object? value) {
    final reader = _deliveryReader(
      value,
      const {'decisionIdentityDigest', 'channels'},
      'deliveryWatch',
    );
    final result = _construct(
      () => PlacementDeliveryWatchV1(
        decisionIdentityDigest: CanonicalDigest(
          reader.string('decisionIdentityDigest'),
        ),
        channels: [
          for (final channel in reader.list('channels'))
            PlacementDeliveryWatchChannelV1.fromJson(channel),
        ],
      ),
    );
    if (!_sameJson(value, result.toJson())) {
      throw const CanonicalFormatException('Watch channels must be sorted.');
    }
    return result;
  }

  /// Decodes exact canonical live watch bytes.
  factory PlacementDeliveryWatchV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeDelivery(bytes, PlacementDeliveryWatchV1.fromJson);

  /// Complete decision identity supplied by the authenticated server.
  final CanonicalDigest decisionIdentityDigest;

  /// Tokens associated with every scope in the delivery's dependency closure.
  final List<PlacementDeliveryWatchChannelV1> channels;

  @override
  Map<String, Object?> toJson() => {
        'decisionIdentityDigest': decisionIdentityDigest.hex,
        'channels': [for (final channel in channels) channel.toJson()],
      };
}

/// An available exact delivery and all of its reachable whole payload frames.
final class PlacementBatchAvailableV1 extends PlacementBatchEntryV1 {
  /// Freezes a sorted closure without duplicate or conflicting references.
  PlacementBatchAvailableV1(
    PlacementMountDescriptorV1 descriptor,
    this.publicDelivery,
    List<PlacementArtifactReferenceV1> artifactClosure, {
    PlacementDeliveryWatchV1? watch,
  })  : artifactClosure = _freezeArtifactClosure(artifactClosure),
        watch = watch == null
            ? null
            : PlacementDeliveryWatchV1.fromJson(watch.toJson()),
        super._(descriptor) {
    if (publicDelivery.mount != descriptor ||
        this
                .artifactClosure
                .where(
                  (ref) => ref.publication == publicDelivery.actualPublication,
                )
                .length !=
            1 ||
        this.artifactClosure.any(
              (ref) =>
                  ref.publication != null &&
                  ref.publication!.surface.target !=
                      descriptor.placement.target,
            )) {
      throw const CanonicalFormatException(
        'Available artifact closure disagrees.',
      );
    }
    if (this.watch != null &&
        (this.watch!.channels.length !=
                publicDelivery.dependencyClosure.length ||
            !publicDelivery.dependencyClosure.containsAll(
              this.watch!.channels.map((channel) => channel.scope),
            ))) {
      throw const CanonicalFormatException(
        'Watch scopes disagree with delivery dependency closure.',
      );
    }
    _requireResponseJsonBudget(toJson());
  }

  /// Safe selected delivery.
  final PublicPlacementDeliveryV1 publicDelivery;

  /// Complete canonical list of exact selected publication descriptors.
  final List<PlacementArtifactReferenceV1> artifactClosure;

  /// Optional complete live watch metadata; absence preserves the delivery.
  final PlacementDeliveryWatchV1? watch;

  @override
  Map<String, Object?> toJson() => {
        'status': 'available',
        'descriptor': descriptor.toJson(),
        'publicDelivery': publicDelivery.toJson(),
        'artifactClosure': [for (final ref in artifactClosure) ref.toJson()],
        if (watch != null) 'watch': watch!.toJson(),
      };
}

/// A fallback decision retaining exact input correlation.
final class PlacementBatchUseFallbackV1 extends PlacementBatchEntryV1 {
  /// Copies diagnostics and retains the admitted descriptor.
  PlacementBatchUseFallbackV1(
    super.descriptor,
    this.reason,
    List<PlacementBatchDiagnosticV1> diagnostics, {
    PlacementDeliveryWatchV1? watch,
  })  : diagnostics = _freezeDiagnostics(diagnostics),
        watch = watch == null
            ? null
            : PlacementDeliveryWatchV1.fromJson(watch.toJson()),
        super._() {
    if (this.watch != null &&
        (this.watch!.channels.length != 1 ||
            this.watch!.channels.single.scope != fallbackWatchScope)) {
      throw const CanonicalFormatException(
        'A fallback watch names only its own placement scope.',
      );
    }
    _requireResponseJsonBudget(toJson());
  }

  /// The placement's own policy scope, the only one a fallback watches.
  DeliveryPolicyScopeV1 get fallbackWatchScope => DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(descriptor.placement),
        family: const DeliveryFamilySelectorV1.none(),
      );

  /// Safe reason for falling back.
  final PlacementBatchRefusalReasonV1 reason;

  /// Bounded immutable diagnostics.
  final List<PlacementBatchDiagnosticV1> diagnostics;

  /// Optional live watch that reports when this placement may now deliver.
  final PlacementDeliveryWatchV1? watch;

  @override
  Map<String, Object?> toJson() => {
        'status': 'useFallback',
        'descriptor': descriptor.toJson(),
        'reason': reason.name,
        'diagnostics': [
          for (final diagnostic in diagnostics) diagnostic.toJson(),
        ],
        if (watch != null) 'watch': watch!.toJson(),
      };
}

/// A complete batch response or a refusal before any descriptor admission.
sealed class PlacementBatchResponseV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Validates ordered request correlation and complete content closure.
  factory PlacementBatchResponseV1({
    required PlacementBatchRequestV1 request,
    required TargetCoordinate expectedTarget,
    required List<PlacementBatchEntryV1> decisions,
    required List<PlacementBatchArtifactV1> artifacts,
    Map<ArtifactIdentityV1, List<int>> heldArtifactBytes,
    SurfaceRegistrationMetadataV1? registration,
  }) = PlacementBatchResolvedV1;

  PlacementBatchResponseV1._();

  /// Refuses the whole request before authenticated descriptor admission.
  factory PlacementBatchResponseV1.refused({
    required PlacementBatchRefusalReasonV1 reason,
    List<PlacementBatchDiagnosticV1> diagnostics,
    SurfaceRegistrationMetadataV1? registration,
  }) = PlacementBatchRefusedV1;

  /// Decodes strict response bytes and validates against the original request.
  factory PlacementBatchResponseV1.fromCanonicalBytes(
    List<int> bytes, {
    required PlacementBatchRequestV1 request,
    TargetCoordinate? expectedTarget,
    Map<ArtifactIdentityV1, List<int>> heldArtifactBytes = const {},
  }) {
    _requireSize(
      bytes.length,
      kMaximumPlacementResponseBytes,
      'Decoded response UTF-8',
    );
    return _construct(
      () => verifyCanonicalRoundTrip(
        PlacementBatchResponseV1.fromJson(
          CanonicalJsonCodec.decode(bytes),
          request: request,
          expectedTarget: expectedTarget,
          heldArtifactBytes: heldArtifactBytes,
        ),
        bytes,
        path: 'placementBatchResponse',
      ),
    );
  }

  /// Decodes a closed authenticated response, optionally pinning its target.
  /// Rows must share one target, inferred from the first row when not supplied.
  factory PlacementBatchResponseV1.fromJson(
    Object? value, {
    required PlacementBatchRequestV1 request,
    TargetCoordinate? expectedTarget,
    Map<ArtifactIdentityV1, List<int>> heldArtifactBytes = const {},
  }) {
    _requireSize(
      CanonicalJsonCodec.encode(value).length,
      kMaximumPlacementResponseBytes,
      'Decoded response UTF-8',
    );
    final json = requireCanonicalObject(value, 'placementBatchResponse');
    final status = requireCanonicalString(json['status'], 'response.status');
    final registration = SurfaceRegistrationMetadataV1.fromServeBody(json);
    _validateRegistrationConfirmation(request, registration);
    final result = _construct(() {
      if (status == 'refused') {
        final reader = _taggedBatchReader(
          json,
          'placementBatchResponse',
          const {'status', 'reason', 'diagnostics'},
          optional: _confirmationKeys,
        );
        return PlacementBatchRefusedV1(
          reason: PlacementBatchRefusalReasonV1.values
              .byName(reader.string('reason')),
          diagnostics: [
            for (final diagnostic in reader.list('diagnostics'))
              PlacementBatchDiagnosticV1.fromJson(diagnostic),
          ],
          registration: registration,
        );
      }
      if (status != 'resolved') {
        throw const CanonicalFormatException('Unknown response status.');
      }
      final reader = _taggedBatchReader(
        json,
        'placementBatchResponse',
        const {'status', 'decisions', 'artifacts'},
        optional: _confirmationKeys,
      );
      final decisions = [
        for (final decision in reader.list('decisions'))
          PlacementBatchEntryV1.fromJson(decision),
      ];
      final artifacts = [
        for (final artifact in reader.list('artifacts'))
          PlacementBatchArtifactV1.fromJson(artifact),
      ];
      final target = expectedTarget ??
          (decisions.isEmpty
              ? null
              : decisions.first.descriptor.placement.target);
      if (target == null) {
        if (request.mounts.isNotEmpty) {
          throw const CanonicalFormatException(
            'A batch needs one decision per mount.',
          );
        }
        if (artifacts.isNotEmpty) {
          throw const CanonicalFormatException(
            'Unreferenced transferred artifact.',
          );
        }
        return PlacementBatchResolvedV1._(const [], const [], registration);
      }
      return PlacementBatchResolvedV1(
        request: request,
        expectedTarget: target,
        decisions: decisions,
        artifacts: artifacts,
        heldArtifactBytes: heldArtifactBytes,
        registration: registration,
      );
    });
    if (!_sameJson(value, result.toJson())) {
      throw const CanonicalFormatException('Batch response is not canonical.');
    }
    return result;
  }

  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    _requireSize(
      bytes.length,
      kMaximumPlacementResponseBytes,
      'Decoded response UTF-8',
    );
    return bytes;
  }
}

/// One ordered result per mount and a deduplicated verified content transfer.
final class PlacementBatchResolvedV1 extends PlacementBatchResponseV1 {
  /// Checks every row and every reachable whole frame before admission.
  factory PlacementBatchResolvedV1({
    required PlacementBatchRequestV1 request,
    required TargetCoordinate expectedTarget,
    required List<PlacementBatchEntryV1> decisions,
    required List<PlacementBatchArtifactV1> artifacts,
    Map<ArtifactIdentityV1, List<int>> heldArtifactBytes = const {},
    SurfaceRegistrationMetadataV1? registration,
  }) {
    _validateRegistrationConfirmation(request, registration);
    if (decisions.length != request.mounts.length) {
      throw const CanonicalFormatException(
        'A batch needs one decision per mount.',
      );
    }
    final frozenDecisions = <PlacementBatchEntryV1>[];
    final publications = <String, Map<String, Object?>>{};
    for (var index = 0; index < decisions.length; index++) {
      final decision =
          PlacementBatchEntryV1.fromJson(decisions[index].toJson());
      decision.descriptor.validateForRequest(
        request.mounts[index],
        expectedTarget: expectedTarget,
      );
      if (decision is PlacementBatchAvailableV1 &&
          decision.publicDelivery.cacheValidity.installedCapabilityHash !=
              request.buildContract.installedCapabilityHash) {
        throw const CanonicalFormatException(
          'Decision capability hash disagrees.',
        );
      }
      if (decision is PlacementBatchAvailableV1) {
        for (final reference in decision.artifactClosure) {
          final publication = reference.publication;
          if (publication == null) continue;
          final key = utf8.decode(
            CanonicalJsonCodec.encode({
              'surface': publication.surface.toJson(),
              'publishedVersion': publication.publishedVersion,
            }),
          );
          final descriptor = reference.descriptor.toJson()
            ..remove('artifactPass')
            ..remove('artifactUrl');
          final coordinate = <String, Object?>{
            'publication': publication.toJson(),
            'descriptor': descriptor,
          };
          if (publications[key] case final previous?) {
            if (!_sameJson(previous, coordinate)) {
              throw const CanonicalFormatException(
                'Conflicting publication descriptors across decisions.',
              );
            }
          } else {
            publications[key] = coordinate;
          }
        }
      }
      frozenDecisions.add(decision);
    }
    final transferred = <ArtifactIdentityV1, PlacementBatchArtifactV1>{};
    for (final artifact in artifacts) {
      if (transferred.containsKey(artifact.identity)) {
        throw const CanonicalFormatException(
          'Duplicate transferred artifact identity.',
        );
      }
      transferred[artifact.identity] = artifact;
    }
    final available = <ArtifactIdentityV1, PlacementBatchArtifactV1>{
      ...transferred,
    };
    final needed = <ArtifactIdentityV1>{};
    var expandedBytes = 0;
    for (final decision
        in frozenDecisions.whereType<PlacementBatchAvailableV1>()) {
      for (final reference in decision.artifactClosure) {
        final identity = reference.identity;
        needed.add(identity);
        if (!available.containsKey(identity)) {
          final held = heldArtifactBytes[identity];
          if (!request.heldArtifacts.contains(identity) || held == null) {
            throw const CanonicalFormatException(
              'Missing artifact content closure.',
            );
          }
          available[identity] =
              PlacementBatchArtifactV1(identity: identity, bytes: held);
        }
      }
      expandedBytes += _validateReachableClosure(decision, available);
      _requireSize(
        expandedBytes,
        kMaximumPlacementExpandedClosureBytes,
        'Expanded selected closure',
      );
    }
    if (!needed.containsAll(transferred.keys)) {
      throw const CanonicalFormatException(
        'Unreferenced transferred artifact.',
      );
    }
    final sortedArtifacts = transferred.values.toList()
      ..sort(
        (a, b) =>
            _compareBytes(a.identity.canonicalBytes, b.identity.canonicalBytes),
      );
    final result = PlacementBatchResolvedV1._(
      List.unmodifiable(frozenDecisions),
      List.unmodifiable(sortedArtifacts),
      registration,
    );
    // Materialize the bounded original response before returning it.
    return result..canonicalBytes;
  }

  PlacementBatchResolvedV1._(this.decisions, this.artifacts, this.registration)
      : super._();

  /// Exact original input order, including correlated fallback rows.
  final List<PlacementBatchEntryV1> decisions;

  /// Content transferred once, in canonical identity order.
  final List<PlacementBatchArtifactV1> artifacts;

  /// Original folded credential confirmation, when registration succeeded.
  final SurfaceRegistrationMetadataV1? registration;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementBatchResponse',
        'schemaVersion': 1,
        'status': 'resolved',
        'decisions': [for (final decision in decisions) decision.toJson()],
        'artifacts': [for (final artifact in artifacts) artifact.toJson()],
        if (registration != null) ...registration!.toJson(),
      };
}

/// Whole-request refusal with no anonymous or dropped descriptor rows.
final class PlacementBatchRefusedV1 extends PlacementBatchResponseV1 {
  /// Creates a bounded refusal before descriptor admission.
  PlacementBatchRefusedV1({
    required this.reason,
    List<PlacementBatchDiagnosticV1> diagnostics = const [],
    this.registration,
  })  : diagnostics = _freezeDiagnostics(diagnostics),
        super._() {
    if (reason != PlacementBatchRefusalReasonV1.invalidAuthority &&
        reason != PlacementBatchRefusalReasonV1.unknownLocator &&
        reason != PlacementBatchRefusalReasonV1.invalidRequest) {
      throw const CanonicalFormatException(
        'Expected a request refusal reason.',
      );
    }
  }

  /// Optional original folded credential confirmation.
  final SurfaceRegistrationMetadataV1? registration;

  /// Safe reason for whole-request refusal.
  final PlacementBatchRefusalReasonV1 reason;

  /// Bounded immutable public diagnostics.
  final List<PlacementBatchDiagnosticV1> diagnostics;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementBatchResponse',
        'schemaVersion': 1,
        'status': 'refused',
        'reason': reason.name,
        'diagnostics': [
          for (final diagnostic in diagnostics) diagnostic.toJson(),
        ],
        if (registration != null) ...registration!.toJson(),
      };
}

const _confirmationKeys = {
  'credentialHandle',
  'expiresAtMicros',
  'serverNowMicros',
};

void _validateRegistrationConfirmation(
  PlacementBatchRequestV1 request,
  SurfaceRegistrationMetadataV1? registration,
) {
  if (registration == null) return;
  SurfaceRegistrationMetadataV1.fromJson(registration.toJson());
  if (request.mode != PlacementBatchModeV1.mount ||
      request.registration == null) {
    throw const CanonicalFormatException(
      'Unexpected registration confirmation.',
    );
  }
}

List<PlacementHeldAssignmentV1> _freezeHeldAssignments(
  List<PlacementHeldAssignmentV1> proofs,
  List<PlacementMountRequestV1> mounts,
) {
  final copied = <PlacementHeldAssignmentV1>[];
  final seen = <String>{};
  for (final proof in proofs) {
    final key = '${utf8.decode(proof.key.canonicalBytes)}\u0000'
        '${proof.hostContractHash}';
    if (!seen.add(key) ||
        !mounts.any(
          (mount) =>
              mount.key == proof.key &&
              mount.hostContractHash == proof.hostContractHash,
        )) {
      throw const CanonicalFormatException(
        'Held assignment is duplicated or unrequested.',
      );
    }
    copied.add(PlacementHeldAssignmentV1.fromJson(proof.toJson()));
  }
  _sortCanonical(copied);
  return List.unmodifiable(copied);
}

CanonicalDigest _domainDigest(String domain, Object? value) => CanonicalDigest(
      crypto.sha256.convert([
        ...utf8.encode('$domain\u0000'),
        ...CanonicalJsonCodec.encode(value),
      ]).toString(),
    );

void _requireSize(int size, int maximum, String field) {
  if (size > maximum) {
    throw CanonicalFormatException('$field exceeds $maximum bytes.');
  }
}

CanonicalObjectReader _unbudgetedReader(
  Object? value,
  Set<String> keys,
  String path,
) =>
    CanonicalObjectReader(
      requireCanonicalObject(value, path),
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );

CanonicalObjectReader _taggedBatchReader(
  Object? value,
  String kind,
  Set<String> keys, {
  Set<String> optional = const {},
}) {
  final reader = CanonicalObjectReader(
    requireCanonicalObject(value, kind),
    allowedKeys: {'kind', 'schemaVersion', ...keys, ...optional},
    requiredKeys: {'kind', 'schemaVersion', ...keys},
    path: kind,
  );
  if (reader.string('kind') != kind || reader.integer('schemaVersion') != 1) {
    throw CanonicalFormatException('Expected $kind version 1.');
  }
  return reader;
}

Uint8List _carrierBytes(String value, int maximumCharacters, String field) {
  _requireSize(value.length, maximumCharacters, '$field carrier');
  return _construct(
    () => SurfaceContractJson.decodeCanonicalBase64Url(value, field),
  );
}

void _validateUuid(String? value, String field) {
  if (value != null &&
      SurfaceScreenDeliveryRequest.normalizeMeteringKey(value) != value) {
    throw CanonicalFormatException('Invalid $field.');
  }
}

void _requireOpaqueReceipt(String value) {
  if (value.isEmpty ||
      value.length > 16 * 1024 ||
      RegExp(r'^[A-Za-z0-9._-]+$').stringMatch(value) != value) {
    throw const CanonicalFormatException('Invalid opaque routing receipt.');
  }
}

void _requireWatchToken(String value) {
  _requireSize(value.length, 16 * 1024, 'Watch token');
  final parts = value.split('.');
  final base64Url = RegExp(r'^[A-Za-z0-9_-]+$');
  if (parts.length != 5 ||
      parts[0] != 'v2' ||
      RegExp(r'^[A-Za-z0-9_-]{8}$').stringMatch(parts[1]) != parts[1] ||
      RegExp(r'^[1-9][0-9]*$').stringMatch(parts[2]) != parts[2] ||
      base64Url.stringMatch(parts[3]) != parts[3] ||
      parts[4].length != 43 ||
      base64Url.stringMatch(parts[4]) != parts[4]) {
    throw const CanonicalFormatException('Invalid watch token framing.');
  }
  final expiry = int.tryParse(parts[2]);
  if (expiry == null || expiry > kMaximumPortableJsonInteger) {
    throw const CanonicalFormatException('Invalid watch token expiry shape.');
  }
  _construct(() {
    utf8.decode(
      SurfaceContractJson.decodeCanonicalBase64Url(parts[3], 'watch.channel'),
    );
    final mac = SurfaceContractJson.decodeCanonicalBase64Url(
      parts[4],
      'watch.mac',
    );
    if (mac.length != 32) {
      throw const CanonicalFormatException('Invalid watch token MAC shape.');
    }
  });
}

List<PlacementDeliveryWatchChannelV1> _freezeDeliveryWatchChannels(
  List<PlacementDeliveryWatchChannelV1> channels,
) {
  final byScope = <DeliveryPolicyScopeV1, PlacementDeliveryWatchChannelV1>{};
  TargetCoordinate? target;
  for (final channel in channels) {
    final snapshot = PlacementDeliveryWatchChannelV1.fromJson(channel.toJson());
    target ??= snapshot.scope.target;
    if (snapshot.scope.target != target ||
        byScope.containsKey(snapshot.scope)) {
      throw const CanonicalFormatException(
        'Watch scope is duplicated or belongs to another target.',
      );
    }
    byScope[snapshot.scope] = snapshot;
  }
  return List.unmodifiable([
    for (final scope in freezeDeliveryDependencyClosureV1(byScope.keys))
      byScope[scope]!,
  ]);
}

List<PlacementBatchDiagnosticV1> _freezeDiagnostics(
  List<PlacementBatchDiagnosticV1> diagnostics,
) {
  if (diagnostics.length > 64) {
    throw const CanonicalFormatException('Too many diagnostics.');
  }
  return List.unmodifiable([
    for (final diagnostic in diagnostics)
      PlacementBatchDiagnosticV1.fromJson(diagnostic.toJson()),
  ]);
}

List<PlacementArtifactReferenceV1> _freezeArtifactClosure(
  List<PlacementArtifactReferenceV1> references,
) {
  final copied = <PlacementArtifactReferenceV1>[];
  final seen = <String>{};
  for (final reference in references) {
    final publication = reference.publication;
    final key = utf8.decode(
      CanonicalJsonCodec.encode(
        publication == null
            ? {
                'dependency': {
                  'surfaceSlug': reference.descriptor.surfaceSlug,
                  'version': reference.descriptor.version,
                },
              }
            : {
                'publication': {
                  'surface': publication.surface.toJson(),
                  'publishedVersion': publication.publishedVersion,
                },
              },
      ),
    );
    if (!seen.add(key)) {
      throw const CanonicalFormatException(
        'Duplicate or conflicting artifact closure.',
      );
    }
    copied.add(PlacementArtifactReferenceV1.fromJson(reference.toJson()));
  }
  _sortCanonical(copied);
  return List.unmodifiable(copied);
}

int _validateReachableClosure(
  PlacementBatchAvailableV1 decision,
  Map<ArtifactIdentityV1, PlacementBatchArtifactV1> content,
) {
  final reached = <PlacementArtifactReferenceV1>{};
  final active = <PlacementArtifactReferenceV1>{};
  final root = decision.artifactClosure.singleWhere(
    (ref) => ref.publication == decision.publicDelivery.actualPublication,
  );
  final rootContentKind = switch (content[root.identity]!._payload) {
    FlowSurfacePayload() => SurfaceContentKindV1.flow,
    BlobSurfacePayload() => SurfaceContentKindV1.single,
  };
  if (decision.publicDelivery.fitRequirement.hosting.contentKind !=
      rootContentKind) {
    throw const CanonicalFormatException(
      'Fit requirement disagrees with root artifact content kind.',
    );
  }
  final pending = <(PlacementArtifactReferenceV1, bool)>[(root, false)];
  var bytes = 0;
  while (pending.isNotEmpty) {
    final (reference, exit) = pending.removeLast();
    if (exit) {
      active.remove(reference);
      continue;
    }
    if (!active.add(reference)) {
      throw const CanonicalFormatException('Cyclic artifact closure.');
    }
    reached.add(reference);
    final artifact = content[reference.identity]!;
    final payload = artifact._payload;
    if (reference.descriptor.payloadKind != null &&
        reference.descriptor.payloadKind != payload.payloadKind) {
      throw const CanonicalFormatException('Artifact payload kind mismatch.');
    }
    bytes += artifact.decodedByteLength;
    _requireSize(
      bytes,
      kMaximumPlacementExpandedClosureBytes,
      'Expanded selected closure',
    );
    pending.add((reference, true));
    if (payload is FlowSurfacePayload) {
      for (final state
          in payload.flowDocument.states.values.whereType<SubFlowState>()) {
        final matches = decision.artifactClosure.where((candidate) {
          final candidatePayload = content[candidate.identity]!._payload;
          return candidate.descriptor.surfaceSlug == state.flow &&
              candidate.descriptor.version == state.version &&
              candidatePayload is FlowSurfacePayload &&
              candidatePayload.flowDocument.flow == state.flow &&
              candidatePayload.flowDocument.version == state.version &&
              candidatePayload.flowDocument.schemaVersion ==
                  state.schemaVersion &&
              candidatePayload.flowDocument.minClient == state.minClient &&
              FlowContentHash.compute(
                    FlowDocumentCodec.encodeCanonicalJson(
                      candidatePayload.flowDocument,
                    ),
                  ) ==
                  state.contentHash;
        }).toList();
        if (matches.length != 1) {
          throw const CanonicalFormatException(
            'Missing or ambiguous subflow closure.',
          );
        }
        pending.add((matches.single, false));
      }
    }
  }
  if (reached.length != decision.artifactClosure.length) {
    throw const CanonicalFormatException('Unreachable artifact closure entry.');
  }
  return bytes;
}

abstract base class _DeliveryValue extends CanonicalValue
    implements ImmutableCanonicalDocument {
  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    _requireSize(
      bytes.length,
      kMaximumPlacementResponseBytes,
      'Public delivery UTF-8',
    );
    return bytes;
  }
}

void _requireResponseJsonBudget(Object? value) => _requireSize(
      CanonicalJsonCodec.encode(value).length,
      kMaximumPlacementResponseBytes,
      'Public delivery UTF-8',
    );

CanonicalObjectReader _deliveryReader(
  Object? value,
  Set<String> keys,
  String path, {
  Set<String> optional = const {},
}) {
  final json = requireCanonicalObject(value, path);
  _requireResponseJsonBudget(json);
  return CanonicalObjectReader(
    json,
    allowedKeys: {...keys, ...optional},
    requiredKeys: keys,
    path: path,
  );
}

T _decodeDelivery<T extends CanonicalValue>(
  List<int> bytes,
  T Function(Object?) read,
) {
  _requireSize(
    bytes.length,
    kMaximumPlacementResponseBytes,
    'Public delivery UTF-8',
  );
  return _construct(
    () => verifyCanonicalRoundTrip(
      read(CanonicalJsonCodec.decode(bytes)),
      bytes,
      path: 'publicDelivery',
    ),
  );
}

abstract base class _PlacementValue extends CanonicalValue
    implements ImmutableCanonicalDocument {
  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    _requireByteBudget(bytes.length);
    return bytes;
  }
}

CanonicalObjectReader _reader(Object? value, Set<String> keys, String path) {
  final json = requireCanonicalObject(value, path);
  _requireJsonBudget(json);
  return CanonicalObjectReader(
    json,
    allowedKeys: keys,
    requiredKeys: keys,
    path: path,
  );
}

T _decode<T extends CanonicalValue>(List<int> bytes, T Function(Object?) read) {
  _requireByteBudget(bytes.length);
  return _construct(
    () => verifyCanonicalRoundTrip(
      read(CanonicalJsonCodec.decode(bytes)),
      bytes,
      path: 'placement',
    ),
  );
}

T _construct<T>(T Function() build) {
  try {
    return build();
  } on FormatException catch (error) {
    throw CanonicalFormatException(error.message);
    // Constructor validators retain their own types outside decoding.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('${error.message}');
  }
}

void _requireContentHash(String value, String field) {
  if (!value.startsWith('sha256:')) {
    throw CanonicalFormatException('$field requires a sha256: content hash.');
  }
  _construct(() => CanonicalDigest(value.substring('sha256:'.length)));
}

void _requireNonnegative(int value, String field) {
  if (value < 0 || value > kMaximumPortableJsonInteger) {
    throw CanonicalFormatException(
      '$field must be a nonnegative portable integer.',
    );
  }
}

void _requirePlatform(String platform) {
  // Reuse the existing bounded lowercase token grammar without closing the
  // set of runtime platforms to whichever ones happen to be installed today.
  _construct(() => DeliverySurfaceTypeId(platform));
}

List<PlacementMountRequestV1> _canonicalMounts(
  List<PlacementMountRequestV1> input,
) {
  final declarations = <(PlacementKeyV1, String), PlacementMountRequestV1>{};
  for (final mount in input) {
    final identity = (mount.key, mount.hostContractHash);
    final previous = declarations[identity];
    if (previous != null && previous != mount) {
      throw const CanonicalFormatException(
        'A key and host contract cannot declare conflicting default surfaces.',
      );
    }
    declarations[identity] = mount;
  }
  final mounts = declarations.values.toList();
  _sortCanonical(mounts);
  return List.unmodifiable(mounts);
}

List<PlacementMountBoundsV1> _canonicalBounds(
  List<PlacementMountBoundsV1> input,
) {
  final occurrences = <(PlacementKeyV1, String, int)>{};
  for (final bound in input) {
    if (!occurrences
        .add((bound.key, bound.hostContractHash, bound.occurrenceIndex))) {
      throw const CanonicalFormatException(
        'Bounds must have unique key/host/occurrence identities.',
      );
    }
  }
  final bounds = List<PlacementMountBoundsV1>.of(input);
  _sortCanonical(bounds);
  return List.unmodifiable(bounds);
}

void _sortCanonical<T extends CanonicalValue>(List<T> values) {
  final bytes = {for (final value in values) value: value.canonicalBytes};
  values.sort((left, right) => _compareBytes(bytes[left]!, bytes[right]!));
}

int _compareBytes(List<int> left, List<int> right) {
  final count = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < count; index++) {
    if (left[index] != right[index]) return left[index] - right[index];
  }
  return left.length - right.length;
}

InstalledCapability _strictCapability(Map<String, Object?> json) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {
      'builtInCatalogVersion',
      'installedLibraries',
      'vocabulary',
    },
    requiredKeys: const {'builtInCatalogVersion', 'installedLibraries'},
    path: 'installedCapability',
  );
  final catalogVersion = reader.integer('builtInCatalogVersion');
  if (catalogVersion <= 0 || catalogVersion > kMaximumPortableJsonInteger) {
    throw const CanonicalFormatException(
      'The built-in catalog version must be positive and portable.',
    );
  }
  final namespaces = <String>{};
  for (final raw in reader.list('installedLibraries')) {
    final library = CanonicalObjectReader(
      requireCanonicalObject(raw, 'installedLibrary'),
      allowedKeys: const {'namespace', 'version', 'compatibleSince'},
      requiredKeys: const {'namespace', 'version'},
      path: 'installedLibrary',
    );
    final namespace = library.string('namespace');
    if (!WidgetLibrary.isValidNamespace(namespace) ||
        !namespaces.add(namespace)) {
      throw const CanonicalFormatException(
        'Installed library namespaces must be valid and unique.',
      );
    }
    final version = library.requiredNullableValue('version');
    if (version != null &&
        (version is! int ||
            version <= 0 ||
            version > kMaximumPortableJsonInteger)) {
      throw const CanonicalFormatException(
        'An installed version must be null or a positive portable integer.',
      );
    }
    if (library.value('compatibleSince') != null ||
        requireCanonicalObject(raw, 'installedLibrary')
            .containsKey('compatibleSince')) {
      if (!InstalledLibrary.isValidCompatibleSince(
        library.value('compatibleSince'),
        version as int?,
      )) {
        throw const CanonicalFormatException(
          'compatibleSince must be a positive installed version floor.',
        );
      }
    }
  }
  final vocabulary = reader.optionalObject('vocabulary');
  if (vocabulary != null) {
    final vocabularyReader = CanonicalObjectReader(
      vocabulary,
      allowedKeys: const {'widgetNames', 'iconCodePoints'},
      requiredKeys: const {'widgetNames', 'iconCodePoints'},
      path: 'vocabulary',
    );
    for (final name in vocabularyReader.list('widgetNames')) {
      requireCanonicalString(name, 'vocabulary.widgetNames');
    }
    for (final raw in vocabularyReader.object('iconCodePoints').values) {
      if (raw is! List<Object?> || raw.any((point) => point is! int)) {
        throw const CanonicalFormatException(
          'Icon code points must be integer lists.',
        );
      }
    }
  }
  final result = _construct(() => InstalledCapability.fromJson(json));
  // The capability owner supplies hashing and ordering. Refuse aliases rather
  // than silently changing supplied vocabulary, library order or version floor.
  if (!_sameJson(json, result.toJson())) {
    throw const CanonicalFormatException(
      'The installed capability must use its canonical wire representation.',
    );
  }
  return result;
}

bool _sameJson(Object? left, Object? right) =>
    _compareBytes(
      CanonicalJsonCodec.encode(left),
      CanonicalJsonCodec.encode(right),
    ) ==
    0;

void _requireByteBudget(int length) {
  if (length > kMaximumPlacementRequestBytes) {
    throw const CanonicalFormatException(
      'Placement transport exceeds 524288 canonical UTF-8 bytes.',
    );
  }
}

void _requireJsonBudget(Object? value) => _JsonBudget().addJson(value);

// Count before encoding or copying. Iterators keep allocation proportional to
// nesting rather than to an untrusted collection's declared length.
final class _JsonBudget {
  var _bytes = 0;

  void _add(int count) {
    _bytes += count;
    _requireByteBudget(_bytes);
  }

  void addListFraming(int count) => _add(2 + (count == 0 ? 0 : count - 1));

  void addObjectFraming(int count) =>
      _add(2 + (count == 0 ? 0 : 2 * count - 1));

  void addCapability(InstalledCapability value) {
    final vocabulary = value.vocabulary;
    addObjectFraming(vocabulary == null ? 2 : 3);
    addJson('builtInCatalogVersion');
    addJson(value.builtInCatalogVersion);
    addJson('installedLibraries');
    addListFraming(value.installedLibraries.length);
    for (final library in value.installedLibraries) {
      addJson(library.toJson());
    }
    if (vocabulary == null) return;
    addJson('vocabulary');
    addObjectFraming(2);
    addJson('widgetNames');
    addListFraming(vocabulary.widgetNames.length);
    vocabulary.widgetNames.forEach(addJson);
    addJson('iconCodePoints');
    addObjectFraming(vocabulary.iconCodePoints.length);
    for (final entry in vocabulary.iconCodePoints.entries) {
      addJson(entry.key);
      addListFraming(entry.value.length);
      entry.value.forEach(addJson);
    }
  }

  void addJson(Object? value) {
    final pending = <Iterator<Object?>>[
      <Object?>[value].iterator,
    ];
    while (pending.isNotEmpty) {
      final iterator = pending.last;
      if (!iterator.moveNext()) {
        pending.removeLast();
        continue;
      }
      switch (iterator.current) {
        case Map<String, Object?>():
          final object = iterator.current! as Map<String, Object?>;
          addObjectFraming(object.length);
          object.keys.forEach(_addString);
          pending.add(object.values.iterator);
        case List<Object?>():
          final list = iterator.current! as List<Object?>;
          addListFraming(list.length);
          pending.add(list.iterator);
        case String():
          _addString(iterator.current! as String);
        default:
          _add(CanonicalJsonCodec.encode(iterator.current).length);
      }
    }
  }

  void _addString(String value) {
    // UTF-16 length is a lower bound on canonical UTF-8 string length.
    _requireByteBudget(_bytes + value.length + 2);
    _add(CanonicalJsonCodec.encode(value).length);
  }
}
