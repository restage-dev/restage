import 'dart:collection';

import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// Maximum number of direct-parent entries in one canonical ancestry index.
const int kMaximumCanonicalNodeParentEdges = 65536;

/// Capability represented by one measurement point.
enum MeasurementCapabilityKind {
  /// Synthetic presentation capability for a canonical node.
  presented('presented'),

  /// Exact source callback capability.
  sourceInteraction('sourceInteraction');

  const MeasurementCapabilityKind(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Optional catalog-proven interaction meaning.
enum NormalizedInteractionKind {
  activate('activate'),
  dismiss('dismiss'),
  select('select'),
  submit('submit'),
  change('change');

  const NormalizedInteractionKind(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Privacy classification inherited by a measurement capability.
enum MeasurementPrivacyClass {
  nonSensitive('nonSensitive'),
  sensitive('sensitive'),
  prohibited('prohibited');

  const MeasurementPrivacyClass(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Whether a point carries no value, activity only, or a reviewed value.
enum SemanticValueClass {
  none('none'),
  activityOnly('activityOnly'),
  explicitReviewedValue('explicitReviewedValue');

  const SemanticValueClass(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Collection treatment for an admitted capability.
enum MeasurementCollectionClass {
  tier1KeepAll('tier1KeepAll'),
  tier2Coalesced('tier2Coalesced'),
  prohibited('prohibited');

  const MeasurementCollectionClass(this.wireName);

  /// Stable canonical-wire spelling.
  final String wireName;
}

/// Frozen identity-only preimage for one exact point occurrence.
///
/// Target, lineage, display metadata, normalization, privacy, semantic-value,
/// and collection metadata deliberately do not participate in this value.
final class MeasurementPointOccurrenceIdentityV1 extends CanonicalDocument {
  /// Creates the identity preimage frozen by the measurement architecture.
  MeasurementPointOccurrenceIdentityV1({
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.artifactId,
    required this.artifactOccurrenceEdgeToken,
    required this.artifactContentHash,
    required this.canonicalNodeToken,
    required this.capabilityKind,
    this.sourceEventIdentity,
  }) {
    final isSource =
        capabilityKind == MeasurementCapabilityKind.sourceInteraction;
    if (isSource != (sourceEventIdentity != null)) {
      throw ArgumentError(
        'A source interaction requires one exact source event; a presentation '
        'uses the synthetic presented slot',
      );
    }
  }

  /// Decodes byte-exact canonical point-occurrence identity JSON.
  factory MeasurementPointOccurrenceIdentityV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPointOccurrenceIdentityV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPointOccurrenceIdentity',
      );

  /// Decodes a strict nested point-occurrence identity object.
  factory MeasurementPointOccurrenceIdentityV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactContentHash',
        'artifactGraphHash',
        'artifactId',
        'artifactOccurrenceEdgeToken',
        'canonicalNodeToken',
        'kind',
        'schemaVersion',
        'slot',
        'surfaceRevisionId',
      },
      requiredKeys: const {
        'artifactContentHash',
        'artifactGraphHash',
        'artifactId',
        'artifactOccurrenceEdgeToken',
        'canonicalNodeToken',
        'kind',
        'schemaVersion',
        'slot',
        'surfaceRevisionId',
      },
      path: 'measurementPointOccurrenceIdentity',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPointOccurrenceIdentity',
    );
    final slot = reader.object('slot');
    final slotKind = requireCanonicalString(
      slot['kind'],
      'measurementPointOccurrenceIdentity.slot.kind',
    );
    late final MeasurementCapabilityKind capabilityKind;
    SourceEventIdentity? sourceEventIdentity;
    switch (slotKind) {
      case 'presented':
        CanonicalObjectReader(
          slot,
          allowedKeys: const {'kind'},
          requiredKeys: const {'kind'},
          path: 'measurementPointOccurrenceIdentity.slot',
        );
        capabilityKind = MeasurementCapabilityKind.presented;
      case 'sourceEvent':
        final slotReader = CanonicalObjectReader(
          slot,
          allowedKeys: const {'kind', 'sourceEventIdentity'},
          requiredKeys: const {'kind', 'sourceEventIdentity'},
          path: 'measurementPointOccurrenceIdentity.slot',
        );
        capabilityKind = MeasurementCapabilityKind.sourceInteraction;
        sourceEventIdentity = SourceEventIdentity(
          slotReader.string('sourceEventIdentity'),
        );
      default:
        throw CanonicalFormatException(
          'Unknown point occurrence slot kind "$slotKind"',
        );
    }
    return _constructManifest(
      'measurementPointOccurrenceIdentity',
      () => MeasurementPointOccurrenceIdentityV1(
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        artifactGraphHash: CanonicalDigest(
          reader.string('artifactGraphHash'),
        ),
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
        artifactContentHash: CanonicalDigest(
          reader.string('artifactContentHash'),
        ),
        canonicalNodeToken: NodeTokenId(
          reader.string('canonicalNodeToken'),
        ),
        capabilityKind: capabilityKind,
        sourceEventIdentity: sourceEventIdentity,
      ),
    );
  }

  final SurfaceRevisionId surfaceRevisionId;
  final CanonicalDigest artifactGraphHash;
  final ArtifactId artifactId;
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;
  final CanonicalDigest artifactContentHash;
  final NodeTokenId canonicalNodeToken;
  final MeasurementCapabilityKind capabilityKind;
  final SourceEventIdentity? sourceEventIdentity;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.pointOccurrence;

  @override
  Map<String, Object?> toJson() => {
        'artifactContentHash': artifactContentHash.hex,
        'artifactGraphHash': artifactGraphHash.hex,
        'artifactId': artifactId.value,
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'canonicalNodeToken': canonicalNodeToken.value,
        'kind': 'measurementPointOccurrenceIdentity',
        'schemaVersion': kMeasurementSchemaVersion,
        'slot': capabilityKind == MeasurementCapabilityKind.presented
            ? <String, Object?>{'kind': 'presented'}
            : <String, Object?>{
                'kind': 'sourceEvent',
                'sourceEventIdentity': sourceEventIdentity!.value,
              },
        'surfaceRevisionId': surfaceRevisionId.value,
      };
}

/// Full manifest record for one point occurrence and its non-identity metadata.
final class MeasurementPointOccurrenceV1 extends CanonicalValue {
  /// Creates one immutable occurrence record.
  MeasurementPointOccurrenceV1({
    required this.target,
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.artifactId,
    required this.artifactOccurrenceEdgeToken,
    required this.artifactContentHash,
    required this.canonicalNodeToken,
    required this.capabilityKind,
    this.sourceEventIdentity,
    this.normalizedInteractionKind,
    required this.privacyClass,
    required this.semanticValueClass,
    required this.collectionClass,
    required this.lineageId,
    required this.displayMetadataRef,
  }) : identity = MeasurementPointOccurrenceIdentityV1(
          surfaceRevisionId: surfaceRevisionId,
          artifactGraphHash: artifactGraphHash,
          artifactId: artifactId,
          artifactOccurrenceEdgeToken: artifactOccurrenceEdgeToken,
          artifactContentHash: artifactContentHash,
          canonicalNodeToken: canonicalNodeToken,
          capabilityKind: capabilityKind,
          sourceEventIdentity: sourceEventIdentity,
        ) {
    if (capabilityKind == MeasurementCapabilityKind.presented &&
        normalizedInteractionKind != null) {
      throw ArgumentError(
        'A synthetic presentation cannot declare normalized interaction '
        'metadata',
      );
    }
    if (capabilityKind == MeasurementCapabilityKind.presented &&
        semanticValueClass != SemanticValueClass.none) {
      throw ArgumentError(
        'A synthetic presentation has no semantic callback value',
      );
    }
    if (privacyClass == MeasurementPrivacyClass.prohibited &&
        collectionClass != MeasurementCollectionClass.prohibited) {
      throw ArgumentError(
        'A prohibited privacy class requires prohibited collection',
      );
    }
  }

  /// Decodes byte-exact canonical point-occurrence record JSON.
  factory MeasurementPointOccurrenceV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementPointOccurrenceV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementPointOccurrence',
      );

  /// Decodes a strict nested point-occurrence record object.
  factory MeasurementPointOccurrenceV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'collectionClass',
        'displayMetadataRef',
        'identity',
        'kind',
        'lineageId',
        'normalizedInteractionKind',
        'occurrenceId',
        'privacyClass',
        'schemaVersion',
        'semanticValueClass',
        'target',
      },
      requiredKeys: const {
        'collectionClass',
        'displayMetadataRef',
        'identity',
        'kind',
        'lineageId',
        'occurrenceId',
        'privacyClass',
        'schemaVersion',
        'semanticValueClass',
        'target',
      },
      path: 'measurementPointOccurrence',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'measurementPointOccurrence',
    );
    final identity = MeasurementPointOccurrenceIdentityV1.fromJson(
      reader.object('identity'),
    );
    if (reader.string('occurrenceId') != identity.canonicalDigest.hex) {
      throw const CanonicalFormatException(
        'measurementPointOccurrence.occurrenceId does not match identity',
      );
    }
    return _constructManifest(
      'measurementPointOccurrence',
      () => MeasurementPointOccurrenceV1(
        target: TargetCoordinate.fromJson(reader.object('target')),
        surfaceRevisionId: identity.surfaceRevisionId,
        artifactGraphHash: identity.artifactGraphHash,
        artifactId: identity.artifactId,
        artifactOccurrenceEdgeToken: identity.artifactOccurrenceEdgeToken,
        artifactContentHash: identity.artifactContentHash,
        canonicalNodeToken: identity.canonicalNodeToken,
        capabilityKind: identity.capabilityKind,
        sourceEventIdentity: identity.sourceEventIdentity,
        normalizedInteractionKind: switch (
            reader.optionalString('normalizedInteractionKind')) {
          final value? => _normalizedInteractionFromWire(value),
          null => null,
        },
        privacyClass: _privacyClassFromWire(
          reader.string('privacyClass'),
        ),
        semanticValueClass: _semanticValueClassFromWire(
          reader.string('semanticValueClass'),
        ),
        collectionClass: _collectionClassFromWire(
          reader.string('collectionClass'),
        ),
        lineageId: PointLineageId(reader.string('lineageId')),
        displayMetadataRef: DisplayMetadataRef(
          reader.string('displayMetadataRef'),
        ),
      ),
    );
  }

