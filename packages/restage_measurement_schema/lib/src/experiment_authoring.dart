import 'dart:collection';
import 'dart:convert';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/manifest.dart'
    show kMaximumGeneratedPresentationReferenceCount;
import 'package:restage_measurement_schema/src/target.dart';

/// Maximum canonical request size accepted by the authoring codec.
const int experimentAuthoringMaximumRequestBytes = 16 * 1024 * 1024;

/// Maximum canonical result size accepted by the authoring codec.
const int experimentAuthoringMaximumResultBytes = 16 * 1024 * 1024;

const int _maximumArms = 16;
const int _maximumDiscoveryPageSize = 100;
const int _maximumIssues = 256;
const int _maximumExperiments = 100;
const int _maximumRelatedValues = 256;
const int _maximumPointSubtreeTreatmentLoci = 1024;
const int _maximumTextBytes = 4096;

abstract base class _ExperimentAuthoringValue extends CanonicalValue {
  _ExperimentAuthoringValue(Map<String, Object?> json)
      : _json = _freezeMap(json);

  final Map<String, Object?> _json;

  @override
  Map<String, Object?> toJson() => _json;
}

/// Stable experiment-authoring operations shared by every public adapter.
enum ExperimentAuthoringOperationV1 {
  discoverTargetsAndCapabilities('discoverTargetsAndCapabilities'),
  openDraft('openDraft'),
  readDraft('readDraft'),
  resolveDraft('resolveDraft'),
  replaceDraft('replaceDraft'),
  copyDraftToTarget('copyDraftToTarget'),
  validateDraft('validateDraft'),
  reviewDraft('reviewDraft'),
  activateDraft('activateDraft'),
  pauseExperiment('pauseExperiment'),
  resumeExperiment('resumeExperiment'),
  concludeExperiment('concludeExperiment'),
  listExperiments('listExperiments'),
  readExperiment('readExperiment'),
  readExperimentResults('readExperimentResults'),
  setExperimentArchived('setExperimentArchived');

  const ExperimentAuthoringOperationV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  /// Whether a request for this operation must carry an idempotency key.
  ///
  /// An operation that changes state requires one and a read refuses one, so a
  /// caller can offer the key exactly where it belongs. Both arms are listed,
  /// so a new operation is a compile error until it is classified.
  bool get requiresIdempotencyKey => switch (this) {
        openDraft ||
        replaceDraft ||
        copyDraftToTarget ||
        reviewDraft ||
        activateDraft ||
        pauseExperiment ||
        resumeExperiment ||
        concludeExperiment ||
        setExperimentArchived =>
          true,
        discoverTargetsAndCapabilities ||
        readDraft ||
        resolveDraft ||
        validateDraft ||
        listExperiments ||
        readExperiment ||
        readExperimentResults =>
          false,
      };

  static ExperimentAuthoringOperationV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Authorization actions evaluated for experiment operations.
enum ExperimentActionV1 {
  read('experiment.read'),
  draftCreate('experiment.draft.create'),
  draftEdit('experiment.draft.edit'),
  validate('experiment.validate'),
  activate('experiment.activate'),
  archive('experiment.archive');

  const ExperimentActionV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentActionV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Analysis families available to an experiment.
enum ExperimentAnalysisKindV1 {
  measureOnly('measureOnly'),
  fixedHorizonNArmRate('fixedHorizonNArmRate');

  const ExperimentAnalysisKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentAnalysisKindV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Supported units assigned independently to experiment arms.
enum ExperimentRandomizedUnitKindV1 {
  assignmentSession('assignmentSession'),
  installation('installation');

  const ExperimentRandomizedUnitKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentRandomizedUnitKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// The immutable randomized-unit default admitted by experiment authoring V1.
final class ExperimentRandomizedUnitDefaultsV1 extends CanonicalValue {
  const ExperimentRandomizedUnitDefaultsV1();

  factory ExperimentRandomizedUnitDefaultsV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentRandomizedUnitDefaultsV1';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'randomizedUnitKind'},
      requiredKeys: const {'kind', 'randomizedUnitKind'},
      path: path,
    );
    _requireKind(reader, 'experimentRandomizedUnitDefaultsV1');
    final randomizedUnitKind = ExperimentRandomizedUnitKindV1._fromWire(
      reader.string('randomizedUnitKind'),
      '$path.randomizedUnitKind',
    );
    if (randomizedUnitKind != ExperimentRandomizedUnitKindV1.installation) {
      throw const CanonicalFormatException(
        'experimentRandomizedUnitDefaultsV1 contains an unsupported value',
      );
    }
    return const ExperimentRandomizedUnitDefaultsV1();
  }

  factory ExperimentRandomizedUnitDefaultsV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        ExperimentRandomizedUnitDefaultsV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'experimentRandomizedUnitDefaultsV1',
      );

  /// Exact randomized-unit kind supplied by this catalogue version.
  ExperimentRandomizedUnitKindV1 get randomizedUnitKind =>
      ExperimentRandomizedUnitKindV1.installation;

  @override
  Map<String, Object?> toJson() => const {
        'kind': 'experimentRandomizedUnitDefaultsV1',
        'randomizedUnitKind': 'installation',
      };
}

/// Direction used by a fixed-horizon rate comparison.
enum ExperimentRateDirectionV1 {
  higherIsBetter('higherIsBetter'),
  lowerIsBetter('lowerIsBetter');

  const ExperimentRateDirectionV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentRateDirectionV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Direction declared by an exact metric definition.
enum ExperimentMetricDirectionV1 {
  higherIsBetter('higherIsBetter'),
  lowerIsBetter('lowerIsBetter'),
  none('none');

  const ExperimentMetricDirectionV1(this.wireName);

  final String wireName;

  static ExperimentMetricDirectionV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Direction in which a guardrail change is harmful.
enum ExperimentAdverseDirectionV1 {
  higherIsWorse('higherIsWorse'),
  lowerIsWorse('lowerIsWorse');

  const ExperimentAdverseDirectionV1(this.wireName);

  final String wireName;

  static ExperimentAdverseDirectionV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Completeness state of a durable authoring draft.
enum ExperimentDraftCompletenessKindV1 {
  incomplete('incomplete'),
  complete('complete');

  const ExperimentDraftCompletenessKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentDraftCompletenessKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Feasibility state returned by fixed-horizon planning.
enum ExperimentPlanningFeasibilityV1 {
  feasible('feasible'),
  infeasible('infeasible'),
  indeterminate('indeterminate');

  const ExperimentPlanningFeasibilityV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentPlanningFeasibilityV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Closed refusal reasons returned by the semantic service.
enum ExperimentAuthoringRefusalCodeV1 {
  validationBlocked('validationBlocked'),
  staleDraft('staleDraft'),
  staleHead('staleHead'),
  notActive('notActive'),
  alreadyPaused('alreadyPaused'),
  notPaused('notPaused'),
  alreadyConcluded('alreadyConcluded'),
  concluded('concluded'),
  staleLifecycleOrdinal('staleLifecycleOrdinal'),

  /// A required review record is unavailable.
  reviewMissing('reviewMissing'),

  /// The review is no longer current.
  reviewStale('reviewStale'),

  /// The review does not match its activation binding.
  reviewBindingMismatch('reviewBindingMismatch'),
  ownershipConflict('ownershipConflict'),
  deniedAction('deniedAction'),
  targetMismatch('targetMismatch'),
  incompatibleReference('incompatibleReference'),
  capabilityUnavailable('capabilityUnavailable'),

  /// A count numerator is unsupported for rate analysis.
  statisticalCountNumeratorUnsupported(
    'statisticalCountNumeratorUnsupported',
  ),
  replayRebinding('replayRebinding'),
  backendUnavailable('backendUnavailable'),
  integrityFailure('integrityFailure'),
  transportUnknownOutcome('transportUnknownOutcome');

  const ExperimentAuthoringRefusalCodeV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentAuthoringRefusalCodeV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Lifecycle state of one accepted experiment.
enum ExperimentLifecycleStateV1 {
  active('active'),
  paused('paused'),
  concluded('concluded');

  const ExperimentLifecycleStateV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentLifecycleStateV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Integrity state of an accepted experiment read.
enum ExperimentIntegrityStateV1 {
  verified('verified'),
  unavailable('unavailable');

  const ExperimentIntegrityStateV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentIntegrityStateV1 _fromWire(String value, String path) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Whether a newer draft exists beside accepted experiment metadata.
enum ExperimentPendingDraftKindV1 {
  none('none'),
  pending('pending');

  const ExperimentPendingDraftKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentPendingDraftKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Availability of an exact inference reference.
enum ExperimentInferenceReferenceKindV1 {
  unavailable('unavailable'),
  exact('exact');

  const ExperimentInferenceReferenceKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentInferenceReferenceKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Availability state of a results projection.
enum ExperimentResultsAvailabilityKindV1 {
  available('available'),
  insufficientEvidence('insufficientEvidence'),
  capabilityUnavailable('capabilityUnavailable'),
  indeterminate('indeterminate'),
  privacyRestricted('privacyRestricted'),
  interrupted('interrupted');

  const ExperimentResultsAvailabilityKindV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentResultsAvailabilityKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Canonical authority families that may supply a resolved default.
enum ExperimentCanonicalDefaultAuthorityKindV1 {
  assignmentAudiencePolicy('assignmentAudiencePolicy'),
  assignmentEligibilityPolicy('assignmentEligibilityPolicy'),
  metricDefinition('metricDefinition'),
  registeredInferenceAdapter('registeredInferenceAdapter');

  const ExperimentCanonicalDefaultAuthorityKindV1(this.wireName);

  final String wireName;

  static ExperimentCanonicalDefaultAuthorityKindV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Stable authoring-draft identity.
final class ExperimentDraftIdV1 extends MeasurementIdentifier {
  ExperimentDraftIdV1(super.value);
}

/// Exact authoring-draft revision identity.
final class ExperimentDraftRevisionIdV1 extends MeasurementIdentifier {
  ExperimentDraftRevisionIdV1(super.value);
}

/// Stable arm identity retained across edits.
final class ExperimentStableArmIdV1 extends MeasurementIdentifier {
  ExperimentStableArmIdV1(super.value);
}

/// Stable metric-binding identity retained across edits.
final class ExperimentMetricBindingIdV1 extends MeasurementIdentifier {
  ExperimentMetricBindingIdV1(super.value);
}

/// Stable review-record locator.
final class ExperimentReviewIdV1 extends MeasurementIdentifier {
  ExperimentReviewIdV1(super.value);
}

/// Stable public experiment identity.
final class ExperimentPublicIdV1 extends MeasurementIdentifier {
  ExperimentPublicIdV1(super.value);
}

/// Exact public experiment revision identity.
final class ExperimentPublicRevisionIdV1 extends MeasurementIdentifier {
  ExperimentPublicRevisionIdV1(super.value);
}

/// Exact public experiment epoch identity.
final class ExperimentPublicEpochIdV1 extends MeasurementIdentifier {
  ExperimentPublicEpochIdV1(super.value);
}

/// Exact public experiment arm identity.
final class ExperimentPublicArmIdV1 extends MeasurementIdentifier {
  ExperimentPublicArmIdV1(super.value);
}

/// One semantic experiment-authoring request.
final class ExperimentAuthoringRequestV1 extends _ExperimentAuthoringValue {
  ExperimentAuthoringRequestV1._(
    Map<String, Object?> json, {
    required this.operation,
    required this.correlationId,
    required this.idempotencyKey,
    required this.payload,
  }) : super(json);

  /// Decodes a strict request object.
  factory ExperimentAuthoringRequestV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'correlationId',
        'idempotencyKey',
        'kind',
        'operation',
        'payload',
        'schemaVersion',
      },
      requiredKeys: const {
        'correlationId',
        'kind',
        'operation',
        'payload',
        'schemaVersion',
      },
      path: 'experimentAuthoringRequest',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentAuthoringRequest',
    );
    final operation = ExperimentAuthoringOperationV1._fromWire(
      reader.string('operation'),
      'experimentAuthoringRequest.operation',
    );
    final correlationId = _boundedString(
      reader.string('correlationId'),
      'experimentAuthoringRequest.correlationId',
    );
    final idempotencyKey = reader.optionalString('idempotencyKey');
    if (operation.requiresIdempotencyKey) {
      if (idempotencyKey == null) {
        throw const CanonicalFormatException(
          'experimentAuthoringRequest.idempotencyKey is required',
        );
      }
      _boundedString(
        idempotencyKey,
        'experimentAuthoringRequest.idempotencyKey',
      );
    } else if (idempotencyKey != null) {
      throw const CanonicalFormatException(
        'experimentAuthoringRequest.idempotencyKey is not admitted',
      );
    }
    final payload = reader.object('payload');
    _validateRequestPayload(operation, payload);
    return ExperimentAuthoringRequestV1._(
      json,
      operation: operation,
      correlationId: correlationId,
      idempotencyKey: idempotencyKey,
      payload: _freezeMap(payload),
    );
  }

  /// Decodes byte-exact canonical request JSON.
  factory ExperimentAuthoringRequestV1.fromCanonicalBytes(List<int> bytes) {
    _checkByteLimit(
      bytes,
      experimentAuthoringMaximumRequestBytes,
      'experimentAuthoringRequest',
    );
    return verifyCanonicalRoundTrip(
      ExperimentAuthoringRequestV1.fromJson(decodeCanonicalObject(bytes)),
      bytes,
      path: 'experimentAuthoringRequest',
    );
  }

  /// Requested operation.
  final ExperimentAuthoringOperationV1 operation;

  /// Caller-provided response correlation identity.
  final String correlationId;

  /// Retry identity for effectful operations.
  final String? idempotencyKey;

  /// Strict operation-specific semantic payload.
  final Map<String, Object?> payload;
}

/// A canonical exact rational used by public experiment projections.
final class ExperimentRationalV1 extends _ExperimentAuthoringValue {
  ExperimentRationalV1._(
    Map<String, Object?> json, {
    required this.numerator,
    required this.denominator,
  }) : super(json);

  /// Decodes a strict rational object.
  factory ExperimentRationalV1.fromJson(
    Map<String, Object?> json, {
    String path = 'experimentRational',
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'denominator', 'numerator'},
      requiredKeys: const {'denominator', 'numerator'},
      path: path,
    );
    final numerator = reader.integer('numerator');
    final denominator = reader.integer('denominator');
    if (denominator <= 0) {
      throw CanonicalFormatException('$path.denominator must be positive');
    }
    return ExperimentRationalV1._(
      json,
      numerator: numerator,
      denominator: denominator,
    );
  }

  /// Exact numerator.
  final int numerator;

  /// Positive exact denominator.
  final int denominator;
}

/// The immutable statistical defaults admitted by experiment authoring V1.
final class ExperimentStatisticalDefaultsV1 extends CanonicalValue {
  const ExperimentStatisticalDefaultsV1();

  factory ExperimentStatisticalDefaultsV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentStatisticalDefaultsV1';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'alpha', 'kind', 'margin', 'power'},
      requiredKeys: const {'alpha', 'kind', 'margin', 'power'},
      path: path,
    );
    _requireKind(reader, 'experimentStatisticalDefaultsV1');
    final margin = ExperimentRationalV1.fromJson(
      reader.object('margin'),
      path: '$path.margin',
    );
    final alpha = ExperimentRationalV1.fromJson(
      reader.object('alpha'),
      path: '$path.alpha',
    );
    final power = ExperimentRationalV1.fromJson(
      reader.object('power'),
      path: '$path.power',
    );
    if (!_isExactRational(margin, 1, 100) ||
        !_isExactRational(alpha, 1, 20) ||
        !_isExactRational(power, 4, 5)) {
      throw const CanonicalFormatException(
        'experimentStatisticalDefaultsV1 contains unsupported values',
      );
    }
    return const ExperimentStatisticalDefaultsV1();
  }

  factory ExperimentStatisticalDefaultsV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        ExperimentStatisticalDefaultsV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'experimentStatisticalDefaultsV1',
      );

  ExperimentRationalV1 get margin => ExperimentRationalV1.fromJson(
        const {'denominator': 100, 'numerator': 1},
      );

  ExperimentRationalV1 get alpha => ExperimentRationalV1.fromJson(
        const {'denominator': 20, 'numerator': 1},
      );

  ExperimentRationalV1 get power => ExperimentRationalV1.fromJson(
        const {'denominator': 5, 'numerator': 4},
      );

  @override
  Map<String, Object?> toJson() => const {
        'alpha': {'denominator': 20, 'numerator': 1},
        'kind': 'experimentStatisticalDefaultsV1',
        'margin': {'denominator': 100, 'numerator': 1},
        'power': {'denominator': 5, 'numerator': 4},
      };
}

/// A safe resolved statistical scalar choice exposed by draft reads.
final class ExperimentResolvedStatisticalChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedStatisticalChoiceV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedValue,
    required this.source,
  }) : super(json);

  factory ExperimentResolvedStatisticalChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
    ExperimentRationalV1? expectedServerDefault,
  }) {
    final kind = _readDiscriminator(json, path);
    if (kind == 'explicitValue') {
      final reader = CanonicalObjectReader(
        json,
        allowedKeys: const {'kind', 'value'},
        requiredKeys: const {'kind', 'value'},
        path: path,
      );
      final value = ExperimentRationalV1.fromJson(
        reader.object('value'),
        path: '$path.value',
      );
      return ExperimentResolvedStatisticalChoiceV1._(
        json,
        kind: kind,
        resolvedValue: value,
        source: null,
      );
    }
    if (kind != 'serverDefault') {
      throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'resolvedValue', 'source'},
      requiredKeys: const {'kind', 'resolvedValue', 'source'},
      path: path,
    );
    final value = ExperimentRationalV1.fromJson(
      reader.object('resolvedValue'),
      path: '$path.resolvedValue',
    );
    final source = ExperimentStatisticalDefaultsV1.fromJson(
      reader.object('source'),
    );
    if (expectedServerDefault != null &&
        !_sameRational(value, expectedServerDefault)) {
      throw CanonicalFormatException(
        '$path.resolvedValue does not match its default',
      );
    }
    return ExperimentResolvedStatisticalChoiceV1._(
      json,
      kind: kind,
      resolvedValue: value,
      source: source,
    );
  }

  final String kind;
  final ExperimentRationalV1 resolvedValue;
  final ExperimentStatisticalDefaultsV1? source;
}

/// An exact public surface reference.
final class ExperimentExactSurfaceReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactSurfaceReferenceV1._(
    Map<String, Object?> json, {
    required this.surfaceId,
    required this.surfaceRevisionId,
  }) : super(json);

  /// Decodes a strict exact surface reference.
  factory ExperimentExactSurfaceReferenceV1.fromJson(
    Map<String, Object?> json, {
    String path = 'exactSurfaceReference',
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'surfaceId', 'surfaceRevisionId'},
      requiredKeys: const {'kind', 'surfaceId', 'surfaceRevisionId'},
      path: path,
    );
    _requireKind(reader, 'exactSurfaceReference');
    return ExperimentExactSurfaceReferenceV1._(
      json,
      surfaceId: _mintedIdentifier(
        reader.string('surfaceId'),
        '$path.surfaceId',
        kMintedSurfaceIdPrefix,
        SurfaceId.new,
      ),
      surfaceRevisionId: _mintedIdentifier(
        reader.string('surfaceRevisionId'),
        '$path.surfaceRevisionId',
        kMintedSurfaceRevisionIdPrefix,
        SurfaceRevisionId.new,
      ),
    );
  }

  /// Stable surface identity.
  final SurfaceId surfaceId;

  /// Exact surface revision identity.
  final SurfaceRevisionId surfaceRevisionId;
}

/// An identity the platform minted, refused when anything else is named.
T _mintedIdentifier<T>(
  String value,
  String path,
  String prefix,
  T Function(String value) build,
) {
  if (!isMintedMeasurementIdentity(value, prefix)) {
    throw CanonicalFormatException(
      '$path must be an identity Restage minted',
    );
  }
  return _identifier(value, path, build);
}

/// One explicit relative arm weight for fixed-horizon planning.
final class ExperimentArmPlanningWeightV1 extends _ExperimentAuthoringValue {
  ExperimentArmPlanningWeightV1._(
    Map<String, Object?> json, {
    required this.armId,
    required this.relativeWeight,
  }) : super(json);

  factory ExperimentArmPlanningWeightV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'armId', 'relativeWeight'},
      requiredKeys: const {'armId', 'relativeWeight'},
      path: path,
    );
    final relativeWeight = reader.integer('relativeWeight');
    if (relativeWeight < 1 || relativeWeight > 100) {
      throw CanonicalFormatException('$path.relativeWeight must be 1..100');
    }
    return ExperimentArmPlanningWeightV1._(
      json,
      armId: _identifier(
        reader.string('armId'),
        '$path.armId',
        ExperimentStableArmIdV1.new,
      ),
      relativeWeight: relativeWeight,
    );
  }

  /// Stable arm identity.
  final ExperimentStableArmIdV1 armId;

  /// Positive relative allocation weight.
  final int relativeWeight;
}

/// Exact registered inference adapter selected by the server.
final class ExperimentExactInferenceAdapterReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactInferenceAdapterReferenceV1._(
    Map<String, Object?> json, {
    required this.adapterId,
    required this.revisionId,
    required this.semanticHash,
  }) : super(json);

  factory ExperimentExactInferenceAdapterReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'adapterId', 'revisionId', 'semanticHash'},
      requiredKeys: const {'adapterId', 'revisionId', 'semanticHash'},
      path: path,
    );
    return ExperimentExactInferenceAdapterReferenceV1._(
      json,
      adapterId: _identifier(
        reader.string('adapterId'),
        '$path.adapterId',
        AuthorityRevisionId.new,
      ),
      revisionId: _identifier(
        reader.string('revisionId'),
        '$path.revisionId',
        AuthorityRevisionId.new,
      ),
      semanticHash: _parsedDigest(
        reader.string('semanticHash'),
        '$path.semanticHash',
      ),
    );
  }

  final AuthorityRevisionId adapterId;
  final AuthorityRevisionId revisionId;
  final CanonicalDigest semanticHash;
}

/// Explicit fixed-horizon planning inputs for one guardrail.
final class ExperimentNArmGuardrailPlanningSelectionV1
    extends _ExperimentAuthoringValue {
  ExperimentNArmGuardrailPlanningSelectionV1._(
    Map<String, Object?> json, {
    required this.guardrailId,
    required this.adverseDirection,
    required this.expectedReferenceRate,
    required this.harmMargin,
    required this.targetPower,
  }) : super(json);

  factory ExperimentNArmGuardrailPlanningSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'adverseDirection',
        'expectedReferenceRate',
        'guardrailId',
        'harmMargin',
        'targetPower',
      },
      requiredKeys: const {
        'adverseDirection',
        'expectedReferenceRate',
        'guardrailId',
        'harmMargin',
        'targetPower',
      },
      path: path,
    );
    final expectedReferenceRate = ExperimentRationalV1.fromJson(
      reader.object('expectedReferenceRate'),
      path: '$path.expectedReferenceRate',
    );
    final harmMargin = ExperimentRationalV1.fromJson(
      reader.object('harmMargin'),
      path: '$path.harmMargin',
    );
    final targetPower = ExperimentRationalV1.fromJson(
      reader.object('targetPower'),
      path: '$path.targetPower',
    );
    _requireOpenProbability(
      expectedReferenceRate,
      '$path.expectedReferenceRate',
    );
    _requirePositiveFraction(harmMargin, '$path.harmMargin');
    _requireSupportedPower(targetPower, '$path.targetPower');
    return ExperimentNArmGuardrailPlanningSelectionV1._(
      json,
      guardrailId: _identifier(
        reader.string('guardrailId'),
        '$path.guardrailId',
        AuthorityRevisionId.new,
      ),
      adverseDirection: ExperimentAdverseDirectionV1._fromWire(
        reader.string('adverseDirection'),
        '$path.adverseDirection',
      ),
      expectedReferenceRate: expectedReferenceRate,
      harmMargin: harmMargin,
      targetPower: targetPower,
    );
  }

  final AuthorityRevisionId guardrailId;
  final ExperimentAdverseDirectionV1 adverseDirection;
  final ExperimentRationalV1 expectedReferenceRate;
  final ExperimentRationalV1 harmMargin;
  final ExperimentRationalV1 targetPower;
}

/// Explicit public inputs for fixed-horizon N-arm rate planning.
final class ExperimentNArmPlanningSelectionV1
    extends _ExperimentAuthoringValue {
  ExperimentNArmPlanningSelectionV1._(
    Map<String, Object?> json, {
    required this.referenceArmId,
    required this.direction,
    required this.expectedBaseline,
    required this.minimumDetectableEffect,
    required this.practicalSuperiorityMarginChoice,
    required this.alphaChoice,
    required this.primaryTargetPowerChoice,
    required this.enrollmentCap,
    required this.followUpDurationMicros,
    required this.maximumEnrollmentDurationMicros,
    required this.outcomeGracePeriodMicros,
    required this.allocationWeights,
    required this.guardrails,
    required this.registeredAdapterSelection,
  }) : super(json);

  /// Decodes a strict planning selection.
  factory ExperimentNArmPlanningSelectionV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentNArmPlanningSelection';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'allocationWeights',
        'alphaChoice',
        'direction',
        'enrollmentCap',
        'expectedBaseline',
        'followUpDurationMicros',
        'guardrails',
        'kind',
        'maximumEnrollmentDurationMicros',
        'minimumDetectableEffect',
        'outcomeGracePeriodMicros',
        'primaryTargetPowerChoice',
        'practicalSuperiorityMarginChoice',
        'referenceArmId',
        'registeredAdapterSelection',
        'schemaVersion',
      },
      requiredKeys: const {
        'allocationWeights',
        'alphaChoice',
        'direction',
        'enrollmentCap',
        'expectedBaseline',
        'followUpDurationMicros',
        'guardrails',
        'kind',
        'maximumEnrollmentDurationMicros',
        'minimumDetectableEffect',
        'outcomeGracePeriodMicros',
        'primaryTargetPowerChoice',
        'practicalSuperiorityMarginChoice',
        'referenceArmId',
        'registeredAdapterSelection',
        'schemaVersion',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentNArmPlanningSelection',
    );
    final referenceArmId = _identifier(
      reader.string('referenceArmId'),
      '$path.referenceArmId',
      ExperimentStableArmIdV1.new,
    );
    final direction = ExperimentRateDirectionV1._fromWire(
      reader.string('direction'),
      '$path.direction',
    );
    final expectedBaseline = ExperimentRationalV1.fromJson(
      reader.object('expectedBaseline'),
      path: '$path.expectedBaseline',
    );
    final minimumDetectableEffect = ExperimentRationalV1.fromJson(
      reader.object('minimumDetectableEffect'),
      path: '$path.minimumDetectableEffect',
    );
    const defaults = ExperimentStatisticalDefaultsV1();
    final practicalSuperiorityMarginChoice =
        ExperimentResolvedStatisticalChoiceV1.fromJson(
      reader.object('practicalSuperiorityMarginChoice'),
      path: '$path.practicalSuperiorityMarginChoice',
      expectedServerDefault: defaults.margin,
    );
    final alphaChoice = ExperimentResolvedStatisticalChoiceV1.fromJson(
      reader.object('alphaChoice'),
      path: '$path.alphaChoice',
      expectedServerDefault: defaults.alpha,
    );
    final primaryTargetPowerChoice =
        ExperimentResolvedStatisticalChoiceV1.fromJson(
      reader.object('primaryTargetPowerChoice'),
      path: '$path.primaryTargetPowerChoice',
      expectedServerDefault: defaults.power,
    );
    _requireOpenProbability(expectedBaseline, '$path.expectedBaseline');
    _requireSupportedAlpha(alphaChoice.resolvedValue, '$path.alphaChoice');
    _requireSupportedPower(
      primaryTargetPowerChoice.resolvedValue,
      '$path.primaryTargetPowerChoice',
    );
    _requirePositiveFraction(
      minimumDetectableEffect,
      '$path.minimumDetectableEffect',
    );
    _requirePositiveFraction(
      practicalSuperiorityMarginChoice.resolvedValue,
      '$path.practicalSuperiorityMarginChoice',
    );
    _requireDirectionalEffectDomain(
      baseline: expectedBaseline,
      effect: minimumDetectableEffect,
      direction: direction,
      path: path,
    );
    _requireStrictlyLess(
      practicalSuperiorityMarginChoice.resolvedValue,
      minimumDetectableEffect,
      '$path.practicalSuperiorityMarginChoice',
    );
    final enrollmentCap = reader.integer('enrollmentCap');
    final followUpDurationMicros = reader.integer('followUpDurationMicros');
    final maximumEnrollmentDurationMicros = reader.integer(
      'maximumEnrollmentDurationMicros',
    );
    final outcomeGracePeriodMicros = reader.integer('outcomeGracePeriodMicros');
    if (enrollmentCap <= 0 ||
        followUpDurationMicros <= 0 ||
        maximumEnrollmentDurationMicros <= 0 ||
        outcomeGracePeriodMicros < 0) {
      throw const CanonicalFormatException(
        'experimentNArmPlanningSelection contains an invalid bound',
      );
    }
    final allocationWeights = _objectList(
      reader.list('allocationWeights'),
      path: '$path.allocationWeights',
      maximumLength: _maximumArms,
      minimumLength: 2,
      decode: (value, itemPath) =>
          ExperimentArmPlanningWeightV1.fromJson(value, path: itemPath),
    );
    _requireUnique(
      allocationWeights.map((entry) => entry.armId.value),
      '$path.allocationWeights.armId',
    );
    if (!allocationWeights.any((entry) => entry.armId == referenceArmId)) {
      throw const CanonicalFormatException(
        'experimentNArmPlanningSelection.referenceArmId is not allocated',
      );
    }
    final guardrails = _objectList(
      reader.list('guardrails'),
      path: '$path.guardrails',
      maximumLength: _maximumRelatedValues,
      decode: (value, itemPath) =>
          ExperimentNArmGuardrailPlanningSelectionV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      guardrails.map((entry) => entry.guardrailId.value),
      '$path.guardrails.guardrailId',
    );
    for (final guardrail in guardrails) {
      _requireGuardrailDomain(
        expectedReferenceRate: guardrail.expectedReferenceRate,
        harmMargin: guardrail.harmMargin,
        adverseDirection: guardrail.adverseDirection,
        path: '$path.guardrails.${guardrail.guardrailId.value}',
      );
    }
    final registeredAdapterSelection = ExperimentResolvedExactSelectionV1<
        ExperimentExactInferenceAdapterReferenceV1>.fromJson(
      reader.object('registeredAdapterSelection'),
      path: '$path.registeredAdapterSelection',
      decodeResolvedExactRef: (value, itemPath) =>
          ExperimentExactInferenceAdapterReferenceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireServerResolvedAdapter(
      registeredAdapterSelection,
      '$path.registeredAdapterSelection',
    );
    return ExperimentNArmPlanningSelectionV1._(
      json,
      referenceArmId: referenceArmId,
      direction: ExperimentMetricDirectionV1._fromWire(
        reader.string('direction'),
        '$path.direction',
      ),
      expectedBaseline: expectedBaseline,
      minimumDetectableEffect: minimumDetectableEffect,
      practicalSuperiorityMarginChoice: practicalSuperiorityMarginChoice,
      alphaChoice: alphaChoice,
      primaryTargetPowerChoice: primaryTargetPowerChoice,
      enrollmentCap: enrollmentCap,
      followUpDurationMicros: followUpDurationMicros,
      maximumEnrollmentDurationMicros: maximumEnrollmentDurationMicros,
      outcomeGracePeriodMicros: outcomeGracePeriodMicros,
      allocationWeights: allocationWeights,
      guardrails: guardrails,
      registeredAdapterSelection: registeredAdapterSelection,
    );
  }

  /// Decodes byte-exact canonical planning-selection JSON.
  factory ExperimentNArmPlanningSelectionV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        ExperimentNArmPlanningSelectionV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'experimentNArmPlanningSelection',
      );

  final ExperimentStableArmIdV1 referenceArmId;
  final ExperimentMetricDirectionV1 direction;
  final ExperimentRationalV1 expectedBaseline;
  final ExperimentRationalV1 minimumDetectableEffect;
  final ExperimentResolvedStatisticalChoiceV1 practicalSuperiorityMarginChoice;
  final ExperimentResolvedStatisticalChoiceV1 alphaChoice;
  final ExperimentResolvedStatisticalChoiceV1 primaryTargetPowerChoice;
  final int enrollmentCap;
  final int followUpDurationMicros;
  final int maximumEnrollmentDurationMicros;
  final int outcomeGracePeriodMicros;
  final List<ExperimentArmPlanningWeightV1> allocationWeights;
  final List<ExperimentNArmGuardrailPlanningSelectionV1> guardrails;
  final ExperimentResolvedExactSelectionV1<
      ExperimentExactInferenceAdapterReferenceV1> registeredAdapterSelection;
}

