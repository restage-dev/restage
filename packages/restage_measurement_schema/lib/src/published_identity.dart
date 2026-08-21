import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/manifest.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// Stable identity of one published surface across immutable revisions.
final class PublishedSurfaceIdentityV1 extends CanonicalDocument {
  /// Creates an identity from its exact target and stable surface ID.
  const PublishedSurfaceIdentityV1({
    required this.target,
    required this.surfaceId,
  });

  /// Decodes byte-exact canonical published-surface identity JSON.
  factory PublishedSurfaceIdentityV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PublishedSurfaceIdentityV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'publishedSurfaceIdentity',
      );

  /// Decodes a strict nested published-surface identity object.
  factory PublishedSurfaceIdentityV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'schemaVersion', 'surfaceId', 'target'},
      requiredKeys: const {'kind', 'schemaVersion', 'surfaceId', 'target'},
      path: 'publishedSurfaceIdentity',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'publishedSurfaceIdentity',
    );
    return _constructCanonical(
      'publishedSurfaceIdentity',
      () => PublishedSurfaceIdentityV1(
        target: TargetCoordinate.fromJson(reader.object('target')),
        surfaceId: SurfaceId(reader.string('surfaceId')),
      ),
    );
  }

  /// Exact control-plane target authority.
  final TargetCoordinate target;

  /// Stable surface identity within [target].
  final SurfaceId surfaceId;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.surfaceIdentity;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'publishedSurfaceIdentity',
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceId': surfaceId.value,
        'target': target.toJson(),
      };
}

/// Immutable published revision of one stable surface.
final class PublishedSurfaceRevisionV1 extends CanonicalDocument {
  /// Creates a published-only revision that seals its graph and manifest.
  PublishedSurfaceRevisionV1({
    required this.revisionId,
    required this.surfaceIdentity,
    required this.analyticsSurfaceKey,
    required this.deliverySurfaceType,
    required this.revisionOrdinal,
    required this.rootArtifactId,
    required this.rootArtifactOccurrenceEdgeToken,
    required this.artifactGraphHash,
    required this.measurementManifestHash,
    required this.measurementSchemaVersion,
    required this.minimumMeasurementClient,
  }) {
    _requirePositivePortable(revisionOrdinal, 'revisionOrdinal');
    _requirePositivePortable(
      minimumMeasurementClient,
      'minimumMeasurementClient',
    );
    if (measurementSchemaVersion != kMeasurementSchemaVersion) {
      throw ArgumentError.value(
        measurementSchemaVersion,
        'measurementSchemaVersion',
        'Expected the supported measurement schema version',
      );
    }
  }