  final TargetCoordinate target;
  final SurfaceRevisionId surfaceRevisionId;
  final CanonicalDigest artifactGraphHash;
  final ArtifactId artifactId;
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;
  final CanonicalDigest artifactContentHash;
  final NodeTokenId canonicalNodeToken;
  final MeasurementCapabilityKind capabilityKind;
  final SourceEventIdentity? sourceEventIdentity;
  final NormalizedInteractionKind? normalizedInteractionKind;
  final MeasurementPrivacyClass privacyClass;
  final SemanticValueClass semanticValueClass;
  final MeasurementCollectionClass collectionClass;
  final PointLineageId lineageId;
  final DisplayMetadataRef displayMetadataRef;

  /// Explicit identity-only preimage for [occurrenceId].
  final MeasurementPointOccurrenceIdentityV1 identity;

  /// Domain-separated ID of [identity], excluding record metadata.
  CanonicalDigest get occurrenceId => identity.canonicalDigest;

  @override
  Map<String, Object?> toJson() => {
        'collectionClass': collectionClass.wireName,
        'displayMetadataRef': displayMetadataRef.value,
        'identity': identity.toJson(),
        'kind': 'measurementPointOccurrence',
        'lineageId': lineageId.value,
        if (normalizedInteractionKind != null)
          'normalizedInteractionKind': normalizedInteractionKind!.wireName,
        'occurrenceId': occurrenceId.hex,
        'privacyClass': privacyClass.wireName,
        'schemaVersion': kMeasurementSchemaVersion,
        'semanticValueClass': semanticValueClass.wireName,
        'target': target.toJson(),
      };
}