void _requireServerResolvedAdapter(
  ExperimentResolvedExactSelectionV1<ExperimentExactInferenceAdapterReferenceV1>
      selection,
  String path,
) {
  final reference = selection.resolvedExactRef;
  final source = selection.source;
  if (selection.kind != 'serverDefault' ||
      reference == null ||
      source is! ExperimentCanonicalAuthorityDefaultSourceV1 ||
      source.authorityKind !=
          ExperimentCanonicalDefaultAuthorityKindV1
              .registeredInferenceAdapter ||
      source.authorityId.value != reference.adapterId.value ||
      source.authorityRevisionId.value != reference.revisionId.value ||
      source.semanticDigest != reference.semanticHash) {
    throw CanonicalFormatException(
      '$path must bind an exact server-resolved adapter authority',
    );
  }
}

/// Closed analysis selection for an experiment draft.
sealed class ExperimentAnalysisSelectionV1 extends _ExperimentAuthoringValue {
  ExperimentAnalysisSelectionV1._(super.json, this.kind);

  /// Decodes a closed analysis-selection branch.
  factory ExperimentAnalysisSelectionV1.fromJson(Map<String, Object?> json) {
    final kind = _readDiscriminator(json, 'experimentAnalysisSelection');
    return switch (kind) {
      'measureOnly' => ExperimentMeasureOnlySelectionV1.fromJson(json),
      'fixedHorizonNArmRate' =>
        ExperimentFixedHorizonNArmRateSelectionV1.fromJson(json),
      _ => throw CanonicalFormatException(
          'experimentAnalysisSelection.kind "$kind" is unsupported',
        ),
    };
  }

  /// Selected analysis family.
  final ExperimentAnalysisKindV1 kind;
}

/// Descriptive measurement without an inferential claim.
final class ExperimentMeasureOnlySelectionV1
    extends ExperimentAnalysisSelectionV1 {
  ExperimentMeasureOnlySelectionV1._(Map<String, Object?> json)
      : super._(json, ExperimentAnalysisKindV1.measureOnly);

  factory ExperimentMeasureOnlySelectionV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: 'experimentMeasureOnlySelection',
    );
    _requireKind(reader, 'measureOnly');
    return ExperimentMeasureOnlySelectionV1._(json);
  }
}

/// Fixed-horizon N-arm rate analysis with explicit planning inputs.
final class ExperimentFixedHorizonNArmRateSelectionV1
    extends ExperimentAnalysisSelectionV1 {
  ExperimentFixedHorizonNArmRateSelectionV1._(
    Map<String, Object?> json,
    this.planningSelection,
  ) : super._(json, ExperimentAnalysisKindV1.fixedHorizonNArmRate);

  factory ExperimentFixedHorizonNArmRateSelectionV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'planningSelection'},
      requiredKeys: const {'kind', 'planningSelection'},
      path: 'experimentFixedHorizonNArmRateSelection',
    );
    _requireKind(reader, 'fixedHorizonNArmRate');
    return ExperimentFixedHorizonNArmRateSelectionV1._(
      json,
      ExperimentNArmPlanningSelectionV1.fromJson(
        reader.object('planningSelection'),
      ),
    );
  }

  /// Explicit statistical inputs.
  final ExperimentNArmPlanningSelectionV1 planningSelection;
}

/// Exact resolved policy reference exposed by a draft.
final class ExperimentExactPolicyReferenceV1 extends _ExperimentAuthoringValue {
  ExperimentExactPolicyReferenceV1._(
    Map<String, Object?> json, {
    required this.policyId,
    required this.revisionId,
    required this.semanticDigest,
  }) : super(json);

  factory ExperimentExactPolicyReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'policyId', 'revisionId', 'semanticDigest'},
      requiredKeys: const {'policyId', 'revisionId', 'semanticDigest'},
      path: path,
    );
    return ExperimentExactPolicyReferenceV1._(
      json,
      policyId: _identifier(
        reader.string('policyId'),
        '$path.policyId',
        AuthorityRevisionId.new,
      ),
      revisionId: _identifier(
        reader.string('revisionId'),
        '$path.revisionId',
        AuthorityRevisionId.new,
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final AuthorityRevisionId policyId;
  final AuthorityRevisionId revisionId;
  final CanonicalDigest semanticDigest;
}

/// An exact metric-definition reference exposed by experiment authoring.
final class ExperimentExactMetricDefinitionReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactMetricDefinitionReferenceV1._(
    Map<String, Object?> json, {
    required this.direction,
    required this.metricDefinitionId,
    required this.metricDefinitionRevisionId,
    required this.metricDefinitionSemanticDigest,
  }) : super(json);

  factory ExperimentExactMetricDefinitionReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'direction',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
      },
      requiredKeys: const {
        'direction',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
      },
      path: path,
    );
    return ExperimentExactMetricDefinitionReferenceV1._(
      json,
      direction: ExperimentMetricDirectionV1._fromWire(
        reader.string('direction'),
        '$path.direction',
      ),
      metricDefinitionId: _identifier(
        reader.string('metricDefinitionId'),
        '$path.metricDefinitionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionRevisionId: _identifier(
        reader.string('metricDefinitionRevisionId'),
        '$path.metricDefinitionRevisionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionSemanticDigest: _parsedDigest(
        reader.string('metricDefinitionSemanticDigest'),
        '$path.metricDefinitionSemanticDigest',
      ),
    );
  }

  final ExperimentMetricDirectionV1 direction;
  final AuthorityRevisionId metricDefinitionId;
  final AuthorityRevisionId metricDefinitionRevisionId;
  final CanonicalDigest metricDefinitionSemanticDigest;
}

/// A stable metric-binding reference within one draft.
final class ExperimentMetricBindingReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentMetricBindingReferenceV1._(
    Map<String, Object?> json,
    this.metricBindingId,
  ) : super(json);

  factory ExperimentMetricBindingReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'metricBindingId'},
      requiredKeys: const {'metricBindingId'},
      path: path,
    );
    return ExperimentMetricBindingReferenceV1._(
      json,
      _identifier(
        reader.string('metricBindingId'),
        '$path.metricBindingId',
        ExperimentMetricBindingIdV1.new,
      ),
    );
  }

  final ExperimentMetricBindingIdV1 metricBindingId;
}

/// An exact installed slot-projection reference.
final class ExperimentExactSlotProjectionReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactSlotProjectionReferenceV1._(
    Map<String, Object?> json, {
    required this.projectionRevisionId,
    required this.canonicalDigest,
    required this.semanticDigest,
  }) : super(json);

  factory ExperimentExactSlotProjectionReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'canonicalDigest',
        'projectionRevisionId',
        'semanticDigest',
      },
      requiredKeys: const {
        'canonicalDigest',
        'projectionRevisionId',
        'semanticDigest',
      },
      path: path,
    );
    return ExperimentExactSlotProjectionReferenceV1._(
      json,
      projectionRevisionId: _identifier(
        reader.string('projectionRevisionId'),
        '$path.projectionRevisionId',
        AuthorityRevisionId.new,
      ),
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final AuthorityRevisionId projectionRevisionId;
  final CanonicalDigest canonicalDigest;
  final CanonicalDigest semanticDigest;
}

/// Exact authority provenance for a resolved server default.
sealed class ExperimentResolvedDefaultSourceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedDefaultSourceV1._(super.json, this.kind);

  factory ExperimentResolvedDefaultSourceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) =>
      switch (_readDiscriminator(json, path)) {
        'canonicalAuthority' =>
          ExperimentCanonicalAuthorityDefaultSourceV1.fromJson(
            json,
            path: path,
          ),
        'publicationCandidate' =>
          ExperimentPublicationCandidateDefaultSourceV1.fromJson(
            json,
            path: path,
          ),
        'installedProjection' =>
          ExperimentInstalledProjectionDefaultSourceV1.fromJson(
            json,
            path: path,
          ),
        final kind => throw CanonicalFormatException(
            '$path.kind "$kind" is unsupported',
          ),
      };

  final String kind;
}

/// Canonical authority that supplied a resolved default reference.
final class ExperimentCanonicalAuthorityDefaultSourceV1
    extends ExperimentResolvedDefaultSourceV1 {
  ExperimentCanonicalAuthorityDefaultSourceV1._(
    Map<String, Object?> json, {
    required this.authorityKind,
    required this.authorityId,
    required this.authorityRevisionId,
    required this.canonicalDigest,
    required this.semanticDigest,
  }) : super._(json, 'canonicalAuthority');

  factory ExperimentCanonicalAuthorityDefaultSourceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'authorityId',
        'authorityKind',
        'authorityRevisionId',
        'canonicalDigest',
        'kind',
        'semanticDigest',
      },
      requiredKeys: const {
        'authorityId',
        'authorityKind',
        'authorityRevisionId',
        'canonicalDigest',
        'kind',
        'semanticDigest',
      },
      path: path,
    );
    _requireKind(reader, 'canonicalAuthority');
    return ExperimentCanonicalAuthorityDefaultSourceV1._(
      json,
      authorityKind: ExperimentCanonicalDefaultAuthorityKindV1._fromWire(
        reader.string('authorityKind'),
        '$path.authorityKind',
      ),
      authorityId: _identifier(
        reader.string('authorityId'),
        '$path.authorityId',
        AuthorityRevisionId.new,
      ),
      authorityRevisionId: _identifier(
        reader.string('authorityRevisionId'),
        '$path.authorityRevisionId',
        AuthorityRevisionId.new,
      ),
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final ExperimentCanonicalDefaultAuthorityKindV1 authorityKind;
  final AuthorityRevisionId authorityId;
  final AuthorityRevisionId authorityRevisionId;
  final CanonicalDigest canonicalDigest;
  final CanonicalDigest semanticDigest;
}

/// Exact catalog candidate that supplied a resolved default candidate.
final class ExperimentPublicationCandidateDefaultSourceV1
    extends ExperimentResolvedDefaultSourceV1 {
  ExperimentPublicationCandidateDefaultSourceV1._(
    Map<String, Object?> json,
    this.candidate,
  ) : super._(json, 'publicationCandidate');

  factory ExperimentPublicationCandidateDefaultSourceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'candidate', 'kind'},
      requiredKeys: const {'candidate', 'kind'},
      path: path,
    );
    _requireKind(reader, 'publicationCandidate');
    return ExperimentPublicationCandidateDefaultSourceV1._(
      json,
      ExperimentExactCandidateV1.fromJson(
        reader.object('candidate'),
        path: '$path.candidate',
      ),
    );
  }

  final ExperimentExactCandidateV1 candidate;
}

/// Installed projection authority that supplied a resolved default.
final class ExperimentInstalledProjectionDefaultSourceV1
    extends ExperimentResolvedDefaultSourceV1 {
  ExperimentInstalledProjectionDefaultSourceV1._(
    Map<String, Object?> json, {
    required this.projectionRevisionId,
    required this.canonicalDigest,
    required this.semanticDigest,
  }) : super._(json, 'installedProjection');

  factory ExperimentInstalledProjectionDefaultSourceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'canonicalDigest',
        'kind',
        'projectionRevisionId',
        'semanticDigest',
      },
      requiredKeys: const {
        'canonicalDigest',
        'kind',
        'projectionRevisionId',
        'semanticDigest',
      },
      path: path,
    );
    _requireKind(reader, 'installedProjection');
    return ExperimentInstalledProjectionDefaultSourceV1._(
      json,
      projectionRevisionId: _identifier(
        reader.string('projectionRevisionId'),
        '$path.projectionRevisionId',
        AuthorityRevisionId.new,
      ),
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final AuthorityRevisionId projectionRevisionId;
  final CanonicalDigest canonicalDigest;
  final CanonicalDigest semanticDigest;
}

/// One resolved required choice in a partial draft read.
final class ExperimentResolvedExactSelectionV1<T extends CanonicalValue>
    extends _ExperimentAuthoringValue {
  ExperimentResolvedExactSelectionV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedExactRef,
    required this.source,
  }) : super(json);

  factory ExperimentResolvedExactSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
    required T Function(Map<String, Object?> json, String path)
        decodeResolvedExactRef,
  }) {
    final kind = _readDiscriminator(json, path);
    final unresolved = kind == 'unselected';
    if (!unresolved && kind != 'serverDefault' && kind != 'exactRef') {
      throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
    final keys = switch (kind) {
      'unselected' => const {'kind'},
      'serverDefault' => const {'kind', 'resolvedExactRef', 'source'},
      _ => const {'kind', 'resolvedExactRef'},
    };
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );
    final resolvedExactRef = unresolved
        ? null
        : decodeResolvedExactRef(
            reader.object('resolvedExactRef'),
            '$path.resolvedExactRef',
          );
    final source = kind == 'serverDefault'
        ? ExperimentResolvedDefaultSourceV1.fromJson(
            reader.object('source'),
            path: '$path.source',
          )
        : null;
    if (kind == 'serverDefault') {
      _requireResolvedDefaultSourceBinding(
        resolvedExactRef: resolvedExactRef!,
        source: source!,
        path: path,
      );
    }
    return ExperimentResolvedExactSelectionV1._(
      json,
      kind: kind,
      resolvedExactRef: resolvedExactRef,
      source: source,
    );
  }

  final String kind;
  final T? resolvedExactRef;
  final ExperimentResolvedDefaultSourceV1? source;
}

void _requireResolvedDefaultSourceBinding({
  required CanonicalValue resolvedExactRef,
  required ExperimentResolvedDefaultSourceV1 source,
  required String path,
}) {
  final matches = switch (resolvedExactRef) {
    final ExperimentExactCandidateV1 reference =>
      source is ExperimentPublicationCandidateDefaultSourceV1 &&
          reference == source.candidate,
    final ExperimentExactInferenceAdapterReferenceV1 reference =>
      _matchesCanonicalDefaultSource(
        source,
        authorityKind: ExperimentCanonicalDefaultAuthorityKindV1
            .registeredInferenceAdapter,
        authorityId: reference.adapterId,
        authorityRevisionId: reference.revisionId,
        semanticDigest: reference.semanticHash,
      ),
    final ExperimentExactMetricDefinitionReferenceV1 reference =>
      _matchesMetricDefinitionDefaultSource(reference, source),
    final ExperimentExactPolicyReferenceV1 reference =>
      source is ExperimentCanonicalAuthorityDefaultSourceV1 &&
          (source.authorityKind ==
                  ExperimentCanonicalDefaultAuthorityKindV1
                      .assignmentAudiencePolicy ||
              source.authorityKind ==
                  ExperimentCanonicalDefaultAuthorityKindV1
                      .assignmentEligibilityPolicy) &&
          _matchesCanonicalDefaultSource(
            source,
            authorityId: reference.policyId,
            authorityRevisionId: reference.revisionId,
            semanticDigest: reference.semanticDigest,
          ),
    final ExperimentExactSlotProjectionReferenceV1 reference =>
      source is ExperimentInstalledProjectionDefaultSourceV1 &&
          source.projectionRevisionId.value ==
              reference.projectionRevisionId.value &&
          source.canonicalDigest == reference.canonicalDigest &&
          source.semanticDigest == reference.semanticDigest,
    final ExperimentExactSurfaceReferenceV1 reference =>
      source is ExperimentPublicationCandidateDefaultSourceV1 &&
          reference == source.candidate.surfaceReference,
    _ => false,
  };
  if (!matches) {
    throw CanonicalFormatException(
      '$path.source must name its resolved authority',
    );
  }
}

bool _matchesCanonicalDefaultSource(
  ExperimentResolvedDefaultSourceV1 source, {
  required AuthorityRevisionId authorityId,
  required AuthorityRevisionId authorityRevisionId,
  required CanonicalDigest semanticDigest,
  ExperimentCanonicalDefaultAuthorityKindV1? authorityKind,
}) =>
    source is ExperimentCanonicalAuthorityDefaultSourceV1 &&
    (authorityKind == null || source.authorityKind == authorityKind) &&
    source.authorityId.value == authorityId.value &&
    source.authorityRevisionId.value == authorityRevisionId.value &&
    source.semanticDigest == semanticDigest;

bool _matchesMetricDefinitionDefaultSource(
  ExperimentExactMetricDefinitionReferenceV1 reference,
  ExperimentResolvedDefaultSourceV1 source,
) =>
    source is ExperimentCanonicalAuthorityDefaultSourceV1 &&
    source.authorityKind ==
        ExperimentCanonicalDefaultAuthorityKindV1.metricDefinition &&
    source.authorityId.value == reference.metricDefinitionId.value &&
    source.authorityRevisionId.value ==
        reference.metricDefinitionRevisionId.value &&
    source.semanticDigest == reference.metricDefinitionSemanticDigest;

ExperimentPolicySelectionV1 _readPolicySelection(
  Map<String, Object?> json, {
  required String path,
  required ExperimentCanonicalDefaultAuthorityKindV1 authorityKind,
}) {
  final selection = ExperimentPolicySelectionV1.fromJson(json, path: path);
  final source = selection.source;
  if (selection.kind == 'serverDefault' &&
      (source is! ExperimentCanonicalAuthorityDefaultSourceV1 ||
          source.authorityKind != authorityKind)) {
    throw CanonicalFormatException(
      '$path.source must name the selected policy authority',
    );
  }
  return selection;
}

/// Primary metric-binding choice in a draft read.
final class ExperimentPrimaryBindingSelectionV1
    extends _ExperimentAuthoringValue {
  ExperimentPrimaryBindingSelectionV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedExactRef,
  }) : super(json);

  factory ExperimentPrimaryBindingSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final keys = kind == 'unselected'
        ? const {'kind'}
        : const {'kind', 'resolvedExactRef'};
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );
    if (kind == 'unselected') {
      return ExperimentPrimaryBindingSelectionV1._(
        json,
        kind: kind,
        resolvedExactRef: null,
      );
    }
    if (kind != 'exactRef') {
      throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
    return ExperimentPrimaryBindingSelectionV1._(
      json,
      kind: kind,
      resolvedExactRef: ExperimentMetricBindingReferenceV1.fromJson(
        reader.object('resolvedExactRef'),
        path: '$path.resolvedExactRef',
      ),
    );
  }

  final String kind;
  final ExperimentMetricBindingReferenceV1? resolvedExactRef;
}

/// A required policy choice in a partial or resolved draft.
sealed class ExperimentPolicySelectionV1 extends _ExperimentAuthoringValue {
  ExperimentPolicySelectionV1._(
    super.json,
    this.kind,
    this.resolvedExactRef,
    this.source,
  );

  factory ExperimentPolicySelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: switch (kind) {
        'unselected' => const {'kind'},
        'serverDefault' => const {'kind', 'resolvedExactRef', 'source'},
        _ => const {'kind', 'resolvedExactRef'},
      },
      requiredKeys: switch (kind) {
        'unselected' => const {'kind'},
        'serverDefault' => const {'kind', 'resolvedExactRef', 'source'},
        _ => const {'kind', 'resolvedExactRef'},
      },
      path: path,
    );
    switch (kind) {
      case 'unselected':
        return ExperimentUnselectedPolicyV1._(json);
      case 'serverDefault':
        final reference = ExperimentExactPolicyReferenceV1.fromJson(
          reader.object('resolvedExactRef'),
          path: '$path.resolvedExactRef',
        );
        final source = ExperimentResolvedDefaultSourceV1.fromJson(
          reader.object('source'),
          path: '$path.source',
        );
        _requireResolvedDefaultSourceBinding(
          resolvedExactRef: reference,
          source: source,
          path: path,
        );
        return ExperimentServerDefaultPolicyV1._(
          json,
          reference,
          source,
        );
      case 'exactRef':
        return ExperimentExactPolicySelectionV1.fromJson(json, path: path);
      default:
        throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
  }

  final String kind;
  final ExperimentExactPolicyReferenceV1? resolvedExactRef;
  final ExperimentResolvedDefaultSourceV1? source;
}

final class ExperimentUnselectedPolicyV1 extends ExperimentPolicySelectionV1 {
  ExperimentUnselectedPolicyV1._(Map<String, Object?> json)
      : super._(json, 'unselected', null, null);
}

final class ExperimentServerDefaultPolicyV1
    extends ExperimentPolicySelectionV1 {
  ExperimentServerDefaultPolicyV1._(
    Map<String, Object?> json,
    ExperimentExactPolicyReferenceV1 reference,
    ExperimentResolvedDefaultSourceV1 source,
  ) : super._(json, 'serverDefault', reference, source);
}

final class ExperimentExactPolicySelectionV1
    extends ExperimentPolicySelectionV1 {
  ExperimentExactPolicySelectionV1._(
    Map<String, Object?> json,
    ExperimentExactPolicyReferenceV1 reference,
  ) : super._(json, 'exactRef', reference, null);

  factory ExperimentExactPolicySelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'resolvedExactRef'},
      requiredKeys: const {'kind', 'resolvedExactRef'},
      path: path,
    );
    _requireKind(reader, 'exactRef');
    return ExperimentExactPolicySelectionV1._(
      json,
      ExperimentExactPolicyReferenceV1.fromJson(
        reader.object('resolvedExactRef'),
        path: '$path.resolvedExactRef',
      ),
    );
  }
}

/// A closed randomized-unit choice in a resolved draft read.
final class ExperimentRandomizedUnitSelectionV1
    extends _ExperimentAuthoringValue {
  ExperimentRandomizedUnitSelectionV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedValue,
    required this.source,
  }) : super(json);

  factory ExperimentRandomizedUnitSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final keys = switch (kind) {
      'serverDefault' => const {'kind', 'resolvedValue', 'source'},
      'explicitValue' => const {'kind', 'value'},
      _ => throw CanonicalFormatException('$path.kind "$kind" is unsupported'),
    };
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );
    final resolvedValue = ExperimentRandomizedUnitKindV1._fromWire(
      reader.string(kind == 'serverDefault' ? 'resolvedValue' : 'value'),
      '$path.${kind == 'serverDefault' ? 'resolvedValue' : 'value'}',
    );
    if (kind == 'serverDefault' &&
        resolvedValue != ExperimentRandomizedUnitKindV1.installation) {
      throw CanonicalFormatException(
        '$path.resolvedValue does not match the catalogued default',
      );
    }
    final source = kind == 'serverDefault'
        ? ExperimentRandomizedUnitDefaultsV1.fromJson(reader.object('source'))
        : null;
    if (source != null && source.randomizedUnitKind != resolvedValue) {
      throw CanonicalFormatException(
        '$path.source does not supply the resolved value',
      );
    }
    return ExperimentRandomizedUnitSelectionV1._(
      json,
      kind: kind,
      resolvedValue: resolvedValue,
      source: source,
    );
  }

  /// Whether the value came from the catalogued default or the author.
  final String kind;

  /// Exact randomized-unit kind used by the draft.
  final ExperimentRandomizedUnitKindV1 resolvedValue;

  /// Catalogued source when [kind] is `serverDefault`.
  final ExperimentRandomizedUnitDefaultsV1? source;
}

/// A required exact-surface choice in a partial or resolved draft.
sealed class ExperimentSurfaceSelectionV1 extends _ExperimentAuthoringValue {
  ExperimentSurfaceSelectionV1._(
    super.json,
    this.kind,
    this.resolvedExactRef,
    this.source,
  );

  factory ExperimentSurfaceSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: switch (kind) {
        'unselected' => const {'kind'},
        'serverDefault' => const {'kind', 'resolvedExactRef', 'source'},
        _ => const {'kind', 'resolvedExactRef'},
      },
      requiredKeys: switch (kind) {
        'unselected' => const {'kind'},
        'serverDefault' => const {'kind', 'resolvedExactRef', 'source'},
        _ => const {'kind', 'resolvedExactRef'},
      },
      path: path,
    );
    switch (kind) {
      case 'unselected':
        return ExperimentUnselectedSurfaceV1._(json);
      case 'serverDefault':
        final reference = ExperimentExactSurfaceReferenceV1.fromJson(
          reader.object('resolvedExactRef'),
          path: '$path.resolvedExactRef',
        );
        final source = ExperimentResolvedDefaultSourceV1.fromJson(
          reader.object('source'),
          path: '$path.source',
        );
        _requireResolvedDefaultSourceBinding(
          resolvedExactRef: reference,
          source: source,
          path: path,
        );
        return ExperimentServerDefaultSurfaceV1._(
          json,
          reference,
          source,
        );
      case 'exactRef':
        return ExperimentExactSurfaceSelectionV1._(
          json,
          ExperimentExactSurfaceReferenceV1.fromJson(
            reader.object('resolvedExactRef'),
            path: '$path.resolvedExactRef',
          ),
        );
      default:
        throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
  }

  final String kind;
  final ExperimentExactSurfaceReferenceV1? resolvedExactRef;
  final ExperimentResolvedDefaultSourceV1? source;
}

final class ExperimentUnselectedSurfaceV1 extends ExperimentSurfaceSelectionV1 {
  ExperimentUnselectedSurfaceV1._(Map<String, Object?> json)
      : super._(json, 'unselected', null, null);
}

final class ExperimentServerDefaultSurfaceV1
    extends ExperimentSurfaceSelectionV1 {
  ExperimentServerDefaultSurfaceV1._(
    Map<String, Object?> json,
    ExperimentExactSurfaceReferenceV1 reference,
    ExperimentResolvedDefaultSourceV1 source,
  ) : super._(json, 'serverDefault', reference, source);
}

final class ExperimentExactSurfaceSelectionV1
    extends ExperimentSurfaceSelectionV1 {
  ExperimentExactSurfaceSelectionV1._(
    Map<String, Object?> json,
    ExperimentExactSurfaceReferenceV1 reference,
  ) : super._(json, 'exactRef', reference, null);
}

/// Subject selection for the independent experiment profile.
final class ExperimentSubjectSelectionV1 extends _ExperimentAuthoringValue {
  ExperimentSubjectSelectionV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedExactRef,
  }) : super(json);

  factory ExperimentSubjectSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: kind == 'subjectless'
          ? const {'kind'}
          : const {'kind', 'resolvedExactRef'},
      requiredKeys: kind == 'subjectless'
          ? const {'kind'}
          : const {'kind', 'resolvedExactRef'},
      path: path,
    );
    if (kind == 'subjectless') {
      return ExperimentSubjectSelectionV1._(
        json,
        kind: kind,
        resolvedExactRef: null,
      );
    }
    if (kind != 'exactSubjectRef') {
      throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
    return ExperimentSubjectSelectionV1._(
      json,
      kind: kind,
      resolvedExactRef: ExperimentExactPolicyReferenceV1.fromJson(
        reader.object('resolvedExactRef'),
        path: '$path.resolvedExactRef',
      ),
    );
  }

  final String kind;
  final ExperimentExactPolicyReferenceV1? resolvedExactRef;
}

/// Safe exact publication context for a point-subtree base.
final class ExperimentExactSurfaceContextV1 extends _ExperimentAuthoringValue {
  ExperimentExactSurfaceContextV1._(
    Map<String, Object?> json, {
    required this.surfaceReference,
    required this.artifactGraphHash,
    required this.measurementManifestHash,
  }) : super(json);

  factory ExperimentExactSurfaceContextV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactGraphHash',
        'kind',
        'measurementManifestHash',
        'surfaceReference',
      },
      requiredKeys: const {
        'artifactGraphHash',
        'kind',
        'measurementManifestHash',
        'surfaceReference',
      },
      path: path,
    );
    _requireKind(reader, 'exactSurfaceContext');
    return ExperimentExactSurfaceContextV1._(
      json,
      surfaceReference: ExperimentExactSurfaceReferenceV1.fromJson(
        reader.object('surfaceReference'),
        path: '$path.surfaceReference',
      ),
      artifactGraphHash: _parsedDigest(
        reader.string('artifactGraphHash'),
        '$path.artifactGraphHash',
      ),
      measurementManifestHash: _parsedDigest(
        reader.string('measurementManifestHash'),
        '$path.measurementManifestHash',
      ),
    );
  }

  final ExperimentExactSurfaceReferenceV1 surfaceReference;
  final CanonicalDigest artifactGraphHash;
  final CanonicalDigest measurementManifestHash;
}

/// One exact point-subtree treatment locus.
final class ExperimentPointSubtreeTreatmentLocusV1
    extends _ExperimentAuthoringValue {
  ExperimentPointSubtreeTreatmentLocusV1._(
    Map<String, Object?> json, {
    required this.locusId,
    required this.presentedPointLineageId,
    required this.pointLineageCanonicalHash,
  }) : super(json);

  factory ExperimentPointSubtreeTreatmentLocusV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'locusId',
        'pointLineageCanonicalHash',
        'presentedPointLineageId',
      },
      requiredKeys: const {
        'locusId',
        'pointLineageCanonicalHash',
        'presentedPointLineageId',
      },
      path: path,
    );
    return ExperimentPointSubtreeTreatmentLocusV1._(
      json,
      locusId: _identifier(
        reader.string('locusId'),
        '$path.locusId',
        AuthorityRevisionId.new,
      ),
      presentedPointLineageId: _identifier(
        reader.string('presentedPointLineageId'),
        '$path.presentedPointLineageId',
        PointLineageId.new,
      ),
      pointLineageCanonicalHash: _parsedDigest(
        reader.string('pointLineageCanonicalHash'),
        '$path.pointLineageCanonicalHash',
      ),
    );
  }

  final AuthorityRevisionId locusId;
  final PointLineageId presentedPointLineageId;
  final CanonicalDigest pointLineageCanonicalHash;
}

/// Exact whole-surface or point-subtree treatment origin.
sealed class ExperimentTreatmentOriginV1 extends _ExperimentAuthoringValue {
  ExperimentTreatmentOriginV1._(super.json, this.kind);