  /// Decodes byte-exact canonical published-surface revision JSON.
  factory PublishedSurfaceRevisionV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PublishedSurfaceRevisionV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'publishedSurfaceRevision',
      );

  /// Decodes a strict nested published-surface revision object.
  factory PublishedSurfaceRevisionV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'analyticsSurfaceKey',
        'artifactGraphHash',
        'deliverySurfaceType',
        'kind',
        'measurementManifestHash',
        'measurementSchemaVersion',
        'minimumMeasurementClient',
        'revisionId',
        'revisionOrdinal',
        'rootArtifactId',
        'rootArtifactOccurrenceEdgeToken',
        'schemaVersion',
        'surfaceIdentity',
      },
      requiredKeys: const {
        'analyticsSurfaceKey',
        'artifactGraphHash',
        'deliverySurfaceType',
        'kind',
        'measurementManifestHash',
        'measurementSchemaVersion',
        'minimumMeasurementClient',
        'revisionId',
        'revisionOrdinal',
        'rootArtifactId',
        'rootArtifactOccurrenceEdgeToken',
        'schemaVersion',
        'surfaceIdentity',
      },
      path: 'publishedSurfaceRevision',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'publishedSurfaceRevision',
    );
    return _constructCanonical(
      'publishedSurfaceRevision',
      () => PublishedSurfaceRevisionV1(
        revisionId: SurfaceRevisionId(reader.string('revisionId')),
        surfaceIdentity: PublishedSurfaceIdentityV1.fromJson(
          reader.object('surfaceIdentity'),
        ),
        analyticsSurfaceKey: AnalyticsSurfaceKey(
          reader.string('analyticsSurfaceKey'),
        ),
        deliverySurfaceType: DeliverySurfaceTypeId(
          reader.string('deliverySurfaceType'),
        ),
        revisionOrdinal: reader.integer('revisionOrdinal'),
        rootArtifactId: ArtifactId(reader.string('rootArtifactId')),
        rootArtifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('rootArtifactOccurrenceEdgeToken'),
        ),
        artifactGraphHash: CanonicalDigest(
          reader.string('artifactGraphHash'),
        ),
        measurementManifestHash: CanonicalDigest(
          reader.string('measurementManifestHash'),
        ),
        measurementSchemaVersion: reader.integer('measurementSchemaVersion'),
        minimumMeasurementClient: reader.integer('minimumMeasurementClient'),
      ),
    );
  }

  /// Exact revision authority.
  final SurfaceRevisionId revisionId;

  /// Embedded stable surface identity.
  final PublishedSurfaceIdentityV1 surfaceIdentity;

  /// Open analytics key preserved without normalization.
  final AnalyticsSurfaceKey analyticsSurfaceKey;

  /// Registered delivery-surface adapter identity.
  final DeliverySurfaceTypeId deliverySurfaceType;

  /// Positive ordinal within the stable surface identity.
  final int revisionOrdinal;

  /// Root published artifact.
  final ArtifactId rootArtifactId;

  /// Synthetic root occurrence edge in the exact graph.
  final ArtifactOccurrenceEdgeToken rootArtifactOccurrenceEdgeToken;

  /// Hash of the exact artifact graph.
  final CanonicalDigest artifactGraphHash;

  /// Hash of the complete measurement manifest.
  final CanonicalDigest measurementManifestHash;

  /// Measurement schema version required by this revision.
  final int measurementSchemaVersion;

  /// Positive minimum client capability revision.
  final int minimumMeasurementClient;

  /// Returns a revision with selected sealed values replaced.
  PublishedSurfaceRevisionV1 copyWith({
    CanonicalDigest? artifactGraphHash,
    CanonicalDigest? measurementManifestHash,
    int? measurementSchemaVersion,
    int? minimumMeasurementClient,
  }) =>
      PublishedSurfaceRevisionV1(
        revisionId: revisionId,
        surfaceIdentity: surfaceIdentity,
        analyticsSurfaceKey: analyticsSurfaceKey,
        deliverySurfaceType: deliverySurfaceType,
        revisionOrdinal: revisionOrdinal,
        rootArtifactId: rootArtifactId,
        rootArtifactOccurrenceEdgeToken: rootArtifactOccurrenceEdgeToken,
        artifactGraphHash: artifactGraphHash ?? this.artifactGraphHash,
        measurementManifestHash:
            measurementManifestHash ?? this.measurementManifestHash,
        measurementSchemaVersion:
            measurementSchemaVersion ?? this.measurementSchemaVersion,
        minimumMeasurementClient:
            minimumMeasurementClient ?? this.minimumMeasurementClient,
      );

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.surfaceIdentity;

  @override
  Map<String, Object?> toJson() => {
        'analyticsSurfaceKey': analyticsSurfaceKey.value,
        'artifactGraphHash': artifactGraphHash.hex,
        'deliverySurfaceType': deliverySurfaceType.value,
        'kind': 'publishedSurfaceRevision',
        'measurementManifestHash': measurementManifestHash.hex,
        'measurementSchemaVersion': measurementSchemaVersion,
        'minimumMeasurementClient': minimumMeasurementClient,
        'revisionId': revisionId.value,
        'revisionOrdinal': revisionOrdinal,
        'rootArtifactId': rootArtifactId.value,
        'rootArtifactOccurrenceEdgeToken':
            rootArtifactOccurrenceEdgeToken.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceIdentity': surfaceIdentity.toJson(),
      };
}

/// Content identity of one published artifact.
final class PublishedArtifactIdentityV1 extends CanonicalDocument {
  /// Creates an identity without graph-bound manifest fields.
  const PublishedArtifactIdentityV1({
    required this.surfaceRevisionId,
    required this.artifactId,
    required this.artifactKind,
    required this.contentHash,
  });

  /// Decodes byte-exact canonical artifact identity JSON.
  factory PublishedArtifactIdentityV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PublishedArtifactIdentityV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'publishedArtifactIdentity',
      );

  /// Decodes a strict nested artifact identity object.
  factory PublishedArtifactIdentityV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactId',
        'artifactKind',
        'contentHash',
        'kind',
        'schemaVersion',
        'surfaceRevisionId',
      },
      requiredKeys: const {
        'artifactId',
        'artifactKind',
        'contentHash',
        'kind',
        'schemaVersion',
        'surfaceRevisionId',
      },
      path: 'publishedArtifactIdentity',
    );
    validateCanonicalDocument(
      reader,
      expectedKind: 'publishedArtifactIdentity',
    );
    return _constructCanonical(
      'publishedArtifactIdentity',
      () => PublishedArtifactIdentityV1(
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactKind: ArtifactKindId(reader.string('artifactKind')),
        contentHash: CanonicalDigest(reader.string('contentHash')),
      ),
    );
  }

  /// Published surface revision containing the artifact.
  final SurfaceRevisionId surfaceRevisionId;

  /// Stable artifact identity within the revision.
  final ArtifactId artifactId;

  /// Registered artifact kind.
  final ArtifactKindId artifactKind;

  /// Exact artifact content hash.
  final CanonicalDigest contentHash;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.artifactIdentity;

  @override
  Map<String, Object?> toJson() => {
        'artifactId': artifactId.value,
        'artifactKind': artifactKind.value,
        'contentHash': contentHash.hex,
        'kind': 'publishedArtifactIdentity',
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceRevisionId': surfaceRevisionId.value,
      };
}

