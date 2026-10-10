import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'package:restage_shared/src/capability/surface_fit.dart';
import 'package:restage_shared/src/placements/placement_delivery.dart';
import 'package:restage_shared/src/placements/placement_history.dart';
import 'package:restage_shared/src/placements/placement_screen_sample.dart';

/// Maximum number of placement keys in a management read.
const kMaximumPlacementManagementEntries = 200;

/// Maximum canonical request size for placement management.
const kMaximumPlacementManagementRequestBytes = 524288;

/// A bounded directory read for one exact authenticated target.
final class PlacementDirectoryRequestV1 extends _ManagementRequest {
  /// Creates a page request with an optional target-bound continuation.
  PlacementDirectoryRequestV1({
    required this.target,
    this.cursor,
    this.limit = 50,
  }) {
    _requireLimit(limit);
    _requireCursor(cursor);
  }

  /// Decodes a closed directory request.
  factory PlacementDirectoryRequestV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(
      json,
      'placementDirectoryRequest',
      const {'target', 'limit'},
      optional: const {'cursor'},
    );
    return PlacementDirectoryRequestV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      limit: reader.integer('limit'),
      cursor: reader.optionalString('cursor'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementDirectoryRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementDirectoryRequestV1.fromJson);

  /// Requested coordinates; admission remains server-owned.
  final TargetCoordinate target;

  /// Opaque continuation bound to the exact target and source cut.
  final String? cursor;

  /// Maximum number of entries returned by this read.
  final int limit;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementDirectoryRequest',
        'schemaVersion': 1,
        'target': target.toJson(),
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      };
}

/// One exact placement and optional observed-history read.
final class PlacementReadRequestV1 extends _ManagementRequest {
  /// Creates a detail request without granting access to its locators.
  PlacementReadRequestV1({
    required this.target,
    required this.key,
    this.observedHistory,
    this.historyCursor,
  }) {
    _requireCursor(historyCursor);
    if (observedHistory != null && observedHistory!.placement != key) {
      throw const CanonicalFormatException(
        'Observed history must address the requested placement.',
      );
    }
  }

  /// Decodes a closed placement detail request.
  factory PlacementReadRequestV1.fromJson(Map<String, Object?> json) {
    final reader = _reader(
      json,
      'placementReadRequest',
      const {'target', 'key'},
      optional: const {'observedHistory', 'historyCursor'},
    );
    final history = reader.optionalObject('observedHistory');
    return PlacementReadRequestV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      key: PlacementKeyV1.fromJson(reader.object('key')),
      observedHistory: history == null
          ? null
          : PlacementObservedHistoryQueryV1.fromJson(history),
      historyCursor: reader.optionalString('historyCursor'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementReadRequestV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementReadRequestV1.fromJson);

  /// Requested exact target.
  final TargetCoordinate target;

  /// Namespace-qualified placement key.
  final PlacementKeyV1 key;

  /// Optional bounded UTC history query for this same placement.
  final PlacementObservedHistoryQueryV1? observedHistory;

  /// Opaque immutable policy-history continuation.
  final String? historyCursor;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementReadRequest',
        'schemaVersion': 1,
        'target': target.toJson(),
        'key': key.toJson(),
        if (observedHistory != null)
          'observedHistory': observedHistory!.toJson(),
        if (historyCursor != null) 'historyCursor': historyCursor,
      };
}

/// An authenticated observed first-paint query for one exact target.
final class PlacementObservedHistoryReadRequestV1 extends _ManagementRequest {
  /// Creates an observed-history read envelope.
  const PlacementObservedHistoryReadRequestV1({
    required this.target,
    required this.query,
  });

  /// Decodes a closed observed-history request.
  factory PlacementObservedHistoryReadRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = _reader(
      json,
      'placementObservedHistoryReadRequest',
      const {'target', 'query'},
    );
    return PlacementObservedHistoryReadRequestV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      query: PlacementObservedHistoryQueryV1.fromJson(reader.object('query')),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementObservedHistoryReadRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decode(bytes, PlacementObservedHistoryReadRequestV1.fromJson);

  /// Requested exact target.
  final TargetCoordinate target;

  /// Bounded UTC query interpreted by the observed-history authority.
  final PlacementObservedHistoryQueryV1 query;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementObservedHistoryReadRequest',
        'schemaVersion': 1,
        'target': target.toJson(),
        'query': query.toJson(),
      };
}

/// A read-only serving probe over an explicit bounded set of placement keys.
final class PlacementSimulationPageRequestV1 extends _ManagementRequest {
  /// Freezes ordered unique keys and one shared serving input value.
  PlacementSimulationPageRequestV1({
    required this.target,
    required List<PlacementKeyV1> keys,
    required this.inputs,
    this.cursor,
  }) : keys = List.unmodifiable(keys) {
    _requireLimit(keys.length);
    _requireCursor(cursor);
    if (keys.toSet().length != keys.length) {
      throw const CanonicalFormatException(
        'Simulation keys must be unique.',
      );
    }
    _requireByteBudget(CanonicalJsonCodec.encode(toJson()).length);
  }