  factory ExperimentTreatmentOriginV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) =>
      switch (_readDiscriminator(json, path)) {
        'wholeSurface' => ExperimentWholeSurfaceTreatmentOriginV1.fromJson(
            json,
            path: path,
          ),
        'pointSubtree' => ExperimentPointSubtreeTreatmentOriginV1.fromJson(
            json,
            path: path,
          ),
        final kind => throw CanonicalFormatException(
            '$path.kind "$kind" is unsupported',
          ),
      };

  final String kind;
}

/// Whole-surface origin over its one exact locus.
final class ExperimentWholeSurfaceTreatmentOriginV1
    extends ExperimentTreatmentOriginV1 {
  ExperimentWholeSurfaceTreatmentOriginV1._(
    Map<String, Object?> json,
    this.locusIds,
  ) : super._(json, 'wholeSurface');

  factory ExperimentWholeSurfaceTreatmentOriginV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'locusIds'},
      requiredKeys: const {'kind', 'locusIds'},
      path: path,
    );
    _requireKind(reader, 'wholeSurface');
    final locusIds = _identifierList(
      reader.list('locusIds'),
      path: '$path.locusIds',
      maximumLength: 1,
      minimumLength: 1,
      build: AuthorityRevisionId.new,
    );
    _requireUnique(
      locusIds.map((value) => value.value),
      '$path.locusIds',
    );
    _requireCanonicalOrder(
      locusIds.map((value) => value.value),
      '$path.locusIds',
    );
    return ExperimentWholeSurfaceTreatmentOriginV1._(json, locusIds);
  }

  final List<AuthorityRevisionId> locusIds;
}

/// Point-subtree origin over its complete exact locus set.
final class ExperimentPointSubtreeTreatmentOriginV1
    extends ExperimentTreatmentOriginV1 {
  ExperimentPointSubtreeTreatmentOriginV1._(
    Map<String, Object?> json, {
    required this.basePublicationContext,
    required this.loci,
  }) : super._(json, 'pointSubtree');

  factory ExperimentPointSubtreeTreatmentOriginV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'basePublicationContext', 'kind', 'loci'},
      requiredKeys: const {'basePublicationContext', 'kind', 'loci'},
      path: path,
    );
    _requireKind(reader, 'pointSubtree');
    final loci = _objectList(
      reader.list('loci'),
      path: '$path.loci',
      maximumLength: _maximumPointSubtreeTreatmentLoci,
      minimumLength: 1,
      decode: (value, itemPath) =>
          ExperimentPointSubtreeTreatmentLocusV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      loci.map((value) => value.locusId.value),
      '$path.loci.locusId',
    );
    _requireCanonicalOrder(
      loci.map((value) => value.locusId.value),
      '$path.loci.locusId',
    );
    return ExperimentPointSubtreeTreatmentOriginV1._(
      json,
      basePublicationContext: ExperimentExactSurfaceContextV1.fromJson(
        reader.object('basePublicationContext'),
        path: '$path.basePublicationContext',
      ),
      loci: loci,
    );
  }

  final ExperimentExactSurfaceContextV1 basePublicationContext;
  final List<ExperimentPointSubtreeTreatmentLocusV1> loci;
}

/// Exact compatible candidate selected for an arm or holdout.
final class ExperimentExactCandidateV1 extends _ExperimentAuthoringValue {
  ExperimentExactCandidateV1._(
    Map<String, Object?> json, {
    required this.label,
    required this.surfaceReference,
    required this.treatmentOrigin,
  }) : super(json);

  factory ExperimentExactCandidateV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'label',
        'surfaceReference',
        'treatmentOrigin',
      },
      requiredKeys: const {
        'kind',
        'label',
        'surfaceReference',
        'treatmentOrigin',
      },
      path: path,
    );
    _requireKind(reader, 'exactCandidate');
    return ExperimentExactCandidateV1._(
      json,
      label: _boundedString(reader.string('label'), '$path.label'),
      surfaceReference: ExperimentExactSurfaceReferenceV1.fromJson(
        reader.object('surfaceReference'),
        path: '$path.surfaceReference',
      ),
      treatmentOrigin: ExperimentTreatmentOriginV1.fromJson(
        reader.object('treatmentOrigin'),
        path: '$path.treatmentOrigin',
      ),
    );
  }

  final String label;
  final ExperimentExactSurfaceReferenceV1 surfaceReference;
  final ExperimentTreatmentOriginV1 treatmentOrigin;
}

/// One stable arm choice in an authoring draft.
final class ExperimentDraftArmChoiceV1 extends _ExperimentAuthoringValue {
  ExperimentDraftArmChoiceV1._(
    Map<String, Object?> json, {
    required this.stableArmId,
    required this.label,
    required this.relativeWeight,
    required this.candidate,
  }) : super(json);

  factory ExperimentDraftArmChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'candidate',
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
      },
      requiredKeys: const {
        'candidate',
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftArmChoice');
    final relativeWeight = reader.integer('relativeWeight');
    if (relativeWeight < 1 || relativeWeight > 100) {
      throw CanonicalFormatException('$path.relativeWeight must be 1..100');
    }
    return ExperimentDraftArmChoiceV1._(
      json,
      stableArmId: _identifier(
        reader.string('stableArmId'),
        '$path.stableArmId',
        ExperimentStableArmIdV1.new,
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      relativeWeight: relativeWeight,
      candidate: ExperimentExactCandidateV1.fromJson(
        reader.object('candidate'),
        path: '$path.candidate',
      ),
    );
  }

  final ExperimentStableArmIdV1 stableArmId;
  final String label;
  final int relativeWeight;
  final ExperimentExactCandidateV1 candidate;

  /// This arm in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'candidateSelection': <String, Object?>{
          'exactRef': candidate.toJson(),
          'kind': 'exactRef',
        },
        'kind': 'experimentDraftArmChoice',
        'label': label,
        'relativeWeight': relativeWeight,
        'stableArmId': stableArmId.value,
      };
}

/// One explicit member holdout in an authoring draft.
final class ExperimentDraftMemberHoldoutChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentDraftMemberHoldoutChoiceV1._(
    Map<String, Object?> json, {
    required this.holdoutId,
    required this.label,
    required this.candidate,
  }) : super(json);

  factory ExperimentDraftMemberHoldoutChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'candidate',
        'holdoutId',
        'kind',
        'label',
      },
      requiredKeys: const {
        'candidate',
        'holdoutId',
        'kind',
        'label',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftMemberHoldoutChoice');
    return ExperimentDraftMemberHoldoutChoiceV1._(
      json,
      holdoutId: _identifier(
        reader.string('holdoutId'),
        '$path.holdoutId',
        AuthorityRevisionId.new,
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      candidate: ExperimentExactCandidateV1.fromJson(
        reader.object('candidate'),
        path: '$path.candidate',
      ),
    );
  }

  final AuthorityRevisionId holdoutId;
  final String label;
  final ExperimentExactCandidateV1 candidate;

  /// This holdout in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'candidateSelection': <String, Object?>{
          'exactRef': candidate.toJson(),
          'kind': 'exactRef',
        },
        'holdoutId': holdoutId.value,
        'kind': 'experimentDraftMemberHoldoutChoice',
        'label': label,
      };
}

/// One exact metric definition selected into a draft.
final class ExperimentDraftMetricBindingChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentDraftMetricBindingChoiceV1._(
    Map<String, Object?> json, {
    required this.metricBindingId,
    required this.label,
    required this.metricDefinitionChoice,
    required this.armProjectionSets,
  }) : super(json);

  factory ExperimentDraftMetricBindingChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'armProjectionSets',
        'kind',
        'label',
        'metricBindingId',
        'metricDefinitionChoice',
      },
      requiredKeys: const {
        'armProjectionSets',
        'kind',
        'label',
        'metricBindingId',
        'metricDefinitionChoice',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftMetricBindingChoice');
    final metricBindingId = _identifier(
      reader.string('metricBindingId'),
      '$path.metricBindingId',
      ExperimentMetricBindingIdV1.new,
    );
    final metricDefinitionChoice = ExperimentResolvedExactSelectionV1<
        ExperimentExactMetricDefinitionReferenceV1>.fromJson(
      reader.object('metricDefinitionChoice'),
      path: '$path.metricDefinitionChoice',
      decodeResolvedExactRef: (value, itemPath) =>
          ExperimentExactMetricDefinitionReferenceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    if (metricDefinitionChoice.resolvedExactRef == null) {
      throw CanonicalFormatException(
        '$path.metricDefinitionChoice must be resolved',
      );
    }
    final armProjectionSets = _objectList(
      reader.list('armProjectionSets'),
      path: '$path.armProjectionSets',
      maximumLength: _maximumArms,
      minimumLength: 2,
      decode: (value, itemPath) =>
          ExperimentResolvedPartialDraftArmProjectionSetChoiceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      armProjectionSets.map((entry) => entry.stableArmId.value),
      '$path.armProjectionSets.stableArmId',
    );
    if (armProjectionSets.any(
      (set) =>
          set.installedProjectionSetChoice.resolvedExactRef == null ||
          set.resolvedMembers.isEmpty,
    )) {
      throw CanonicalFormatException(
        '$path.armProjectionSets must contain selected installed projection sets',
      );
    }
    return ExperimentDraftMetricBindingChoiceV1._(
      json,
      metricBindingId: metricBindingId,
      label: _boundedString(reader.string('label'), '$path.label'),
      metricDefinitionChoice: metricDefinitionChoice,
      armProjectionSets: armProjectionSets,
    );
  }

  final ExperimentMetricBindingIdV1 metricBindingId;
  final String label;
  final ExperimentResolvedExactSelectionV1<
      ExperimentExactMetricDefinitionReferenceV1> metricDefinitionChoice;
  final List<ExperimentResolvedPartialDraftArmProjectionSetChoiceV1>
      armProjectionSets;

  /// This metric binding in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'armProjectionSets': [
          for (final set in armProjectionSets) set.toMutationJson(),
        ],
        'kind': 'experimentDraftMetricBindingChoice',
        'label': label,
        'metricBindingId': metricBindingId.value,
        'metricDefinitionChoice': _mutationSelectionJson(
          metricDefinitionChoice.toJson(),
        ),
      };
}

/// One guardrail role assigned to a selected metric binding.
final class ExperimentDraftGuardrailChoiceV1 extends _ExperimentAuthoringValue {
  ExperimentDraftGuardrailChoiceV1._(
    Map<String, Object?> json, {
    required this.guardrailId,
    required this.metricBindingId,
  }) : super(json);

  factory ExperimentDraftGuardrailChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'guardrailId', 'kind', 'metricBindingId'},
      requiredKeys: const {'guardrailId', 'kind', 'metricBindingId'},
      path: path,
    );
    _requireKind(reader, 'experimentDraftGuardrailChoice');
    return ExperimentDraftGuardrailChoiceV1._(
      json,
      guardrailId: _identifier(
        reader.string('guardrailId'),
        '$path.guardrailId',
        AuthorityRevisionId.new,
      ),
      metricBindingId: _identifier(
        reader.string('metricBindingId'),
        '$path.metricBindingId',
        ExperimentMetricBindingIdV1.new,
      ),
    );
  }

  final AuthorityRevisionId guardrailId;
  final ExperimentMetricBindingIdV1 metricBindingId;

  /// This guardrail role in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'guardrailId': guardrailId.value,
        'kind': 'experimentDraftGuardrailChoice',
        'metricBindingId': metricBindingId.value,
      };
}

/// Analysis state exposed by an incomplete draft read.
final class ExperimentPartialAnalysisSelectionV1
    extends _ExperimentAuthoringValue {
  ExperimentPartialAnalysisSelectionV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.resolvedSelection,
  }) : super(json);

  factory ExperimentPartialAnalysisSelectionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    if (kind == 'unselected') {
      CanonicalObjectReader(
        json,
        allowedKeys: const {'kind'},
        requiredKeys: const {'kind'},
        path: path,
      );
      return ExperimentPartialAnalysisSelectionV1._(
        json,
        kind: kind,
        resolvedSelection: null,
      );
    }
    final selection = ExperimentAnalysisSelectionV1.fromJson(json);
    return ExperimentPartialAnalysisSelectionV1._(
      json,
      kind: kind,
      resolvedSelection: selection,
    );
  }

  final String kind;
  final ExperimentAnalysisSelectionV1? resolvedSelection;
}

/// One stable arm and its resolved partial candidate choice.
final class ExperimentResolvedPartialDraftArmChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedPartialDraftArmChoiceV1._(
    Map<String, Object?> json, {
    required this.stableArmId,
    required this.label,
    required this.relativeWeight,
    required this.candidateSelection,
  }) : super(json);

  factory ExperimentResolvedPartialDraftArmChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'candidateSelection',
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
      },
      requiredKeys: const {
        'candidateSelection',
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftArmChoice');
    final relativeWeight = reader.integer('relativeWeight');
    if (relativeWeight < 1 || relativeWeight > 100) {
      throw CanonicalFormatException('$path.relativeWeight must be 1..100');
    }
    return ExperimentResolvedPartialDraftArmChoiceV1._(
      json,
      stableArmId: _identifier(
        reader.string('stableArmId'),
        '$path.stableArmId',
        ExperimentStableArmIdV1.new,
      ),
      label: _boundedString(
        reader.string('label'),
        '$path.label',
        allowEmpty: true,
      ),
      relativeWeight: relativeWeight,
      candidateSelection: ExperimentResolvedExactSelectionV1<
          ExperimentExactCandidateV1>.fromJson(
        reader.object('candidateSelection'),
        path: '$path.candidateSelection',
        decodeResolvedExactRef: (value, itemPath) =>
            ExperimentExactCandidateV1.fromJson(value, path: itemPath),
      ),
    );
  }

  final ExperimentStableArmIdV1 stableArmId;
  final String label;
  final int relativeWeight;
  final ExperimentResolvedExactSelectionV1<ExperimentExactCandidateV1>
      candidateSelection;

  /// This arm in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'candidateSelection': _mutationSelectionJson(
          candidateSelection.toJson(),
        ),
        'kind': 'experimentDraftArmChoice',
        'label': label,
        'relativeWeight': relativeWeight,
        'stableArmId': stableArmId.value,
      };
}

/// One partial member-holdout candidate choice.
final class ExperimentResolvedPartialDraftMemberHoldoutChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedPartialDraftMemberHoldoutChoiceV1._(
    Map<String, Object?> json, {
    required this.holdoutId,
    required this.label,
    required this.candidateSelection,
  }) : super(json);

  factory ExperimentResolvedPartialDraftMemberHoldoutChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'candidateSelection',
        'holdoutId',
        'kind',
        'label',
      },
      requiredKeys: const {
        'candidateSelection',
        'holdoutId',
        'kind',
        'label',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftMemberHoldoutChoice');
    return ExperimentResolvedPartialDraftMemberHoldoutChoiceV1._(
      json,
      holdoutId: _identifier(
        reader.string('holdoutId'),
        '$path.holdoutId',
        AuthorityRevisionId.new,
      ),
      label: _boundedString(
        reader.string('label'),
        '$path.label',
        allowEmpty: true,
      ),
      candidateSelection: ExperimentResolvedExactSelectionV1<
          ExperimentExactCandidateV1>.fromJson(
        reader.object('candidateSelection'),
        path: '$path.candidateSelection',
        decodeResolvedExactRef: (value, itemPath) =>
            ExperimentExactCandidateV1.fromJson(value, path: itemPath),
      ),
    );
  }

  final AuthorityRevisionId holdoutId;
  final String label;
  final ExperimentResolvedExactSelectionV1<ExperimentExactCandidateV1>
      candidateSelection;

  /// This holdout in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'candidateSelection': _mutationSelectionJson(
          candidateSelection.toJson(),
        ),
        'holdoutId': holdoutId.value,
        'kind': 'experimentDraftMemberHoldoutChoice',
        'label': label,
      };
}

/// One selected installed projection set for a stable arm in a draft read.
///
/// An arm may be omitted from a binding's sets when the choices are sent back
/// as a replacement; it takes the set its siblings measure, resolved against
/// that arm's own candidate.
final class ExperimentResolvedPartialDraftArmProjectionSetChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedPartialDraftArmProjectionSetChoiceV1._(
    Map<String, Object?> json, {
    required this.installedProjectionSetChoice,
    required this.resolvedMembers,
    required this.stableArmId,
  }) : super(json);

  factory ExperimentResolvedPartialDraftArmProjectionSetChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'installedProjectionSetChoice',
        'kind',
        'resolvedMembers',
        'stableArmId',
      },
      requiredKeys: const {
        'installedProjectionSetChoice',
        'kind',
        'resolvedMembers',
        'stableArmId',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftArmProjectionSetChoice');
    final installedProjectionSetChoice = ExperimentResolvedExactSelectionV1<
        ExperimentInstalledProjectionSetCapabilityV1>.fromJson(
      reader.object('installedProjectionSetChoice'),
      path: '$path.installedProjectionSetChoice',
      decodeResolvedExactRef: (value, itemPath) =>
          ExperimentInstalledProjectionSetCapabilityV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    if (installedProjectionSetChoice.kind == 'serverDefault') {
      throw CanonicalFormatException(
        '$path.installedProjectionSetChoice must be an exact reference',
      );
    }
    final resolvedMembers = _objectList(
      reader.list('resolvedMembers'),
      path: '$path.resolvedMembers',
      maximumLength: kMaximumGeneratedPresentationReferenceCount,
      decode: (value, itemPath) =>
          ExperimentInstalledProjectionSetMemberV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      resolvedMembers.map((entry) => entry.identityKey),
      '$path.resolvedMembers.slotId',
    );
    _requireCanonicalOrder(
      resolvedMembers.map((entry) => entry.identityKey),
      '$path.resolvedMembers',
    );
    final selected = installedProjectionSetChoice.resolvedExactRef;
    if (selected == null && resolvedMembers.isNotEmpty) {
      throw CanonicalFormatException(
        '$path.resolvedMembers requires an installed projection-set choice',
      );
    }
    if (selected != null &&
        !_sameCanonicalValueLists(resolvedMembers, selected.members)) {
      throw CanonicalFormatException(
        '$path.resolvedMembers must match installedProjectionSetChoice',
      );
    }
    return ExperimentResolvedPartialDraftArmProjectionSetChoiceV1._(
      json,
      installedProjectionSetChoice: installedProjectionSetChoice,
      resolvedMembers: resolvedMembers,
      stableArmId: _identifier(
        reader.string('stableArmId'),
        '$path.stableArmId',
        ExperimentStableArmIdV1.new,
      ),
    );
  }

  final ExperimentResolvedExactSelectionV1<
          ExperimentInstalledProjectionSetCapabilityV1>
      installedProjectionSetChoice;
  final List<ExperimentInstalledProjectionSetMemberV1> resolvedMembers;
  final ExperimentStableArmIdV1 stableArmId;

  /// This projection set in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'installedProjectionSetChoice': _mutationSelectionJson(
          installedProjectionSetChoice.toJson(),
        ),
        'kind': 'experimentDraftArmProjectionSetChoice',
        'stableArmId': stableArmId.value,
      };
}

/// One stable metric-binding graph in a partial draft read.
final class ExperimentResolvedPartialDraftMetricBindingChoiceV1
    extends _ExperimentAuthoringValue {
  ExperimentResolvedPartialDraftMetricBindingChoiceV1._(
    Map<String, Object?> json, {
    required this.metricBindingId,
    required this.label,
    required this.metricDefinitionChoice,
    required this.armProjectionSets,
  }) : super(json);

  factory ExperimentResolvedPartialDraftMetricBindingChoiceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'armProjectionSets',
        'kind',
        'label',
        'metricBindingId',
        'metricDefinitionChoice',
      },
      requiredKeys: const {
        'armProjectionSets',
        'kind',
        'label',
        'metricBindingId',
        'metricDefinitionChoice',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftMetricBindingChoice');
    final metricBindingId = _identifier(
      reader.string('metricBindingId'),
      '$path.metricBindingId',
      ExperimentMetricBindingIdV1.new,
    );
    final armProjectionSets = _objectList(
      reader.list('armProjectionSets'),
      path: '$path.armProjectionSets',
      maximumLength: _maximumArms,
      decode: (value, itemPath) =>
          ExperimentResolvedPartialDraftArmProjectionSetChoiceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      armProjectionSets.map((entry) => entry.stableArmId.value),
      '$path.armProjectionSets.stableArmId',
    );
    return ExperimentResolvedPartialDraftMetricBindingChoiceV1._(
      json,
      metricBindingId: metricBindingId,
      label: _boundedString(
        reader.string('label'),
        '$path.label',
        allowEmpty: true,
      ),
      metricDefinitionChoice: ExperimentResolvedExactSelectionV1<
          ExperimentExactMetricDefinitionReferenceV1>.fromJson(
        reader.object('metricDefinitionChoice'),
        path: '$path.metricDefinitionChoice',
        decodeResolvedExactRef: (value, itemPath) =>
            ExperimentExactMetricDefinitionReferenceV1.fromJson(
          value,
          path: itemPath,
        ),
      ),
      armProjectionSets: armProjectionSets,
    );
  }

  final ExperimentMetricBindingIdV1 metricBindingId;
  final String label;
  final ExperimentResolvedExactSelectionV1<
      ExperimentExactMetricDefinitionReferenceV1> metricDefinitionChoice;
  final List<ExperimentResolvedPartialDraftArmProjectionSetChoiceV1>
      armProjectionSets;

  /// This metric binding in the draft-mutation vocabulary.
  Map<String, Object?> toMutationJson() => <String, Object?>{
        'armProjectionSets': [
          for (final set in armProjectionSets) set.toMutationJson(),
        ],
        'kind': 'experimentDraftMetricBindingChoice',
        'label': label,
        'metricBindingId': metricBindingId.value,
        'metricDefinitionChoice': _mutationSelectionJson(
          metricDefinitionChoice.toJson(),
        ),
      };
}

/// The complete or resolved-partial choices exposed by a draft read.
sealed class ExperimentDraftReadChoicesV1 extends _ExperimentAuthoringValue {
  ExperimentDraftReadChoicesV1._(super.json);

  factory ExperimentDraftReadChoicesV1.fromJson(
    Map<String, Object?> json, {
    required bool complete,
  }) =>
      complete
          ? ExperimentDraftChoicesV1.fromJson(json)
          : ExperimentResolvedPartialDraftChoicesV1.fromJson(json);

  List<CanonicalValue> get arms;
  ExperimentPolicySelectionV1 get assignmentAudienceSelection;

  /// These choices in the draft-mutation vocabulary.
  ///
  /// Every selection is rebuilt from its kind and, where one was chosen, the
  /// exact reference it names; what the platform resolved for the author is
  /// not sent back.
  Map<String, Object?> toMutationChoicesJson() {
    final json = toJson();
    final (arms, guardrails, memberHoldouts, metricBindings) = switch (this) {
      final ExperimentDraftChoicesV1 choices => (
          [for (final arm in choices.arms) arm.toMutationJson()],
          [for (final role in choices.guardrails) role.toMutationJson()],
          [
            for (final holdout in choices.memberHoldouts)
              holdout.toMutationJson(),
          ],
          [
            for (final binding in choices.metricBindings)
              binding.toMutationJson(),
          ],
        ),
      final ExperimentResolvedPartialDraftChoicesV1 choices => (
          [for (final arm in choices.arms) arm.toMutationJson()],
          [for (final role in choices.guardrails) role.toMutationJson()],
          [
            for (final holdout in choices.memberHoldouts)
              holdout.toMutationJson(),
          ],
          [
            for (final binding in choices.metricBindings)
              binding.toMutationJson(),
          ],
        ),
    };
    return <String, Object?>{
      'analysisSelection': _mutationAnalysisJson(
        _mutationObject(json, 'analysisSelection'),
      ),
      'arms': arms,
      'assignmentAudienceSelection': _mutationSelectionJson(
        _mutationObject(json, 'assignmentAudienceSelection'),
      ),
      'assignmentEligibilitySelection': _mutationSelectionJson(
        _mutationObject(json, 'assignmentEligibilitySelection'),
      ),
      'description': json['description'],
      'diagnosticBindingIds': json['diagnosticBindingIds'],
      'guardrails': guardrails,
      'kind': 'experimentDraftChoices',
      'label': json['label'],
      'layerHoldoutIds': json['layerHoldoutIds'],
      'memberHoldouts': memberHoldouts,
      'memberNoTreatment': _mutationSelectionJson(
        _mutationObject(json, 'memberNoTreatment'),
      ),
      'metricBindings': metricBindings,
      'primaryBindingSelection': _mutationSelectionJson(
        _mutationObject(json, 'primaryBindingSelection'),
      ),
      'randomizedUnitSelection': _mutationSelectionJson(
        _mutationObject(json, 'randomizedUnitSelection'),
      ),
      'rootSurfaceSelection': _mutationSelectionJson(
        _mutationObject(json, 'rootSurfaceSelection'),
      ),
      'subjectSelection': _mutationSelectionJson(
        _mutationObject(json, 'subjectSelection'),
      ),
    };
  }
}

Map<String, Object?> _mutationObject(Map<String, Object?> json, String key) =>
    requireCanonicalObject(json[key], 'experimentDraftChoices.$key');

/// One read selection in the draft-mutation vocabulary.
Map<String, Object?> _mutationSelectionJson(Map<String, Object?> selection) {
  final kind = selection['kind'];
  return switch (kind) {
    'unselected' || 'serverDefault' || 'subjectless' => <String, Object?>{
        'kind': kind,
      },
    'exactRef' || 'exactSubjectRef' => <String, Object?>{
        'exactRef': selection['resolvedExactRef'],
        'kind': kind,
      },
    'explicitValue' => <String, Object?>{
        'kind': kind,
        'value': selection['value'],
      },
    _ => throw CanonicalFormatException(
        'A draft selection of kind "$kind" has no mutation form',
      ),
  };
}

Map<String, Object?> _mutationAnalysisJson(Map<String, Object?> analysis) {
  final kind = analysis['kind'];
  return switch (kind) {
    'unselected' || 'measureOnly' => <String, Object?>{'kind': kind},
    'fixedHorizonNArmRate' => <String, Object?>{
        'kind': kind,
        'planningSelection': _mutationPlanningJson(
          _mutationObject(analysis, 'planningSelection'),
        ),
      },
    _ => throw CanonicalFormatException(
        'A draft analysis of kind "$kind" has no mutation form',
      ),
  };
}

Map<String, Object?> _mutationGuardrailPlanningJson(
  Map<String, Object?> guardrail,
) =>
    <String, Object?>{
      'expectedReferenceRate': guardrail['expectedReferenceRate'],
      'guardrailId': guardrail['guardrailId'],
      'harmMargin': guardrail['harmMargin'],
      'targetPower': guardrail['targetPower'],
    };

Map<String, Object?> _mutationPlanningJson(Map<String, Object?> planning) {
  final guardrails = planning['guardrails'];
  if (guardrails is! List<Object?>) {
    throw const CanonicalFormatException(
      'experimentNArmPlanningSelection.guardrails must be a list',
    );
  }
  return <String, Object?>{
    'allocationWeights': planning['allocationWeights'],
    'alphaChoice': _mutationSelectionJson(
      _mutationObject(planning, 'alphaChoice'),
    ),
    'enrollmentCap': planning['enrollmentCap'],
    'expectedBaseline': planning['expectedBaseline'],
    'followUpDurationMicros': planning['followUpDurationMicros'],
    'guardrails': [
      for (final value in guardrails)
        _mutationGuardrailPlanningJson(
          requireCanonicalObject(
            value,
            'experimentNArmPlanningSelection.guardrails[]',
          ),
        ),
    ],
    'kind': 'experimentNArmPlanningSelection',
    'maximumEnrollmentDurationMicros':
        planning['maximumEnrollmentDurationMicros'],
    'minimumDetectableEffect': planning['minimumDetectableEffect'],
    'outcomeGracePeriodMicros': planning['outcomeGracePeriodMicros'],
    'practicalSuperiorityMarginChoice': _mutationSelectionJson(
      _mutationObject(planning, 'practicalSuperiorityMarginChoice'),
    ),
    'primaryTargetPowerChoice': _mutationSelectionJson(
      _mutationObject(planning, 'primaryTargetPowerChoice'),
    ),
    'referenceArmId': planning['referenceArmId'],
    'schemaVersion': planning['schemaVersion'],
  };
}