/// Published artifact record carrying its graph-bound local manifest.
final class PublishedArtifactV1 extends CanonicalValue {
  /// Creates an artifact with a sorted unique child definition set.
  PublishedArtifactV1({
    required this.identity,
    required List<ArtifactId> childArtifactIds,
    required this.localMeasurementManifest,
  }) : childArtifactIds = _sortedUniqueArtifactIds(childArtifactIds) {
    if (identity.surfaceRevisionId !=
            localMeasurementManifest.surfaceRevisionId ||
        identity.artifactId != localMeasurementManifest.artifactId ||
        identity.contentHash != localMeasurementManifest.artifactContentHash ||
        !_sameArtifactIds(
          this.childArtifactIds,
          localMeasurementManifest.childArtifactIds,
        )) {
      throw ArgumentError(
        'Artifact identity, child set, and local manifest must agree',
      );
    }
  }

  /// Decodes a strict nested published-artifact object.
  factory PublishedArtifactV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'childArtifactIds',
        'identity',
        'kind',
        'localMeasurementManifest',
      },
      requiredKeys: const {
        'childArtifactIds',
        'identity',
        'kind',
        'localMeasurementManifest',
      },
      path: 'publishedArtifact',
    );
    if (reader.string('kind') != 'publishedArtifact') {
      throw const CanonicalFormatException(
        'publishedArtifact.kind must be "publishedArtifact"',
      );
    }
    return _constructCanonical(
      'publishedArtifact',
      () => PublishedArtifactV1(
        identity: PublishedArtifactIdentityV1.fromJson(
          reader.object('identity'),
        ),
        childArtifactIds: reader
            .list('childArtifactIds')
            .map(
              (value) => ArtifactId(
                requireCanonicalString(value, 'childArtifactIds[]'),
              ),
            )
            .toList(),
        localMeasurementManifest: LocalMeasurementManifestV1.fromJson(
          reader.object('localMeasurementManifest'),
        ),
      ),
    );
  }

  /// Exact artifact identity.
  final PublishedArtifactIdentityV1 identity;

  /// Sorted unique direct child definition set.
  final List<ArtifactId> childArtifactIds;

  /// Exact local manifest authenticated by the publication bundle.
  final LocalMeasurementManifestV1 localMeasurementManifest;

  /// Returns an artifact with selected bundle fields replaced.
  PublishedArtifactV1 copyWith({
    List<ArtifactId>? childArtifactIds,
    LocalMeasurementManifestV1? localMeasurementManifest,
  }) =>
      PublishedArtifactV1(
        identity: identity,
        childArtifactIds: childArtifactIds ?? this.childArtifactIds,
        localMeasurementManifest:
            localMeasurementManifest ?? this.localMeasurementManifest,
      );

  @override
  Map<String, Object?> toJson() => {
        'childArtifactIds': [
          for (final artifactId in childArtifactIds) artifactId.value,
        ],
        'identity': identity.toJson(),
        'kind': 'publishedArtifact',
        'localMeasurementManifest': localMeasurementManifest.toJson(),
      };
}

/// One incoming artifact occurrence edge in an exact publication graph.
final class ArtifactOccurrenceEdgeV1 extends CanonicalValue {
  /// Creates an edge; omit [parentEdgeToken] only for the synthetic root.
  const ArtifactOccurrenceEdgeV1({
    required this.edgeToken,
    required this.artifactId,
    required this.artifactIdentityHash,
    this.parentEdgeToken,
  });