  /// Decodes a closed page simulation request.
  factory PlacementSimulationPageRequestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = _reader(
      json,
      'placementSimulationPageRequest',
      const {'target', 'keys', 'inputs'},
      optional: const {'cursor'},
    );
    final keys = reader.list('keys');
    _requireLimit(keys.length);
    return PlacementSimulationPageRequestV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      keys: [
        for (final key in keys)
          PlacementKeyV1.fromJson(requireCanonicalObject(key, 'keys[]')),
      ],
      inputs: DeliverySimulationInputsV1.fromJson(reader.object('inputs')),
      cursor: reader.optionalString('cursor'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementSimulationPageRequestV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      _decode(bytes, PlacementSimulationPageRequestV1.fromJson);

  /// Requested exact target.
  final TargetCoordinate target;

  /// Explicit keys in requested probe order.
  final List<PlacementKeyV1> keys;

  /// One serving-owned simulation input value used for every key.
  final DeliverySimulationInputsV1 inputs;

  /// Opaque continuation bound to the keys, inputs, target and authority cut.
  final String? cursor;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementSimulationPageRequest',
        'schemaVersion': 1,
        'target': target.toJson(),
        'keys': [for (final key in keys) key.toJson()],
        'inputs': inputs.toJson(),
        if (cursor != null) 'cursor': cursor,
      };
}

/// Qualification of one bounded directory read.
enum PlacementDirectoryStatusV1 {
  /// The requested page was acquired from its admitted source.
  available,

  /// The exact target has no registered placement declarations.
  noDiscoveries,

  /// The continuation belongs to different coordinates or request inputs.
  cursorQueryMismatch,

  /// Source authority changed since the continuation was issued.
  cursorStale,

  /// The requested authority exceeds the bounded read capacity.
  resourceLimitExceeded,

  /// Retained authority could not be qualified.
  authorityUnavailable,
}

/// Qualification of the immutable source closure requested by a detail read.
enum PlacementAuthorityStatusV1 {
  /// Every retained reference was acquired and qualified.
  available,

  /// The requested source closure could not be qualified.
  unavailable,

  /// The closure exceeded its bounded read capacity.
  resourceLimitExceeded,
}

/// Freshness of a declared build, independently of uploaded screen samples.
enum PlacementBuildFreshnessV1 {
  /// Authored declaration with no authenticated SDK observation.
  unreported,

  /// An SDK observation lies within the server's reporting census.
  reporting,

  /// The retained observation predates the server's reporting cutoff.
  stale,
}

/// Availability of an authored screen association.
enum PlacementDirectorySampleStatusV1 {
  /// No authored screen association has been registered.
  absent,

  /// A current frame head points to a readable private sample.
  bound,

  /// A deleted frame head retains its association revision.
  removed,
}

/// Exact page clocks and a digest of the retained source generation.
final class PlacementManagementCutV1 extends _ManagementResult {
  /// Preserves the admitted census clock and published Measurement cut.
  PlacementManagementCutV1({
    required this.asOfMicros,
    required this.publicationGeneration,
    required this.publishedAsOfMicros,
    required this.validUntilMicros,
    required this.sourceDigest,
  }) {
    _requireNonnegative(asOfMicros, 'asOfMicros');
    _requireNonnegative(publicationGeneration, 'publicationGeneration');
    _requireNonnegative(publishedAsOfMicros, 'publishedAsOfMicros');
    _requireNonnegative(validUntilMicros, 'validUntilMicros');
    CanonicalDigest(sourceDigest);
    if (publishedAsOfMicros > asOfMicros || validUntilMicros < asOfMicros) {
      throw const CanonicalFormatException('Invalid placement management cut.');
    }
  }

  /// Decodes a closed authority cut.
  factory PlacementManagementCutV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(json, 'placementManagementCut', const {
      'asOfMicros',
      'publicationGeneration',
      'publishedAsOfMicros',
      'validUntilMicros',
      'sourceDigest',
    });
    return PlacementManagementCutV1(
      asOfMicros: r.integer('asOfMicros'),
      publicationGeneration: r.integer('publicationGeneration'),
      publishedAsOfMicros: r.integer('publishedAsOfMicros'),
      validUntilMicros: r.integer('validUntilMicros'),
      sourceDigest: r.string('sourceDigest'),
    );
  }

  /// UTC timestamp of the admitted census and sample snapshot.
  final int asOfMicros;

  /// Adopted Measurement publication generation, or zero before adoption.
  final int publicationGeneration;

  /// UTC timestamp of the published observed-history population.
  final int publishedAsOfMicros;

  /// Expiry of that exact published population.
  final int validUntilMicros;

  /// SHA-256 generation digest binding the bounded source facts.
  final String sourceDigest;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementManagementCut',
        'schemaVersion': 1,
        'asOfMicros': asOfMicros,
        'publicationGeneration': publicationGeneration,
        'publishedAsOfMicros': publishedAsOfMicros,
        'validUntilMicros': validUntilMicros,
        'sourceDigest': sourceDigest,
      };
}