/// Resolved public projection of zero or partial draft choices.
final class ExperimentResolvedPartialDraftChoicesV1
    extends ExperimentDraftReadChoicesV1 {
  ExperimentResolvedPartialDraftChoicesV1._(
    Map<String, Object?> json, {
    required this.analysisSelection,
    required this.arms,
    required this.assignmentAudienceSelection,
    required this.assignmentEligibilitySelection,
    required this.description,
    required this.diagnosticBindingIds,
    required this.guardrails,
    required this.label,
    required this.layerHoldoutIds,
    required this.memberHoldouts,
    required this.memberNoTreatment,
    required this.metricBindings,
    required this.primaryBindingSelection,
    required this.randomizedUnitSelection,
    required this.rootSurfaceSelection,
    required this.subjectSelection,
  }) : super._(json);

  factory ExperimentResolvedPartialDraftChoicesV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentResolvedPartialDraftChoices';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analysisSelection',
        'arms',
        'assignmentAudienceSelection',
        'assignmentEligibilitySelection',
        'description',
        'diagnosticBindingIds',
        'guardrails',
        'kind',
        'label',
        'layerHoldoutIds',
        'memberHoldouts',
        'memberNoTreatment',
        'metricBindings',
        'primaryBindingSelection',
        'randomizedUnitSelection',
        'rootSurfaceSelection',
        'subjectSelection',
      },
      requiredKeys: const {
        'analysisSelection',
        'arms',
        'assignmentAudienceSelection',
        'assignmentEligibilitySelection',
        'description',
        'diagnosticBindingIds',
        'guardrails',
        'kind',
        'label',
        'layerHoldoutIds',
        'memberHoldouts',
        'memberNoTreatment',
        'metricBindings',
        'primaryBindingSelection',
        'randomizedUnitSelection',
        'rootSurfaceSelection',
        'subjectSelection',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftChoices');
    final arms = _objectList(
      reader.list('arms'),
      path: '$path.arms',
      maximumLength: _maximumArms,
      decode: (value, itemPath) =>
          ExperimentResolvedPartialDraftArmChoiceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      arms.map((entry) => entry.stableArmId.value),
      '$path.arms.stableArmId',
    );
    final metricBindings = _objectList(
      reader.list('metricBindings'),
      path: '$path.metricBindings',
      maximumLength: _maximumRelatedValues,
      decode: (value, itemPath) =>
          ExperimentResolvedPartialDraftMetricBindingChoiceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      metricBindings.map((entry) => entry.metricBindingId.value),
      '$path.metricBindings.metricBindingId',
    );
    final primaryBindingSelection =
        ExperimentPrimaryBindingSelectionV1.fromJson(
      reader.object('primaryBindingSelection'),
      path: '$path.primaryBindingSelection',
    );
    return ExperimentResolvedPartialDraftChoicesV1._(
      json,
      analysisSelection: ExperimentPartialAnalysisSelectionV1.fromJson(
        reader.object('analysisSelection'),
        path: '$path.analysisSelection',
      ),
      arms: arms,
      assignmentAudienceSelection: _readPolicySelection(
        reader.object('assignmentAudienceSelection'),
        path: '$path.assignmentAudienceSelection',
        authorityKind:
            ExperimentCanonicalDefaultAuthorityKindV1.assignmentAudiencePolicy,
      ),
      assignmentEligibilitySelection: _readPolicySelection(
        reader.object('assignmentEligibilitySelection'),
        path: '$path.assignmentEligibilitySelection',
        authorityKind: ExperimentCanonicalDefaultAuthorityKindV1
            .assignmentEligibilityPolicy,
      ),
      description: _boundedString(
        reader.string('description'),
        '$path.description',
        allowEmpty: true,
      ),
      diagnosticBindingIds: _identifierList(
        reader.list('diagnosticBindingIds'),
        path: '$path.diagnosticBindingIds',
        maximumLength: _maximumRelatedValues,
        build: ExperimentMetricBindingIdV1.new,
      ),
      guardrails: _objectList(
        reader.list('guardrails'),
        path: '$path.guardrails',
        maximumLength: _maximumRelatedValues,
        decode: (value, itemPath) => ExperimentDraftGuardrailChoiceV1.fromJson(
          value,
          path: itemPath,
        ),
      ),
      label: _boundedString(
        reader.string('label'),
        '$path.label',
        allowEmpty: true,
      ),
      layerHoldoutIds: _identifierList(
        reader.list('layerHoldoutIds'),
        path: '$path.layerHoldoutIds',
        maximumLength: _maximumRelatedValues,
        build: AuthorityRevisionId.new,
      ),
      memberHoldouts: _objectList(
        reader.list('memberHoldouts'),
        path: '$path.memberHoldouts',
        maximumLength: _maximumRelatedValues,
        decode: (value, itemPath) =>
            ExperimentResolvedPartialDraftMemberHoldoutChoiceV1.fromJson(
          value,
          path: itemPath,
        ),
      ),
      memberNoTreatment: ExperimentResolvedExactSelectionV1<
          ExperimentExactCandidateV1>.fromJson(
        reader.object('memberNoTreatment'),
        path: '$path.memberNoTreatment',
        decodeResolvedExactRef: (value, itemPath) =>
            ExperimentExactCandidateV1.fromJson(value, path: itemPath),
      ),
      metricBindings: metricBindings,
      primaryBindingSelection: primaryBindingSelection,
      randomizedUnitSelection: ExperimentRandomizedUnitSelectionV1.fromJson(
        reader.object('randomizedUnitSelection'),
        path: '$path.randomizedUnitSelection',
      ),
      rootSurfaceSelection: ExperimentSurfaceSelectionV1.fromJson(
        reader.object('rootSurfaceSelection'),
        path: '$path.rootSurfaceSelection',
      ),
      subjectSelection: ExperimentSubjectSelectionV1.fromJson(
        reader.object('subjectSelection'),
        path: '$path.subjectSelection',
      ),
    );
  }

  final ExperimentPartialAnalysisSelectionV1 analysisSelection;
  @override
  final List<ExperimentResolvedPartialDraftArmChoiceV1> arms;
  @override
  final ExperimentPolicySelectionV1 assignmentAudienceSelection;
  final ExperimentPolicySelectionV1 assignmentEligibilitySelection;
  final String description;
  final List<ExperimentMetricBindingIdV1> diagnosticBindingIds;
  final List<ExperimentDraftGuardrailChoiceV1> guardrails;
  final String label;
  final List<AuthorityRevisionId> layerHoldoutIds;
  final List<ExperimentResolvedPartialDraftMemberHoldoutChoiceV1>
      memberHoldouts;
  final ExperimentResolvedExactSelectionV1<ExperimentExactCandidateV1>
      memberNoTreatment;
  final List<ExperimentResolvedPartialDraftMetricBindingChoiceV1>
      metricBindings;
  final ExperimentPrimaryBindingSelectionV1 primaryBindingSelection;
  final ExperimentRandomizedUnitSelectionV1 randomizedUnitSelection;
  final ExperimentSurfaceSelectionV1 rootSurfaceSelection;
  final ExperimentSubjectSelectionV1 subjectSelection;
}

/// Persisted semantic choices of an experiment draft.
final class ExperimentDraftChoicesV1 extends ExperimentDraftReadChoicesV1 {
  ExperimentDraftChoicesV1._(
    Map<String, Object?> json, {
    required this.analysisSelection,
    required this.arms,
    required this.assignmentAudienceSelection,
    required this.assignmentEligibilitySelection,
    required this.description,
    required this.diagnosticBindingIds,
    required this.guardrails,
    required this.label,
    required this.layerHoldoutIds,
    required this.memberHoldouts,
    required this.memberNoTreatment,
    required this.metricBindings,
    required this.primaryBindingSelection,
    required this.randomizedUnitSelection,
    required this.rootSurfaceSelection,
    required this.subjectSelection,
  }) : super._(json);

  /// Decodes strict draft choices.
  ///
  /// Pass [asReplacement] to decode choices being sent back as a replacement,
  /// where a metric binding may omit an arm that takes what its siblings
  /// measure. What the platform returns always covers every arm.
  factory ExperimentDraftChoicesV1.fromJson(
    Map<String, Object?> json, {
    bool asReplacement = false,
  }) {
    const path = 'experimentDraftChoices';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analysisSelection',
        'arms',
        'assignmentAudienceSelection',
        'assignmentEligibilitySelection',
        'description',
        'diagnosticBindingIds',
        'guardrails',
        'kind',
        'label',
        'layerHoldoutIds',
        'memberHoldouts',
        'memberNoTreatment',
        'metricBindings',
        'primaryBindingSelection',
        'randomizedUnitSelection',
        'rootSurfaceSelection',
        'subjectSelection',
      },
      requiredKeys: const {
        'analysisSelection',
        'arms',
        'assignmentAudienceSelection',
        'assignmentEligibilitySelection',
        'description',
        'diagnosticBindingIds',
        'guardrails',
        'kind',
        'label',
        'layerHoldoutIds',
        'memberHoldouts',
        'memberNoTreatment',
        'metricBindings',
        'primaryBindingSelection',
        'randomizedUnitSelection',
        'rootSurfaceSelection',
        'subjectSelection',
      },
      path: path,
    );
    _requireKind(reader, 'experimentDraftChoices');
    final arms = _objectList(
      reader.list('arms'),
      path: '$path.arms',
      maximumLength: _maximumArms,
      decode: (value, itemPath) =>
          ExperimentDraftArmChoiceV1.fromJson(value, path: itemPath),
    );
    _requireUnique(
      arms.map((entry) => entry.stableArmId.value),
      '$path.arms.stableArmId',
    );
    final metricBindings = _objectList(
      reader.list('metricBindings'),
      path: '$path.metricBindings',
      maximumLength: _maximumRelatedValues,
      decode: (value, itemPath) =>
          ExperimentDraftMetricBindingChoiceV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      metricBindings.map((entry) => entry.metricBindingId.value),
      '$path.metricBindings.metricBindingId',
    );
    final primaryBindingSelection =
        ExperimentPrimaryBindingSelectionV1.fromJson(
      reader.object('primaryBindingSelection'),
      path: '$path.primaryBindingSelection',
    );
    final primaryBindingId = primaryBindingSelection.resolvedExactRef;
    if (primaryBindingId == null) {
      throw CanonicalFormatException(
        '$path.primaryBindingSelection must be resolved',
      );
    }
    final diagnosticBindingIds = _identifierList(
      reader.list('diagnosticBindingIds'),
      path: '$path.diagnosticBindingIds',
      maximumLength: _maximumRelatedValues,
      build: ExperimentMetricBindingIdV1.new,
    );
    final guardrails = _objectList(
      reader.list('guardrails'),
      path: '$path.guardrails',
      maximumLength: _maximumRelatedValues,
      decode: (value, itemPath) =>
          ExperimentDraftGuardrailChoiceV1.fromJson(value, path: itemPath),
    );
    final bindingIds =
        metricBindings.map((entry) => entry.metricBindingId.value).toSet();
    for (final bindingId in <ExperimentMetricBindingIdV1>[
      primaryBindingId.metricBindingId,
      ...diagnosticBindingIds,
      ...guardrails.map((entry) => entry.metricBindingId),
    ]) {
      if (!bindingIds.contains(bindingId.value)) {
        throw CanonicalFormatException(
          '$path references an absent metric binding',
        );
      }
    }
    final analysisSelection = ExperimentAnalysisSelectionV1.fromJson(
      reader.object('analysisSelection'),
    );
    if (analysisSelection is ExperimentFixedHorizonNArmRateSelectionV1) {
      _requireExactGuardrailPlanningClosure(
        analysisSelection.planningSelection,
        guardrails,
        metricBindings,
        path,
      );
    }
    final choices = ExperimentDraftChoicesV1._(
      json,
      analysisSelection: analysisSelection,
      arms: arms,
      assignmentAudienceSelection: _readPolicySelection(
        reader.object('assignmentAudienceSelection'),
        path: '$path.assignmentAudienceSelection',
        authorityKind:
            ExperimentCanonicalDefaultAuthorityKindV1.assignmentAudiencePolicy,
      ),
      assignmentEligibilitySelection: _readPolicySelection(
        reader.object('assignmentEligibilitySelection'),
        path: '$path.assignmentEligibilitySelection',
        authorityKind: ExperimentCanonicalDefaultAuthorityKindV1
            .assignmentEligibilityPolicy,
      ),
      description: _boundedString(
        reader.string('description'),
        '$path.description',
      ),
      diagnosticBindingIds: diagnosticBindingIds,
      guardrails: guardrails,
      label: _boundedString(reader.string('label'), '$path.label'),
      layerHoldoutIds: _identifierList(
        reader.list('layerHoldoutIds'),
        path: '$path.layerHoldoutIds',
        maximumLength: _maximumRelatedValues,
        build: AuthorityRevisionId.new,
      ),
      memberHoldouts: _objectList(
        reader.list('memberHoldouts'),
        path: '$path.memberHoldouts',
        maximumLength: _maximumRelatedValues,
        decode: (value, itemPath) =>
            ExperimentDraftMemberHoldoutChoiceV1.fromJson(
          value,
          path: itemPath,
        ),
      ),
      memberNoTreatment: ExperimentResolvedExactSelectionV1<
          ExperimentExactCandidateV1>.fromJson(
        reader.object('memberNoTreatment'),
        path: '$path.memberNoTreatment',
        decodeResolvedExactRef: (value, itemPath) =>
            ExperimentExactCandidateV1.fromJson(value, path: itemPath),
      ),
      metricBindings: metricBindings,
      primaryBindingSelection: primaryBindingSelection,
      randomizedUnitSelection: ExperimentRandomizedUnitSelectionV1.fromJson(
        reader.object('randomizedUnitSelection'),
        path: '$path.randomizedUnitSelection',
      ),
      rootSurfaceSelection: ExperimentSurfaceSelectionV1.fromJson(
        reader.object('rootSurfaceSelection'),
        path: '$path.rootSurfaceSelection',
      ),
      subjectSelection: ExperimentSubjectSelectionV1.fromJson(
        reader.object('subjectSelection'),
        path: '$path.subjectSelection',
      ),
    );
    _requireCompleteDraftChoices(choices, path, asReplacement: asReplacement);
    return choices;
  }

  final ExperimentAnalysisSelectionV1 analysisSelection;
  @override
  final List<ExperimentDraftArmChoiceV1> arms;
  @override
  final ExperimentPolicySelectionV1 assignmentAudienceSelection;
  final ExperimentPolicySelectionV1 assignmentEligibilitySelection;
  final String description;
  final List<ExperimentMetricBindingIdV1> diagnosticBindingIds;
  final List<ExperimentDraftGuardrailChoiceV1> guardrails;
  final String label;
  final List<AuthorityRevisionId> layerHoldoutIds;
  final List<ExperimentDraftMemberHoldoutChoiceV1> memberHoldouts;
  final ExperimentResolvedExactSelectionV1<ExperimentExactCandidateV1>
      memberNoTreatment;
  final List<ExperimentDraftMetricBindingChoiceV1> metricBindings;
  final ExperimentPrimaryBindingSelectionV1 primaryBindingSelection;
  final ExperimentRandomizedUnitSelectionV1 randomizedUnitSelection;
  final ExperimentSurfaceSelectionV1 rootSurfaceSelection;
  final ExperimentSubjectSelectionV1 subjectSelection;
}

void _requireCompleteDraftChoices(
  ExperimentDraftChoicesV1 choices,
  String path, {
  bool asReplacement = false,
}) {
  if (choices.arms.length < 2) {
    throw CanonicalFormatException(
      '$path.arms must contain 2..$_maximumArms entries',
    );
  }
  if (choices.rootSurfaceSelection.resolvedExactRef == null ||
      choices.assignmentAudienceSelection.resolvedExactRef == null ||
      choices.assignmentEligibilitySelection.resolvedExactRef == null ||
      choices.memberNoTreatment.resolvedExactRef == null ||
      choices.primaryBindingSelection.resolvedExactRef == null) {
    throw CanonicalFormatException(
      '$path must resolve every required selection',
    );
  }
  if (choices.metricBindings.isEmpty ||
      choices.metricBindings.any(
        (binding) =>
            binding.metricDefinitionChoice.resolvedExactRef == null ||
            binding.armProjectionSets.any(
              (set) =>
                  set.installedProjectionSetChoice.resolvedExactRef == null ||
                  set.resolvedMembers.isEmpty,
            ),
      )) {
    throw CanonicalFormatException(
      '$path.metricBindings must resolve every selected metric',
    );
  }
  final armIds = choices.arms.map((arm) => arm.stableArmId.value);
  for (final binding in choices.metricBindings) {
    final setPath = '$path.metricBindings.${binding.metricBindingId.value}'
        '.armProjectionSets';
    final setArmIds = binding.armProjectionSets.map(
      (set) => set.stableArmId.value,
    );
    if (asReplacement) {
      _requireIdentifierSubset(
        expected: armIds,
        actual: setArmIds,
        path: setPath,
        expectedDescription: '$path.arms',
      );
    } else {
      _requireExactIdentifierSet(
        expected: armIds,
        actual: setArmIds,
        path: setPath,
        expectedDescription: '$path.arms',
      );
    }
  }
  final analysis = choices.analysisSelection;
  if (analysis is ExperimentFixedHorizonNArmRateSelectionV1) {
    _requireExactIdentifierSet(
      expected: armIds,
      actual: analysis.planningSelection.allocationWeights.map(
        (weight) => weight.armId.value,
      ),
      path: '$path.analysisSelection.planningSelection.allocationWeights',
      expectedDescription: '$path.arms',
    );
  }
}

/// Requires distinct identifiers, every one of them among [expected].
void _requireIdentifierSubset({
  required Iterable<String> expected,
  required Iterable<String> actual,
  required String path,
  required String expectedDescription,
}) {
  final actualList = actual.toList(growable: false);
  final actualSet = actualList.toSet();
  if (actualSet.length != actualList.length ||
      !expected.toSet().containsAll(actualSet)) {
    throw CanonicalFormatException(
      '$path must name distinct entries drawn from $expectedDescription',
    );
  }
}

void _requireExactIdentifierSet({
  required Iterable<String> expected,
  required Iterable<String> actual,
  required String path,
  required String expectedDescription,
}) {
  final expectedSet = expected.toSet();
  final actualSet = actual.toSet();
  if (expectedSet.length != actualSet.length ||
      !expectedSet.containsAll(actualSet)) {
    throw CanonicalFormatException(
      '$path must exactly match $expectedDescription',
    );
  }
}

void _requireExactGuardrailPlanningClosure(
  ExperimentNArmPlanningSelectionV1 planning,
  List<ExperimentDraftGuardrailChoiceV1> roles,
  List<ExperimentDraftMetricBindingChoiceV1> bindings,
  String path,
) {
  final plannedById = {
    for (final guardrail in planning.guardrails)
      guardrail.guardrailId.value: guardrail,
  };
  if (plannedById.length != roles.length ||
      roles.any((role) => !plannedById.containsKey(role.guardrailId.value))) {
    throw CanonicalFormatException(
      '$path.analysisSelection guardrails do not match metric roles',
    );
  }
  final bindingsById = {
    for (final binding in bindings) binding.metricBindingId.value: binding,
  };
  for (final role in roles) {
    final binding = bindingsById[role.metricBindingId.value];
    final definition = binding?.metricDefinitionChoice.resolvedExactRef;
    final planned = plannedById[role.guardrailId.value]!;
    final expectedDirection = switch (definition?.direction) {
      ExperimentMetricDirectionV1.higherIsBetter =>
        ExperimentAdverseDirectionV1.lowerIsWorse,
      ExperimentMetricDirectionV1.lowerIsBetter =>
        ExperimentAdverseDirectionV1.higherIsWorse,
      ExperimentMetricDirectionV1.none || null => null,
    };
    if (expectedDirection == null ||
        planned.adverseDirection != expectedDirection) {
      throw CanonicalFormatException(
        '$path.analysisSelection guardrail direction disagrees with its '
        'metric definition',
      );
    }
  }
}

/// Exact draft revision and compare-and-swap binding.
final class ExperimentDraftBindingV1 extends _ExperimentAuthoringValue {
  ExperimentDraftBindingV1._(
    Map<String, Object?> json, {
    required this.draftId,
    required this.draftRevisionId,
    required this.expectedCas,
  }) : super(json);

  factory ExperimentDraftBindingV1.fromJson(
    Map<String, Object?> json, {
    String path = 'experimentDraftBinding',
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'draftId', 'draftRevisionId', 'expectedCas'},
      requiredKeys: const {'draftId', 'draftRevisionId', 'expectedCas'},
      path: path,
    );
    return ExperimentDraftBindingV1._(
      json,
      draftId: _identifier(
        reader.string('draftId'),
        '$path.draftId',
        ExperimentDraftIdV1.new,
      ),
      draftRevisionId: _identifier(
        reader.string('draftRevisionId'),
        '$path.draftRevisionId',
        ExperimentDraftRevisionIdV1.new,
      ),
      expectedCas: _boundedString(
        reader.string('expectedCas'),
        '$path.expectedCas',
      ),
    );
  }

  final ExperimentDraftIdV1 draftId;
  final ExperimentDraftRevisionIdV1 draftRevisionId;
  final String expectedCas;
}

/// Completeness projection for a draft revision.
final class ExperimentDraftCompletenessV1 extends _ExperimentAuthoringValue {
  ExperimentDraftCompletenessV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.missingFieldPaths,
  }) : super(json);

  factory ExperimentDraftCompletenessV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = ExperimentDraftCompletenessKindV1._fromWire(
      _readDiscriminator(json, path),
      '$path.kind',
    );
    final incomplete = kind == ExperimentDraftCompletenessKindV1.incomplete;
    final reader = CanonicalObjectReader(
      json,
      allowedKeys:
          incomplete ? const {'kind', 'missingFieldPaths'} : const {'kind'},
      requiredKeys:
          incomplete ? const {'kind', 'missingFieldPaths'} : const {'kind'},
      path: path,
    );
    final missingFieldPaths = incomplete
        ? _stringList(
            reader.list('missingFieldPaths'),
            path: '$path.missingFieldPaths',
            maximumLength: _maximumIssues,
          )
        : const <String>[];
    if (incomplete) {
      if (missingFieldPaths.isEmpty) {
        throw CanonicalFormatException(
          '$path.missingFieldPaths must contain at least one entry',
        );
      }
      _requireCanonicalOrder(missingFieldPaths, '$path.missingFieldPaths');
    }
    return ExperimentDraftCompletenessV1._(
      json,
      kind: kind,
      missingFieldPaths: missingFieldPaths,
    );
  }

  final ExperimentDraftCompletenessKindV1 kind;
  final List<String> missingFieldPaths;
}

/// Typed draft conflict returned by a safe draft projection.
final class ExperimentDraftConflictV1 extends _ExperimentAuthoringValue {
  ExperimentDraftConflictV1._(
    Map<String, Object?> json, {
    required this.code,
    required this.fieldPath,
    required this.messageKey,
  }) : super(json);

  factory ExperimentDraftConflictV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'fieldPath', 'kind', 'messageKey'},
      requiredKeys: const {'code', 'fieldPath', 'kind', 'messageKey'},
      path: path,
    );
    _requireKind(reader, 'experimentDraftConflict');
    return ExperimentDraftConflictV1._(
      json,
      code: _boundedString(reader.string('code'), '$path.code'),
      fieldPath: _boundedString(reader.string('fieldPath'), '$path.fieldPath'),
      messageKey: _boundedString(
        reader.string('messageKey'),
        '$path.messageKey',
      ),
    );
  }

  final String code;
  final String fieldPath;
  final String messageKey;
}

/// An accepted response that names the target it was resolved against.
///
/// A caller that addressed one target can compare it against every response
/// that carries one, without knowing which response it received.
abstract interface class ExperimentTargetBoundViewV1 {
  /// The target this response was resolved against.
  TargetCoordinate get target;
}

/// Safe public projection of one durable experiment draft.
final class ExperimentDraftViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentDraftViewV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.draftId,
    required this.draftRevisionId,
    required this.expectedCas,
    required this.revisionOrdinal,
    required this.semanticDigest,
    required this.choices,
    required this.completeness,
    required this.conflicts,
  }) : super(json);

  /// Decodes a strict draft projection.
  factory ExperimentDraftViewV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentDraftView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'choices',
        'completeness',
        'conflicts',
        'draftId',
        'draftRevisionId',
        'expectedCas',
        'experimentId',
        'kind',
        'revisionOrdinal',
        'schemaVersion',
        'semanticDigest',
        'target',
      },
      requiredKeys: const {
        'choices',
        'completeness',
        'conflicts',
        'draftId',
        'draftRevisionId',
        'expectedCas',
        'experimentId',
        'kind',
        'revisionOrdinal',
        'schemaVersion',
        'semanticDigest',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentDraftView');
    final revisionOrdinal = _positiveInteger(
      reader.integer('revisionOrdinal'),
      '$path.revisionOrdinal',
    );
    final completeness = ExperimentDraftCompletenessV1.fromJson(
      reader.object('completeness'),
      path: '$path.completeness',
    );
    final choices = ExperimentDraftReadChoicesV1.fromJson(
      reader.object('choices'),
      complete: completeness.kind == ExperimentDraftCompletenessKindV1.complete,
    );
    final choicesArePartial =
        choices is ExperimentResolvedPartialDraftChoicesV1;
    final draftIsIncomplete =
        completeness.kind == ExperimentDraftCompletenessKindV1.incomplete;
    if (choicesArePartial != draftIsIncomplete) {
      throw const CanonicalFormatException(
        'experimentDraftView choices do not match completeness',
      );
    }
    return ExperimentDraftViewV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      experimentId: _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      ),
      draftId: _identifier(
        reader.string('draftId'),
        '$path.draftId',
        ExperimentDraftIdV1.new,
      ),
      draftRevisionId: _identifier(
        reader.string('draftRevisionId'),
        '$path.draftRevisionId',
        ExperimentDraftRevisionIdV1.new,
      ),
      expectedCas: _boundedString(
        reader.string('expectedCas'),
        '$path.expectedCas',
      ),
      revisionOrdinal: revisionOrdinal,
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
      choices: choices,
      completeness: completeness,
      conflicts: _objectList(
        reader.list('conflicts'),
        path: '$path.conflicts',
        maximumLength: _maximumIssues,
        decode: (value, itemPath) =>
            ExperimentDraftConflictV1.fromJson(value, path: itemPath),
      ),
    );
  }

  final TargetCoordinate target;
  final ExperimentPublicIdV1 experimentId;
  final ExperimentDraftIdV1 draftId;
  final ExperimentDraftRevisionIdV1 draftRevisionId;
  final String expectedCas;
  final int revisionOrdinal;
  final CanonicalDigest semanticDigest;
  final ExperimentDraftReadChoicesV1 choices;
  final ExperimentDraftCompletenessV1 completeness;
  final List<ExperimentDraftConflictV1> conflicts;
}

/// Availability of one authorization action at a discovered target.
final class ExperimentActionAvailabilityV1 extends _ExperimentAuthoringValue {
  ExperimentActionAvailabilityV1._(
    Map<String, Object?> json, {
    required this.action,
    required this.available,
    required this.reasonCode,
  }) : super(json);

  factory ExperimentActionAvailabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'action', 'available', 'kind', 'reasonCode'},
      requiredKeys: const {'action', 'available', 'kind'},
      path: path,
    );
    _requireKind(reader, 'experimentActionAvailability');
    final available = reader.boolean('available');
    final reasonCode = reader.optionalString('reasonCode');
    if (available == (reasonCode != null)) {
      throw CanonicalFormatException(
        '$path.reasonCode must be present exactly when unavailable',
      );
    }
    return ExperimentActionAvailabilityV1._(
      json,
      action: ExperimentActionV1._fromWire(
        reader.string('action'),
        '$path.action',
      ),
      available: available,
      reasonCode: reasonCode == null
          ? null
          : _boundedString(reasonCode, '$path.reasonCode'),
    );
  }

  final ExperimentActionV1 action;
  final bool available;
  final String? reasonCode;
}

/// One selectable named environment.
final class ExperimentNamedEnvironmentOptionV1
    extends _ExperimentAuthoringValue {
  ExperimentNamedEnvironmentOptionV1._(
    Map<String, Object?> json, {
    required this.namedEnvironmentId,
    required this.label,
    required this.selected,
  }) : super(json);

  factory ExperimentNamedEnvironmentOptionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'label', 'namedEnvironmentId', 'selected'},
      requiredKeys: const {'kind', 'label', 'namedEnvironmentId', 'selected'},
      path: path,
    );
    _requireKind(reader, 'experimentNamedEnvironmentOption');
    final id = reader.integer('namedEnvironmentId');
    return ExperimentNamedEnvironmentOptionV1._(
      json,
      namedEnvironmentId: _positiveIdentifier(
        id,
        '$path.namedEnvironmentId',
        NamedEnvironmentId.new,
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      selected: reader.boolean('selected'),
    );
  }

  final NamedEnvironmentId namedEnvironmentId;
  final String label;
  final bool selected;
}

/// One selectable runtime plane.
final class ExperimentRuntimePlaneOptionV1 extends _ExperimentAuthoringValue {
  ExperimentRuntimePlaneOptionV1._(
    Map<String, Object?> json, {
    required this.runtimePlane,
    required this.label,
    required this.selected,
  }) : super(json);

  factory ExperimentRuntimePlaneOptionV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'label', 'runtimePlane', 'selected'},
      requiredKeys: const {'kind', 'label', 'runtimePlane', 'selected'},
      path: path,
    );
    _requireKind(reader, 'experimentRuntimePlaneOption');
    final runtimePlane = reader.string('runtimePlane');
    if (runtimePlane != 'sandbox' && runtimePlane != 'live') {
      throw CanonicalFormatException(
        '$path.runtimePlane "$runtimePlane" is unsupported',
      );
    }
    return ExperimentRuntimePlaneOptionV1._(
      json,
      runtimePlane: runtimePlane,
      label: _boundedString(reader.string('label'), '$path.label'),
      selected: reader.boolean('selected'),
    );
  }

  final String runtimePlane;
  final String label;
  final bool selected;
}

/// One compatible exact published surface.
final class ExperimentSurfaceCapabilityV1 extends _ExperimentAuthoringValue {
  ExperimentSurfaceCapabilityV1._(
    Map<String, Object?> json, {
    required this.analysisChoices,
    required this.deliverySurfaceType,
    required this.installedMetricCapabilities,
    required this.label,
    required this.surfaceReference,
    required this.treatmentOrigins,
  }) : super(json);

  factory ExperimentSurfaceCapabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analysisChoices',
        'deliverySurfaceType',
        'installedMetricCapabilities',
        'kind',
        'label',
        'surfaceReference',
        'treatmentOrigins',
      },
      requiredKeys: const {
        'analysisChoices',
        'deliverySurfaceType',
        'installedMetricCapabilities',
        'kind',
        'label',
        'surfaceReference',
        'treatmentOrigins',
      },
      path: path,
    );
    _requireKind(reader, 'experimentSurfaceCapability');
    final analysisChoices = _enumList(
      reader.list('analysisChoices'),
      path: '$path.analysisChoices',
      maximumLength: ExperimentAnalysisKindV1.values.length,
      decode: ExperimentAnalysisKindV1._fromWire,
    );
    final treatmentOrigins = _objectList(
      reader.list('treatmentOrigins'),
      path: '$path.treatmentOrigins',
      minimumLength: 1,
      maximumLength: 2,
      decode: (value, itemPath) =>
          ExperimentTreatmentOriginV1.fromJson(value, path: itemPath),
    );
    _requireUnique(
      treatmentOrigins.map((origin) => utf8.decode(origin.canonicalBytes)),
      '$path.treatmentOrigins',
    );
    if (treatmentOrigins.first is! ExperimentWholeSurfaceTreatmentOriginV1 ||
        (treatmentOrigins.length == 2 &&
            treatmentOrigins[1] is! ExperimentPointSubtreeTreatmentOriginV1)) {
      throw const CanonicalFormatException(
        'experimentSurfaceCapability.treatmentOrigins must contain wholeSurface followed by an optional pointSubtree origin',
      );
    }
    final installedMetricCapabilities = _objectList(
      reader.list('installedMetricCapabilities'),
      path: '$path.installedMetricCapabilities',
      maximumLength: kMaximumGeneratedPresentationReferenceCount,
      decode: (value, itemPath) =>
          ExperimentInstalledMetricCapabilityV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      installedMetricCapabilities.map((entry) => entry.identityKey),
      '$path.installedMetricCapabilities',
    );
    _requireCanonicalOrder(
      installedMetricCapabilities.map((entry) => entry.identityKey),
      '$path.installedMetricCapabilities',
    );
    return ExperimentSurfaceCapabilityV1._(
      json,
      analysisChoices: analysisChoices,
      deliverySurfaceType: _identifier(
        reader.string('deliverySurfaceType'),
        '$path.deliverySurfaceType',
        DeliverySurfaceTypeId.new,
      ),
      installedMetricCapabilities: installedMetricCapabilities,
      label: _boundedString(reader.string('label'), '$path.label'),
      surfaceReference: ExperimentExactSurfaceReferenceV1.fromJson(
        reader.object('surfaceReference'),
        path: '$path.surfaceReference',
      ),
      treatmentOrigins: treatmentOrigins,
    );
  }

  final List<ExperimentAnalysisKindV1> analysisChoices;
  final DeliverySurfaceTypeId deliverySurfaceType;
  final List<ExperimentInstalledMetricCapabilityV1> installedMetricCapabilities;
  final String label;
  final ExperimentExactSurfaceReferenceV1 surfaceReference;
  final List<ExperimentTreatmentOriginV1> treatmentOrigins;

  /// Builds one exact candidate from a discovered treatment origin.
  ExperimentExactCandidateV1 exactCandidateFor(
    ExperimentTreatmentOriginV1 origin,
  ) {
    if (!treatmentOrigins.contains(origin)) {
      throw ArgumentError.value(
        origin,
        'origin',
        'must be a discovered treatment origin for this surface',
      );
    }
    return ExperimentExactCandidateV1.fromJson({
      'kind': 'exactCandidate',
      'label': label,
      'surfaceReference': surfaceReference.toJson(),
      'treatmentOrigin': origin.toJson(),
    }, path: 'experimentSurfaceCapability.exactCandidateFor');
  }
}