  /// Decodes a strict nested occurrence-edge object.
  factory ArtifactOccurrenceEdgeV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactId',
        'artifactIdentityHash',
        'edgeToken',
        'kind',
        'parentEdgeToken',
      },
      requiredKeys: const {
        'artifactId',
        'artifactIdentityHash',
        'edgeToken',
        'kind',
      },
      path: 'artifactOccurrenceEdge',
    );
    if (reader.string('kind') != 'artifactOccurrenceEdge') {
      throw const CanonicalFormatException(
        'artifactOccurrenceEdge.kind must be "artifactOccurrenceEdge"',
      );
    }
    return _constructCanonical(
      'artifactOccurrenceEdge',
      () => ArtifactOccurrenceEdgeV1(
        edgeToken: ArtifactOccurrenceEdgeToken(reader.string('edgeToken')),
        parentEdgeToken: switch (reader.optionalString('parentEdgeToken')) {
          final value? => ArtifactOccurrenceEdgeToken(value),
          null => null,
        },
        artifactId: ArtifactId(reader.string('artifactId')),
        artifactIdentityHash: CanonicalDigest(
          reader.string('artifactIdentityHash'),
        ),
      ),
    );
  }

  /// Unique incoming edge token.
  final ArtifactOccurrenceEdgeToken edgeToken;

  /// Parent occurrence edge, absent only for the synthetic root.
  final ArtifactOccurrenceEdgeToken? parentEdgeToken;

  /// Artifact referenced by this occurrence.
  final ArtifactId artifactId;

  /// Hash of the exact artifact identity.
  final CanonicalDigest artifactIdentityHash;

  @override
  Map<String, Object?> toJson() => {
        'artifactId': artifactId.value,
        'artifactIdentityHash': artifactIdentityHash.hex,
        'edgeToken': edgeToken.value,
        'kind': 'artifactOccurrenceEdge',
        if (parentEdgeToken != null) 'parentEdgeToken': parentEdgeToken!.value,
      };
}

/// Exact immutable artifact occurrence graph for one surface revision.
final class ExactArtifactGraphV1 extends CanonicalDocument {
  /// Creates and validates graph-internal topology and identity closure.
  ExactArtifactGraphV1({
    required this.surfaceRevisionId,
    required this.rootEdgeToken,
    required List<PublishedArtifactIdentityV1> artifactIdentities,
    required List<ArtifactOccurrenceEdgeV1> occurrenceEdges,
  })  : artifactIdentities = _sortedUniqueArtifactIdentities(
          artifactIdentities,
        ),
        occurrenceEdges = _sortedUniqueOccurrenceEdges(occurrenceEdges) {
    _validateGraph();
  }

