import 'dart:typed_data';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/manifest.dart';
import 'package:restage_measurement_schema/src/publication_binding.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// An inert, exact publication collection decision from an authenticated read.
final class MeasurementCollectionDecisionV1 {
  /// Creates a finite grant shared within one SDK configuration generation.
  MeasurementCollectionDecisionV1({
    required this.bindingReference,
    required this.target,
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.measurementManifestHash,
    required this.privacyPolicyRevisionId,
    required this.privacyPolicySemanticHash,
    required this.collectionBudgetRevisionId,
    required this.collectionBudgetSemanticHash,
    required this.privacyClassificationRevisionId,
    required this.privacyClassificationSemanticHash,
    required this.sessionAdmissionLimit,
  }) {
    final admittedPolicyPair = switch ((
      privacyPolicyRevisionId.value,
      collectionBudgetRevisionId.value,
    )) {
      ('restage.manifest-privacy.v1', 'restage.collection-budget.v2') ||
      ('restage.manifest-privacy.v2', 'restage.collection-budget.v3') =>
        true,
      _ => false,
    };
    if (!admittedPolicyPair ||
        privacyClassificationRevisionId.value !=
            'restage.privacy-classification.v1') {
      throw const CanonicalFormatException(
        'Unsupported collection policy revision',
      );
    }
    if (sessionAdmissionLimit <= 0 || sessionAdmissionLimit > 1000) {
      throw const CanonicalFormatException(
        'Unsupported session admission limit',
      );
    }
  }

  /// Decodes the closed supported decision version and canonical encoding.
  factory MeasurementCollectionDecisionV1.fromCanonicalBytes(List<int> bytes) {
    if (bytes.length > 16384) {
      throw const CanonicalFormatException('Collection decision is too large');
    }
    final reader = CanonicalObjectReader(
      decodeCanonicalObject(bytes),
      allowedKeys: _keys,
      requiredKeys: _keys,
      path: 'measurementCollectionDecision',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementCollectionDecision',
    );
    if (reader.integer('decisionVersion') != 1 ||
        reader.string('admittedCollectionClass') != 'tier2Coalesced' ||
        reader.string('budgetScope') !=
            'exactPublicationContextPerSdkConfigurationGeneration' ||
        reader.string('pointPrivacy') != 'manifestDeclaredOnly' ||
        reader.string('privacyClassification') != 'subjectless') {
      throw const CanonicalFormatException('Unsupported collection decision');
    }
    return MeasurementCollectionDecisionV1(
      bindingReference: MeasurementPublicationBindingReferenceV1.fromJson(
        reader.object('bindingReference'),
      ),
      target: TargetCoordinate.fromJson(reader.object('target')),
      surfaceRevisionId: SurfaceRevisionId(reader.string('surfaceRevisionId')),
      artifactGraphHash: CanonicalDigest(reader.string('artifactGraphHash')),
      measurementManifestHash:
          CanonicalDigest(reader.string('measurementManifestHash')),
      privacyPolicyRevisionId:
          AuthorityRevisionId(reader.string('privacyPolicyRevisionId')),
      privacyPolicySemanticHash:
          CanonicalDigest(reader.string('privacyPolicySemanticHash')),
      collectionBudgetRevisionId:
          AuthorityRevisionId(reader.string('collectionBudgetRevisionId')),
      collectionBudgetSemanticHash:
          CanonicalDigest(reader.string('collectionBudgetSemanticHash')),
      privacyClassificationRevisionId:
          AuthorityRevisionId(reader.string('privacyClassificationRevisionId')),
      privacyClassificationSemanticHash:
          CanonicalDigest(reader.string('privacyClassificationSemanticHash')),
      sessionAdmissionLimit: reader.integer('sessionAdmissionLimit'),
    );
  }