/// Closed reasons for an unavailable metric capability.
enum ExperimentMetricCapabilityUnavailableReasonV1 {
  presentationUnavailable('metric.presentationUnavailable'),
  installedProjectionUnavailable('metric.installedProjectionUnavailable');

  const ExperimentMetricCapabilityUnavailableReasonV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentMetricCapabilityUnavailableReasonV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Availability of one metric capability.
final class ExperimentMetricCapabilityAvailabilityV1
    extends _ExperimentAuthoringValue {
  ExperimentMetricCapabilityAvailabilityV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.reasonCode,
  }) : super(json);

  factory ExperimentMetricCapabilityAvailabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = _readDiscriminator(json, path);
    final available = kind == 'available';
    if (!available && kind != 'unavailable') {
      throw CanonicalFormatException('$path.kind "$kind" is unsupported');
    }
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: available ? const {'kind'} : const {'kind', 'reasonCode'},
      requiredKeys: available ? const {'kind'} : const {'kind', 'reasonCode'},
      path: path,
    );
    return ExperimentMetricCapabilityAvailabilityV1._(
      json,
      kind: kind,
      reasonCode: available
          ? null
          : ExperimentMetricCapabilityUnavailableReasonV1._fromWire(
              reader.string('reasonCode'),
              '$path.reasonCode',
            ),
    );
  }

  final String kind;
  final ExperimentMetricCapabilityUnavailableReasonV1? reasonCode;

  bool get isAvailable => kind == 'available';
}

/// Exact installed metric-binding authority for one presentation group.
final class ExperimentExactMetricBindingReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactMetricBindingReferenceV1._(
    Map<String, Object?> json, {
    required this.canonicalDigest,
    required this.metricBindingId,
    required this.metricBindingRevisionId,
    required this.semanticDigest,
  }) : super(json);

  factory ExperimentExactMetricBindingReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'canonicalDigest',
        'metricBindingId',
        'metricBindingRevisionId',
        'semanticDigest',
      },
      requiredKeys: const {
        'canonicalDigest',
        'metricBindingId',
        'metricBindingRevisionId',
        'semanticDigest',
      },
      path: path,
    );
    return ExperimentExactMetricBindingReferenceV1._(
      json,
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      metricBindingId: _identifier(
        reader.string('metricBindingId'),
        '$path.metricBindingId',
        AuthorityRevisionId.new,
      ),
      metricBindingRevisionId: _identifier(
        reader.string('metricBindingRevisionId'),
        '$path.metricBindingRevisionId',
        AuthorityRevisionId.new,
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final CanonicalDigest canonicalDigest;
  final AuthorityRevisionId metricBindingId;
  final AuthorityRevisionId metricBindingRevisionId;
  final CanonicalDigest semanticDigest;

  String get identityKey =>
      '${metricBindingId.value}\u0000${metricBindingRevisionId.value}'
      '\u0000${canonicalDigest.hex}\u0000${semanticDigest.hex}';
}

/// Exact installed projection-set authority for one presentation group.
final class ExperimentExactProjectionSetReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactProjectionSetReferenceV1._(
    Map<String, Object?> json, {
    required this.canonicalDigest,
    required this.projectionSetId,
    required this.semanticDigest,
  }) : super(json);

  factory ExperimentExactProjectionSetReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'canonicalDigest',
        'projectionSetId',
        'semanticDigest',
      },
      requiredKeys: const {
        'canonicalDigest',
        'projectionSetId',
        'semanticDigest',
      },
      path: path,
    );
    return ExperimentExactProjectionSetReferenceV1._(
      json,
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      projectionSetId: _identifier(
        reader.string('projectionSetId'),
        '$path.projectionSetId',
        AuthorityRevisionId.new,
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final CanonicalDigest canonicalDigest;
  final AuthorityRevisionId projectionSetId;
  final CanonicalDigest semanticDigest;

  String get identityKey =>
      '${projectionSetId.value}\u0000${canonicalDigest.hex}'
      '\u0000${semanticDigest.hex}';
}

/// Exact compatibility-proof authority for one presentation group.
final class ExperimentExactCompatibilityProofReferenceV1
    extends _ExperimentAuthoringValue {
  ExperimentExactCompatibilityProofReferenceV1._(
    Map<String, Object?> json, {
    required this.canonicalDigest,
    required this.compatibilityProofRevisionId,
    required this.semanticDigest,
  }) : super(json);

  factory ExperimentExactCompatibilityProofReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'canonicalDigest',
        'compatibilityProofRevisionId',
        'semanticDigest',
      },
      requiredKeys: const {
        'canonicalDigest',
        'compatibilityProofRevisionId',
        'semanticDigest',
      },
      path: path,
    );
    return ExperimentExactCompatibilityProofReferenceV1._(
      json,
      canonicalDigest: _parsedDigest(
        reader.string('canonicalDigest'),
        '$path.canonicalDigest',
      ),
      compatibilityProofRevisionId: _identifier(
        reader.string('compatibilityProofRevisionId'),
        '$path.compatibilityProofRevisionId',
        AuthorityRevisionId.new,
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
    );
  }

  final CanonicalDigest canonicalDigest;
  final AuthorityRevisionId compatibilityProofRevisionId;
  final CanonicalDigest semanticDigest;

  String get identityKey =>
      '${compatibilityProofRevisionId.value}\u0000${canonicalDigest.hex}'
      '\u0000${semanticDigest.hex}';
}

/// One installed projection member in a complete presentation group.
final class ExperimentInstalledProjectionSetMemberV1
    extends _ExperimentAuthoringValue {
  ExperimentInstalledProjectionSetMemberV1._(
    Map<String, Object?> json, {
    required this.projectionReference,
    required this.slotId,
  }) : super(json);

  factory ExperimentInstalledProjectionSetMemberV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'projectionReference', 'slotId'},
      requiredKeys: const {'kind', 'projectionReference', 'slotId'},
      path: path,
    );
    _requireKind(reader, 'experimentInstalledProjectionSetMember');
    return ExperimentInstalledProjectionSetMemberV1._(
      json,
      projectionReference: ExperimentExactSlotProjectionReferenceV1.fromJson(
        reader.object('projectionReference'),
        path: '$path.projectionReference',
      ),
      slotId: _identifier(
        reader.string('slotId'),
        '$path.slotId',
        AuthorityRevisionId.new,
      ),
    );
  }

  final ExperimentExactSlotProjectionReferenceV1 projectionReference;
  final AuthorityRevisionId slotId;

  String get identityKey => slotId.value;
}

/// One complete installed projection set available for a surface-local metric.
final class ExperimentInstalledProjectionSetCapabilityV1
    extends _ExperimentAuthoringValue {
  ExperimentInstalledProjectionSetCapabilityV1._(
    Map<String, Object?> json, {
    required this.compatibilityProofReference,
    required this.label,
    required this.members,
    required this.metricBindingReference,
    required this.projectionSetReference,
  }) : super(json);

  factory ExperimentInstalledProjectionSetCapabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'compatibilityProofReference',
        'kind',
        'label',
        'members',
        'metricBindingReference',
        'projectionSetReference',
      },
      requiredKeys: const {
        'compatibilityProofReference',
        'kind',
        'label',
        'members',
        'metricBindingReference',
        'projectionSetReference',
      },
      path: path,
    );
    _requireKind(reader, 'experimentInstalledProjectionSetCapability');
    final members = _objectList(
      reader.list('members'),
      path: '$path.members',
      minimumLength: 1,
      maximumLength: kMaximumGeneratedPresentationReferenceCount,
      decode: (value, itemPath) =>
          ExperimentInstalledProjectionSetMemberV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      members.map((entry) => entry.identityKey),
      '$path.members.slotId',
    );
    _requireCanonicalOrder(
      members.map((entry) => entry.identityKey),
      '$path.members',
    );
    return ExperimentInstalledProjectionSetCapabilityV1._(
      json,
      compatibilityProofReference:
          ExperimentExactCompatibilityProofReferenceV1.fromJson(
        reader.object('compatibilityProofReference'),
        path: '$path.compatibilityProofReference',
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      members: members,
      metricBindingReference: ExperimentExactMetricBindingReferenceV1.fromJson(
        reader.object('metricBindingReference'),
        path: '$path.metricBindingReference',
      ),
      projectionSetReference: ExperimentExactProjectionSetReferenceV1.fromJson(
        reader.object('projectionSetReference'),
        path: '$path.projectionSetReference',
      ),
    );
  }

  final ExperimentExactCompatibilityProofReferenceV1
      compatibilityProofReference;
  final String label;
  final List<ExperimentInstalledProjectionSetMemberV1> members;
  final ExperimentExactMetricBindingReferenceV1 metricBindingReference;
  final ExperimentExactProjectionSetReferenceV1 projectionSetReference;

  String get identityKey => '${metricBindingReference.identityKey}\u0000'
      '${projectionSetReference.identityKey}\u0000'
      '${compatibilityProofReference.identityKey}';
}

/// One surface-local metric and its complete installed presentation groups.
final class ExperimentInstalledMetricCapabilityV1
    extends _ExperimentAuthoringValue {
  ExperimentInstalledMetricCapabilityV1._(
    Map<String, Object?> json, {
    required this.availability,
    required this.installedProjectionSets,
    required this.metricDefinitionId,
    required this.metricDefinitionRevisionId,
    required this.metricDefinitionSemanticDigest,
  }) : super(json);

  factory ExperimentInstalledMetricCapabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'availability',
        'installedProjectionSets',
        'kind',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
      },
      requiredKeys: const {
        'availability',
        'installedProjectionSets',
        'kind',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
      },
      path: path,
    );
    _requireKind(reader, 'experimentInstalledMetricCapability');
    final availability = ExperimentMetricCapabilityAvailabilityV1.fromJson(
      reader.object('availability'),
      path: '$path.availability',
    );
    final installedProjectionSets = _objectList(
      reader.list('installedProjectionSets'),
      path: '$path.installedProjectionSets',
      maximumLength: kMaximumGeneratedPresentationReferenceCount,
      decode: (value, itemPath) =>
          ExperimentInstalledProjectionSetCapabilityV1.fromJson(
        value,
        path: itemPath,
      ),
    );
    _requireUnique(
      installedProjectionSets.map((entry) => entry.identityKey),
      '$path.installedProjectionSets',
    );
    _requireCanonicalOrder(
      installedProjectionSets.map((entry) => entry.identityKey),
      '$path.installedProjectionSets',
    );
    if (availability.isAvailable != installedProjectionSets.isNotEmpty) {
      throw CanonicalFormatException(
        '$path.availability must match installedProjectionSets',
      );
    }
    if (!availability.isAvailable &&
        availability.reasonCode !=
            ExperimentMetricCapabilityUnavailableReasonV1
                .installedProjectionUnavailable) {
      throw CanonicalFormatException(
        '$path.availability.reasonCode must be metric.installedProjectionUnavailable',
      );
    }
    return ExperimentInstalledMetricCapabilityV1._(
      json,
      availability: availability,
      installedProjectionSets: installedProjectionSets,
      metricDefinitionId: _identifier(
        reader.string('metricDefinitionId'),
        '$path.metricDefinitionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionRevisionId: _identifier(
        reader.string('metricDefinitionRevisionId'),
        '$path.metricDefinitionRevisionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionSemanticDigest: _parsedDigest(
        reader.string('metricDefinitionSemanticDigest'),
        '$path.metricDefinitionSemanticDigest',
      ),
    );
  }

  final ExperimentMetricCapabilityAvailabilityV1 availability;
  final List<ExperimentInstalledProjectionSetCapabilityV1>
      installedProjectionSets;
  final AuthorityRevisionId metricDefinitionId;
  final AuthorityRevisionId metricDefinitionRevisionId;
  final CanonicalDigest metricDefinitionSemanticDigest;

  String get identityKey =>
      '${metricDefinitionId.value}\u0000${metricDefinitionRevisionId.value}'
      '\u0000${metricDefinitionSemanticDigest.hex}';
}

/// One metric definition and its supported analysis choices.
final class ExperimentMetricCapabilityV1 extends _ExperimentAuthoringValue {
  ExperimentMetricCapabilityV1._(
    Map<String, Object?> json, {
    required this.analysisChoices,
    required this.availability,
    required this.direction,
    required this.label,
    required this.metricDefinitionId,
    required this.metricDefinitionRevisionId,
    required this.metricDefinitionSemanticDigest,
    required this.metricKind,
  }) : super(json);

  factory ExperimentMetricCapabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analysisChoices',
        'availability',
        'direction',
        'kind',
        'label',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
        'metricKind',
      },
      requiredKeys: const {
        'analysisChoices',
        'availability',
        'direction',
        'kind',
        'label',
        'metricDefinitionId',
        'metricDefinitionRevisionId',
        'metricDefinitionSemanticDigest',
        'metricKind',
      },
      path: path,
    );
    _requireKind(reader, 'experimentMetricCapability');
    final analysisChoices = _enumList(
      reader.list('analysisChoices'),
      path: '$path.analysisChoices',
      maximumLength: ExperimentAnalysisKindV1.values.length,
      decode: ExperimentAnalysisKindV1._fromWire,
    );
    final availability = ExperimentMetricCapabilityAvailabilityV1.fromJson(
      reader.object('availability'),
      path: '$path.availability',
    );
    final metricKind = _identifier(
      reader.string('metricKind'),
      '$path.metricKind',
      ArtifactKindId.new,
    );
    if (metricKind.value == 'rate') {
      if (!availability.isAvailable || analysisChoices.isEmpty) {
        throw CanonicalFormatException(
          '$path must expose analysis choices for an available rate metric',
        );
      }
    } else if (availability.isAvailable ||
        availability.reasonCode !=
            ExperimentMetricCapabilityUnavailableReasonV1
                .presentationUnavailable ||
        analysisChoices.isNotEmpty) {
      throw CanonicalFormatException(
        '$path must expose an empty presentation-unavailable capability',
      );
    }
    return ExperimentMetricCapabilityV1._(
      json,
      analysisChoices: analysisChoices,
      availability: availability,
      direction: ExperimentMetricDirectionV1._fromWire(
        reader.string('direction'),
        '$path.direction',
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      metricDefinitionId: _identifier(
        reader.string('metricDefinitionId'),
        '$path.metricDefinitionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionRevisionId: _identifier(
        reader.string('metricDefinitionRevisionId'),
        '$path.metricDefinitionRevisionId',
        AuthorityRevisionId.new,
      ),
      metricDefinitionSemanticDigest: _parsedDigest(
        reader.string('metricDefinitionSemanticDigest'),
        '$path.metricDefinitionSemanticDigest',
      ),
      metricKind: metricKind,
    );
  }

  final List<ExperimentAnalysisKindV1> analysisChoices;
  final ExperimentMetricCapabilityAvailabilityV1 availability;
  final ExperimentMetricDirectionV1 direction;
  final String label;
  final AuthorityRevisionId metricDefinitionId;
  final AuthorityRevisionId metricDefinitionRevisionId;
  final CanonicalDigest metricDefinitionSemanticDigest;
  final ArtifactKindId metricKind;
}

/// Exact target and capability discovery projection.
final class ExperimentTargetDiscoveryV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentTargetDiscoveryV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.organizationLabel,
    required this.appLabel,
    required this.environmentLabel,
    required this.namedEnvironments,
    required this.runtimePlanes,
    required this.surfaceCapabilities,
    required this.metricCapabilities,
    required this.actionAvailability,
    required this.nextPageCursor,
  }) : super(json);

  /// Decodes a strict discovery projection.
  factory ExperimentTargetDiscoveryV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentTargetDiscovery';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'actionAvailability',
        'appLabel',
        'environmentLabel',
        'kind',
        'metricCapabilities',
        'namedEnvironments',
        'nextPageCursor',
        'organizationLabel',
        'runtimePlanes',
        'schemaVersion',
        'surfaceCapabilities',
        'target',
      },
      requiredKeys: const {
        'actionAvailability',
        'appLabel',
        'environmentLabel',
        'kind',
        'metricCapabilities',
        'namedEnvironments',
        'nextPageCursor',
        'organizationLabel',
        'runtimePlanes',
        'schemaVersion',
        'surfaceCapabilities',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentTargetDiscovery',
    );
    final actionAvailability = _objectList(
      reader.list('actionAvailability'),
      path: '$path.actionAvailability',
      maximumLength: ExperimentActionV1.values.length,
      decode: (value, itemPath) =>
          ExperimentActionAvailabilityV1.fromJson(value, path: itemPath),
    );
    if (actionAvailability.length != ExperimentActionV1.values.length) {
      throw const CanonicalFormatException(
        'experimentTargetDiscovery.actionAvailability is incomplete',
      );
    }
    _requireUnique(
      actionAvailability.map((entry) => entry.action.wireName),
      '$path.actionAvailability.action',
    );
    final nextPageCursor = switch (reader.requiredNullableValue(
      'nextPageCursor',
    )) {
      null => null,
      final String value when value.isNotEmpty => _boundedString(
          value,
          '$path.nextPageCursor',
        ),
      _ => throw const CanonicalFormatException(
          'experimentTargetDiscovery.nextPageCursor must be a nonempty string or null',
        ),
    };
    final namedEnvironments = _objectList(
      reader.list('namedEnvironments'),
      path: '$path.namedEnvironments',
      maximumLength: null,
      decode: (value, itemPath) =>
          ExperimentNamedEnvironmentOptionV1.fromJson(value, path: itemPath),
    );
    final surfaceCapabilities = _objectList(
      reader.list('surfaceCapabilities'),
      path: '$path.surfaceCapabilities',
      maximumLength: null,
      decode: (value, itemPath) =>
          ExperimentSurfaceCapabilityV1.fromJson(value, path: itemPath),
    );
    final metricCapabilities = _objectList(
      reader.list('metricCapabilities'),
      path: '$path.metricCapabilities',
      maximumLength: null,
      decode: (value, itemPath) =>
          ExperimentMetricCapabilityV1.fromJson(value, path: itemPath),
    );
    if (namedEnvironments.length +
            surfaceCapabilities.length +
            metricCapabilities.length >
        _maximumDiscoveryPageSize) {
      throw const CanonicalFormatException(
        'experimentTargetDiscovery emits more than 100 page entries',
      );
    }
    return ExperimentTargetDiscoveryV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      organizationLabel: _boundedString(
        reader.string('organizationLabel'),
        '$path.organizationLabel',
      ),
      appLabel: _boundedString(reader.string('appLabel'), '$path.appLabel'),
      environmentLabel: _boundedString(
        reader.string('environmentLabel'),
        '$path.environmentLabel',
      ),
      namedEnvironments: namedEnvironments,
      runtimePlanes: _objectList(
        reader.list('runtimePlanes'),
        path: '$path.runtimePlanes',
        maximumLength: 2,
        decode: (value, itemPath) =>
            ExperimentRuntimePlaneOptionV1.fromJson(value, path: itemPath),
      ),
      surfaceCapabilities: surfaceCapabilities,
      metricCapabilities: metricCapabilities,
      actionAvailability: actionAvailability,
      nextPageCursor: nextPageCursor,
    );
  }

  final TargetCoordinate target;
  final String organizationLabel;
  final String appLabel;
  final String environmentLabel;
  final List<ExperimentNamedEnvironmentOptionV1> namedEnvironments;
  final List<ExperimentRuntimePlaneOptionV1> runtimePlanes;
  final List<ExperimentSurfaceCapabilityV1> surfaceCapabilities;
  final List<ExperimentMetricCapabilityV1> metricCapabilities;
  final List<ExperimentActionAvailabilityV1> actionAvailability;
  final String? nextPageCursor;
}

/// Closed validation issue codes.
enum ExperimentValidationIssueCodeV1 {
  incompleteDraft('incompleteDraft'),
  incompatibleReference('incompatibleReference'),
  staleDependency('staleDependency'),
  guardrailUnavailable('guardrailUnavailable'),
  planningInfeasible('planningInfeasible'),
  planningIndeterminate('planningIndeterminate'),
  planningAuthorityUnavailable('planningAuthorityUnavailable');

  const ExperimentValidationIssueCodeV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentValidationIssueCodeV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// Closed capability-unavailability codes.
enum ExperimentCapabilityReasonCodeV1 {
  surfaceUnavailable('surfaceUnavailable'),
  metricReadUnavailable('metricReadUnavailable'),
  metricPresentationUnavailable('metricPresentationUnavailable'),
  statisticalAnalysisUnavailable('statisticalAnalysisUnavailable'),

  /// Count-shaped numerators are unavailable for fixed-horizon rate analysis.
  statisticalCountNumeratorUnsupported(
    'statisticalCountNumeratorUnsupported',
  );

  const ExperimentCapabilityReasonCodeV1(this.wireName);

  /// Stable wire spelling.
  final String wireName;

  static ExperimentCapabilityReasonCodeV1 _fromWire(
    String value,
    String path,
  ) =>
      _enumFromWire(values, value, path, (entry) => entry.wireName);
}

/// One typed validation issue bound to a public field path.
final class ExperimentValidationIssueV1 extends _ExperimentAuthoringValue {
  ExperimentValidationIssueV1._(
    Map<String, Object?> json, {
    required this.code,
    required this.fieldPath,
    required this.messageKey,
  }) : super(json);

  factory ExperimentValidationIssueV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'fieldPath', 'kind', 'messageKey'},
      requiredKeys: const {'code', 'fieldPath', 'kind', 'messageKey'},
      path: path,
    );
    _requireKind(reader, 'experimentValidationIssue');
    return ExperimentValidationIssueV1._(
      json,
      code: ExperimentValidationIssueCodeV1._fromWire(
        reader.string('code'),
        '$path.code',
      ),
      fieldPath: _boundedString(reader.string('fieldPath'), '$path.fieldPath'),
      messageKey: _boundedString(
        reader.string('messageKey'),
        '$path.messageKey',
      ),
    );
  }

  final ExperimentValidationIssueCodeV1 code;
  final String fieldPath;
  final String messageKey;
}

/// One typed capability reason tied to an exact public reference.
final class ExperimentCapabilityReasonV1 extends _ExperimentAuthoringValue {
  ExperimentCapabilityReasonV1._(
    Map<String, Object?> json, {
    required this.code,
    required this.referenceId,
  }) : super(json);

  factory ExperimentCapabilityReasonV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'kind', 'referenceId'},
      requiredKeys: const {'code', 'kind', 'referenceId'},
      path: path,
    );
    _requireKind(reader, 'experimentCapabilityReason');
    return ExperimentCapabilityReasonV1._(
      json,
      code: ExperimentCapabilityReasonCodeV1._fromWire(
        reader.string('code'),
        '$path.code',
      ),
      referenceId: _identifier(
        reader.string('referenceId'),
        '$path.referenceId',
        AuthorityRevisionId.new,
      ),
    );
  }

  final ExperimentCapabilityReasonCodeV1 code;
  final AuthorityRevisionId referenceId;
}

/// Safe projection of one fixed-horizon planning computation.
final class ExperimentNArmPlanningPreviewV1 extends _ExperimentAuthoringValue {
  ExperimentNArmPlanningPreviewV1._(
    Map<String, Object?> json, {
    required this.reviewedSelection,
    required this.feasibility,
    required this.planningIntentDigest,
    required this.allocationAuthorityDigest,
    required this.plannedPerArmEnrollment,
    required this.plannedTotalEnrollment,
    required this.certifiedScales,
    required this.plannedFollowUpDurationMicros,
    required this.plannedMaximumEnrollmentDurationMicros,
    required this.plannerIdentityDigest,
    required this.resultDigest,
  }) : super(json);

  /// Decodes a strict safe planning projection.
  factory ExperimentNArmPlanningPreviewV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentNArmPlanningPreview';
    final feasibility = ExperimentPlanningFeasibilityV1._fromWire(
      requireCanonicalString(json['feasibility'], '$path.feasibility'),
      '$path.feasibility',
    );
    final feasible = feasibility == ExperimentPlanningFeasibilityV1.feasible;
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: feasible
          ? const {
              'allocationAuthorityDigest',
              'certifiedScales',
              'feasibility',
              'kind',
              'plannedFollowUpDurationMicros',
              'plannedMaximumEnrollmentDurationMicros',
              'plannedPerArmEnrollment',
              'plannedTotalEnrollment',
              'plannerIdentityDigest',
              'planningIntentDigest',
              'resultDigest',
              'reviewedSelection',
              'schemaVersion',
            }
          : const {
              'allocationAuthorityDigest',
              'feasibility',
              'kind',
              'planningIntentDigest',
              'reviewedSelection',
              'schemaVersion',
            },
      requiredKeys: feasible
          ? const {
              'allocationAuthorityDigest',
              'certifiedScales',
              'feasibility',
              'kind',
              'plannedFollowUpDurationMicros',
              'plannedMaximumEnrollmentDurationMicros',
              'plannedPerArmEnrollment',
              'plannedTotalEnrollment',
              'plannerIdentityDigest',
              'planningIntentDigest',
              'resultDigest',
              'reviewedSelection',
              'schemaVersion',
            }
          : const {
              'allocationAuthorityDigest',
              'feasibility',
              'kind',
              'planningIntentDigest',
              'reviewedSelection',
              'schemaVersion',
            },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentNArmPlanningPreview',
    );
    Map<String, int>? plannedPerArmEnrollment;
    int? plannedTotalEnrollment;
    Map<String, String>? certifiedScales;
    int? plannedFollowUpDurationMicros;
    int? plannedMaximumEnrollmentDurationMicros;
    CanonicalDigest? plannerIdentityDigest;
    CanonicalDigest? resultDigest;
    if (feasible) {
      plannedPerArmEnrollment = _positiveIntegerMap(
        reader.object('plannedPerArmEnrollment'),
        path: '$path.plannedPerArmEnrollment',
        maximumLength: _maximumArms,
      );
      plannedTotalEnrollment = _positiveInteger(
        reader.integer('plannedTotalEnrollment'),
        '$path.plannedTotalEnrollment',
      );
      if (plannedPerArmEnrollment.values.fold<int>(0, (a, b) => a + b) !=
          plannedTotalEnrollment) {
        throw const CanonicalFormatException(
          'experimentNArmPlanningPreview enrollment totals disagree',
        );
      }
      certifiedScales = _certifiedScales(
        reader.object('certifiedScales'),
        '$path.certifiedScales',
      );
      plannedFollowUpDurationMicros = _nonNegativeInteger(
        reader.integer('plannedFollowUpDurationMicros'),
        '$path.plannedFollowUpDurationMicros',
      );
      plannedMaximumEnrollmentDurationMicros = _positiveInteger(
        reader.integer('plannedMaximumEnrollmentDurationMicros'),
        '$path.plannedMaximumEnrollmentDurationMicros',
      );
      plannerIdentityDigest = _parsedDigest(
        reader.string('plannerIdentityDigest'),
        '$path.plannerIdentityDigest',
      );
      resultDigest = _parsedDigest(
        reader.string('resultDigest'),
        '$path.resultDigest',
      );
    }
    final reviewedSelection = ExperimentNArmPlanningSelectionV1.fromJson(
      reader.object('reviewedSelection'),
    );
    if (feasible) {
      _requireExactIdentifierSet(
        expected: reviewedSelection.allocationWeights.map(
          (weight) => weight.armId.value,
        ),
        actual: plannedPerArmEnrollment!.keys,
        path: '$path.plannedPerArmEnrollment',
        expectedDescription: '$path.reviewedSelection.allocationWeights',
      );
    }
    return ExperimentNArmPlanningPreviewV1._(
      json,
      reviewedSelection: reviewedSelection,
      feasibility: feasibility,
      planningIntentDigest: _parsedDigest(
        reader.string('planningIntentDigest'),
        '$path.planningIntentDigest',
      ),
      allocationAuthorityDigest: _parsedDigest(
        reader.string('allocationAuthorityDigest'),
        '$path.allocationAuthorityDigest',
      ),
      plannedPerArmEnrollment: plannedPerArmEnrollment,
      plannedTotalEnrollment: plannedTotalEnrollment,
      certifiedScales: certifiedScales,
      plannedFollowUpDurationMicros: plannedFollowUpDurationMicros,
      plannedMaximumEnrollmentDurationMicros:
          plannedMaximumEnrollmentDurationMicros,
      plannerIdentityDigest: plannerIdentityDigest,
      resultDigest: resultDigest,
    );
  }

  final ExperimentNArmPlanningSelectionV1 reviewedSelection;
  final ExperimentPlanningFeasibilityV1 feasibility;
  final CanonicalDigest planningIntentDigest;
  final CanonicalDigest allocationAuthorityDigest;
  final Map<String, int>? plannedPerArmEnrollment;
  final int? plannedTotalEnrollment;
  final Map<String, String>? certifiedScales;
  final int? plannedFollowUpDurationMicros;
  final int? plannedMaximumEnrollmentDurationMicros;
  final CanonicalDigest? plannerIdentityDigest;
  final CanonicalDigest? resultDigest;
}

/// Validation projection for one exact draft revision.
final class ExperimentValidationViewV1 extends _ExperimentAuthoringValue {
  ExperimentValidationViewV1._(
    Map<String, Object?> json, {
    required this.draftBinding,
    required this.issues,
    required this.capabilityReasons,
    required this.planningPreview,
  }) : super(json);

  /// Decodes a strict validation projection.
  factory ExperimentValidationViewV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentValidationView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'capabilityReasons',
        'draftBinding',
        'issues',
        'kind',
        'planningPreview',
        'schemaVersion',
      },
      requiredKeys: const {
        'capabilityReasons',
        'draftBinding',
        'issues',
        'kind',
        'planningPreview',
        'schemaVersion',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentValidationView',
    );
    final planningPreview = reader.requiredNullableValue('planningPreview');
    return ExperimentValidationViewV1._(
      json,
      draftBinding: ExperimentDraftBindingV1.fromJson(
        reader.object('draftBinding'),
        path: '$path.draftBinding',
      ),
      issues: _objectList(
        reader.list('issues'),
        path: '$path.issues',
        maximumLength: _maximumIssues,
        decode: (value, itemPath) =>
            ExperimentValidationIssueV1.fromJson(value, path: itemPath),
      ),
      capabilityReasons: _objectList(
        reader.list('capabilityReasons'),
        path: '$path.capabilityReasons',
        maximumLength: _maximumIssues,
        decode: (value, itemPath) =>
            ExperimentCapabilityReasonV1.fromJson(value, path: itemPath),
      ),
      planningPreview: planningPreview == null
          ? null
          : ExperimentNArmPlanningPreviewV1.fromJson(
              requireCanonicalObject(
                planningPreview,
                '$path.planningPreview',
              ),
            ),
    );
  }

  final ExperimentDraftBindingV1 draftBinding;
  final List<ExperimentValidationIssueV1> issues;
  final List<ExperimentCapabilityReasonV1> capabilityReasons;
  final ExperimentNArmPlanningPreviewV1? planningPreview;
}

/// Bounded locator for one immutable authoring review.
final class ExperimentReviewReferenceV1 extends _ExperimentAuthoringValue {
  ExperimentReviewReferenceV1._(
    Map<String, Object?> json, {
    required this.reviewId,
    required this.recordDigest,
  }) : super(json);