/// Safe declared host shape and dated reporting facts for one exact build.
final class PlacementDirectoryBuildV1 extends _ManagementResult {
  /// Requires observed timestamps to agree with the declaration and geometry.
  PlacementDirectoryBuildV1({
    required this.appBuildContractHash,
    required this.platform,
    required this.mount,
    required this.hostContract,
    required this.freshness,
    this.buildOrdinal,
    this.firstObservedAtMicros,
    this.lastObservedAtMicros,
    this.geometry,
  }) {
    _requireHash(appBuildContractHash);
    DeliverySurfaceTypeId(platform);
    if (buildOrdinal != null) {
      _requireNonnegative(buildOrdinal!, 'buildOrdinal');
    }
    if (mount.hostContractHash != hostContract.contentHash ||
        (firstObservedAtMicros == null) != (lastObservedAtMicros == null) ||
        (freshness == PlacementBuildFreshnessV1.unreported) !=
            (lastObservedAtMicros == null)) {
      throw const CanonicalFormatException('Invalid declared build facts.');
    }
    if (firstObservedAtMicros != null) {
      _requireNonnegative(firstObservedAtMicros!, 'firstObservedAtMicros');
      _requireNonnegative(lastObservedAtMicros!, 'lastObservedAtMicros');
      if (firstObservedAtMicros! > lastObservedAtMicros!) {
        throw const CanonicalFormatException(
          'Invalid build observation order.',
        );
      }
    }
    if (geometry != null &&
        (lastObservedAtMicros == null ||
            geometry!.appBuildContractHash != appBuildContractHash ||
            geometry!.serverObservedAtMicros > lastObservedAtMicros! ||
            geometry!.mounts.any(
              (bound) =>
                  bound.key != mount.key ||
                  bound.hostContractHash != mount.hostContractHash,
            ))) {
      throw const CanonicalFormatException(
        'Geometry belongs to another build.',
      );
    }
  }

  /// Decodes a closed build summary without host data values.
  factory PlacementDirectoryBuildV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementDirectoryBuild',
      const {
        'appBuildContractHash',
        'platform',
        'mount',
        'hostContract',
        'freshness',
      },
      optional: const {
        'buildOrdinal',
        'firstObservedAtMicros',
        'lastObservedAtMicros',
        'geometry',
      },
    );
    final geometry = r.optionalObject('geometry');
    return PlacementDirectoryBuildV1(
      appBuildContractHash: r.string('appBuildContractHash'),
      platform: r.string('platform'),
      mount: PlacementMountRequestV1.fromJson(r.object('mount')),
      hostContract: SurfaceHostContractV1.fromJson(r.object('hostContract')),
      freshness: _enum(r.string('freshness'), PlacementBuildFreshnessV1.values),
      buildOrdinal: r.optionalInteger('buildOrdinal'),
      firstObservedAtMicros: r.optionalInteger('firstObservedAtMicros'),
      lastObservedAtMicros: r.optionalInteger('lastObservedAtMicros'),
      geometry: geometry == null
          ? null
          : PlacementReportedGeometryV1.fromJson(geometry),
    );
  }

  /// Immutable offline build identity.
  final String appBuildContractHash;

  /// Canonical runtime platform token.
  final String platform;

  /// Build ordinal, absent when the app supplied none.
  final int? buildOrdinal;

  /// Exact declared placement key, host hash and optional default locator.
  final PlacementMountRequestV1 mount;

  /// Safe host shape, containing no observed host values.
  final SurfaceHostContractV1 hostContract;

  /// Qualification under the server-owned reporting cutoff.
  final PlacementBuildFreshnessV1 freshness;

  /// First authenticated server observation, absent for declarations only.
  final int? firstObservedAtMicros;

  /// Last authenticated server observation, absent for declarations only.
  final int? lastObservedAtMicros;

  /// Separately dated layout facts in their own reported frame.
  final PlacementReportedGeometryV1? geometry;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementDirectoryBuild',
        'schemaVersion': 1,
        'appBuildContractHash': appBuildContractHash,
        'platform': platform,
        'mount': mount.toJson(),
        'hostContract': hostContract.toJson(),
        'freshness': freshness.name,
        if (buildOrdinal != null) 'buildOrdinal': buildOrdinal,
        if (firstObservedAtMicros != null)
          'firstObservedAtMicros': firstObservedAtMicros,
        if (lastObservedAtMicros != null)
          'lastObservedAtMicros': lastObservedAtMicros,
        if (geometry != null) 'geometry': geometry!.toJson(),
      };
}

/// One namespace-qualified placement with its admitted native authority.
final class PlacementDirectoryItemV1 extends _ManagementResult {
  /// Preserves complete target agreement across policy, builds and sample.
  PlacementDirectoryItemV1({
    required this.key,
    required this.policy,
    required List<PlacementDirectoryBuildV1> builds,
    required this.sampleStatus,
    required this.canEdit,
    required this.canManageSamples,
    this.sample,
  }) : builds = List.unmodifiable(builds) {
    final identity = policy.scope.root.placement;
    if (identity == null ||
        identity.key != key ||
        !policy.rootPresent ||
        builds.any((build) => build.mount.key != key) ||
        (sampleStatus == PlacementDirectorySampleStatusV1.bound) !=
            (sample != null) ||
        (sample != null && sample!.target != identity.target)) {
      throw const CanonicalFormatException(
        'Placement item authority disagrees.',
      );
    }
    final seen = <(String, String)>{};
    for (final build in builds) {
      if (!seen
          .add((build.appBuildContractHash, build.mount.hostContractHash))) {
        throw const CanonicalFormatException('Duplicate placement build.');
      }
    }
  }