/// Generated source-level reference to one exact occurrence and lineage.
final class GeneratedPointReferenceV1 extends CanonicalDocument {
  /// Creates an inert generated-reference contract.
  const GeneratedPointReferenceV1({
    required this.referenceId,
    required this.target,
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.occurrenceId,
    required this.lineageId,
    required this.sourceEventIdentity,
    required this.dartSymbol,
  });

  /// Decodes byte-exact canonical generated-reference JSON.
  factory GeneratedPointReferenceV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        GeneratedPointReferenceV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'generatedPointReference',
      );

  /// Decodes a strict nested generated-reference object.
  factory GeneratedPointReferenceV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactGraphHash',
        'dartSymbol',
        'kind',
        'lineageId',
        'occurrenceId',
        'referenceId',
        'schemaVersion',
        'sourceEventIdentity',
        'surfaceRevisionId',
        'target',
      },
      requiredKeys: const {
        'artifactGraphHash',
        'dartSymbol',
        'kind',
        'lineageId',
        'occurrenceId',
        'referenceId',
        'schemaVersion',
        'sourceEventIdentity',
        'surfaceRevisionId',
        'target',
      },
      path: 'generatedPointReference',
    );
    validateCanonicalDocument(reader, expectedKind: 'generatedPointReference');
    return _constructManifest(
      'generatedPointReference',
      () => GeneratedPointReferenceV1(
        referenceId: GeneratedReferenceId(reader.string('referenceId')),
        target: TargetCoordinate.fromJson(reader.object('target')),
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        artifactGraphHash: CanonicalDigest(
          reader.string('artifactGraphHash'),
        ),
        occurrenceId: CanonicalDigest(reader.string('occurrenceId')),
        lineageId: PointLineageId(reader.string('lineageId')),
        sourceEventIdentity: SourceEventIdentity(
          reader.string('sourceEventIdentity'),
        ),
        dartSymbol: GeneratedDartSymbol(reader.string('dartSymbol')),
      ),
    );
  }

  final GeneratedReferenceId referenceId;
  final TargetCoordinate target;
  final SurfaceRevisionId surfaceRevisionId;
  final CanonicalDigest artifactGraphHash;
  final CanonicalDigest occurrenceId;
  final PointLineageId lineageId;
  final SourceEventIdentity sourceEventIdentity;
  final GeneratedDartSymbol dartSymbol;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.generatedReference;

  @override
  Map<String, Object?> toJson() => {
        'artifactGraphHash': artifactGraphHash.hex,
        'dartSymbol': dartSymbol.value,
        'kind': 'generatedPointReference',
        'lineageId': lineageId.value,
        'occurrenceId': occurrenceId.hex,
        'referenceId': referenceId.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'sourceEventIdentity': sourceEventIdentity.value,
        'surfaceRevisionId': surfaceRevisionId.value,
        'target': target.toJson(),
      };
}