  /// Decodes a strict review reference.
  factory ExperimentReviewReferenceV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentReviewReference';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'recordDigest',
        'reviewId',
        'schemaVersion',
      },
      requiredKeys: const {
        'kind',
        'recordDigest',
        'reviewId',
        'schemaVersion',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentReviewReference',
    );
    return ExperimentReviewReferenceV1._(
      json,
      reviewId: _identifier(
        reader.string('reviewId'),
        '$path.reviewId',
        ExperimentReviewIdV1.new,
      ),
      recordDigest: _parsedDigest(
        reader.string('recordDigest'),
        '$path.recordDigest',
      ),
    );
  }

  /// Decodes byte-exact canonical review-reference JSON.
  factory ExperimentReviewReferenceV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        ExperimentReviewReferenceV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'experimentReviewReference',
      );

  final ExperimentReviewIdV1 reviewId;
  final CanonicalDigest recordDigest;
}

/// One fixed consequence shown during exact review.
final class ExperimentReviewConsequenceV1 extends _ExperimentAuthoringValue {
  ExperimentReviewConsequenceV1._(
    Map<String, Object?> json, {
    required this.code,
    required this.messageKey,
  }) : super(json);

  factory ExperimentReviewConsequenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'code', 'kind', 'messageKey'},
      requiredKeys: const {'code', 'kind', 'messageKey'},
      path: path,
    );
    _requireKind(reader, 'experimentReviewConsequence');
    final code = reader.string('code');
    if (code != 'manualPromotionOnly' && code != 'noInterimLooks') {
      throw CanonicalFormatException('$path.code "$code" is unsupported');
    }
    return ExperimentReviewConsequenceV1._(
      json,
      code: code,
      messageKey: _boundedString(
        reader.string('messageKey'),
        '$path.messageKey',
      ),
    );
  }

  final String code;
  final String messageKey;
}

/// Safe exact configuration and consequence review.
final class ExperimentReviewViewV1 extends _ExperimentAuthoringValue {
  ExperimentReviewViewV1._(
    Map<String, Object?> json, {
    required this.draftBinding,
    required this.configuration,
    required this.consequences,
    required this.planningPreview,
    required this.reviewReference,
    required this.recordDigest,
    required this.projectionDigest,
    required this.issuedAtMicros,
  }) : super(json);

  /// Decodes a strict review projection.
  factory ExperimentReviewViewV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentReviewView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'configuration',
        'consequences',
        'draftBinding',
        'issuedAtMicros',
        'kind',
        'planningPreview',
        'projectionDigest',
        'recordDigest',
        'reviewReference',
        'schemaVersion',
      },
      requiredKeys: const {
        'configuration',
        'consequences',
        'draftBinding',
        'issuedAtMicros',
        'kind',
        'planningPreview',
        'projectionDigest',
        'recordDigest',
        'reviewReference',
        'schemaVersion',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentReviewView');
    final planningPreview = reader.requiredNullableValue('planningPreview');
    final recordDigest = _parsedDigest(
      reader.string('recordDigest'),
      '$path.recordDigest',
    );
    final reviewReference = ExperimentReviewReferenceV1.fromJson(
      reader.object('reviewReference'),
    );
    if (reviewReference.recordDigest != recordDigest) {
      throw const CanonicalFormatException(
        'experimentReviewView record digests disagree',
      );
    }
    return ExperimentReviewViewV1._(
      json,
      draftBinding: ExperimentDraftBindingV1.fromJson(
        reader.object('draftBinding'),
        path: '$path.draftBinding',
      ),
      configuration: ExperimentDraftChoicesV1.fromJson(
        reader.object('configuration'),
      ),
      consequences: _objectList(
        reader.list('consequences'),
        path: '$path.consequences',
        maximumLength: _maximumIssues,
        decode: (value, itemPath) =>
            ExperimentReviewConsequenceV1.fromJson(value, path: itemPath),
      ),
      planningPreview: planningPreview == null
          ? null
          : ExperimentNArmPlanningPreviewV1.fromJson(
              requireCanonicalObject(planningPreview, '$path.planningPreview'),
            ),
      reviewReference: reviewReference,
      recordDigest: recordDigest,
      projectionDigest: _parsedDigest(
        reader.string('projectionDigest'),
        '$path.projectionDigest',
      ),
      issuedAtMicros: _positiveInteger(
        reader.integer('issuedAtMicros'),
        '$path.issuedAtMicros',
      ),
    );
  }

  final ExperimentDraftBindingV1 draftBinding;
  final ExperimentDraftChoicesV1 configuration;
  final List<ExperimentReviewConsequenceV1> consequences;
  final ExperimentNArmPlanningPreviewV1? planningPreview;
  final ExperimentReviewReferenceV1 reviewReference;
  final CanonicalDigest recordDigest;
  final CanonicalDigest projectionDigest;
  final int issuedAtMicros;
}

/// Exact correlation used to re-read a verified Live experiment.
final class ExperimentLiveReadReferenceV1 extends _ExperimentAuthoringValue {
  ExperimentLiveReadReferenceV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.activationOrdinal,
    required this.receiptDigest,
  }) : super(json);

  factory ExperimentLiveReadReferenceV1.fromJson(
    Map<String, Object?> json, {
    String path = 'experimentLiveReadReference',
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'activationOrdinal',
        'experimentId',
        'kind',
        'receiptDigest',
        'target',
      },
      requiredKeys: const {
        'activationOrdinal',
        'experimentId',
        'kind',
        'receiptDigest',
        'target',
      },
      path: path,
    );
    _requireKind(reader, 'experimentLiveReadReference');
    return ExperimentLiveReadReferenceV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      experimentId: _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      ),
      activationOrdinal: _positiveInteger(
        reader.integer('activationOrdinal'),
        '$path.activationOrdinal',
      ),
      receiptDigest: _parsedDigest(
        reader.string('receiptDigest'),
        '$path.receiptDigest',
      ),
    );
  }

  final TargetCoordinate target;
  final ExperimentPublicIdV1 experimentId;
  final int activationOrdinal;
  final CanonicalDigest receiptDigest;
}

/// Safe accepted activation projection.
final class ExperimentActivationAcceptedViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentActivationAcceptedViewV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.experimentRevisionId,
    required this.experimentEpochId,
    required this.activationOrdinal,
    required this.lifecycleOrdinal,
    required this.receiptDigest,
    required this.immutablePublicationDigest,
    required this.liveReadReference,
  }) : super(json);

  /// Decodes a strict accepted activation projection.
  factory ExperimentActivationAcceptedViewV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentActivationAcceptedView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'activationOrdinal',
        'experimentEpochId',
        'experimentId',
        'experimentRevisionId',
        'immutablePublicationDigest',
        'kind',
        'lifecycleOrdinal',
        'liveReadReference',
        'receiptDigest',
        'schemaVersion',
        'target',
      },
      requiredKeys: const {
        'activationOrdinal',
        'experimentEpochId',
        'experimentId',
        'experimentRevisionId',
        'immutablePublicationDigest',
        'kind',
        'lifecycleOrdinal',
        'liveReadReference',
        'receiptDigest',
        'schemaVersion',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentActivationAcceptedView',
    );
    final target = TargetCoordinate.fromJson(reader.object('target'));
    final experimentId = _identifier(
      reader.string('experimentId'),
      '$path.experimentId',
      ExperimentPublicIdV1.new,
    );
    final activationOrdinal = _positiveInteger(
      reader.integer('activationOrdinal'),
      '$path.activationOrdinal',
    );
    final receiptDigest = _parsedDigest(
      reader.string('receiptDigest'),
      '$path.receiptDigest',
    );
    final liveReadReference = ExperimentLiveReadReferenceV1.fromJson(
      reader.object('liveReadReference'),
      path: '$path.liveReadReference',
    );
    if (liveReadReference.target != target ||
        liveReadReference.experimentId != experimentId ||
        liveReadReference.activationOrdinal != activationOrdinal ||
        liveReadReference.receiptDigest != receiptDigest) {
      throw const CanonicalFormatException(
        'experimentActivationAcceptedView Live read correlation disagrees',
      );
    }
    return ExperimentActivationAcceptedViewV1._(
      json,
      target: target,
      experimentId: experimentId,
      experimentRevisionId: _identifier(
        reader.string('experimentRevisionId'),
        '$path.experimentRevisionId',
        ExperimentPublicRevisionIdV1.new,
      ),
      experimentEpochId: _identifier(
        reader.string('experimentEpochId'),
        '$path.experimentEpochId',
        ExperimentPublicEpochIdV1.new,
      ),
      activationOrdinal: activationOrdinal,
      lifecycleOrdinal: _positiveInteger(
        reader.integer('lifecycleOrdinal'),
        '$path.lifecycleOrdinal',
      ),
      receiptDigest: receiptDigest,
      immutablePublicationDigest: _parsedDigest(
        reader.string('immutablePublicationDigest'),
        '$path.immutablePublicationDigest',
      ),
      liveReadReference: liveReadReference,
    );
  }

  final TargetCoordinate target;
  final ExperimentPublicIdV1 experimentId;
  final ExperimentPublicRevisionIdV1 experimentRevisionId;
  final ExperimentPublicEpochIdV1 experimentEpochId;
  final int activationOrdinal;
  final int lifecycleOrdinal;
  final CanonicalDigest receiptDigest;
  final CanonicalDigest immutablePublicationDigest;
  final ExperimentLiveReadReferenceV1 liveReadReference;
}

/// Safe accepted projection for one lifecycle transition.
final class ExperimentLifecycleAcceptedViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentLifecycleAcceptedViewV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.lifecycleState,
    required this.transitionedAtMicros,
    required this.lifecycleOrdinal,
    required this.receiptDigest,
    required this.experimentEpochId,
  }) : super(json);

  /// Decodes a strict accepted lifecycle projection.
  factory ExperimentLifecycleAcceptedViewV1.fromJson(
    Map<String, Object?> json, {
    ExperimentLifecycleStateV1? expectedLifecycleState,
  }) {
    const path = 'experimentLifecycleAcceptedView';
    final lifecycleState = ExperimentLifecycleStateV1._fromWire(
      requireCanonicalString(json['lifecycleState'], '$path.lifecycleState'),
      '$path.lifecycleState',
    );
    final hasEpoch = lifecycleState == ExperimentLifecycleStateV1.active;
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: hasEpoch
          ? const {
              'experimentEpochId',
              'experimentId',
              'kind',
              'lifecycleOrdinal',
              'lifecycleState',
              'receiptDigest',
              'schemaVersion',
              'target',
              'transitionedAtMicros',
            }
          : const {
              'experimentId',
              'kind',
              'lifecycleOrdinal',
              'lifecycleState',
              'receiptDigest',
              'schemaVersion',
              'target',
              'transitionedAtMicros',
            },
      requiredKeys: hasEpoch
          ? const {
              'experimentEpochId',
              'experimentId',
              'kind',
              'lifecycleOrdinal',
              'lifecycleState',
              'receiptDigest',
              'schemaVersion',
              'target',
              'transitionedAtMicros',
            }
          : const {
              'experimentId',
              'kind',
              'lifecycleOrdinal',
              'lifecycleState',
              'receiptDigest',
              'schemaVersion',
              'target',
              'transitionedAtMicros',
            },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentLifecycleAcceptedView',
    );
    if (expectedLifecycleState != null &&
        lifecycleState != expectedLifecycleState) {
      throw CanonicalFormatException(
        '$path.lifecycleState does not match its operation',
      );
    }
    return ExperimentLifecycleAcceptedViewV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      experimentId: _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      ),
      lifecycleState: lifecycleState,
      transitionedAtMicros: _positiveInteger(
        reader.integer('transitionedAtMicros'),
        '$path.transitionedAtMicros',
      ),
      lifecycleOrdinal: _positiveInteger(
        reader.integer('lifecycleOrdinal'),
        '$path.lifecycleOrdinal',
      ),
      receiptDigest: _parsedDigest(
        reader.string('receiptDigest'),
        '$path.receiptDigest',
      ),
      experimentEpochId: hasEpoch
          ? _identifier(
              reader.string('experimentEpochId'),
              '$path.experimentEpochId',
              ExperimentPublicEpochIdV1.new,
            )
          : null,
    );
  }

  final TargetCoordinate target;
  final ExperimentPublicIdV1 experimentId;
  final ExperimentLifecycleStateV1 lifecycleState;
  final int transitionedAtMicros;
  final int lifecycleOrdinal;
  final CanonicalDigest receiptDigest;
  final ExperimentPublicEpochIdV1? experimentEpochId;
}

/// Separate pending-draft state shown beside accepted metadata.
final class ExperimentPendingDraftSummaryV1 extends _ExperimentAuthoringValue {
  ExperimentPendingDraftSummaryV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.draftId,
    required this.draftRevisionId,
    required this.revisionOrdinal,
    required this.semanticDigest,
    required this.completeness,
  }) : super(json);

  factory ExperimentPendingDraftSummaryV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = ExperimentPendingDraftKindV1._fromWire(
      _readDiscriminator(json, path),
      '$path.kind',
    );
    if (kind == ExperimentPendingDraftKindV1.none) {
      CanonicalObjectReader(
        json,
        allowedKeys: const {'kind'},
        requiredKeys: const {'kind'},
        path: path,
      );
      return ExperimentPendingDraftSummaryV1._(
        json,
        kind: kind,
        draftId: null,
        draftRevisionId: null,
        revisionOrdinal: null,
        semanticDigest: null,
        completeness: null,
      );
    }
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'completeness',
        'draftId',
        'draftRevisionId',
        'kind',
        'revisionOrdinal',
        'semanticDigest',
      },
      requiredKeys: const {
        'completeness',
        'draftId',
        'draftRevisionId',
        'kind',
        'revisionOrdinal',
        'semanticDigest',
      },
      path: path,
    );
    return ExperimentPendingDraftSummaryV1._(
      json,
      kind: kind,
      draftId: _identifier(
        reader.string('draftId'),
        '$path.draftId',
        ExperimentDraftIdV1.new,
      ),
      draftRevisionId: _identifier(
        reader.string('draftRevisionId'),
        '$path.draftRevisionId',
        ExperimentDraftRevisionIdV1.new,
      ),
      revisionOrdinal: _positiveInteger(
        reader.integer('revisionOrdinal'),
        '$path.revisionOrdinal',
      ),
      semanticDigest: _parsedDigest(
        reader.string('semanticDigest'),
        '$path.semanticDigest',
      ),
      completeness: ExperimentDraftCompletenessV1.fromJson(
        reader.object('completeness'),
        path: '$path.completeness',
      ),
    );
  }

  final ExperimentPendingDraftKindV1 kind;
  final ExperimentDraftIdV1? draftId;
  final ExperimentDraftRevisionIdV1? draftRevisionId;
  final int? revisionOrdinal;
  final CanonicalDigest? semanticDigest;
  final ExperimentDraftCompletenessV1? completeness;
}

/// Exact inference locator or an honest unavailable reason.
final class ExperimentInferenceReferenceV1 extends _ExperimentAuthoringValue {
  ExperimentInferenceReferenceV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.reasonCode,
    required this.inferenceRevisionId,
    required this.resultDigest,
  }) : super(json);

  factory ExperimentInferenceReferenceV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = ExperimentInferenceReferenceKindV1._fromWire(
      _readDiscriminator(json, path),
      '$path.kind',
    );
    if (kind == ExperimentInferenceReferenceKindV1.unavailable) {
      final reader = CanonicalObjectReader(
        json,
        allowedKeys: const {'kind', 'reasonCode'},
        requiredKeys: const {'kind', 'reasonCode'},
        path: path,
      );
      return ExperimentInferenceReferenceV1._(
        json,
        kind: kind,
        reasonCode: _boundedString(
          reader.string('reasonCode'),
          '$path.reasonCode',
        ),
        inferenceRevisionId: null,
        resultDigest: null,
      );
    }
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'inferenceRevisionId', 'kind', 'resultDigest'},
      requiredKeys: const {'inferenceRevisionId', 'kind', 'resultDigest'},
      path: path,
    );
    return ExperimentInferenceReferenceV1._(
      json,
      kind: kind,
      reasonCode: null,
      inferenceRevisionId: _identifier(
        reader.string('inferenceRevisionId'),
        '$path.inferenceRevisionId',
        AuthorityRevisionId.new,
      ),
      resultDigest: _parsedDigest(
        reader.string('resultDigest'),
        '$path.resultDigest',
      ),
    );
  }

  final ExperimentInferenceReferenceKindV1 kind;
  final String? reasonCode;
  final AuthorityRevisionId? inferenceRevisionId;
  final CanonicalDigest? resultDigest;
}

/// Closed Live availability for a draft-only experiment entry.
final class ExperimentDraftLiveStateV1 extends _ExperimentAuthoringValue {
  ExperimentDraftLiveStateV1._(Map<String, Object?> json) : super(json);

  factory ExperimentDraftLiveStateV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'reasonCode'},
      requiredKeys: const {'kind', 'reasonCode'},
      path: path,
    );
    if (reader.string('kind') != 'unavailable' ||
        reader.string('reasonCode') != 'notActivated') {
      throw CanonicalFormatException('$path is not a draft Live state');
    }
    return ExperimentDraftLiveStateV1._(json);
  }

  String get kind => 'unavailable';
  String get reasonCode => 'notActivated';
}

/// An accepted or draft-only entry in an experiment list.
sealed class ExperimentListEntryV1 extends _ExperimentAuthoringValue {
  ExperimentListEntryV1._(super.json);

  factory ExperimentListEntryV1.fromJson(Map<String, Object?> json) =>
      switch (_readDiscriminator(json, 'experimentListEntry')) {
        'experimentSummary' => ExperimentSummaryV1.fromJson(json),
        'experimentIntegrityUnavailableSummary' =>
          ExperimentIntegrityUnavailableSummaryV1.fromJson(json),
        'experimentDraftSummary' => ExperimentDraftSummaryV1.fromJson(json),
        final kind => throw CanonicalFormatException(
            'experimentListEntry.kind "$kind" is unsupported',
          ),
      };

  TargetCoordinate get target;
  ExperimentPublicIdV1 get experimentId;
  int get controlPlaneOrdinal;
}

/// Accepted experiment metadata whose immutable presentation is unavailable.
final class ExperimentIntegrityUnavailableSummaryV1
    extends ExperimentListEntryV1 {
  ExperimentIntegrityUnavailableSummaryV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.integrityState,
    required this.lifecycleState,
    required this.activationOrdinal,
    required this.lifecycleOrdinal,
    required this.controlPlaneOrdinal,
    required this.acceptedAtMicros,
    required this.archivedAtMicros,
    required this.pendingDraft,
    required this.inferenceReference,
    required this.liveReadReference,
  }) : super._(json);

  factory ExperimentIntegrityUnavailableSummaryV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentIntegrityUnavailableSummary';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'acceptedAtMicros',
        'activationOrdinal',
        'archivedAtMicros',
        'controlPlaneOrdinal',
        'experimentId',
        'inferenceReference',
        'integrityState',
        'kind',
        'lifecycleOrdinal',
        'lifecycleState',
        'liveReadReference',
        'pendingDraft',
        'schemaVersion',
        'target',
      },
      requiredKeys: const {
        'acceptedAtMicros',
        'activationOrdinal',
        'archivedAtMicros',
        'controlPlaneOrdinal',
        'experimentId',
        'inferenceReference',
        'integrityState',
        'kind',
        'lifecycleOrdinal',
        'lifecycleState',
        'liveReadReference',
        'pendingDraft',
        'schemaVersion',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentIntegrityUnavailableSummary',
    );
    final integrityState = ExperimentIntegrityStateV1._fromWire(
      reader.string('integrityState'),
      '$path.integrityState',
    );
    if (integrityState != ExperimentIntegrityStateV1.unavailable) {
      throw const CanonicalFormatException(
        'experimentIntegrityUnavailableSummary requires unavailable integrity',
      );
    }
    final target = TargetCoordinate.fromJson(reader.object('target'));
    final experimentId = _identifier(
      reader.string('experimentId'),
      '$path.experimentId',
      ExperimentPublicIdV1.new,
    );
    final activationOrdinal = _positiveInteger(
      reader.integer('activationOrdinal'),
      '$path.activationOrdinal',
    );
    final liveReadReference = ExperimentLiveReadReferenceV1.fromJson(
      reader.object('liveReadReference'),
      path: '$path.liveReadReference',
    );
    if (liveReadReference.target != target ||
        liveReadReference.experimentId != experimentId ||
        liveReadReference.activationOrdinal != activationOrdinal) {
      throw const CanonicalFormatException(
        'experimentIntegrityUnavailableSummary Live read correlation disagrees',
      );
    }
    final archivedAtMicros = switch (reader.requiredNullableValue(
      'archivedAtMicros',
    )) {
      null => null,
      final int value => _positiveInteger(value, '$path.archivedAtMicros'),
      _ => throw const CanonicalFormatException(
          'experimentIntegrityUnavailableSummary.archivedAtMicros must be '
          'an integer or null',
        ),
    };
    return ExperimentIntegrityUnavailableSummaryV1._(
      json,
      target: target,
      experimentId: experimentId,
      integrityState: integrityState,
      lifecycleState: ExperimentLifecycleStateV1._fromWire(
        reader.string('lifecycleState'),
        '$path.lifecycleState',
      ),
      activationOrdinal: activationOrdinal,
      lifecycleOrdinal: _positiveInteger(
        reader.integer('lifecycleOrdinal'),
        '$path.lifecycleOrdinal',
      ),
      controlPlaneOrdinal: _positiveInteger(
        reader.integer('controlPlaneOrdinal'),
        '$path.controlPlaneOrdinal',
      ),
      acceptedAtMicros: _positiveInteger(
        reader.integer('acceptedAtMicros'),
        '$path.acceptedAtMicros',
      ),
      archivedAtMicros: archivedAtMicros,
      pendingDraft: ExperimentPendingDraftSummaryV1.fromJson(
        reader.object('pendingDraft'),
        path: '$path.pendingDraft',
      ),
      inferenceReference: ExperimentInferenceReferenceV1.fromJson(
        reader.object('inferenceReference'),
        path: '$path.inferenceReference',
      ),
      liveReadReference: liveReadReference,
    );
  }

  @override
  final TargetCoordinate target;
  @override
  final ExperimentPublicIdV1 experimentId;
  final ExperimentIntegrityStateV1 integrityState;

  /// Exact lifecycle state at the accepted activation head.
  final ExperimentLifecycleStateV1 lifecycleState;
  final int activationOrdinal;
  final int lifecycleOrdinal;
  @override
  final int controlPlaneOrdinal;
  final int acceptedAtMicros;
  final int? archivedAtMicros;
  final ExperimentPendingDraftSummaryV1 pendingDraft;
  final ExperimentInferenceReferenceV1 inferenceReference;
  final ExperimentLiveReadReferenceV1 liveReadReference;
}

/// Safe accepted metadata for one experiment.
final class ExperimentSummaryV1 extends ExperimentListEntryV1 {
  ExperimentSummaryV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.label,
    required this.lifecycleState,
    required this.integrityState,
    required this.activationOrdinal,
    required this.lifecycleOrdinal,
    required this.controlPlaneOrdinal,
    required this.acceptedAtMicros,
    required this.archivedAtMicros,
    required this.pendingDraft,
    required this.inferenceReference,
    required this.liveReadReference,
  }) : super._(json);

  /// Decodes a strict experiment summary.
  factory ExperimentSummaryV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentSummary';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'acceptedAtMicros',
        'activationOrdinal',
        'archivedAtMicros',
        'controlPlaneOrdinal',
        'experimentId',
        'inferenceReference',
        'integrityState',
        'kind',
        'label',
        'lifecycleOrdinal',
        'lifecycleState',
        'liveReadReference',
        'pendingDraft',
        'schemaVersion',
        'target',
      },
      requiredKeys: const {
        'acceptedAtMicros',
        'activationOrdinal',
        'archivedAtMicros',
        'controlPlaneOrdinal',
        'experimentId',
        'inferenceReference',
        'integrityState',
        'kind',
        'label',
        'lifecycleOrdinal',
        'lifecycleState',
        'liveReadReference',
        'pendingDraft',
        'schemaVersion',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentSummary');
    final archivedAtMicros = switch (reader.requiredNullableValue(
      'archivedAtMicros',
    )) {
      null => null,
      final int value => _positiveInteger(value, '$path.archivedAtMicros'),
      _ => throw const CanonicalFormatException(
          'experimentSummary.archivedAtMicros must be an integer or null',
        ),
    };
    final target = TargetCoordinate.fromJson(reader.object('target'));
    final experimentId = _identifier(
      reader.string('experimentId'),
      '$path.experimentId',
      ExperimentPublicIdV1.new,
    );
    final activationOrdinal = _positiveInteger(
      reader.integer('activationOrdinal'),
      '$path.activationOrdinal',
    );
    final liveReadReference = ExperimentLiveReadReferenceV1.fromJson(
      reader.object('liveReadReference'),
      path: '$path.liveReadReference',
    );
    if (liveReadReference.target != target ||
        liveReadReference.experimentId != experimentId ||
        liveReadReference.activationOrdinal != activationOrdinal) {
      throw const CanonicalFormatException(
        'experimentSummary Live read correlation disagrees',
      );
    }
    final integrityState = ExperimentIntegrityStateV1._fromWire(
      reader.string('integrityState'),
      '$path.integrityState',
    );
    if (integrityState != ExperimentIntegrityStateV1.verified) {
      throw const CanonicalFormatException(
        'experimentSummary requires verified integrity',
      );
    }
    return ExperimentSummaryV1._(
      json,
      target: target,
      experimentId: experimentId,
      label: _boundedString(reader.string('label'), '$path.label'),
      lifecycleState: ExperimentLifecycleStateV1._fromWire(
        reader.string('lifecycleState'),
        '$path.lifecycleState',
      ),
      integrityState: integrityState,
      activationOrdinal: activationOrdinal,
      lifecycleOrdinal: _positiveInteger(
        reader.integer('lifecycleOrdinal'),
        '$path.lifecycleOrdinal',
      ),
      controlPlaneOrdinal: _positiveInteger(
        reader.integer('controlPlaneOrdinal'),
        '$path.controlPlaneOrdinal',
      ),
      acceptedAtMicros: _positiveInteger(
        reader.integer('acceptedAtMicros'),
        '$path.acceptedAtMicros',
      ),
      archivedAtMicros: archivedAtMicros,
      pendingDraft: ExperimentPendingDraftSummaryV1.fromJson(
        reader.object('pendingDraft'),
        path: '$path.pendingDraft',
      ),
      inferenceReference: ExperimentInferenceReferenceV1.fromJson(
        reader.object('inferenceReference'),
        path: '$path.inferenceReference',
      ),
      liveReadReference: liveReadReference,
    );
  }

  @override
  final TargetCoordinate target;
  @override
  final ExperimentPublicIdV1 experimentId;
  final String label;
  final ExperimentLifecycleStateV1 lifecycleState;
  final ExperimentIntegrityStateV1 integrityState;
  final int activationOrdinal;
  final int lifecycleOrdinal;
  @override
  final int controlPlaneOrdinal;

  final int acceptedAtMicros;
  final int? archivedAtMicros;
  final ExperimentPendingDraftSummaryV1 pendingDraft;
  final ExperimentInferenceReferenceV1 inferenceReference;
  final ExperimentLiveReadReferenceV1 liveReadReference;
}

/// Safe metadata for an experiment that has not been activated.
final class ExperimentDraftSummaryV1 extends ExperimentListEntryV1 {
  ExperimentDraftSummaryV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.draftId,
    required this.draftRevisionId,
    required this.controlPlaneOrdinal,
    required this.label,
    required this.completeness,
    required this.createdAtMicros,
    required this.archivedAtMicros,
    required this.liveState,
  }) : super._(json);

  factory ExperimentDraftSummaryV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentDraftSummary';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'archivedAtMicros',
        'completeness',
        'controlPlaneOrdinal',
        'createdAtMicros',
        'draftId',
        'draftRevisionId',
        'experimentId',
        'kind',
        'label',
        'liveState',
        'schemaVersion',
        'target',
      },
      requiredKeys: const {
        'archivedAtMicros',
        'completeness',
        'controlPlaneOrdinal',
        'createdAtMicros',
        'draftId',
        'draftRevisionId',
        'experimentId',
        'kind',
        'label',
        'liveState',
        'schemaVersion',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentDraftSummary');
    final completeness = ExperimentDraftCompletenessV1.fromJson(
      reader.object('completeness'),
      path: '$path.completeness',
    );
    final createdAtMicros = _positiveInteger(
      reader.integer('createdAtMicros'),
      '$path.createdAtMicros',
    );
    final archivedAtMicros = switch (reader.requiredNullableValue(
      'archivedAtMicros',
    )) {
      null => null,
      final int value => _positiveInteger(value, '$path.archivedAtMicros'),
      _ => throw const CanonicalFormatException(
          'experimentDraftSummary.archivedAtMicros must be an integer or null',
        ),
    };
    if (archivedAtMicros != null && archivedAtMicros < createdAtMicros) {
      throw const CanonicalFormatException(
        'experimentDraftSummary archive time precedes creation',
      );
    }
    return ExperimentDraftSummaryV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      experimentId: _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      ),
      draftId: _identifier(
        reader.string('draftId'),
        '$path.draftId',
        ExperimentDraftIdV1.new,
      ),
      draftRevisionId: _identifier(
        reader.string('draftRevisionId'),
        '$path.draftRevisionId',
        ExperimentDraftRevisionIdV1.new,
      ),
      controlPlaneOrdinal: _positiveInteger(
        reader.integer('controlPlaneOrdinal'),
        '$path.controlPlaneOrdinal',
      ),
      label: _boundedString(
        reader.string('label'),
        '$path.label',
        allowEmpty:
            completeness.kind == ExperimentDraftCompletenessKindV1.incomplete,
      ),
      completeness: completeness,
      createdAtMicros: createdAtMicros,
      archivedAtMicros: archivedAtMicros,
      liveState: ExperimentDraftLiveStateV1.fromJson(
        reader.object('liveState'),
        path: '$path.liveState',
      ),
    );
  }

  @override
  final TargetCoordinate target;
  @override
  final ExperimentPublicIdV1 experimentId;
  final ExperimentDraftIdV1 draftId;
  final ExperimentDraftRevisionIdV1 draftRevisionId;
  @override
  final int controlPlaneOrdinal;
  final String label;
  final ExperimentDraftCompletenessV1 completeness;
  final int createdAtMicros;
  final int? archivedAtMicros;
  final ExperimentDraftLiveStateV1 liveState;
}