  /// Decodes byte-exact canonical exact-artifact-graph JSON.
  factory ExactArtifactGraphV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        ExactArtifactGraphV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'exactArtifactGraph',
      );

  /// Decodes a strict nested exact-artifact-graph object.
  factory ExactArtifactGraphV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'artifactIdentities',
        'kind',
        'occurrenceEdges',
        'rootEdgeToken',
        'schemaVersion',
        'surfaceRevisionId',
      },
      requiredKeys: const {
        'artifactIdentities',
        'kind',
        'occurrenceEdges',
        'rootEdgeToken',
        'schemaVersion',
        'surfaceRevisionId',
      },
      path: 'exactArtifactGraph',
    );
    validateCanonicalDocument(reader, expectedKind: 'exactArtifactGraph');
    return _constructCanonical(
      'exactArtifactGraph',
      () => ExactArtifactGraphV1(
        surfaceRevisionId: SurfaceRevisionId(
          reader.string('surfaceRevisionId'),
        ),
        rootEdgeToken: ArtifactOccurrenceEdgeToken(
          reader.string('rootEdgeToken'),
        ),
        artifactIdentities: reader
            .list('artifactIdentities')
            .map(
              (value) => PublishedArtifactIdentityV1.fromJson(
                requireCanonicalObject(value, 'artifactIdentities[]'),
              ),
            )
            .toList(),
        occurrenceEdges: reader
            .list('occurrenceEdges')
            .map(
              (value) => ArtifactOccurrenceEdgeV1.fromJson(
                requireCanonicalObject(value, 'occurrenceEdges[]'),
              ),
            )
            .toList(),
      ),
    );
  }

  /// Published surface revision represented by the graph.
  final SurfaceRevisionId surfaceRevisionId;

  /// Synthetic root occurrence edge token.
  final ArtifactOccurrenceEdgeToken rootEdgeToken;

  /// Sorted exact artifact identity closure.
  final List<PublishedArtifactIdentityV1> artifactIdentities;

  /// Sorted exact artifact occurrence edge set.
  final List<ArtifactOccurrenceEdgeV1> occurrenceEdges;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.artifactGraph;

  void _validateGraph() {
    if (artifactIdentities.isEmpty || occurrenceEdges.isEmpty) {
      throw ArgumentError('An exact artifact graph must not be empty');
    }
    final identities = {
      for (final identity in artifactIdentities)
        identity.artifactId.value: identity,
    };
    for (final identity in artifactIdentities) {
      if (identity.surfaceRevisionId != surfaceRevisionId) {
        throw ArgumentError(
          'Every artifact identity must join the graph surface revision',
        );
      }
    }
    final edges = {
      for (final edge in occurrenceEdges) edge.edgeToken.value: edge,
    };
    final roots =
        occurrenceEdges.where((edge) => edge.parentEdgeToken == null).toList();
    if (roots.length != 1 || roots.single.edgeToken != rootEdgeToken) {
      throw ArgumentError(
        'The graph must have one synthetic root matching rootEdgeToken',
      );
    }

    final usedArtifactIds = <String>{};
    final children = <String, List<String>>{};
    for (final edge in occurrenceEdges) {
      final identity = identities[edge.artifactId.value];
      if (identity == null ||
          identity.canonicalDigest != edge.artifactIdentityHash) {
        throw ArgumentError(
          'Every edge must join one exact artifact identity',
        );
      }
      usedArtifactIds.add(edge.artifactId.value);
      final parent = edge.parentEdgeToken;
      if (parent != null) {
        if (!edges.containsKey(parent.value)) {
          throw ArgumentError('Every non-root edge parent must exist');
        }
        children.putIfAbsent(parent.value, () => <String>[]).add(
              edge.edgeToken.value,
            );
      }
    }
    if (usedArtifactIds.length != identities.length) {
      throw ArgumentError(
        'Artifact identities must exactly match the referenced closure',
      );
    }

    final visiting = <String>{};
    final reachable = <String>{};
    void visit(String edgeToken) {
      if (!visiting.add(edgeToken)) {
        throw ArgumentError('The artifact occurrence graph must be acyclic');
      }
      if (reachable.add(edgeToken)) {
        (children[edgeToken] ?? const <String>[]).forEach(visit);
      }
      visiting.remove(edgeToken);
    }

    visit(rootEdgeToken.value);
    if (reachable.length != occurrenceEdges.length) {
      throw ArgumentError('Every occurrence edge must be root-reachable');
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'artifactIdentities': [
          for (final identity in artifactIdentities) identity.toJson(),
        ],
        'kind': 'exactArtifactGraph',
        'occurrenceEdges': [
          for (final edge in occurrenceEdges) edge.toJson(),
        ],
        'rootEdgeToken': rootEdgeToken.value,
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceRevisionId': surfaceRevisionId.value,
      };
}

/// Origin-neutral canonical node-token authority.
final class CanonicalNodeTokenV1 extends CanonicalDocument {
  /// Creates one canonical node-token record.
  const CanonicalNodeTokenV1({required this.nodeTokenId});

  /// Decodes byte-exact canonical node-token JSON.
  factory CanonicalNodeTokenV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        CanonicalNodeTokenV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'canonicalNodeToken',
      );

  /// Decodes a strict nested canonical node-token object.
  factory CanonicalNodeTokenV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'kind', 'nodeTokenId', 'schemaVersion'},
      requiredKeys: const {'kind', 'nodeTokenId', 'schemaVersion'},
      path: 'canonicalNodeToken',
    );
    validateCanonicalDocument(reader, expectedKind: 'canonicalNodeToken');
    return _constructCanonical(
      'canonicalNodeToken',
      () => CanonicalNodeTokenV1(
        nodeTokenId: NodeTokenId(reader.string('nodeTokenId')),
      ),
    );
  }

  /// Durable origin-neutral node-token identity.
  final NodeTokenId nodeTokenId;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.nodeToken;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'canonicalNodeToken',
        'nodeTokenId': nodeTokenId.value,
        'schemaVersion': kMeasurementSchemaVersion,
      };
}

/// One code identity to canonical node-token binding.
final class CodeIdentityBindingV1 extends CanonicalValue {
  /// Creates one identity binding without source-locator metadata.
  const CodeIdentityBindingV1({
    required this.codeIdentityId,
    required this.canonicalNodeTokenId,
  });