/// Manifest emitted for one immutable local artifact.
final class LocalMeasurementManifestV1 extends CanonicalDocument {
  /// Creates one local manifest and validates its internal identity joins.
  LocalMeasurementManifestV1({
    required this.manifestId,
    required this.target,
    required this.surfaceRevisionId,
    required this.artifactGraphHash,
    required this.artifactId,
    required this.artifactContentHash,
    required List<ArtifactId> childArtifactIds,
    required List<MeasurementPointOccurrenceV1> points,
    required List<GeneratedPointReferenceV1> generatedReferences,
    required this.privacyPolicyRevisionId,
    required this.collectionBudgetRevisionId,
  })  : childArtifactIds = _sortedUniqueIds(
          childArtifactIds,
          label: 'child artifact IDs',
        ),
        points = _sortedUniquePoints(points),
        generatedReferences = _sortedUniqueReferences(generatedReferences) {
    if (this.childArtifactIds.contains(artifactId)) {
      throw ArgumentError('An artifact cannot list itself as a child');
    }
    for (final point in this.points) {
      if (point.target != target ||
          point.surfaceRevisionId != surfaceRevisionId ||
          point.artifactGraphHash != artifactGraphHash ||
          point.artifactId != artifactId ||
          point.artifactContentHash != artifactContentHash) {
        throw ArgumentError(
          'Every point must join the exact local artifact context',
        );
      }
    }
    final pointById = {
      for (final point in this.points) point.occurrenceId.hex: point,
    };
    for (final reference in this.generatedReferences) {
      final point = pointById[reference.occurrenceId.hex];
      if (reference.target != target ||
          reference.surfaceRevisionId != surfaceRevisionId ||
          reference.artifactGraphHash != artifactGraphHash ||
          point == null ||
          point.lineageId != reference.lineageId ||
          point.sourceEventIdentity != reference.sourceEventIdentity) {
        throw ArgumentError(
          'Every generated reference must join an exact source point',
        );
      }
    }
  }