/// Bounded page of accepted experiment summaries.
final class ExperimentListViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentListViewV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experiments,
    required this.nextPageCursor,
  }) : super(json);

  /// Decodes a strict experiment list.
  factory ExperimentListViewV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentListView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'experiments',
        'kind',
        'nextPageCursor',
        'schemaVersion',
        'target',
      },
      requiredKeys: const {
        'experiments',
        'kind',
        'nextPageCursor',
        'schemaVersion',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentListView');
    final nextPageCursor = switch (reader.requiredNullableValue(
      'nextPageCursor',
    )) {
      null => null,
      final String value => _boundedString(value, '$path.nextPageCursor'),
      _ => throw const CanonicalFormatException(
          'experimentListView.nextPageCursor must be a string or null',
        ),
    };
    final target = TargetCoordinate.fromJson(reader.object('target'));
    final experiments = _objectList(
      reader.list('experiments'),
      path: '$path.experiments',
      maximumLength: _maximumExperiments,
      decode: (value, _) => ExperimentListEntryV1.fromJson(value),
    );
    if (experiments.any((entry) => entry.target != target)) {
      throw const CanonicalFormatException(
        'experimentListView contains a different target',
      );
    }
    _requireUnique(
      experiments.map((entry) => entry.experimentId.value),
      '$path.experiments.experimentId',
    );
    return ExperimentListViewV1._(
      json,
      target: target,
      experiments: experiments,
      nextPageCursor: nextPageCursor,
    );
  }

  final TargetCoordinate target;
  final List<ExperimentListEntryV1> experiments;
  final String? nextPageCursor;
}

/// One immutable accepted arm projection.
final class ExperimentArmDetailV1 extends _ExperimentAuthoringValue {
  ExperimentArmDetailV1._(
    Map<String, Object?> json, {
    required this.stableArmId,
    required this.label,
    required this.relativeWeight,
    required this.surfaceRevisionId,
  }) : super(json);

  factory ExperimentArmDetailV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
        'surfaceRevisionId',
      },
      requiredKeys: const {
        'kind',
        'label',
        'relativeWeight',
        'stableArmId',
        'surfaceRevisionId',
      },
      path: path,
    );
    _requireKind(reader, 'experimentArmDetail');
    return ExperimentArmDetailV1._(
      json,
      stableArmId: _identifier(
        reader.string('stableArmId'),
        '$path.stableArmId',
        ExperimentStableArmIdV1.new,
      ),
      label: _boundedString(reader.string('label'), '$path.label'),
      relativeWeight: _boundedRelativeWeight(
        reader.integer('relativeWeight'),
        '$path.relativeWeight',
      ),
      surfaceRevisionId: _identifier(
        reader.string('surfaceRevisionId'),
        '$path.surfaceRevisionId',
        SurfaceRevisionId.new,
      ),
    );
  }

  final ExperimentStableArmIdV1 stableArmId;
  final String label;
  final int relativeWeight;
  final SurfaceRevisionId surfaceRevisionId;
}

/// An accepted or draft-only experiment read.
sealed class ExperimentReadViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentReadViewV1._(super.json);

  factory ExperimentReadViewV1.fromJson(Map<String, Object?> json) =>
      switch (_readDiscriminator(json, 'experimentReadView')) {
        'experimentDetail' => ExperimentDetailV1.fromJson(json),
        'experimentIntegrityUnavailableDetail' =>
          ExperimentIntegrityUnavailableDetailV1.fromJson(json),
        'experimentDraftDetail' => ExperimentDraftDetailV1.fromJson(json),
        final kind => throw CanonicalFormatException(
            'experimentReadView.kind "$kind" is unsupported',
          ),
      };

  @override
  TargetCoordinate get target;

  ExperimentPublicIdV1 get experimentId;
}

/// Accepted experiment detail without immutable presentation metadata.
final class ExperimentIntegrityUnavailableDetailV1
    extends ExperimentReadViewV1 {
  ExperimentIntegrityUnavailableDetailV1._(
    Map<String, Object?> json,
    this.summary,
  ) : super._(json);

  factory ExperimentIntegrityUnavailableDetailV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentIntegrityUnavailableDetail';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'schemaVersion', 'summary'},
      requiredKeys: const {'kind', 'schemaVersion', 'summary'},
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentIntegrityUnavailableDetail',
    );
    return ExperimentIntegrityUnavailableDetailV1._(
      json,
      ExperimentIntegrityUnavailableSummaryV1.fromJson(
        reader.object('summary'),
      ),
    );
  }

  final ExperimentIntegrityUnavailableSummaryV1 summary;

  @override
  TargetCoordinate get target => summary.target;

  @override
  ExperimentPublicIdV1 get experimentId => summary.experimentId;
}

/// Detailed safe projection of one accepted experiment.
final class ExperimentDetailV1 extends ExperimentReadViewV1 {
  ExperimentDetailV1._(
    Map<String, Object?> json, {
    required this.summary,
    required this.description,
    required this.arms,
  }) : super._(json);

  /// Decodes a strict experiment detail.
  factory ExperimentDetailV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentDetail';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'arms',
        'description',
        'kind',
        'schemaVersion',
        'summary',
      },
      requiredKeys: const {
        'arms',
        'description',
        'kind',
        'schemaVersion',
        'summary',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentDetail');
    final arms = _objectList(
      reader.list('arms'),
      path: '$path.arms',
      maximumLength: _maximumArms,
      minimumLength: 2,
      decode: (value, itemPath) =>
          ExperimentArmDetailV1.fromJson(value, path: itemPath),
    );
    _requireUnique(
      arms.map((entry) => entry.stableArmId.value),
      '$path.arms.stableArmId',
    );
    return ExperimentDetailV1._(
      json,
      summary: ExperimentSummaryV1.fromJson(reader.object('summary')),
      description: _boundedString(
        reader.string('description'),
        '$path.description',
      ),
      arms: arms,
    );
  }

  final ExperimentSummaryV1 summary;
  final String description;
  final List<ExperimentArmDetailV1> arms;

  @override
  TargetCoordinate get target => summary.target;

  @override
  ExperimentPublicIdV1 get experimentId => summary.experimentId;
}

/// Detailed safe projection of an experiment draft.
final class ExperimentDraftDetailV1 extends ExperimentReadViewV1 {
  ExperimentDraftDetailV1._(
    Map<String, Object?> json, {
    required this.summary,
    required this.draft,
  }) : super._(json);

  factory ExperimentDraftDetailV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentDraftDetail';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'draft', 'kind', 'schemaVersion', 'summary'},
      requiredKeys: const {'draft', 'kind', 'schemaVersion', 'summary'},
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentDraftDetail');
    final summary = ExperimentDraftSummaryV1.fromJson(
      reader.object('summary'),
    );
    final draft = ExperimentDraftViewV1.fromJson(reader.object('draft'));
    final draftLabel = switch (draft.choices) {
      ExperimentResolvedPartialDraftChoicesV1 choices => choices.label,
      ExperimentDraftChoicesV1 choices => choices.label,
    };
    if (summary.target != draft.target ||
        summary.experimentId != draft.experimentId ||
        summary.draftId != draft.draftId ||
        summary.draftRevisionId != draft.draftRevisionId ||
        summary.label != draftLabel ||
        summary.completeness != draft.completeness) {
      throw const CanonicalFormatException(
        'experimentDraftDetail summary and draft disagree',
      );
    }
    return ExperimentDraftDetailV1._(
      json,
      summary: summary,
      draft: draft,
    );
  }

  final ExperimentDraftSummaryV1 summary;
  final ExperimentDraftViewV1 draft;

  @override
  TargetCoordinate get target => summary.target;

  @override
  ExperimentPublicIdV1 get experimentId => summary.experimentId;
}

/// Closed availability projection for experiment results.
final class ExperimentResultsAvailabilityV1 extends _ExperimentAuthoringValue {
  ExperimentResultsAvailabilityV1._(
    Map<String, Object?> json, {
    required this.kind,
    required this.reasonCode,
  }) : super(json);

  factory ExperimentResultsAvailabilityV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final kind = ExperimentResultsAvailabilityKindV1._fromWire(
      _readDiscriminator(json, path),
      '$path.kind',
    );
    final available = kind == ExperimentResultsAvailabilityKindV1.available;
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: available ? const {'kind'} : const {'kind', 'reasonCode'},
      requiredKeys: available ? const {'kind'} : const {'kind', 'reasonCode'},
      path: path,
    );
    return ExperimentResultsAvailabilityV1._(
      json,
      kind: kind,
      reasonCode: available
          ? null
          : _boundedString(reader.string('reasonCode'), '$path.reasonCode'),
    );
  }

  final ExperimentResultsAvailabilityKindV1 kind;
  final String? reasonCode;
}

/// Exact confidence interval for one arm statistic.
final class ExperimentResultIntervalV1 extends _ExperimentAuthoringValue {
  ExperimentResultIntervalV1._(
    Map<String, Object?> json, {
    required this.lower,
    required this.upper,
  }) : super(json);

  factory ExperimentResultIntervalV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'lower', 'upper'},
      requiredKeys: const {'lower', 'upper'},
      path: path,
    );
    return ExperimentResultIntervalV1._(
      json,
      lower: ExperimentRationalV1.fromJson(
        reader.object('lower'),
        path: '$path.lower',
      ),
      upper: ExperimentRationalV1.fromJson(
        reader.object('upper'),
        path: '$path.upper',
      ),
    );
  }

  final ExperimentRationalV1 lower;
  final ExperimentRationalV1 upper;
}

/// Safe result statistics for one stable arm.
final class ExperimentArmResultV1 extends _ExperimentAuthoringValue {
  ExperimentArmResultV1._(
    Map<String, Object?> json, {
    required this.stableArmId,
    required this.admittedCount,
    required this.observedCount,
    required this.successCount,
    required this.rate,
    required this.effect,
    required this.interval,
  }) : super(json);

  factory ExperimentArmResultV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'admittedCount',
        'effect',
        'interval',
        'kind',
        'observedCount',
        'rate',
        'stableArmId',
        'successCount',
      },
      requiredKeys: const {
        'admittedCount',
        'effect',
        'interval',
        'kind',
        'observedCount',
        'rate',
        'stableArmId',
        'successCount',
      },
      path: path,
    );
    _requireKind(reader, 'experimentArmResult');
    final admittedCount = _nonNegativeInteger(
      reader.integer('admittedCount'),
      '$path.admittedCount',
    );
    final observedCount = _nonNegativeInteger(
      reader.integer('observedCount'),
      '$path.observedCount',
    );
    final successCount = _nonNegativeInteger(
      reader.integer('successCount'),
      '$path.successCount',
    );
    if (observedCount > admittedCount || successCount > observedCount) {
      throw CanonicalFormatException('$path counts are inconsistent');
    }
    final rate = ExperimentRationalV1.fromJson(
      reader.object('rate'),
      path: '$path.rate',
    );
    _requireProbability(rate, '$path.rate');
    return ExperimentArmResultV1._(
      json,
      stableArmId: _identifier(
        reader.string('stableArmId'),
        '$path.stableArmId',
        ExperimentStableArmIdV1.new,
      ),
      admittedCount: admittedCount,
      observedCount: observedCount,
      successCount: successCount,
      rate: rate,
      effect: ExperimentRationalV1.fromJson(
        reader.object('effect'),
        path: '$path.effect',
      ),
      interval: ExperimentResultIntervalV1.fromJson(
        reader.object('interval'),
        path: '$path.interval',
      ),
    );
  }

  final ExperimentStableArmIdV1 stableArmId;
  final int admittedCount;
  final int observedCount;
  final int successCount;
  final ExperimentRationalV1 rate;
  final ExperimentRationalV1 effect;
  final ExperimentResultIntervalV1 interval;
}

/// Safe outcome of one configured guardrail.
final class ExperimentGuardrailOutcomeV1 extends _ExperimentAuthoringValue {
  ExperimentGuardrailOutcomeV1._(
    Map<String, Object?> json, {
    required this.guardrailId,
    required this.outcome,
  }) : super(json);

  factory ExperimentGuardrailOutcomeV1.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'guardrailId', 'kind', 'outcome'},
      requiredKeys: const {'guardrailId', 'kind', 'outcome'},
      path: path,
    );
    _requireKind(reader, 'experimentGuardrailOutcome');
    final outcome = reader.string('outcome');
    if (!const {
      'withinBound',
      'exceededBound',
      'insufficientEvidence',
      'indeterminate',
    }.contains(outcome)) {
      throw CanonicalFormatException('$path.outcome "$outcome" is unsupported');
    }
    return ExperimentGuardrailOutcomeV1._(
      json,
      guardrailId: _identifier(
        reader.string('guardrailId'),
        '$path.guardrailId',
        AuthorityRevisionId.new,
      ),
      outcome: outcome,
    );
  }

  final AuthorityRevisionId guardrailId;
  final String outcome;
}

/// Safe statistics and explicit availability for one experiment result.
final class ExperimentResultsViewV1 extends _ExperimentAuthoringValue
    implements ExperimentTargetBoundViewV1 {
  ExperimentResultsViewV1._(
    Map<String, Object?> json, {
    required this.target,
    required this.experimentId,
    required this.analysis,
    required this.lifecycleState,
    required this.availability,
    required this.designDigest,
    required this.epochDigest,
    required this.resultDigest,
    required this.generatedAtMicros,
    required this.armResults,
    required this.guardrailOutcomes,
    required this.structuredCopyKeys,
  }) : super(json);

  /// Decodes a strict experiment-results projection.
  factory ExperimentResultsViewV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentResultsView';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analysis',
        'armResults',
        'availability',
        'designDigest',
        'epochDigest',
        'experimentId',
        'generatedAtMicros',
        'guardrailOutcomes',
        'kind',
        'lifecycleState',
        'resultDigest',
        'schemaVersion',
        'structuredCopyKeys',
        'target',
      },
      requiredKeys: const {
        'analysis',
        'armResults',
        'availability',
        'designDigest',
        'epochDigest',
        'experimentId',
        'generatedAtMicros',
        'guardrailOutcomes',
        'kind',
        'lifecycleState',
        'resultDigest',
        'schemaVersion',
        'structuredCopyKeys',
        'target',
      },
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'experimentResultsView');
    final availability = ExperimentResultsAvailabilityV1.fromJson(
      reader.object('availability'),
      path: '$path.availability',
    );
    final armResults = _objectList(
      reader.list('armResults'),
      path: '$path.armResults',
      maximumLength: _maximumArms,
      decode: (value, itemPath) =>
          ExperimentArmResultV1.fromJson(value, path: itemPath),
    );
    final guardrailOutcomes = _objectList(
      reader.list('guardrailOutcomes'),
      path: '$path.guardrailOutcomes',
      maximumLength: _maximumRelatedValues,
      decode: (value, itemPath) =>
          ExperimentGuardrailOutcomeV1.fromJson(value, path: itemPath),
    );
    if (availability.kind != ExperimentResultsAvailabilityKindV1.available &&
        (armResults.isNotEmpty || guardrailOutcomes.isNotEmpty)) {
      throw const CanonicalFormatException(
        'experimentResultsView unavailable results contain statistics',
      );
    }
    return ExperimentResultsViewV1._(
      json,
      target: TargetCoordinate.fromJson(reader.object('target')),
      experimentId: _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      ),
      analysis: ExperimentAnalysisKindV1._fromWire(
        reader.string('analysis'),
        '$path.analysis',
      ),
      lifecycleState: ExperimentLifecycleStateV1._fromWire(
        reader.string('lifecycleState'),
        '$path.lifecycleState',
      ),
      availability: availability,
      designDigest: _parsedDigest(
        reader.string('designDigest'),
        '$path.designDigest',
      ),
      epochDigest: _parsedDigest(
        reader.string('epochDigest'),
        '$path.epochDigest',
      ),
      resultDigest: _parsedDigest(
        reader.string('resultDigest'),
        '$path.resultDigest',
      ),
      generatedAtMicros: _positiveInteger(
        reader.integer('generatedAtMicros'),
        '$path.generatedAtMicros',
      ),
      armResults: armResults,
      guardrailOutcomes: guardrailOutcomes,
      structuredCopyKeys: _stringList(
        reader.list('structuredCopyKeys'),
        path: '$path.structuredCopyKeys',
        maximumLength: _maximumRelatedValues,
      ),
    );
  }

  final TargetCoordinate target;
  final ExperimentPublicIdV1 experimentId;
  final ExperimentAnalysisKindV1 analysis;
  final ExperimentLifecycleStateV1 lifecycleState;
  final ExperimentResultsAvailabilityV1 availability;
  final CanonicalDigest designDigest;
  final CanonicalDigest epochDigest;
  final CanonicalDigest resultDigest;
  final int generatedAtMicros;
  final List<ExperimentArmResultV1> armResults;
  final List<ExperimentGuardrailOutcomeV1> guardrailOutcomes;
  final List<String> structuredCopyKeys;
}

/// Public refusal details for one semantic operation.
final class ExperimentAuthoringRefusalV1 extends _ExperimentAuthoringValue {
  ExperimentAuthoringRefusalV1._(
    Map<String, Object?> json, {
    required this.code,
    required this.messageKey,
    required this.retryable,
  }) : super(json);

  /// Decodes strict refusal details.
  factory ExperimentAuthoringRefusalV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentAuthoringRefusal';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'code',
        'kind',
        'messageKey',
        'retryable',
        'schemaVersion',
      },
      requiredKeys: const {
        'code',
        'kind',
        'messageKey',
        'retryable',
        'schemaVersion',
      },
      path: path,
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'experimentAuthoringRefusal',
    );
    final code = ExperimentAuthoringRefusalCodeV1._fromWire(
      reader.string('code'),
      '$path.code',
    );
    final retryable = reader.boolean('retryable');
    final expectedRetryable =
        code == ExperimentAuthoringRefusalCodeV1.backendUnavailable ||
            code == ExperimentAuthoringRefusalCodeV1.transportUnknownOutcome;
    if (retryable != expectedRetryable) {
      throw const CanonicalFormatException(
        'experimentAuthoringRefusal.retryable disagrees with its code',
      );
    }
    return ExperimentAuthoringRefusalV1._(
      json,
      code: code,
      messageKey: _boundedString(
        reader.string('messageKey'),
        '$path.messageKey',
      ),
      retryable: retryable,
    );
  }

  final ExperimentAuthoringRefusalCodeV1 code;
  final String messageKey;
  final bool retryable;
}

/// Closed result union for semantic experiment operations.
sealed class ExperimentAuthoringResultV1 extends _ExperimentAuthoringValue {
  ExperimentAuthoringResultV1._(
    super.json, {
    required this.operation,
    required this.correlationId,
  });

  /// Decodes a strict accepted or refused result.
  factory ExperimentAuthoringResultV1.fromJson(Map<String, Object?> json) {
    final kind = _readDiscriminator(json, 'experimentAuthoringResult');
    return switch (kind) {
      'accepted' => ExperimentAuthoringAcceptedV1.fromJson(json),
      'refused' => ExperimentAuthoringRefusedV1.fromJson(json),
      _ => throw CanonicalFormatException(
          'experimentAuthoringResult.kind "$kind" is unsupported',
        ),
    };
  }

  /// Decodes byte-exact canonical result JSON.
  factory ExperimentAuthoringResultV1.fromCanonicalBytes(List<int> bytes) {
    _checkByteLimit(
      bytes,
      experimentAuthoringMaximumResultBytes,
      'experimentAuthoringResult',
    );
    return verifyCanonicalRoundTrip(
      ExperimentAuthoringResultV1.fromJson(decodeCanonicalObject(bytes)),
      bytes,
      path: 'experimentAuthoringResult',
    );
  }

  /// Operation that produced this result.
  final ExperimentAuthoringOperationV1 operation;

  /// Correlation identity copied from the request.
  final String correlationId;
}

/// Accepted semantic operation and its operation-specific response.
final class ExperimentAuthoringAcceptedV1 extends ExperimentAuthoringResultV1 {
  ExperimentAuthoringAcceptedV1._(
    Map<String, Object?> json, {
    required ExperimentAuthoringOperationV1 operation,
    required String correlationId,
    required this.response,
  }) : super._(
          json,
          operation: operation,
          correlationId: correlationId,
        );

  factory ExperimentAuthoringAcceptedV1.fromJson(
    Map<String, Object?> json,
  ) {
    const path = 'experimentAuthoringAccepted';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'correlationId',
        'kind',
        'operation',
        'response',
        'schemaVersion',
      },
      requiredKeys: const {
        'correlationId',
        'kind',
        'operation',
        'response',
        'schemaVersion',
      },
      path: path,
    );
    _validateVersionAndKind(reader, 'accepted');
    final operation = ExperimentAuthoringOperationV1._fromWire(
      reader.string('operation'),
      '$path.operation',
    );
    return ExperimentAuthoringAcceptedV1._(
      json,
      operation: operation,
      correlationId: _boundedString(
        reader.string('correlationId'),
        '$path.correlationId',
      ),
      response: _decodeAcceptedResponse(operation, reader.object('response')),
    );
  }

  /// Safe response projection selected by [operation].
  final CanonicalValue response;
}

/// Refused semantic operation with a closed refusal discriminator.
final class ExperimentAuthoringRefusedV1 extends ExperimentAuthoringResultV1 {
  ExperimentAuthoringRefusedV1._(
    Map<String, Object?> json, {
    required ExperimentAuthoringOperationV1 operation,
    required String correlationId,
    required this.refusal,
  }) : super._(
          json,
          operation: operation,
          correlationId: correlationId,
        );

  factory ExperimentAuthoringRefusedV1.fromJson(Map<String, Object?> json) {
    const path = 'experimentAuthoringRefused';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'correlationId',
        'kind',
        'operation',
        'refusal',
        'schemaVersion',
      },
      requiredKeys: const {
        'correlationId',
        'kind',
        'operation',
        'refusal',
        'schemaVersion',
      },
      path: path,
    );
    _validateVersionAndKind(reader, 'refused');
    return ExperimentAuthoringRefusedV1._(
      json,
      operation: ExperimentAuthoringOperationV1._fromWire(
        reader.string('operation'),
        '$path.operation',
      ),
      correlationId: _boundedString(
        reader.string('correlationId'),
        '$path.correlationId',
      ),
      refusal: ExperimentAuthoringRefusalV1.fromJson(
        reader.object('refusal'),
      ),
    );
  }

  /// Public-safe refusal details.
  final ExperimentAuthoringRefusalV1 refusal;
}

CanonicalValue _decodeAcceptedResponse(
  ExperimentAuthoringOperationV1 operation,
  Map<String, Object?> json,
) =>
    switch (operation) {
      ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities =>
        ExperimentTargetDiscoveryV1.fromJson(json),
      ExperimentAuthoringOperationV1.openDraft ||
      ExperimentAuthoringOperationV1.readDraft ||
      ExperimentAuthoringOperationV1.resolveDraft ||
      ExperimentAuthoringOperationV1.replaceDraft ||
      ExperimentAuthoringOperationV1.copyDraftToTarget =>
        ExperimentDraftViewV1.fromJson(json),
      ExperimentAuthoringOperationV1.validateDraft =>
        ExperimentValidationViewV1.fromJson(json),
      ExperimentAuthoringOperationV1.reviewDraft =>
        ExperimentReviewViewV1.fromJson(
          json,
        ),
      ExperimentAuthoringOperationV1.activateDraft =>
        ExperimentActivationAcceptedViewV1.fromJson(json),
      ExperimentAuthoringOperationV1.pauseExperiment =>
        ExperimentLifecycleAcceptedViewV1.fromJson(
          json,
          expectedLifecycleState: ExperimentLifecycleStateV1.paused,
        ),
      ExperimentAuthoringOperationV1.resumeExperiment =>
        ExperimentLifecycleAcceptedViewV1.fromJson(
          json,
          expectedLifecycleState: ExperimentLifecycleStateV1.active,
        ),
      ExperimentAuthoringOperationV1.concludeExperiment =>
        ExperimentLifecycleAcceptedViewV1.fromJson(
          json,
          expectedLifecycleState: ExperimentLifecycleStateV1.concluded,
        ),
      ExperimentAuthoringOperationV1.listExperiments =>
        ExperimentListViewV1.fromJson(json),
      ExperimentAuthoringOperationV1.readExperiment ||
      ExperimentAuthoringOperationV1.setExperimentArchived =>
        ExperimentReadViewV1.fromJson(json),
      ExperimentAuthoringOperationV1.readExperimentResults =>
        ExperimentResultsViewV1.fromJson(json),
    };

void _validateRequestPayload(
  ExperimentAuthoringOperationV1 operation,
  Map<String, Object?> payload,
) {
  const path = 'experimentAuthoringRequest.payload';
  switch (operation) {
    case ExperimentAuthoringOperationV1.discoverTargetsAndCapabilities:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'pageCursor', 'pageSize'},
        requiredKeys: const {'pageSize'},
        path: path,
      );
      final pageSize = reader.integer('pageSize');
      if (pageSize <= 0 || pageSize > _maximumDiscoveryPageSize) {
        throw const CanonicalFormatException(
          'experimentAuthoringRequest.payload.pageSize is outside 1..100',
        );
      }
      final pageCursor = reader.optionalString('pageCursor');
      if (pageCursor != null) {
        _boundedString(pageCursor, '$path.pageCursor');
      }
    case ExperimentAuthoringOperationV1.openDraft:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'initialCandidate'},
        requiredKeys: const {},
        path: path,
      );
      final initialCandidate = reader.optionalObject('initialCandidate');
      if (initialCandidate != null) {
        ExperimentExactSurfaceReferenceV1.fromJson(
          initialCandidate,
          path: '$path.initialCandidate',
        );
      }
    case ExperimentAuthoringOperationV1.readDraft:
    case ExperimentAuthoringOperationV1.validateDraft:
    case ExperimentAuthoringOperationV1.reviewDraft:
      ExperimentDraftBindingV1.fromJson(payload, path: path);
    case ExperimentAuthoringOperationV1.resolveDraft:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'draftId'},
        requiredKeys: const {'draftId'},
        path: path,
      );
      _identifier(
        reader.string('draftId'),
        '$path.draftId',
        ExperimentDraftIdV1.new,
      );
    case ExperimentAuthoringOperationV1.copyDraftToTarget:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'sourceDraft', 'sourceTarget'},
        requiredKeys: const {'sourceDraft', 'sourceTarget'},
        path: path,
      );
      TargetCoordinate.fromJson(reader.object('sourceTarget'));
      ExperimentDraftBindingV1.fromJson(
        reader.object('sourceDraft'),
        path: '$path.sourceDraft',
      );
    case ExperimentAuthoringOperationV1.replaceDraft:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {
          'draftId',
          'draftRevisionId',
          'expectedCas',
          'replacement',
        },
        requiredKeys: const {
          'draftId',
          'draftRevisionId',
          'expectedCas',
          'replacement',
        },
        path: path,
      );
      _validateDraftBindingFields(reader, path);
      _validateDraftMutationChoices(reader.object('replacement'));
    case ExperimentAuthoringOperationV1.activateDraft:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {
          'draftId',
          'draftRevisionId',
          'expectedCas',
          'reviewReference',
        },
        requiredKeys: const {
          'draftId',
          'draftRevisionId',
          'expectedCas',
          'reviewReference',
        },
        path: path,
      );
      _validateDraftBindingFields(reader, path);
      ExperimentReviewReferenceV1.fromJson(reader.object('reviewReference'));
    case ExperimentAuthoringOperationV1.pauseExperiment:
    case ExperimentAuthoringOperationV1.resumeExperiment:
    case ExperimentAuthoringOperationV1.concludeExperiment:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'expectedLifecycleOrdinal', 'experimentId'},
        requiredKeys: const {'expectedLifecycleOrdinal', 'experimentId'},
        path: path,
      );
      _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      );
      _positiveInteger(
        reader.integer('expectedLifecycleOrdinal'),
        '$path.expectedLifecycleOrdinal',
      );
    case ExperimentAuthoringOperationV1.listExperiments:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'pageCursor', 'pageSize'},
        requiredKeys: const {'pageSize'},
        path: path,
      );
      final pageSize = reader.integer('pageSize');
      if (pageSize <= 0 || pageSize > _maximumExperiments) {
        throw const CanonicalFormatException(
          'experimentAuthoringRequest.payload.pageSize is outside 1..100',
        );
      }
      final pageCursor = reader.optionalString('pageCursor');
      if (pageCursor != null) _boundedString(pageCursor, '$path.pageCursor');
    case ExperimentAuthoringOperationV1.readExperiment:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {'experimentId'},
        requiredKeys: const {'experimentId'},
        path: path,
      );
      _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      );
    case ExperimentAuthoringOperationV1.readExperimentResults:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {
          'activationOrdinal',
          'experimentId',
          'resultDigest',
        },
        requiredKeys: const {
          'activationOrdinal',
          'experimentId',
          'resultDigest',
        },
        path: path,
      );
      _validateExperimentSelector(reader, path);
      _parsedDigest(reader.string('resultDigest'), '$path.resultDigest');
    case ExperimentAuthoringOperationV1.setExperimentArchived:
      final reader = CanonicalObjectReader(
        payload,
        allowedKeys: const {
          'archived',
          'expectedControlPlaneOrdinal',
          'experimentId',
        },
        requiredKeys: const {
          'archived',
          'expectedControlPlaneOrdinal',
          'experimentId',
        },
        path: path,
      );
      reader.boolean('archived');
      _identifier(
        reader.string('experimentId'),
        '$path.experimentId',
        ExperimentPublicIdV1.new,
      );
      _positiveInteger(
        reader.integer('expectedControlPlaneOrdinal'),
        '$path.expectedControlPlaneOrdinal',
      );
  }
}

void _validateDraftMutationAnalysisSelection(
  Map<String, Object?> json,
  String path,
) {
  final kind = _readDiscriminator(json, path);
  if (kind == 'unselected' || kind == 'measureOnly') {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: path,
    );
    if (reader.string('kind') != kind) {
      throw CanonicalFormatException('$path.kind is invalid');
    }
    return;
  }
  if (kind != 'fixedHorizonNArmRate') {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'kind', 'planningSelection'},
    requiredKeys: const {'kind', 'planningSelection'},
    path: path,
  );
  _validatePlanningMutationSelection(
    reader.object('planningSelection'),
    '$path.planningSelection',
  );
}