  /// Decodes a closed placement item.
  factory PlacementDirectoryItemV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementDirectoryItem',
      const {
        'key',
        'policy',
        'builds',
        'sampleStatus',
        'canEdit',
        'canManageSamples',
      },
      optional: const {
        'sample',
      },
    );
    final sample = r.optionalObject('sample');
    return PlacementDirectoryItemV1(
      key: PlacementKeyV1.fromJson(r.object('key')),
      policy: DeliveryPolicyReadV1.fromJson(r.object('policy')),
      builds: [
        for (final build in r.list('builds'))
          PlacementDirectoryBuildV1.fromJson(
            requireCanonicalObject(build, 'builds[]'),
          ),
      ],
      sampleStatus: _enum(
        r.string('sampleStatus'),
        PlacementDirectorySampleStatusV1.values,
      ),
      canEdit: r.boolean('canEdit'),
      canManageSamples: r.boolean('canManageSamples'),
      sample:
          sample == null ? null : PlacementScreenSampleRefV1.fromJson(sample),
    );
  }

  /// Canonical key; equal visible labels retain distinct namespaces.
  final PlacementKeyV1 key;

  /// Exact current policy or proved absence of a configured policy head.
  final DeliveryPolicyReadV1 policy;

  /// Qualified authored declarations and dated SDK reporting facts.
  final List<PlacementDirectoryBuildV1> builds;

  /// Current authored frame availability.
  final PlacementDirectorySampleStatusV1 sampleStatus;

  /// Optional authorized image reference; pages contain no image bytes.
  final PlacementScreenSampleRefV1? sample;

  /// Current actor's admitted policy-authoring capability.
  final bool canEdit;

  /// Current actor's admitted authored-sample capability.
  final bool canManageSamples;

  /// Human-facing label within its canonical namespace.
  String get label => key.slug;

  /// Namespace discriminator for labels that collide.
  String get namespace => key.isGeneratedDefault ? 'generatedDefault' : 'named';

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementDirectoryItem',
        'schemaVersion': 1,
        'key': key.toJson(),
        'policy': policy.toJson(),
        'builds': [for (final build in builds) build.toJson()],
        'sampleStatus': sampleStatus.name,
        'canEdit': canEdit,
        'canManageSamples': canManageSamples,
        if (sample != null) 'sample': sample!.toJson(),
      };
}

/// A bounded directory page from one admitted census and sample snapshot.
final class PlacementDirectoryPageV1 extends _ManagementResult {
  /// Requires every item to belong to the page's exact target.
  PlacementDirectoryPageV1({
    required this.target,
    required this.cut,
    required this.reportingCutoffMicros,
    required this.status,
    required List<PlacementDirectoryItemV1> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items) {
    _requireNonnegative(reportingCutoffMicros, 'reportingCutoffMicros');
    _requireCursor(nextCursor);
    if (items.length > kMaximumPlacementManagementEntries ||
        items.any((item) => item.policy.scope.target != target) ||
        items.map((item) => item.key).toSet().length != items.length ||
        (status != PlacementDirectoryStatusV1.available &&
            (items.isNotEmpty || nextCursor != null)) ||
        reportingCutoffMicros > cut.asOfMicros) {
      throw const CanonicalFormatException('Invalid placement directory page.');
    }
  }

  /// Decodes a closed directory result.
  factory PlacementDirectoryPageV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementDirectoryPage',
      const {
        'target',
        'cut',
        'reportingCutoffMicros',
        'status',
        'items',
      },
      optional: const {
        'nextCursor',
      },
    );
    return PlacementDirectoryPageV1(
      target: TargetCoordinate.fromJson(r.object('target')),
      cut: PlacementManagementCutV1.fromJson(r.object('cut')),
      reportingCutoffMicros: r.integer('reportingCutoffMicros'),
      status: _enum(r.string('status'), PlacementDirectoryStatusV1.values),
      items: [
        for (final item in r.list('items'))
          PlacementDirectoryItemV1.fromJson(
            requireCanonicalObject(item, 'items[]'),
          ),
      ],
      nextCursor: r.optionalString('nextCursor'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementDirectoryPageV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeResult(bytes, PlacementDirectoryPageV1.fromJson);

  /// Exact admitted target.
  final TargetCoordinate target;

  /// Clocks and native source generation shared by all page families.
  final PlacementManagementCutV1 cut;

  /// Fixed server reporting-census cutoff, separate from analytics retention.
  final int reportingCutoffMicros;

  /// Distinguishes real empty discovery from unavailable authority.
  final PlacementDirectoryStatusV1 status;

  /// Entries in stable canonical key order.
  final List<PlacementDirectoryItemV1> items;

  /// Opaque continuation for this target, filter and source generation.
  final String? nextCursor;

  /// UTC timestamp of the admitted census and authored sample read.
  int get asOfMicros => cut.asOfMicros;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementDirectoryPage',
        'schemaVersion': 1,
        'target': target.toJson(),
        'cut': cut.toJson(),
        'reportingCutoffMicros': reportingCutoffMicros,
        'status': status.name,
        'items': [for (final item in items) item.toJson()],
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// The current nomination owner's qualification of an experiment requirement.
enum PlacementExperimentRequirementV1 {
  /// Current authority proves no experiment nomination for the exact scope.
  absent,

  /// A qualified current nomination requires the experiment serving authority.
  potentiallyActive,

  /// Current experiment authority could not be qualified.
  integrityUnavailable,
}

/// Safe exact references from a qualified current experiment nomination.
final class PlacementExperimentReferenceV1 extends _ManagementResult {
  /// Retains actual head and publication identities without private authority.
  PlacementExperimentReferenceV1({
    required this.experimentId,
    required this.experimentEpochId,
    required this.headLifecycleEventOrdinal,
    required this.publicationRevisionId,
    required this.publicationDigest,
  }) {
    AuthorityRevisionId(experimentId);
    AuthorityRevisionId(experimentEpochId);
    AuthorityRevisionId(publicationRevisionId);
    CanonicalDigest(publicationDigest);
    _requireNonnegative(headLifecycleEventOrdinal, 'headLifecycleEventOrdinal');
    if (headLifecycleEventOrdinal == 0) {
      throw const CanonicalFormatException(
        'Experiment head ordinal must be positive.',
      );
    }
  }

  /// Decodes the closed safe reference projection.
  factory PlacementExperimentReferenceV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(json, 'placementExperimentReference', const {
      'experimentId',
      'experimentEpochId',
      'headLifecycleEventOrdinal',
      'publicationRevisionId',
      'publicationDigest',
    });
    return PlacementExperimentReferenceV1(
      experimentId: r.string('experimentId'),
      experimentEpochId: r.string('experimentEpochId'),
      headLifecycleEventOrdinal: r.integer('headLifecycleEventOrdinal'),
      publicationRevisionId: r.string('publicationRevisionId'),
      publicationDigest: r.string('publicationDigest'),
    );
  }

  /// Actual experiment identity.
  final String experimentId;

  /// Actual currently nominated experiment epoch.
  final String experimentEpochId;

  /// Ordinal of the retained current lifecycle head.
  final int headLifecycleEventOrdinal;

  /// Immutable accepted experiment publication revision.
  final String publicationRevisionId;

  /// Digest of that exact accepted publication.
  final String publicationDigest;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementExperimentReference',
        'schemaVersion': 1,
        'experimentId': experimentId,
        'experimentEpochId': experimentEpochId,
        'headLifecycleEventOrdinal': headLifecycleEventOrdinal,
        'publicationRevisionId': publicationRevisionId,
        'publicationDigest': publicationDigest,
      };
}

/// Qualified surface-family authority reachable from a placement's plan.
final class PlacementSurfaceAuthorityV1 extends _ManagementResult {
  /// Requires one exact target and family across all retained references.
  PlacementSurfaceAuthorityV1({
    required this.surface,
    required this.policy,
    required List<DeliveryPublicationReferenceV1> publications,
    required this.experimentRequirement,
    required List<PlacementExperimentReferenceV1> experiments,
    this.activePublication,
  })  : publications = List.unmodifiable(publications),
        experiments = List.unmodifiable(experiments) {
    if (policy.scope.root.surface != surface.surfaceIdentity ||
        policy.scope.family != surface.family ||
        publications.any((publication) => publication.surface != surface) ||
        publications.toSet().length != publications.length ||
        (activePublication != null &&
            !publications.contains(activePublication)) ||
        (experimentRequirement == PlacementExperimentRequirementV1.absent &&
            experiments.isNotEmpty)) {
      throw const CanonicalFormatException(
        'Surface authority references disagree.',
      );
    }
  }