  /// Decodes byte-exact canonical local-manifest JSON.
  factory LocalMeasurementManifestV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        LocalMeasurementManifestV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'localMeasurementManifest',
      );

  /// Decodes a strict nested local-manifest object.
  factory LocalMeasurementManifestV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactContentHash',
        'artifactGraphHash',
        'artifactId',
        'childArtifactIds',
        'collectionBudgetRevisionId',
        'generatedReferences',
        'kind',
        'manifestId',
        'points',
        'privacyPolicyRevisionId',
        'schemaVersion',
        'surfaceRevisionId',
        'target',
      },
      requiredKeys: const {
        'artifactContentHash',
        'artifactGraphHash',
        'artifactId',
        'childArtifactIds',
        'collectionBudgetRevisionId',
        'generatedReferences',
        'kind',
        'manifestId',
        'points',
        'privacyPolicyRevisionId',
        'schemaVersion',
        'surfaceRevisionId',
        'target',
      },
      path: 'localMeasurementManifest',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'localMeasurementManifest',
    );
    return _constructManifest(
      'localMeasurementManifest',
      () => LocalMeasurementManifestV1(
        manifestId: MeasurementManifestId(reader.string('manifestId')),
        target: TargetCoordinate.fromJson(reader.object('target')),
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        artifactGraphHash: CanonicalDigest(
          reader.string('artifactGraphHash'),
        ),
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactContentHash: CanonicalDigest(
          reader.string('artifactContentHash'),
        ),
        childArtifactIds: reader
            .list('childArtifactIds')
            .map(
              (value) => ArtifactId(
                requireCanonicalString(value, 'childArtifactIds[]'),
              ),
            )
            .toList(),
        points: reader
            .list('points')
            .map(
              (value) => MeasurementPointOccurrenceV1.fromJson(
                requireCanonicalObject(value, 'points[]'),
              ),
            )
            .toList(),
        generatedReferences: reader
            .list('generatedReferences')
            .map(
              (value) => GeneratedPointReferenceV1.fromJson(
                requireCanonicalObject(value, 'generatedReferences[]'),
              ),
            )
            .toList(),
        privacyPolicyRevisionId: AuthorityRevisionId(
          reader.string('privacyPolicyRevisionId'),
        ),
        collectionBudgetRevisionId: AuthorityRevisionId(
          reader.string('collectionBudgetRevisionId'),
        ),
      ),
    );
  }

  final MeasurementManifestId manifestId;
  final TargetCoordinate target;
  final SurfaceRevisionId surfaceRevisionId;
  final CanonicalDigest artifactGraphHash;
  final ArtifactId artifactId;
  final CanonicalDigest artifactContentHash;
  final List<ArtifactId> childArtifactIds;
  final List<MeasurementPointOccurrenceV1> points;
  final List<GeneratedPointReferenceV1> generatedReferences;
  final AuthorityRevisionId privacyPolicyRevisionId;
  final AuthorityRevisionId collectionBudgetRevisionId;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.localManifest;

  @override
  Map<String, Object?> toJson() => {
        'artifactContentHash': artifactContentHash.hex,
        'artifactGraphHash': artifactGraphHash.hex,
        'artifactId': artifactId.value,
        'childArtifactIds': [for (final child in childArtifactIds) child.value],
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'generatedReferences': [
          for (final reference in generatedReferences) reference.toJson(),
        ],
        'kind': 'localMeasurementManifest',
        'manifestId': manifestId.value,
        'points': [for (final point in points) point.toJson()],
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceRevisionId': surfaceRevisionId.value,
        'target': target.toJson(),
      };
}

/// One canonical node paired with its exact artifact occurrence.
final class AncestryNodeRefV1 extends CanonicalValue {
  AncestryNodeRefV1({
    required this.artifactOccurrenceEdgeToken,
    required this.canonicalNodeToken,
  });

  factory AncestryNodeRefV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactOccurrenceEdgeToken',
        'canonicalNodeToken',
      },
      requiredKeys: const {
        'artifactOccurrenceEdgeToken',
        'canonicalNodeToken',
      },
      path: 'ancestryNodeRef',
    );
    return _constructManifest(
      'ancestryNodeRef',
      () => AncestryNodeRefV1(
        artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('artifactOccurrenceEdgeToken'),
        ),
        canonicalNodeToken: NodeTokenId(reader.string('canonicalNodeToken')),
      ),
    );
  }

  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;
  final NodeTokenId canonicalNodeToken;

  String get _sortKey =>
      '${artifactOccurrenceEdgeToken.value}\u0000${canonicalNodeToken.value}';

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'canonicalNodeToken': canonicalNodeToken.value,
      };
}

/// One node and its omission-only direct parent.
final class CanonicalNodeParentEdgeV1 extends CanonicalValue {
  CanonicalNodeParentEdgeV1({required this.node, this.parent});

  factory CanonicalNodeParentEdgeV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'node', 'parent'},
      requiredKeys: const {'node'},
      path: 'canonicalNodeParentEdge',
    );
    final parent = reader.optionalObject('parent');
    return _constructManifest(
      'canonicalNodeParentEdge',
      () => CanonicalNodeParentEdgeV1(
        node: AncestryNodeRefV1.fromJson(reader.object('node')),
        parent: parent == null ? null : AncestryNodeRefV1.fromJson(parent),
      ),
    );
  }

  final AncestryNodeRefV1 node;
  final AncestryNodeRefV1? parent;

  @override
  Map<String, Object?> toJson() => {
        'node': node.toJson(),
        if (parent != null) 'parent': parent!.toJson(),
      };
}