void _validatePlanningMutationSelection(
  Map<String, Object?> json,
  String path,
) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {
      'allocationWeights',
      'alphaChoice',
      'enrollmentCap',
      'expectedBaseline',
      'followUpDurationMicros',
      'guardrails',
      'kind',
      'maximumEnrollmentDurationMicros',
      'minimumDetectableEffect',
      'outcomeGracePeriodMicros',
      'primaryTargetPowerChoice',
      'practicalSuperiorityMarginChoice',
      'referenceArmId',
      'schemaVersion',
    },
    requiredKeys: const {
      'allocationWeights',
      'alphaChoice',
      'enrollmentCap',
      'expectedBaseline',
      'followUpDurationMicros',
      'guardrails',
      'kind',
      'maximumEnrollmentDurationMicros',
      'minimumDetectableEffect',
      'outcomeGracePeriodMicros',
      'primaryTargetPowerChoice',
      'practicalSuperiorityMarginChoice',
      'referenceArmId',
      'schemaVersion',
    },
    path: path,
  );
  validateCanonicalDocument(
    reader,
    expectedKind: 'experimentNArmPlanningSelection',
  );
  final referenceArmId = _identifier(
    reader.string('referenceArmId'),
    '$path.referenceArmId',
    ExperimentStableArmIdV1.new,
  );
  final expectedBaseline = ExperimentRationalV1.fromJson(
    reader.object('expectedBaseline'),
    path: '$path.expectedBaseline',
  );
  final minimumDetectableEffect = ExperimentRationalV1.fromJson(
    reader.object('minimumDetectableEffect'),
    path: '$path.minimumDetectableEffect',
  );
  _requireOpenProbability(expectedBaseline, '$path.expectedBaseline');
  _requirePositiveFraction(
    minimumDetectableEffect,
    '$path.minimumDetectableEffect',
  );
  final margin = _validateUnresolvedStatisticalChoice(
    reader.object('practicalSuperiorityMarginChoice'),
    '$path.practicalSuperiorityMarginChoice',
    (value) => _requirePositiveFraction(
      value,
      '$path.practicalSuperiorityMarginChoice.value',
    ),
  );
  _validateUnresolvedStatisticalChoice(
    reader.object('alphaChoice'),
    '$path.alphaChoice',
    (value) => _requireSupportedAlpha(value, '$path.alphaChoice.value'),
  );
  _validateUnresolvedStatisticalChoice(
    reader.object('primaryTargetPowerChoice'),
    '$path.primaryTargetPowerChoice',
    (value) => _requireSupportedPower(
      value,
      '$path.primaryTargetPowerChoice.value',
    ),
  );
  _requireStrictlyLess(
    margin ?? const ExperimentStatisticalDefaultsV1().margin,
    minimumDetectableEffect,
    '$path.practicalSuperiorityMarginChoice',
  );
  final enrollmentCap = reader.integer('enrollmentCap');
  final followUpDurationMicros = reader.integer('followUpDurationMicros');
  final maximumEnrollmentDurationMicros = reader.integer(
    'maximumEnrollmentDurationMicros',
  );
  final outcomeGracePeriodMicros = reader.integer('outcomeGracePeriodMicros');
  if (enrollmentCap <= 0 ||
      followUpDurationMicros <= 0 ||
      maximumEnrollmentDurationMicros <= 0 ||
      outcomeGracePeriodMicros < 0) {
    throw CanonicalFormatException('$path contains an invalid bound');
  }
  final allocationWeights = _objectList(
    reader.list('allocationWeights'),
    path: '$path.allocationWeights',
    maximumLength: _maximumArms,
    minimumLength: 2,
    decode: (value, itemPath) =>
        ExperimentArmPlanningWeightV1.fromJson(value, path: itemPath),
  );
  _requireUnique(
    allocationWeights.map((entry) => entry.armId.value),
    '$path.allocationWeights.armId',
  );
  if (!allocationWeights.any((entry) => entry.armId == referenceArmId)) {
    throw CanonicalFormatException('$path.referenceArmId is not allocated');
  }
  final guardrailIds = _objectList(
    reader.list('guardrails'),
    path: '$path.guardrails',
    maximumLength: _maximumRelatedValues,
    decode: (value, itemPath) {
      final guardrail = CanonicalObjectReader(
        value,
        allowedKeys: const {
          'expectedReferenceRate',
          'guardrailId',
          'harmMargin',
          'targetPower',
        },
        requiredKeys: const {
          'expectedReferenceRate',
          'guardrailId',
          'harmMargin',
          'targetPower',
        },
        path: itemPath,
      );
      final guardrailId = _identifier(
        guardrail.string('guardrailId'),
        '$itemPath.guardrailId',
        AuthorityRevisionId.new,
      );
      final expectedReferenceRate = ExperimentRationalV1.fromJson(
        guardrail.object('expectedReferenceRate'),
        path: '$itemPath.expectedReferenceRate',
      );
      final harmMargin = ExperimentRationalV1.fromJson(
        guardrail.object('harmMargin'),
        path: '$itemPath.harmMargin',
      );
      final targetPower = ExperimentRationalV1.fromJson(
        guardrail.object('targetPower'),
        path: '$itemPath.targetPower',
      );
      _requireOpenProbability(
        expectedReferenceRate,
        '$itemPath.expectedReferenceRate',
      );
      _requirePositiveFraction(harmMargin, '$itemPath.harmMargin');
      _requireSupportedPower(targetPower, '$itemPath.targetPower');
      return guardrailId.value;
    },
  );
  _requireUnique(guardrailIds, '$path.guardrails.guardrailId');
}

ExperimentRationalV1? _validateUnresolvedStatisticalChoice(
  Map<String, Object?> json,
  String path,
  void Function(ExperimentRationalV1 value) validateValue,
) {
  final kind = _readDiscriminator(json, path);
  if (kind == 'serverDefault') {
    CanonicalObjectReader(
      json,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: path,
    );
    return null;
  }
  if (kind != 'explicitValue') {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'kind', 'value'},
    requiredKeys: const {'kind', 'value'},
    path: path,
  );
  final value = ExperimentRationalV1.fromJson(
    reader.object('value'),
    path: '$path.value',
  );
  validateValue(value);
  return value;
}

void _validateDraftMutationChoices(Map<String, Object?> json) {
  const path = 'experimentDraftMutationChoices';
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {
      'analysisSelection',
      'arms',
      'assignmentAudienceSelection',
      'assignmentEligibilitySelection',
      'description',
      'diagnosticBindingIds',
      'guardrails',
      'kind',
      'label',
      'layerHoldoutIds',
      'memberHoldouts',
      'memberNoTreatment',
      'metricBindings',
      'primaryBindingSelection',
      'randomizedUnitSelection',
      'rootSurfaceSelection',
      'subjectSelection',
    },
    requiredKeys: const {
      'analysisSelection',
      'arms',
      'assignmentAudienceSelection',
      'assignmentEligibilitySelection',
      'description',
      'diagnosticBindingIds',
      'guardrails',
      'kind',
      'label',
      'layerHoldoutIds',
      'memberHoldouts',
      'memberNoTreatment',
      'metricBindings',
      'primaryBindingSelection',
      'randomizedUnitSelection',
      'rootSurfaceSelection',
      'subjectSelection',
    },
    path: path,
  );
  _requireKind(reader, 'experimentDraftChoices');
  _boundedString(reader.string('label'), '$path.label', allowEmpty: true);
  _boundedString(
    reader.string('description'),
    '$path.description',
    allowEmpty: true,
  );
  _validateMutationSelection(
    reader.object('assignmentAudienceSelection'),
    '$path.assignmentAudienceSelection',
    (value, itemPath) =>
        ExperimentExactPolicyReferenceV1.fromJson(value, path: itemPath),
  );
  _validateMutationSelection(
    reader.object('assignmentEligibilitySelection'),
    '$path.assignmentEligibilitySelection',
    (value, itemPath) =>
        ExperimentExactPolicyReferenceV1.fromJson(value, path: itemPath),
  );
  _validateRandomizedUnitMutationSelection(
    reader.object('randomizedUnitSelection'),
    '$path.randomizedUnitSelection',
  );
  _validateMutationSelection(
    reader.object('rootSurfaceSelection'),
    '$path.rootSurfaceSelection',
    (value, itemPath) =>
        ExperimentExactSurfaceReferenceV1.fromJson(value, path: itemPath),
  );
  _validateMutationSelection(
    reader.object('memberNoTreatment'),
    '$path.memberNoTreatment',
    (value, itemPath) =>
        ExperimentExactCandidateV1.fromJson(value, path: itemPath),
  );
  _validateMutationSelection(
    reader.object('primaryBindingSelection'),
    '$path.primaryBindingSelection',
    (value, itemPath) =>
        ExperimentMetricBindingReferenceV1.fromJson(value, path: itemPath),
    allowServerDefault: false,
  );
  _validateMutationSubjectSelection(
    reader.object('subjectSelection'),
    '$path.subjectSelection',
  );
  final analysis = reader.object('analysisSelection');
  _validateDraftMutationAnalysisSelection(
    analysis,
    '$path.analysisSelection',
  );
  final arms = _objectList(
    reader.list('arms'),
    path: '$path.arms',
    maximumLength: _maximumArms,
    decode: (value, itemPath) {
      final arm = CanonicalObjectReader(
        value,
        allowedKeys: const {
          'candidateSelection',
          'kind',
          'label',
          'relativeWeight',
          'stableArmId',
        },
        requiredKeys: const {
          'candidateSelection',
          'kind',
          'label',
          'relativeWeight',
          'stableArmId',
        },
        path: itemPath,
      );
      _requireKind(arm, 'experimentDraftArmChoice');
      _identifier(
        arm.string('stableArmId'),
        '$itemPath.stableArmId',
        ExperimentStableArmIdV1.new,
      );
      _boundedString(
        arm.string('label'),
        '$itemPath.label',
        allowEmpty: true,
      );
      _boundedRelativeWeight(
        arm.integer('relativeWeight'),
        '$itemPath.relativeWeight',
      );
      _validateMutationSelection(
        arm.object('candidateSelection'),
        '$itemPath.candidateSelection',
        (value, candidatePath) => ExperimentExactCandidateV1.fromJson(
          value,
          path: candidatePath,
        ),
      );
      return arm.string('stableArmId');
    },
  );
  _requireUnique(arms, '$path.arms.stableArmId');
  final bindings = _objectList(
    reader.list('metricBindings'),
    path: '$path.metricBindings',
    maximumLength: _maximumRelatedValues,
    decode: (value, itemPath) {
      final binding = CanonicalObjectReader(
        value,
        allowedKeys: const {
          'armProjectionSets',
          'kind',
          'label',
          'metricBindingId',
          'metricDefinitionChoice',
        },
        requiredKeys: const {
          'armProjectionSets',
          'kind',
          'label',
          'metricBindingId',
          'metricDefinitionChoice',
        },
        path: itemPath,
      );
      _requireKind(binding, 'experimentDraftMetricBindingChoice');
      final bindingId = _identifier(
        binding.string('metricBindingId'),
        '$itemPath.metricBindingId',
        ExperimentMetricBindingIdV1.new,
      );
      _boundedString(
        binding.string('label'),
        '$itemPath.label',
        allowEmpty: true,
      );
      _validateMutationSelection(
        binding.object('metricDefinitionChoice'),
        '$itemPath.metricDefinitionChoice',
        (value, definitionPath) =>
            ExperimentExactMetricDefinitionReferenceV1.fromJson(
          value,
          path: definitionPath,
        ),
      );
      final projectionSets = _objectList(
        binding.list('armProjectionSets'),
        path: '$itemPath.armProjectionSets',
        maximumLength: _maximumArms,
        decode: (projectionSet, projectionSetPath) {
          final setReader = CanonicalObjectReader(
            projectionSet,
            allowedKeys: const {
              'installedProjectionSetChoice',
              'kind',
              'stableArmId',
            },
            requiredKeys: const {
              'installedProjectionSetChoice',
              'kind',
              'stableArmId',
            },
            path: projectionSetPath,
          );
          _requireKind(
            setReader,
            'experimentDraftArmProjectionSetChoice',
          );
          final armId = _identifier(
            setReader.string('stableArmId'),
            '$projectionSetPath.stableArmId',
            ExperimentStableArmIdV1.new,
          );
          _validateInstalledProjectionSetMutationSelection(
            setReader.object('installedProjectionSetChoice'),
            '$projectionSetPath.installedProjectionSetChoice',
          );
          return armId.value;
        },
      );
      _requireUnique(
        projectionSets,
        '$itemPath.armProjectionSets.stableArmId',
      );
      return bindingId.value;
    },
  );
  _requireUnique(bindings, '$path.metricBindings.metricBindingId');
  _identifierList(
    reader.list('diagnosticBindingIds'),
    path: '$path.diagnosticBindingIds',
    maximumLength: _maximumRelatedValues,
    build: ExperimentMetricBindingIdV1.new,
  );
  _identifierList(
    reader.list('layerHoldoutIds'),
    path: '$path.layerHoldoutIds',
    maximumLength: _maximumRelatedValues,
    build: AuthorityRevisionId.new,
  );
  _objectList(
    reader.list('guardrails'),
    path: '$path.guardrails',
    maximumLength: _maximumRelatedValues,
    decode: (value, itemPath) =>
        ExperimentDraftGuardrailChoiceV1.fromJson(value, path: itemPath),
  );
  _objectList(
    reader.list('memberHoldouts'),
    path: '$path.memberHoldouts',
    maximumLength: _maximumRelatedValues,
    decode: (value, itemPath) {
      final holdout = CanonicalObjectReader(
        value,
        allowedKeys: const {
          'candidateSelection',
          'holdoutId',
          'kind',
          'label',
        },
        requiredKeys: const {
          'candidateSelection',
          'holdoutId',
          'kind',
          'label',
        },
        path: itemPath,
      );
      _requireKind(holdout, 'experimentDraftMemberHoldoutChoice');
      _identifier(
        holdout.string('holdoutId'),
        '$itemPath.holdoutId',
        AuthorityRevisionId.new,
      );
      _boundedString(
        holdout.string('label'),
        '$itemPath.label',
        allowEmpty: true,
      );
      _validateMutationSelection(
        holdout.object('candidateSelection'),
        '$itemPath.candidateSelection',
        (candidate, candidatePath) => ExperimentExactCandidateV1.fromJson(
          candidate,
          path: candidatePath,
        ),
      );
      return holdout.string('holdoutId');
    },
  );
  _validateMutationDirectionalDomain(json, analysis, path);
}

void _validateMutationDirectionalDomain(
  Map<String, Object?> choices,
  Map<String, Object?> analysis,
  String path,
) {
  if (_readDiscriminator(analysis, '$path.analysisSelection') !=
      'fixedHorizonNArmRate') {
    return;
  }
  final planning = analysis['planningSelection']! as Map<String, Object?>;
  final bindingsById = <String, Map<String, Object?>>{
    for (final value in choices['metricBindings']! as List<Object?>)
      (value! as Map<String, Object?>)['metricBindingId']! as String:
          value as Map<String, Object?>,
  };

  ExperimentMetricDirectionV1? metricDirection(String bindingId) {
    final selection = bindingsById[bindingId]?['metricDefinitionChoice'];
    if (selection is! Map<String, Object?> || selection['kind'] != 'exactRef') {
      return null;
    }
    final exactRef = selection['exactRef'];
    if (exactRef is! Map<String, Object?>) return null;
    return ExperimentExactMetricDefinitionReferenceV1.fromJson(
      exactRef,
      path: '$path.metricBindings.metricDefinitionChoice.exactRef',
    ).direction;
  }

  final primarySelection = choices['primaryBindingSelection'];
  if (primarySelection is Map<String, Object?> &&
      primarySelection['kind'] == 'exactRef') {
    final primaryReference = primarySelection['exactRef'];
    final primaryBindingId = primaryReference is Map<String, Object?>
        ? primaryReference['metricBindingId']
        : null;
    final metric =
        primaryBindingId is String ? metricDirection(primaryBindingId) : null;
    if (metric != null) {
      final direction = switch (metric) {
        ExperimentMetricDirectionV1.higherIsBetter =>
          ExperimentRateDirectionV1.higherIsBetter,
        ExperimentMetricDirectionV1.lowerIsBetter =>
          ExperimentRateDirectionV1.lowerIsBetter,
        ExperimentMetricDirectionV1.none => throw CanonicalFormatException(
            '$path primary metric has no fixed-horizon direction',
          ),
      };
      _requireDirectionalEffectDomain(
        baseline: ExperimentRationalV1.fromJson(
          planning['expectedBaseline']! as Map<String, Object?>,
          path: '$path.analysisSelection.planningSelection.expectedBaseline',
        ),
        effect: ExperimentRationalV1.fromJson(
          planning['minimumDetectableEffect']! as Map<String, Object?>,
          path:
              '$path.analysisSelection.planningSelection.minimumDetectableEffect',
        ),
        direction: direction,
        path: '$path.analysisSelection.planningSelection',
      );
    }
  }

  final plannedGuardrails = <String, Map<String, Object?>>{
    for (final value in planning['guardrails']! as List<Object?>)
      (value! as Map<String, Object?>)['guardrailId']! as String:
          value as Map<String, Object?>,
  };
  for (final value in choices['guardrails']! as List<Object?>) {
    final role = value! as Map<String, Object?>;
    final planned = plannedGuardrails[role['guardrailId']];
    final metric = metricDirection(role['metricBindingId']! as String);
    if (planned == null || metric == null) continue;
    final adverseDirection = switch (metric) {
      ExperimentMetricDirectionV1.higherIsBetter =>
        ExperimentAdverseDirectionV1.lowerIsWorse,
      ExperimentMetricDirectionV1.lowerIsBetter =>
        ExperimentAdverseDirectionV1.higherIsWorse,
      ExperimentMetricDirectionV1.none => throw CanonicalFormatException(
          '$path guardrail metric has no fixed-horizon direction',
        ),
    };
    _requireGuardrailDomain(
      expectedReferenceRate: ExperimentRationalV1.fromJson(
        planned['expectedReferenceRate']! as Map<String, Object?>,
        path:
            '$path.analysisSelection.planningSelection.guardrails.expectedReferenceRate',
      ),
      harmMargin: ExperimentRationalV1.fromJson(
        planned['harmMargin']! as Map<String, Object?>,
        path: '$path.analysisSelection.planningSelection.guardrails.harmMargin',
      ),
      adverseDirection: adverseDirection,
      path: '$path.analysisSelection.planningSelection.guardrails',
    );
  }
}

void _validateMutationSelection<T extends CanonicalValue>(
  Map<String, Object?> json,
  String path,
  T Function(Map<String, Object?> json, String path) decodeExactRef, {
  bool allowServerDefault = true,
}) {
  final kind = _readDiscriminator(json, path);
  final keys = kind == 'exactRef' ? const {'exactRef', 'kind'} : const {'kind'};
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: keys,
    requiredKeys: keys,
    path: path,
  );
  if (kind != 'unselected' &&
      (kind != 'serverDefault' || !allowServerDefault) &&
      kind != 'exactRef') {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
  if (kind == 'exactRef') {
    decodeExactRef(reader.object('exactRef'), '$path.exactRef');
  }
}

void _validateInstalledProjectionSetMutationSelection(
  Map<String, Object?> json,
  String path,
) {
  final kind = _readDiscriminator(json, path);
  if (kind == 'unselected') {
    CanonicalObjectReader(
      json,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: path,
    );
    return;
  }
  if (kind != 'exactRef') {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'exactRef', 'kind'},
    requiredKeys: const {'exactRef', 'kind'},
    path: path,
  );
  ExperimentInstalledProjectionSetCapabilityV1.fromJson(
    reader.object('exactRef'),
    path: '$path.exactRef',
  );
}

void _validateRandomizedUnitMutationSelection(
  Map<String, Object?> json,
  String path,
) {
  final kind = _readDiscriminator(json, path);
  final keys = switch (kind) {
    'serverDefault' => const {'kind'},
    'explicitValue' => const {'kind', 'value'},
    _ => throw CanonicalFormatException('$path.kind "$kind" is unsupported'),
  };
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: keys,
    requiredKeys: keys,
    path: path,
  );
  if (kind == 'explicitValue') {
    ExperimentRandomizedUnitKindV1._fromWire(
      reader.string('value'),
      '$path.value',
    );
  }
}

void _validateMutationSubjectSelection(
  Map<String, Object?> json,
  String path,
) {
  final kind = _readDiscriminator(json, path);
  if (kind == 'subjectless') {
    CanonicalObjectReader(
      json,
      allowedKeys: const {'kind'},
      requiredKeys: const {'kind'},
      path: path,
    );
    return;
  }
  if (kind != 'exactSubjectRef') {
    throw CanonicalFormatException('$path.kind "$kind" is unsupported');
  }
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'exactRef', 'kind'},
    requiredKeys: const {'exactRef', 'kind'},
    path: path,
  );
  ExperimentExactPolicyReferenceV1.fromJson(
    reader.object('exactRef'),
    path: '$path.exactRef',
  );
}

void _validateDraftBindingFields(CanonicalObjectReader reader, String path) {
  _identifier(
    reader.string('draftId'),
    '$path.draftId',
    ExperimentDraftIdV1.new,
  );
  _identifier(
    reader.string('draftRevisionId'),
    '$path.draftRevisionId',
    ExperimentDraftRevisionIdV1.new,
  );
  _boundedString(reader.string('expectedCas'), '$path.expectedCas');
}

void _validateExperimentSelector(CanonicalObjectReader reader, String path) {
  _identifier(
    reader.string('experimentId'),
    '$path.experimentId',
    ExperimentPublicIdV1.new,
  );
  _positiveInteger(
    reader.integer('activationOrdinal'),
    '$path.activationOrdinal',
  );
}

T _enumFromWire<T>(
  Iterable<T> values,
  String value,
  String path,
  String Function(T value) wireName,
) {
  for (final entry in values) {
    if (wireName(entry) == value) return entry;
  }
  throw CanonicalFormatException('$path "$value" is unsupported');
}

void _requireKind(CanonicalObjectReader reader, String expected) {
  final actual = reader.string('kind');
  if (actual != expected) {
    throw CanonicalFormatException(
      '${reader.path}.kind "$actual" is not "$expected"',
    );
  }
}

void _validateVersionAndKind(
  CanonicalObjectReader reader,
  String expectedKind,
) {
  final version = reader.integer('schemaVersion');
  if (version != kMeasurementSchemaVersion) {
    throw CanonicalFormatException(
      '${reader.path}.schemaVersion $version is unsupported',
    );
  }
  _requireKind(reader, expectedKind);
}

String _readDiscriminator(Map<String, Object?> json, String path) =>
    requireCanonicalString(json['kind'], '$path.kind');

String _boundedString(
  String value,
  String path, {
  bool allowEmpty = false,
}) {
  try {
    CanonicalJsonCodec.encode(value);
  } on CanonicalFormatException {
    throw CanonicalFormatException('$path must contain well-formed Unicode');
  }
  final length = utf8.encode(value).length;
  if ((!allowEmpty && length == 0) || length > _maximumTextBytes) {
    throw CanonicalFormatException(
      '$path must contain ${allowEmpty ? '0' : '1'}..$_maximumTextBytes UTF-8 bytes',
    );
  }
  return value;
}

T _identifier<T>(
  String value,
  String path,
  T Function(String value) build,
) {
  try {
    return build(value);
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

T _positiveIdentifier<T>(
  int value,
  String path,
  T Function(int value) build,
) {
  try {
    return build(value);
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

/// Parses a stored hex digest, naming the field when it is malformed.
CanonicalDigest _parsedDigest(String value, String path) {
  try {
    return CanonicalDigest(value);
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

int _positiveInteger(int value, String path) {
  if (value <= 0 || value > kMaximumPortableJsonInteger) {
    throw CanonicalFormatException('$path must be a positive portable integer');
  }
  return value;
}

int _boundedRelativeWeight(int value, String path) {
  if (value < 1 || value > 100) {
    throw CanonicalFormatException('$path must be 1..100');
  }
  return value;
}

int _nonNegativeInteger(int value, String path) {
  if (value < 0) {
    throw CanonicalFormatException('$path must be non-negative');
  }
  return value;
}

void _requireProbability(ExperimentRationalV1 value, String path) {
  if (value.numerator < 0 || value.numerator > value.denominator) {
    throw CanonicalFormatException('$path must be within zero and one');
  }
}

void _requireOpenProbability(ExperimentRationalV1 value, String path) {
  if (value.numerator <= 0 || value.numerator >= value.denominator) {
    throw CanonicalFormatException(
      '$path must be strictly between zero and one',
    );
  }
}

void _requireSupportedAlpha(ExperimentRationalV1 value, String path) {
  if (!_isExactRational(value, 1, 20) && !_isExactRational(value, 1, 100)) {
    throw CanonicalFormatException('$path must be 1/20 or 1/100');
  }
}

void _requireSupportedPower(ExperimentRationalV1 value, String path) {
  _requireOpenProbability(value, path);
  if (value.numerator * 5 < value.denominator * 4) {
    throw CanonicalFormatException('$path must be at least 4/5');
  }
}

void _requireDirectionalEffectDomain({
  required ExperimentRationalV1 baseline,
  required ExperimentRationalV1 effect,
  required ExperimentRateDirectionV1 direction,
  required String path,
}) {
  final valid = switch (direction) {
    ExperimentRateDirectionV1.higherIsBetter =>
      baseline.numerator * effect.denominator +
              effect.numerator * baseline.denominator <
          baseline.denominator * effect.denominator,
    ExperimentRateDirectionV1.lowerIsBetter =>
      baseline.numerator * effect.denominator >
          effect.numerator * baseline.denominator,
  };
  if (!valid) {
    throw CanonicalFormatException(
      '$path expected baseline and effect leave the probability domain',
    );
  }
}

void _requireStrictlyLess(
  ExperimentRationalV1 left,
  ExperimentRationalV1 right,
  String path,
) {
  if (left.numerator * right.denominator >=
      right.numerator * left.denominator) {
    throw CanonicalFormatException('$path must be below the planned effect');
  }
}

void _requireSumBelowOne(
  ExperimentRationalV1 left,
  ExperimentRationalV1 right,
  String path,
) {
  if (left.numerator * right.denominator + right.numerator * left.denominator >=
      left.denominator * right.denominator) {
    throw CanonicalFormatException('$path must remain below one');
  }
}

void _requireGuardrailDomain({
  required ExperimentRationalV1 expectedReferenceRate,
  required ExperimentRationalV1 harmMargin,
  required ExperimentAdverseDirectionV1 adverseDirection,
  required String path,
}) {
  switch (adverseDirection) {
    case ExperimentAdverseDirectionV1.higherIsWorse:
      _requireSumBelowOne(expectedReferenceRate, harmMargin, path);
    case ExperimentAdverseDirectionV1.lowerIsWorse:
      _requireStrictlyLess(harmMargin, expectedReferenceRate, path);
  }
}

void _requirePositiveFraction(ExperimentRationalV1 value, String path) {
  if (value.numerator <= 0 || value.numerator >= value.denominator) {
    throw CanonicalFormatException(
      '$path must be a positive fraction below one',
    );
  }
}

bool _isExactRational(
  ExperimentRationalV1 value,
  int numerator,
  int denominator,
) =>
    value.numerator == numerator && value.denominator == denominator;

bool _sameRational(
  ExperimentRationalV1 left,
  ExperimentRationalV1 right,
) =>
    left.numerator == right.numerator && left.denominator == right.denominator;

List<T> _objectList<T>(
  List<Object?> values, {
  required String path,
  required int? maximumLength,
  int minimumLength = 0,
  required T Function(Map<String, Object?> value, String path) decode,
}) {
  if (values.length < minimumLength ||
      (maximumLength != null && values.length > maximumLength)) {
    throw CanonicalFormatException(
      maximumLength == null
          ? '$path must contain at least $minimumLength entries'
          : '$path must contain $minimumLength..$maximumLength entries',
    );
  }
  return List<T>.unmodifiable([
    for (var index = 0; index < values.length; index++)
      decode(
        requireCanonicalObject(values[index], '$path[$index]'),
        '$path[$index]',
      ),
  ]);
}

List<T> _identifierList<T>(
  List<Object?> values, {
  required String path,
  required int maximumLength,
  int minimumLength = 0,
  required T Function(String value) build,
}) {
  if (values.length < minimumLength || values.length > maximumLength) {
    throw CanonicalFormatException(
      '$path must contain $minimumLength..$maximumLength entries',
    );
  }
  final result = List<T>.unmodifiable([
    for (var index = 0; index < values.length; index++)
      _identifier(
        requireCanonicalString(values[index], '$path[$index]'),
        '$path[$index]',
        build,
      ),
  ]);
  _requireUnique(
    values.map((value) => requireCanonicalString(value, '$path[]')),
    path,
  );
  return result;
}

List<T> _enumList<T>(
  List<Object?> values, {
  required String path,
  required int maximumLength,
  required T Function(String value, String path) decode,
}) {
  if (values.length > maximumLength) {
    throw CanonicalFormatException(
      '$path must contain at most $maximumLength entries',
    );
  }
  final result = List<T>.unmodifiable([
    for (var index = 0; index < values.length; index++)
      decode(
        requireCanonicalString(values[index], '$path[$index]'),
        '$path[$index]',
      ),
  ]);
  if (result.toSet().length != result.length) {
    throw CanonicalFormatException('$path contains duplicate entries');
  }
  return result;
}

List<String> _stringList(
  List<Object?> values, {
  required String path,
  required int maximumLength,
}) {
  if (values.length > maximumLength) {
    throw CanonicalFormatException(
      '$path must contain at most $maximumLength entries',
    );
  }
  final result = List<String>.unmodifiable([
    for (var index = 0; index < values.length; index++)
      _boundedString(
        requireCanonicalString(values[index], '$path[$index]'),
        '$path[$index]',
      ),
  ]);
  _requireUnique(result, path);
  return result;
}

void _requireUnique(Iterable<String> values, String path) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw CanonicalFormatException('$path contains duplicate "$value"');
    }
  }
}

void _requireCanonicalOrder(Iterable<String> values, String path) {
  String? previous;
  for (final value in values) {
    if (previous != null && previous.compareTo(value) >= 0) {
      throw CanonicalFormatException('$path must be in canonical order');
    }
    previous = value;
  }
}

bool _sameCanonicalValueLists(
  Iterable<CanonicalValue> left,
  Iterable<CanonicalValue> right,
) {
  final leftValues = left.toList(growable: false);
  final rightValues = right.toList(growable: false);
  if (leftValues.length != rightValues.length) return false;
  for (var index = 0; index < leftValues.length; index++) {
    final leftBytes = leftValues[index].canonicalBytes;
    final rightBytes = rightValues[index].canonicalBytes;
    if (leftBytes.length != rightBytes.length) return false;
    for (var byteIndex = 0; byteIndex < leftBytes.length; byteIndex++) {
      if (leftBytes[byteIndex] != rightBytes[byteIndex]) return false;
    }
  }
  return true;
}

Map<String, int> _positiveIntegerMap(
  Map<String, Object?> json, {
  required String path,
  required int maximumLength,
}) {
  if (json.isEmpty || json.length > maximumLength) {
    throw CanonicalFormatException(
      '$path must contain 1..$maximumLength entries',
    );
  }
  final result = <String, int>{};
  for (final entry in json.entries) {
    _identifier(entry.key, '$path.${entry.key}', ExperimentStableArmIdV1.new);
    final value = entry.value;
    if (value is! int) {
      throw CanonicalFormatException('$path.${entry.key} must be an integer');
    }
    result[entry.key] = _positiveInteger(
      value,
      '$path.${entry.key}',
    );
  }
  return UnmodifiableMapView(result);
}

Map<String, String> _certifiedScales(
  Map<String, Object?> json,
  String path,
) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: const {'allocationScale', 'effectScale'},
    requiredKeys: const {'allocationScale', 'effectScale'},
    path: path,
  );
  final result = <String, String>{};
  for (final key in ['allocationScale', 'effectScale']) {
    final value = reader.string(key);
    if (!RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(value)) {
      throw CanonicalFormatException('$path.$key must be a positive decimal');
    }
    result[key] = value;
  }
  return UnmodifiableMapView(result);
}

void _checkByteLimit(List<int> bytes, int maximum, String path) {
  if (bytes.length > maximum) {
    throw CanonicalFormatException('$path exceeds $maximum canonical bytes');
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    UnmodifiableMapView<String, Object?>(
      <String, Object?>{
        for (final entry in value.entries) entry.key: _freezeJson(entry.value),
      },
    );

Object? _freezeJson(Object? value) {
  if (value == null || value is bool || value is int || value is String) {
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value is Map<String, Object?>) return _freezeMap(value);
  throw CanonicalFormatException(
    'Unsupported public JSON value type ${value.runtimeType}',
  );
}