  /// Decodes the closed exact surface-family projection.
  factory PlacementSurfaceAuthorityV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementSurfaceAuthority',
      const {
        'surface',
        'policy',
        'publications',
        'experimentRequirement',
        'experiments',
      },
      optional: const {
        'activePublication',
      },
    );
    final active = r.optionalObject('activePublication');
    return PlacementSurfaceAuthorityV1(
      surface: DeliverySurfaceReferenceV1.fromJson(r.object('surface')),
      policy: DeliveryPolicyReadV1.fromJson(r.object('policy')),
      publications: [
        for (final publication in r.list('publications'))
          DeliveryPublicationReferenceV1.fromJson(
            requireCanonicalObject(publication, 'publications[]'),
          ),
      ],
      experimentRequirement: _enum(
        r.string('experimentRequirement'),
        PlacementExperimentRequirementV1.values,
      ),
      experiments: [
        for (final experiment in r.list('experiments'))
          PlacementExperimentReferenceV1.fromJson(
            requireCanonicalObject(experiment, 'experiments[]'),
          ),
      ],
      activePublication: active == null
          ? null
          : DeliveryPublicationReferenceV1.fromJson(active),
    );
  }

  /// Exact opaque surface identity and its selected family.
  final DeliverySurfaceReferenceV1 surface;

  /// Qualified current surface-family policy, including proved head absence.
  final DeliveryPolicyReadV1 policy;

  /// Qualified immutable publication references in the bounded closure.
  final List<DeliveryPublicationReferenceV1> publications;

  /// Actual default pointer for the exact family, when present.
  final DeliveryPublicationReferenceV1? activePublication;

  /// Current experiment nomination qualification from its owning reader.
  final PlacementExperimentRequirementV1 experimentRequirement;

  /// Safe actual experiment references; no sealed preimages or output bytes.
  final List<PlacementExperimentReferenceV1> experiments;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementSurfaceAuthority',
        'schemaVersion': 1,
        'surface': surface.toJson(),
        'policy': policy.toJson(),
        'publications': [
          for (final publication in publications) publication.toJson(),
        ],
        'experimentRequirement': experimentRequirement.name,
        'experiments': [
          for (final experiment in experiments) experiment.toJson(),
        ],
        if (activePublication != null)
          'activePublication': activePublication!.toJson(),
      };
}

/// Qualification of an exact placement detail request.
enum PlacementReadStatusV1 {
  /// The placement is registered and its requested facts were acquired.
  available,

  /// The admitted exact target contains no such placement key.
  notFound,

  /// The immutable history cursor addresses another target or key.
  cursorQueryMismatch,

  /// Source authority changed since the history continuation was issued.
  cursorStale,

  /// Requested facts exceed the bounded acquisition capacity.
  resourceLimitExceeded,

  /// Retained source authority could not be qualified.
  authorityUnavailable,
}