/// Exact direct-parent authority for every canonical node in one publication.
final class CanonicalNodeAncestryIndexV1 extends CanonicalValue {
  CanonicalNodeAncestryIndexV1({
    required this.rootNode,
    required List<CanonicalNodeParentEdgeV1> directParentEdges,
  }) : directParentEdges = _sortedAncestryEdges(
          _requireAncestryEdgeLength(directParentEdges),
        ) {
    final byNode = <String, CanonicalNodeParentEdgeV1>{};
    for (final edge in this.directParentEdges) {
      if (byNode.containsKey(edge.node._sortKey)) {
        throw ArgumentError('Ancestry nodes must be unique');
      }
      byNode[edge.node._sortKey] = edge;
    }
    final roots = this.directParentEdges.where((edge) => edge.parent == null);
    if (roots.length != 1 || roots.single.node != rootNode) {
      throw ArgumentError('An ancestry index requires its exact single root');
    }
    for (final edge in this.directParentEdges) {
      final parent = edge.parent;
      if (parent != null && !byNode.containsKey(parent._sortKey)) {
        throw ArgumentError('Every ancestry parent must be present');
      }
    }
    for (final edge in this.directParentEdges) {
      final visited = <String>{};
      var cursor = edge;
      while (cursor.parent != null) {
        if (!visited.add(cursor.node._sortKey)) {
          throw ArgumentError('Canonical node ancestry must be acyclic');
        }
        cursor = byNode[cursor.parent!._sortKey]!;
      }
      if (cursor.node != rootNode) {
        throw ArgumentError('Every ancestry node must reach the root');
      }
    }
  }

  factory CanonicalNodeAncestryIndexV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'directParentEdges',
        'kind',
        'rootNode',
      },
      requiredKeys: const {
        'directParentEdges',
        'kind',
        'rootNode',
      },
      path: 'canonicalNodeAncestryIndex',
    );
    if (reader.string('kind') != 'canonicalNodeAncestryIndex') {
      throw const CanonicalFormatException(
        'canonicalNodeAncestryIndex.kind is invalid',
      );
    }
    return _constructManifest(
      'canonicalNodeAncestryIndex',
      () => CanonicalNodeAncestryIndexV1(
        rootNode: AncestryNodeRefV1.fromJson(reader.object('rootNode')),
        directParentEdges: _readBoundedAncestryEdges(reader)
            .map(
              (value) => CanonicalNodeParentEdgeV1.fromJson(
                requireCanonicalObject(value, 'directParentEdges[]'),
              ),
            )
            .toList(),
      ),
    );
  }

  final AncestryNodeRefV1 rootNode;
  final List<CanonicalNodeParentEdgeV1> directParentEdges;

  @override
  Map<String, Object?> toJson() => {
        'directParentEdges': [
          for (final edge in directParentEdges) edge.toJson(),
        ],
        'kind': 'canonicalNodeAncestryIndex',
        'rootNode': rootNode.toJson(),
      };
}

List<CanonicalNodeParentEdgeV1> _sortedAncestryEdges(
  List<CanonicalNodeParentEdgeV1> values,
) {
  final copy = values.toList()
    ..sort((left, right) => left.node._sortKey.compareTo(right.node._sortKey));
  return List.unmodifiable(copy);
}

List<CanonicalNodeParentEdgeV1> _requireAncestryEdgeLength(
  List<CanonicalNodeParentEdgeV1> values,
) {
  if (values.isEmpty || values.length > kMaximumCanonicalNodeParentEdges) {
    throw ArgumentError(
      'An ancestry index requires 1..$kMaximumCanonicalNodeParentEdges edges',
    );
  }
  return values;
}

List<Object?> _readBoundedAncestryEdges(CanonicalObjectReader reader) {
  final values = reader.list('directParentEdges');
  if (values.isEmpty || values.length > kMaximumCanonicalNodeParentEdges) {
    throw CanonicalFormatException(
      '${reader.path}.directParentEdges exceeds its raw input bound',
    );
  }
  return values;
}