  /// Decodes a strict nested code-identity binding object.
  factory CodeIdentityBindingV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'codeIdentityId', 'kind', 'nodeTokenId'},
      requiredKeys: const {'codeIdentityId', 'kind', 'nodeTokenId'},
      path: 'codeIdentityBinding',
    );
    if (reader.string('kind') != 'codeIdentityBinding') {
      throw const CanonicalFormatException(
        'codeIdentityBinding.kind must be "codeIdentityBinding"',
      );
    }
    return _constructCanonical(
      'codeIdentityBinding',
      () => CodeIdentityBindingV1(
        codeIdentityId: CodeIdentityId(reader.string('codeIdentityId')),
        canonicalNodeTokenId: NodeTokenId(reader.string('nodeTokenId')),
      ),
    );
  }

  /// Stable code identity.
  final CodeIdentityId codeIdentityId;

  /// Canonical node token bound one-to-one to [codeIdentityId].
  final NodeTokenId canonicalNodeTokenId;

  @override
  Map<String, Object?> toJson() => {
        'codeIdentityId': codeIdentityId.value,
        'kind': 'codeIdentityBinding',
        'nodeTokenId': canonicalNodeTokenId.value,
      };
}

/// Canonical code-identity ledger for one stable published surface.
final class CodeIdentityLedgerV1 extends CanonicalDocument {
  /// Creates a sorted one-to-one code identity ledger.
  CodeIdentityLedgerV1({
    required this.surfaceIdentity,
    required List<CodeIdentityBindingV1> bindings,
  }) : bindings = _sortedUniqueCodeBindings(bindings);

  /// Decodes byte-exact canonical code-identity ledger JSON.
  factory CodeIdentityLedgerV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        CodeIdentityLedgerV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'codeIdentityLedger',
      );

  /// Decodes a strict nested code-identity ledger object.
  factory CodeIdentityLedgerV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'bindings',
        'kind',
        'schemaVersion',
        'surfaceIdentity',
      },
      requiredKeys: const {
        'bindings',
        'kind',
        'schemaVersion',
        'surfaceIdentity',
      },
      path: 'codeIdentityLedger',
    );
    validateCanonicalDocument(reader, expectedKind: 'codeIdentityLedger');
    return _constructCanonical(
      'codeIdentityLedger',
      () => CodeIdentityLedgerV1(
        surfaceIdentity: PublishedSurfaceIdentityV1.fromJson(
          reader.object('surfaceIdentity'),
        ),
        bindings: reader
            .list('bindings')
            .map(
              (value) => CodeIdentityBindingV1.fromJson(
                requireCanonicalObject(value, 'bindings[]'),
              ),
            )
            .toList(),
      ),
    );
  }

  /// Stable surface identity owning the ledger.
  final PublishedSurfaceIdentityV1 surfaceIdentity;

  /// Sorted one-to-one identity bindings.
  final List<CodeIdentityBindingV1> bindings;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.codeIdentity;

  @override
  Map<String, Object?> toJson() => {
        'bindings': [for (final binding in bindings) binding.toJson()],
        'kind': 'codeIdentityLedger',
        'schemaVersion': kMeasurementSchemaVersion,
        'surfaceIdentity': surfaceIdentity.toJson(),
      };
}