/// Placement details, immutable policy history and optional observed history.
final class PlacementReadV1 extends _ManagementResult {
  /// Preserves typed absence and closure qualification at one admitted cut.
  PlacementReadV1({
    required this.target,
    required this.key,
    required this.cut,
    required this.reportingCutoffMicros,
    required this.status,
    required this.authorityStatus,
    required List<PlacementSurfaceAuthorityV1> surfaces,
    required this.placementExperimentRequirement,
    required List<PlacementExperimentReferenceV1> placementExperiments,
    this.item,
    this.policyHistory,
    this.historyNextCursor,
    this.observedHistory,
  })  : surfaces = List.unmodifiable(surfaces),
        placementExperiments = List.unmodifiable(placementExperiments) {
    _requireNonnegative(reportingCutoffMicros, 'reportingCutoffMicros');
    _requireCursor(historyNextCursor);
    if ((status == PlacementReadStatusV1.available && item == null) ||
        (status == PlacementReadStatusV1.notFound && item != null) ||
        (item != null &&
            (item!.key != key || item!.policy.scope.target != target)) ||
        surfaces.any((authority) => authority.surface.target != target) ||
        (policyHistory != null &&
            (policyHistory!.scope.root.placement?.key != key ||
                policyHistory!.scope.target != target)) ||
        (observedHistory != null &&
            (observedHistory!.target != target ||
                observedHistory!.placement != key ||
                observedHistory!.publicationGeneration !=
                    cut.publicationGeneration ||
                observedHistory!.publishedAsOfMicros !=
                    cut.publishedAsOfMicros ||
                observedHistory!.validUntilMicros != cut.validUntilMicros))) {
      throw const CanonicalFormatException(
        'Placement detail authority disagrees.',
      );
    }
  }

  /// Decodes a closed placement detail result.
  factory PlacementReadV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementRead',
      const {
        'target',
        'key',
        'cut',
        'reportingCutoffMicros',
        'status',
        'authorityStatus',
        'surfaces',
        'placementExperimentRequirement',
        'placementExperiments',
      },
      optional: const {
        'item',
        'policyHistory',
        'historyNextCursor',
        'observedHistory',
      },
    );
    final item = r.optionalObject('item');
    final history = r.optionalObject('policyHistory');
    final observed = r.optionalObject('observedHistory');
    return PlacementReadV1(
      target: TargetCoordinate.fromJson(r.object('target')),
      key: PlacementKeyV1.fromJson(r.object('key')),
      cut: PlacementManagementCutV1.fromJson(r.object('cut')),
      reportingCutoffMicros: r.integer('reportingCutoffMicros'),
      status: _enum(r.string('status'), PlacementReadStatusV1.values),
      authorityStatus:
          _enum(r.string('authorityStatus'), PlacementAuthorityStatusV1.values),
      surfaces: [
        for (final surface in r.list('surfaces'))
          PlacementSurfaceAuthorityV1.fromJson(
            requireCanonicalObject(surface, 'surfaces[]'),
          ),
      ],
      placementExperimentRequirement: _enum(
        r.string('placementExperimentRequirement'),
        PlacementExperimentRequirementV1.values,
      ),
      placementExperiments: [
        for (final experiment in r.list('placementExperiments'))
          PlacementExperimentReferenceV1.fromJson(
            requireCanonicalObject(experiment, 'placementExperiments[]'),
          ),
      ],
      item: item == null ? null : PlacementDirectoryItemV1.fromJson(item),
      policyHistory:
          history == null ? null : DeliveryPolicyHistoryV1.fromJson(history),
      historyNextCursor: r.optionalString('historyNextCursor'),
      observedHistory: observed == null
          ? null
          : PlacementObservedHistoryV1.fromJson(observed),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementReadV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeResult(bytes, PlacementReadV1.fromJson);

  /// Exact admitted target.
  final TargetCoordinate target;

  /// Exact requested placement key.
  final PlacementKeyV1 key;

  /// One admitted census, sample and published-history cut.
  final PlacementManagementCutV1 cut;

  /// Server-owned reporting cutoff.
  final int reportingCutoffMicros;

  /// Exact-key availability and requested-read qualification.
  final PlacementReadStatusV1 status;

  /// Qualified directory item, absent only when its source is unavailable.
  final PlacementDirectoryItemV1? item;

  /// Qualification of the immutable surface and experiment closure.
  final PlacementAuthorityStatusV1 authorityStatus;

  /// Safe exact reachable surface-version and experiment references.
  final List<PlacementSurfaceAuthorityV1> surfaces;

  /// Qualification of canonical experiments on this exact placement root.
  final PlacementExperimentRequirementV1 placementExperimentRequirement;

  /// Actual retained canonical experiment authority for this placement root.
  final List<PlacementExperimentReferenceV1> placementExperiments;

  /// Bounded immutable policy releases, independent of observed first paint.
  final DeliveryPolicyHistoryV1? policyHistory;

  /// Target, key, head and cut-bound immutable history continuation.
  final String? historyNextCursor;

  /// Optional authenticated first-paint history with coverage qualification.
  final PlacementObservedHistoryV1? observedHistory;

  /// UTC timestamp of the admitted census and sample snapshot.
  int get asOfMicros => cut.asOfMicros;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementRead',
        'schemaVersion': 1,
        'target': target.toJson(),
        'key': key.toJson(),
        'cut': cut.toJson(),
        'reportingCutoffMicros': reportingCutoffMicros,
        'status': status.name,
        'authorityStatus': authorityStatus.name,
        'surfaces': [for (final surface in surfaces) surface.toJson()],
        'placementExperimentRequirement': placementExperimentRequirement.name,
        'placementExperiments': [
          for (final experiment in placementExperiments) experiment.toJson(),
        ],
        if (item != null) 'item': item!.toJson(),
        if (policyHistory != null) 'policyHistory': policyHistory!.toJson(),
        if (historyNextCursor != null) 'historyNextCursor': historyNextCursor,
        if (observedHistory != null)
          'observedHistory': observedHistory!.toJson(),
      };
}