/// Complete, root-reachable local-artifact closure for one surface revision.
final class CompleteMeasurementManifestV1 extends CanonicalDocument {
  /// Creates and validates an exact complete artifact closure.
  CompleteMeasurementManifestV1({
    required this.manifestId,
    required this.target,
    required this.surfaceId,
    required this.surfaceRevisionId,
    required this.rootArtifactId,
    required this.artifactGraphHash,
    required List<LocalMeasurementManifestV1> localManifests,
    required this.nodeAncestryIndex,
    required this.privacyPolicyRevisionId,
    required this.collectionBudgetRevisionId,
  }) : localManifests = _sortedUniqueLocalManifests(localManifests) {
    final byArtifact = {
      for (final manifest in this.localManifests)
        manifest.artifactId.value: manifest,
    };
    if (!byArtifact.containsKey(rootArtifactId.value)) {
      throw ArgumentError('The root artifact local manifest is missing');
    }
    for (final manifest in this.localManifests) {
      if (manifest.target != target ||
          manifest.surfaceRevisionId != surfaceRevisionId ||
          manifest.artifactGraphHash != artifactGraphHash ||
          manifest.privacyPolicyRevisionId != privacyPolicyRevisionId ||
          manifest.collectionBudgetRevisionId != collectionBudgetRevisionId) {
        throw ArgumentError(
          'Every local manifest must join the complete manifest context',
        );
      }
    }
    final currentOccurrenceByLineage = <String, String>{};
    for (final manifest in this.localManifests) {
      for (final point in manifest.points) {
        final lineageId = point.lineageId.value;
        if (currentOccurrenceByLineage.containsKey(lineageId)) {
          throw ArgumentError(
            'A complete manifest may contain only one current occurrence per '
            'lineage',
          );
        }
        currentOccurrenceByLineage[lineageId] = point.occurrenceId.hex;
      }
    }

    final reachable = <String>{};
    final visiting = <String>{};
    void visit(String artifactId) {
      if (visiting.contains(artifactId)) {
        throw ArgumentError('The artifact closure must be acyclic');
      }
      if (!reachable.add(artifactId)) return;
      final manifest = byArtifact[artifactId];
      if (manifest == null) {
        throw ArgumentError(
          'Referenced child artifact $artifactId has no local manifest',
        );
      }
      visiting.add(artifactId);
      for (final child in manifest.childArtifactIds) {
        visit(child.value);
      }
      visiting.remove(artifactId);
    }

    visit(rootArtifactId.value);
    if (reachable.length != byArtifact.length) {
      throw ArgumentError(
        'Every local manifest must be reachable from the root artifact',
      );
    }
  }

  /// Decodes byte-exact canonical complete-manifest JSON.
  factory CompleteMeasurementManifestV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        CompleteMeasurementManifestV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'completeMeasurementManifest',
      );

  /// Decodes a strict nested complete-manifest object.
  factory CompleteMeasurementManifestV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactGraphHash',
        'collectionBudgetRevisionId',
        'kind',
        'localManifests',
        'manifestId',
        'nodeAncestryIndex',
        'privacyPolicyRevisionId',
        'rootArtifactId',
        'schemaVersion',
        'surfaceId',
        'surfaceRevisionId',
        'target',
      },
      requiredKeys: const {
        'artifactGraphHash',
        'collectionBudgetRevisionId',
        'kind',
        'localManifests',
        'manifestId',
        'nodeAncestryIndex',
        'privacyPolicyRevisionId',
        'rootArtifactId',
        'schemaVersion',
        'surfaceId',
        'surfaceRevisionId',
        'target',
      },
      path: 'completeMeasurementManifest',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'completeMeasurementManifest',
    );
    return _constructManifest(
      'completeMeasurementManifest',
      () => CompleteMeasurementManifestV1(
        manifestId: MeasurementManifestId(reader.string('manifestId')),
        target: TargetCoordinate.fromJson(reader.object('target')),
        surfaceId: SurfaceId(reader.string('surfaceId')),
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        rootArtifactId: ArtifactId(reader.string('rootArtifactId')),
        artifactGraphHash: CanonicalDigest(
          reader.string('artifactGraphHash'),
        ),
        localManifests: reader
            .list('localManifests')
            .map(
              (value) => LocalMeasurementManifestV1.fromJson(
                requireCanonicalObject(value, 'localManifests[]'),
              ),
            )
            .toList(),
        nodeAncestryIndex: CanonicalNodeAncestryIndexV1.fromJson(
          reader.object('nodeAncestryIndex'),
        ),
        privacyPolicyRevisionId: AuthorityRevisionId(
          reader.string('privacyPolicyRevisionId'),
        ),
        collectionBudgetRevisionId: AuthorityRevisionId(
          reader.string('collectionBudgetRevisionId'),
        ),
      ),
    );
  }

  final MeasurementManifestId manifestId;
  final TargetCoordinate target;
  final SurfaceId surfaceId;
  final SurfaceRevisionId surfaceRevisionId;
  final ArtifactId rootArtifactId;
  final CanonicalDigest artifactGraphHash;
  final List<LocalMeasurementManifestV1> localManifests;
  final CanonicalNodeAncestryIndexV1 nodeAncestryIndex;
  final AuthorityRevisionId privacyPolicyRevisionId;
  final AuthorityRevisionId collectionBudgetRevisionId;

  /// All points in deterministic artifact and occurrence-ID order.
  List<MeasurementPointOccurrenceV1> get points => UnmodifiableListView(
        [for (final manifest in localManifests) ...manifest.points],
      );

  /// All generated references in deterministic artifact/reference order.
  List<GeneratedPointReferenceV1> get generatedReferences =>
      UnmodifiableListView(
        [
          for (final manifest in localManifests)
            ...manifest.generatedReferences,
        ],
      );

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.completeManifest;

  @override
  Map<String, Object?> toJson() => {
        'artifactGraphHash': artifactGraphHash.hex,
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'kind': 'completeMeasurementManifest',
        'localManifests': [
          for (final manifest in localManifests) manifest.toJson(),
        ],
        'manifestId': manifestId.value,
        'nodeAncestryIndex': nodeAncestryIndex.toJson(),
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
        'rootArtifactId': rootArtifactId.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId.value,
        'surfaceRevisionId': surfaceRevisionId.value,
        'target': target.toJson(),
      };
}