/// Validates the joins across one complete published measurement bundle.
///
/// This is a pure mechanical validator. It performs no publication,
/// compatibility, compiler, or runtime behavior.
void validatePublishedMeasurementBundleV1({
  required PublishedSurfaceRevisionV1 surfaceRevision,
  required ExactArtifactGraphV1 artifactGraph,
  required List<PublishedArtifactV1> publishedArtifacts,
  required CompleteMeasurementManifestV1 completeManifest,
}) {
  if (surfaceRevision.revisionId != artifactGraph.surfaceRevisionId ||
      surfaceRevision.artifactGraphHash != artifactGraph.canonicalDigest) {
    throw ArgumentError('The surface revision must seal the exact graph');
  }
  if (surfaceRevision.measurementManifestHash !=
      completeManifest.canonicalDigest) {
    throw ArgumentError(
      'The surface revision must seal the complete measurement manifest',
    );
  }
  if (completeManifest.target != surfaceRevision.surfaceIdentity.target ||
      completeManifest.surfaceId != surfaceRevision.surfaceIdentity.surfaceId ||
      completeManifest.surfaceRevisionId != surfaceRevision.revisionId ||
      completeManifest.rootArtifactId != surfaceRevision.rootArtifactId ||
      completeManifest.artifactGraphHash != artifactGraph.canonicalDigest) {
    throw ArgumentError(
      'The complete manifest must join the published surface revision',
    );
  }

  final graphEdges = {
    for (final edge in artifactGraph.occurrenceEdges)
      edge.edgeToken.value: edge,
  };
  final ancestry = completeManifest.nodeAncestryIndex;
  final ancestryNodeKeys = {
    for (final edge in ancestry.directParentEdges)
      '${edge.node.artifactOccurrenceEdgeToken.value}\u0000'
          '${edge.node.canonicalNodeToken.value}',
  };
  for (final point in completeManifest.points) {
    final key = '${point.artifactOccurrenceEdgeToken.value}\u0000'
        '${point.canonicalNodeToken.value}';
    if (!ancestryNodeKeys.contains(key)) {
      throw ArgumentError(
        'Every manifest point must have exact canonical ancestry',
      );
    }
  }
  final ancestryRootEdge =
      graphEdges[ancestry.rootNode.artifactOccurrenceEdgeToken.value];
  if (ancestryRootEdge == null ||
      ancestryRootEdge.edgeToken != artifactGraph.rootEdgeToken) {
    throw ArgumentError('The canonical ancestry root must join the graph root');
  }
  final crossOccurrenceBridgeCounts = <String, int>{
    for (final edge in artifactGraph.occurrenceEdges) edge.edgeToken.value: 0,
  };
  var graphRootCount = 0;
  for (final parentEdge in ancestry.directParentEdges) {
    final nodeOccurrence =
        graphEdges[parentEdge.node.artifactOccurrenceEdgeToken.value];
    if (nodeOccurrence == null) {
      throw ArgumentError(
        'Every ancestry node must join an artifact graph occurrence',
      );
    }
    final parent = parentEdge.parent;
    if (parent == null) {
      if (nodeOccurrence.edgeToken != artifactGraph.rootEdgeToken) {
        throw ArgumentError(
          'Only the graph-root occurrence may contain the ancestry root',
        );
      }
      graphRootCount++;
      continue;
    }
    final parentOccurrence =
        graphEdges[parent.artifactOccurrenceEdgeToken.value];
    if (parentOccurrence == null) {
      throw ArgumentError(
        'Every ancestry parent must join an artifact graph occurrence',
      );
    }
    if (nodeOccurrence.edgeToken == parentOccurrence.edgeToken) {
      continue;
    }
    if (nodeOccurrence.parentEdgeToken != parentOccurrence.edgeToken) {
      throw ArgumentError(
        'Cross-artifact ancestry must follow the exact graph parent edge',
      );
    }
    crossOccurrenceBridgeCounts[nodeOccurrence.edgeToken.value] =
        crossOccurrenceBridgeCounts[nodeOccurrence.edgeToken.value]! + 1;
  }
  if (graphRootCount != 1 ||
      crossOccurrenceBridgeCounts[artifactGraph.rootEdgeToken.value] != 0) {
    throw ArgumentError(
      'The graph-root occurrence requires exactly one global ancestry root',
    );
  }
  for (final occurrence in artifactGraph.occurrenceEdges) {
    if (occurrence.edgeToken == artifactGraph.rootEdgeToken) continue;
    if (crossOccurrenceBridgeCounts[occurrence.edgeToken.value] != 1) {
      throw ArgumentError(
        'Every non-root artifact occurrence requires exactly one canonical '
        'root bridge',
      );
    }
  }
  final rootEdge = graphEdges[artifactGraph.rootEdgeToken.value]!;
  if (surfaceRevision.rootArtifactOccurrenceEdgeToken != rootEdge.edgeToken ||
      surfaceRevision.rootArtifactId != rootEdge.artifactId) {
    throw ArgumentError('The published root must match the graph root');
  }

  final artifacts = _uniquePublishedArtifacts(publishedArtifacts);
  final graphIdentities = {
    for (final identity in artifactGraph.artifactIdentities)
      identity.artifactId.value: identity,
  };
  if (!_sameKeys(artifacts.keys, graphIdentities.keys)) {
    throw ArgumentError(
      'Published artifacts must exactly match the graph identity closure',
    );
  }
  final completeLocals = {
    for (final manifest in completeManifest.localManifests)
      manifest.artifactId.value: manifest,
  };
  if (!_sameKeys(artifacts.keys, completeLocals.keys)) {
    throw ArgumentError(
      'Published artifacts must exactly match the local manifest closure',
    );
  }

  final childEdges = <String, List<ArtifactOccurrenceEdgeV1>>{};
  for (final edge in artifactGraph.occurrenceEdges) {
    final parent = edge.parentEdgeToken;
    if (parent != null) {
      childEdges.putIfAbsent(parent.value, () => []).add(edge);
    }
  }

  for (final entry in artifacts.entries) {
    final artifact = entry.value;
    final identity = graphIdentities[entry.key]!;
    final local = artifact.localMeasurementManifest;
    final completeLocal = completeLocals[entry.key]!;
    if (artifact.identity != identity ||
        artifact.identity.surfaceRevisionId != surfaceRevision.revisionId ||
        local.target != surfaceRevision.surfaceIdentity.target ||
        local.surfaceRevisionId != surfaceRevision.revisionId ||
        local.artifactGraphHash != artifactGraph.canonicalDigest ||
        local.artifactId != identity.artifactId ||
        local.artifactContentHash != identity.contentHash ||
        local != completeLocal) {
      throw ArgumentError(
        'Every published artifact must join its graph identity and manifest',
      );
    }
    if (!_sameArtifactIds(artifact.childArtifactIds, local.childArtifactIds)) {
      throw ArgumentError(
        'Published and local artifact child definition sets must agree',
      );
    }

    for (final occurrence in artifactGraph.occurrenceEdges
        .where((edge) => edge.artifactId == identity.artifactId)) {
      final graphChildren = childEdges[occurrence.edgeToken.value]
              ?.map((edge) => edge.artifactId)
              .toList() ??
          const <ArtifactId>[];
      if (!_sameArtifactIds(artifact.childArtifactIds, graphChildren)) {
        throw ArgumentError(
          'Every artifact occurrence must agree with its child definition set',
        );
      }
    }

    for (final point in local.points) {
      final edge = graphEdges[point.artifactOccurrenceEdgeToken.value];
      if (edge == null ||
          edge.artifactId != point.artifactId ||
          edge.artifactIdentityHash != identity.canonicalDigest ||
          point.artifactContentHash != identity.contentHash) {
        throw ArgumentError(
          'Every manifest point must resolve to its exact graph occurrence',
        );
      }
    }
  }
}