/// One pure serving probe for an exact qualified build and host contract.
final class PlacementSimulationProbeV1 extends _ManagementResult {
  /// Refuses serving credentials or assignments in a read-only simulation.
  PlacementSimulationProbeV1({
    required this.key,
    required this.reason,
    required List<DeliveryPolicySimulationV1> decisions,
    this.appBuildContractHash,
    this.hostContractHash,
    this.delivery,
  }) : decisions = List.unmodifiable(decisions) {
    if (reason.isEmpty ||
        reason.length > 256 ||
        (appBuildContractHash == null) != (hostContractHash == null) ||
        decisions.length > 2 ||
        (decisions.isNotEmpty &&
            (!decisions.first.scope.root.isPlacement ||
                decisions.first.scope.root.placement?.key != key)) ||
        (decisions.length == 2 && decisions.last.scope.root.isPlacement) ||
        (delivery != null &&
            (delivery!.assignment != null ||
                delivery!.routingSelectionReceipt != null ||
                delivery!.mount.placement.key != key ||
                delivery!.mount.hostContractHash != hostContractHash))) {
      throw const CanonicalFormatException(
        'Invalid read-only simulation probe.',
      );
    }
    if (appBuildContractHash != null) {
      _requireHash(appBuildContractHash!);
      _requireHash(hostContractHash!);
    }
  }

  /// Decodes the closed safe probe result.
  factory PlacementSimulationProbeV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementSimulationProbe',
      const {
        'key',
        'reason',
        'decisions',
      },
      optional: const {
        'appBuildContractHash',
        'hostContractHash',
        'delivery',
      },
    );
    final delivery = r.optionalObject('delivery');
    return PlacementSimulationProbeV1(
      key: PlacementKeyV1.fromJson(r.object('key')),
      reason: r.string('reason'),
      decisions: [
        for (final decision in r.list('decisions'))
          DeliveryPolicySimulationV1.fromJson(
            requireCanonicalObject(decision, 'decisions[]'),
          ),
      ],
      appBuildContractHash: r.optionalString('appBuildContractHash'),
      hostContractHash: r.optionalString('hostContractHash'),
      delivery: delivery == null
          ? null
          : PublicPlacementDeliveryV1.fromJson(delivery),
    );
  }

  /// Exact evaluated placement key.
  final PlacementKeyV1 key;

  /// Owning probe's safe result or exact discovery-absence reason.
  final String reason;

  /// Exact offline build identity, absent when no reporting build is available.
  final String? appBuildContractHash;

  /// Exact host shape evaluated for this build.
  final String? hostContractHash;

  /// Ordered safe placement and surface selection projections.
  final List<DeliveryPolicySimulationV1> decisions;

  /// Safe delivered path with no receipt or assignment authority.
  final PublicPlacementDeliveryV1? delivery;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementSimulationProbe',
        'schemaVersion': 1,
        'key': key.toJson(),
        'reason': reason,
        'decisions': [for (final decision in decisions) decision.toJson()],
        if (appBuildContractHash != null)
          'appBuildContractHash': appBuildContractHash,
        if (hostContractHash != null) 'hostContractHash': hostContractHash,
        if (delivery != null) 'delivery': delivery!.toJson(),
      };
}

/// Ordered per-build probes over the explicitly requested placement keys.
final class PlacementSimulationPageV1 extends _ManagementResult {
  /// Preserves evaluated keys and the exact admitted authority cut.
  PlacementSimulationPageV1({
    required this.target,
    required this.cut,
    required this.status,
    required List<PlacementKeyV1> evaluatedKeys,
    required List<PlacementSimulationProbeV1> probes,
    this.nextCursor,
  })  : evaluatedKeys = List.unmodifiable(evaluatedKeys),
        probes = List.unmodifiable(probes) {
    _requireCursor(nextCursor);
    if (evaluatedKeys.length > kMaximumPlacementManagementEntries ||
        evaluatedKeys.toSet().length != evaluatedKeys.length ||
        probes.any(
          (probe) =>
              !evaluatedKeys.contains(probe.key) ||
              probe.decisions
                  .any((decision) => decision.scope.target != target) ||
              (probe.delivery != null &&
                  probe.delivery!.mount.placement.target != target),
        ) ||
        (status != PlacementDirectoryStatusV1.available &&
            (evaluatedKeys.isNotEmpty ||
                probes.isNotEmpty ||
                nextCursor != null))) {
      throw const CanonicalFormatException(
        'Simulation page authority disagrees.',
      );
    }
  }