List<ArtifactId> _sortedUniqueIds(
  List<ArtifactId> values, {
  required String label,
}) {
  final copy = values.toList()..sort((a, b) => a.value.compareTo(b.value));
  _rejectAdjacentDuplicates(copy.map((value) => value.value), label);
  return List.unmodifiable(copy);
}

List<MeasurementPointOccurrenceV1> _sortedUniquePoints(
  List<MeasurementPointOccurrenceV1> values,
) {
  final copy = values.toList()
    ..sort((a, b) => a.occurrenceId.hex.compareTo(b.occurrenceId.hex));
  _rejectAdjacentDuplicates(
    copy.map((value) => value.occurrenceId.hex),
    'point occurrence IDs',
  );
  return List.unmodifiable(copy);
}

List<GeneratedPointReferenceV1> _sortedUniqueReferences(
  List<GeneratedPointReferenceV1> values,
) {
  final copy = values.toList()
    ..sort((a, b) => a.referenceId.value.compareTo(b.referenceId.value));
  _rejectAdjacentDuplicates(
    copy.map((value) => value.referenceId.value),
    'generated reference IDs',
  );
  return List.unmodifiable(copy);
}

List<LocalMeasurementManifestV1> _sortedUniqueLocalManifests(
  List<LocalMeasurementManifestV1> values,
) {
  final copy = values.toList()
    ..sort((a, b) => a.artifactId.value.compareTo(b.artifactId.value));
  _rejectAdjacentDuplicates(
    copy.map((value) => value.artifactId.value),
    'local artifact IDs',
  );
  return List.unmodifiable(copy);
}

void _rejectAdjacentDuplicates(Iterable<String> values, String label) {
  String? prior;
  for (final value in values) {
    if (value == prior) throw ArgumentError('$label must be unique');
    prior = value;
  }
}

NormalizedInteractionKind _normalizedInteractionFromWire(String value) =>
    _wireEnum(
      NormalizedInteractionKind.values,
      value,
      (entry) => entry.wireName,
      'normalized interaction kind',
    );

MeasurementPrivacyClass _privacyClassFromWire(String value) => _wireEnum(
      MeasurementPrivacyClass.values,
      value,
      (entry) => entry.wireName,
      'measurement privacy class',
    );

SemanticValueClass _semanticValueClassFromWire(String value) => _wireEnum(
      SemanticValueClass.values,
      value,
      (entry) => entry.wireName,
      'semantic value class',
    );

MeasurementCollectionClass _collectionClassFromWire(String value) => _wireEnum(
      MeasurementCollectionClass.values,
      value,
      (entry) => entry.wireName,
      'measurement collection class',
    );

T _wireEnum<T>(
  List<T> values,
  String value,
  String Function(T) wireName,
  String label,
) {
  for (final entry in values) {
    if (wireName(entry) == value) return entry;
  }
  throw CanonicalFormatException('Unknown $label "$value"');
}

T _constructManifest<T>(String path, T Function() create) {
  try {
    return create();
  } catch (error) {
    if (error is! ArgumentError) rethrow;
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