  static const _keys = {
    'kind',
    'schemaVersion',
    'decisionVersion',
    'bindingReference',
    'target',
    'surfaceRevisionId',
    'artifactGraphHash',
    'measurementManifestHash',
    'privacyPolicyRevisionId',
    'privacyPolicySemanticHash',
    'collectionBudgetRevisionId',
    'collectionBudgetSemanticHash',
    'privacyClassificationRevisionId',
    'privacyClassificationSemanticHash',
    'admittedCollectionClass',
    'sessionAdmissionLimit',
    'budgetScope',
    'pointPrivacy',
    'privacyClassification',
  };

  /// Exact immutable binding selected by the mounted publication.
  final MeasurementPublicationBindingReferenceV1 bindingReference;

  /// Authenticated target that owns the publication and policies.
  final TargetCoordinate target;

  /// Exact immutable surface revision.
  final SurfaceRevisionId surfaceRevisionId;

  /// Digest of the exact published artifact graph.
  final CanonicalDigest artifactGraphHash;

  /// Digest of the complete immutable measurement manifest.
  final CanonicalDigest measurementManifestHash;

  /// Supported manifest privacy policy revision.
  final AuthorityRevisionId privacyPolicyRevisionId;

  /// Semantic digest of the admitted manifest privacy policy.
  final CanonicalDigest privacyPolicySemanticHash;

  /// Supported finite collection budget revision.
  final AuthorityRevisionId collectionBudgetRevisionId;

  /// Semantic digest of the admitted budget policy.
  final CanonicalDigest collectionBudgetSemanticHash;

  /// Supported subjectless classification revision.
  final AuthorityRevisionId privacyClassificationRevisionId;

  /// Semantic digest of the admitted classification policy.
  final CanonicalDigest privacyClassificationSemanticHash;

  /// Total admissions; repeated reads do not replenish the local shared ledger.
  final int sessionAdmissionLimit;

  /// The only collection class admitted by this decision version.
  MeasurementCollectionClass get admittedCollectionClass =>
      MeasurementCollectionClass.tier2Coalesced;

  /// Scope of the shared, monotonically tightening session ledger.
  String get budgetScope =>
      'exactPublicationContextPerSdkConfigurationGeneration';

  /// Requires each captured point to retain its manifest privacy declaration.
  String get pointPrivacy => 'manifestDeclaredOnly';

  /// The admitted identity treatment.
  String get privacyClassification => 'subjectless';

  /// Whether every publication and manifest policy coordinate agrees.
  bool matchesBinding(MeasurementPublicationBindingV1 binding) {
    final manifest = binding.completeMeasurementManifest;
    return bindingReference == binding.reference &&
        target == manifest.target &&
        surfaceRevisionId == manifest.surfaceRevisionId &&
        artifactGraphHash == manifest.artifactGraphHash &&
        measurementManifestHash == manifest.canonicalDigest &&
        privacyPolicyRevisionId == manifest.privacyPolicyRevisionId &&
        collectionBudgetRevisionId == manifest.collectionBudgetRevisionId;
  }

  /// Exact canonical decision bytes, returned as a fresh allocation.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// The closed canonical decision object.
  Map<String, Object?> toJson() => {
        'kind': 'measurementCollectionDecision',
        'schemaVersion': kMeasurementSchemaVersion,
        'decisionVersion': 1,
        'bindingReference': bindingReference.toJson(),
        'target': target.toJson(),
        'surfaceRevisionId': surfaceRevisionId.value,
        'artifactGraphHash': artifactGraphHash.hex,
        'measurementManifestHash': measurementManifestHash.hex,
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
        'privacyPolicySemanticHash': privacyPolicySemanticHash.hex,
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'collectionBudgetSemanticHash': collectionBudgetSemanticHash.hex,
        'privacyClassificationRevisionId':
            privacyClassificationRevisionId.value,
        'privacyClassificationSemanticHash':
            privacyClassificationSemanticHash.hex,
        'admittedCollectionClass': admittedCollectionClass.wireName,
        'sessionAdmissionLimit': sessionAdmissionLimit,
        'budgetScope': budgetScope,
        'pointPrivacy': pointPrivacy,
        'privacyClassification': privacyClassification,
      };
}