  /// Decodes a closed bounded page simulation result.
  factory PlacementSimulationPageV1.fromJson(Map<String, Object?> json) {
    final r = _resultReader(
      json,
      'placementSimulationPage',
      const {
        'target',
        'cut',
        'status',
        'evaluatedKeys',
        'probes',
      },
      optional: const {
        'nextCursor',
      },
    );
    return PlacementSimulationPageV1(
      target: TargetCoordinate.fromJson(r.object('target')),
      cut: PlacementManagementCutV1.fromJson(r.object('cut')),
      status: _enum(r.string('status'), PlacementDirectoryStatusV1.values),
      evaluatedKeys: [
        for (final key in r.list('evaluatedKeys'))
          PlacementKeyV1.fromJson(
            requireCanonicalObject(key, 'evaluatedKeys[]'),
          ),
      ],
      probes: [
        for (final probe in r.list('probes'))
          PlacementSimulationProbeV1.fromJson(
            requireCanonicalObject(probe, 'probes[]'),
          ),
      ],
      nextCursor: r.optionalString('nextCursor'),
    );
  }

  /// Decodes only the exact canonical representation.
  factory PlacementSimulationPageV1.fromCanonicalBytes(List<int> bytes) =>
      _decodeResult(bytes, PlacementSimulationPageV1.fromJson);

  /// Exact admitted target.
  final TargetCoordinate target;

  /// Source clocks and immutable generation used by every probe.
  final PlacementManagementCutV1 cut;

  /// Qualification of the bounded acquisition and continuation.
  final PlacementDirectoryStatusV1 status;

  /// Explicit keys evaluated by this page in request order.
  final List<PlacementKeyV1> evaluatedKeys;

  /// Per-build probes; multiple reporting hosts for one key stay distinct.
  final List<PlacementSimulationProbeV1> probes;

  /// Continuation when a bounded page has more qualified probes to evaluate.
  final String? nextCursor;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'placementSimulationPage',
        'schemaVersion': 1,
        'target': target.toJson(),
        'cut': cut.toJson(),
        'status': status.name,
        'evaluatedKeys': [for (final key in evaluatedKeys) key.toJson()],
        'probes': [for (final probe in probes) probe.toJson()],
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

abstract base class _ManagementRequest extends CanonicalValue
    implements ImmutableCanonicalDocument {
  const _ManagementRequest();

  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    _requireByteBudget(bytes.length);
    return bytes;
  }
}

abstract base class _ManagementResult extends CanonicalValue
    implements ImmutableCanonicalDocument {
  @override
  Uint8List get canonicalBytes {
    final bytes = super.canonicalBytes;
    _requireResultBudget(bytes.length);
    return bytes;
  }
}

CanonicalObjectReader _resultReader(
  Map<String, Object?> json,
  String kind,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  _requireResultBudget(CanonicalJsonCodec.encode(json).length);
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', 'schemaVersion', ...required, ...optional},
    requiredKeys: {'kind', 'schemaVersion', ...required},
    path: kind,
  );
  if (reader.string('kind') != kind || reader.integer('schemaVersion') != 1) {
    throw CanonicalFormatException('Expected $kind version 1.');
  }
  return reader;
}

T _decodeResult<T extends CanonicalValue>(
  List<int> bytes,
  T Function(Map<String, Object?>) decode,
) {
  _requireResultBudget(bytes.length);
  return verifyCanonicalRoundTrip(
    decode(decodeCanonicalObject(bytes)),
    bytes,
    path: 'placementManagement',
  );
}

T _enum<T extends Enum>(String value, List<T> values) => values.firstWhere(
      (entry) => entry.name == value,
      orElse: () => throw CanonicalFormatException('Unknown value "$value".'),
    );

void _requireNonnegative(int value, String name) {
  if (value < 0 || value > kMaximumPortableJsonInteger) {
    throw CanonicalFormatException('$name must be nonnegative and portable.');
  }
}

void _requireHash(String value) {
  if (!value.startsWith('sha256:')) {
    throw const CanonicalFormatException('Expected a sha256 content hash.');
  }
  CanonicalDigest(value.substring('sha256:'.length));
}

void _requireResultBudget(int length) {
  if (length > kMaximumPlacementResponseBytes) {
    throw const CanonicalFormatException(
      'Placement management result is too large.',
    );
  }
}

CanonicalObjectReader _reader(
  Map<String, Object?> json,
  String kind,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  _requireByteBudget(CanonicalJsonCodec.encode(json).length);
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', 'schemaVersion', ...required, ...optional},
    requiredKeys: {'kind', 'schemaVersion', ...required},
    path: kind,
  );
  if (reader.string('kind') != kind || reader.integer('schemaVersion') != 1) {
    throw CanonicalFormatException('Expected $kind version 1.');
  }
  return reader;
}

T _decode<T extends CanonicalValue>(
  List<int> bytes,
  T Function(Map<String, Object?>) decode,
) {
  _requireByteBudget(bytes.length);
  return verifyCanonicalRoundTrip(
    decode(decodeCanonicalObject(bytes)),
    bytes,
    path: 'placementManagement',
  );
}

void _requireLimit(int value) {
  if (value < 1 || value > kMaximumPlacementManagementEntries) {
    throw const CanonicalFormatException(
      'Placement management reads require 1..200 entries.',
    );
  }
}

void _requireCursor(String? value) {
  if (value != null &&
      (value.isEmpty ||
          value.length > 4096 ||
          RegExp(r'^[A-Za-z0-9_-]+$').stringMatch(value) != value)) {
    throw const CanonicalFormatException('Invalid placement cursor.');
  }
}

void _requireByteBudget(int length) {
  if (length > kMaximumPlacementManagementRequestBytes) {
    throw const CanonicalFormatException(
      'Placement management request exceeds its byte limit.',
    );
  }
}