List<PublishedArtifactIdentityV1> _sortedUniqueArtifactIdentities(
  List<PublishedArtifactIdentityV1> values,
) {
  final copy = values.toList()
    ..sort(
      (left, right) => left.artifactId.value.compareTo(
        right.artifactId.value,
      ),
    );
  _rejectDuplicateStrings(
    copy.map((identity) => identity.artifactId.value),
    'Artifact identities',
  );
  return List.unmodifiable(copy);
}

List<ArtifactOccurrenceEdgeV1> _sortedUniqueOccurrenceEdges(
  List<ArtifactOccurrenceEdgeV1> values,
) {
  final copy = values.toList()
    ..sort(
      (left, right) => left.edgeToken.value.compareTo(
        right.edgeToken.value,
      ),
    );
  _rejectDuplicateStrings(
    copy.map((edge) => edge.edgeToken.value),
    'Artifact occurrence edge tokens',
  );
  return List.unmodifiable(copy);
}

List<ArtifactId> _sortedUniqueArtifactIds(List<ArtifactId> values) {
  final copy = values.toList()
    ..sort((left, right) => left.value.compareTo(right.value));
  _rejectDuplicateStrings(
    copy.map((artifactId) => artifactId.value),
    'Child artifact IDs',
  );
  return List.unmodifiable(copy);
}

List<CodeIdentityBindingV1> _sortedUniqueCodeBindings(
  List<CodeIdentityBindingV1> values,
) {
  final copy = values.toList()
    ..sort(
      (left, right) => left.codeIdentityId.value.compareTo(
        right.codeIdentityId.value,
      ),
    );
  _rejectDuplicateStrings(
    copy.map((binding) => binding.codeIdentityId.value),
    'Code identity IDs',
  );
  final nodeTokens = <String>{};
  for (final binding in copy) {
    if (!nodeTokens.add(binding.canonicalNodeTokenId.value)) {
      throw ArgumentError('Canonical node token IDs must be one-to-one');
    }
  }
  return List.unmodifiable(copy);
}

Map<String, PublishedArtifactV1> _uniquePublishedArtifacts(
  List<PublishedArtifactV1> values,
) {
  final result = <String, PublishedArtifactV1>{};
  for (final artifact in List<PublishedArtifactV1>.of(values)) {
    final artifactId = artifact.identity.artifactId.value;
    if (result.containsKey(artifactId)) {
      throw ArgumentError('Published artifact IDs must be unique');
    }
    result[artifactId] = artifact;
  }
  return result;
}

bool _sameArtifactIds(List<ArtifactId> left, List<ArtifactId> right) =>
    _sameKeys(
      left.map((value) => value.value),
      right.map((value) => value.value),
    );

bool _sameKeys(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

void _rejectDuplicateStrings(Iterable<String> values, String label) {
  String? prior;
  for (final value in values) {
    if (value == prior) throw ArgumentError('$label must be unique');
    prior = value;
  }
}

void _requirePositivePortable(int value, String name) {
  if (value <= 0 || value > kMaximumPortableJsonInteger) {
    throw ArgumentError.value(
      value,
      name,
      'Expected a positive portable JSON integer',
    );
  }
}

T _constructCanonical<T>(String path, T Function() create) {
  try {
    return create();
  } catch (error) {
    if (error is! ArgumentError) rethrow;
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}
