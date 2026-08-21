import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  final target = _target();
  final surfaceIdentity = PublishedSurfaceIdentityV1(
    target: target,
    surfaceId: SurfaceId('surface.checkout'),
  );

  test('published identity fixtures freeze all five hash families', () {
    final fixtures = <_IdentityFixture>[
      _IdentityFixture(
        'published_surface_identity_v1.json',
        CanonicalHashDomain.surfaceIdentity,
        '0772e5742fe277da9f47f66d01e9631cc88f63dfe7ca6736ab1f40d29954b54f',
        PublishedSurfaceIdentityV1.fromCanonicalBytes,
      ),
      _IdentityFixture(
        'published_surface_revision_v1.json',
        CanonicalHashDomain.surfaceIdentity,
        '9258b60b27979f95de308c96b062f15077c0ffcb15b3aef943e4a97edaaf64ef',
        PublishedSurfaceRevisionV1.fromCanonicalBytes,
      ),
      _IdentityFixture(
        'published_artifact_identity_v1.json',
        CanonicalHashDomain.artifactIdentity,
        '92fde673884cc4b71bdac85ae58987d0a7eb6138ef96b280e7ab1fc422bd5760',
        PublishedArtifactIdentityV1.fromCanonicalBytes,
      ),
      _IdentityFixture(
        'exact_artifact_graph_v1.json',
        CanonicalHashDomain.artifactGraph,
        '45306d98400229228275b56091bc079dc8b572e4b1a66ac570cf7f58d8a65829',
        ExactArtifactGraphV1.fromCanonicalBytes,
      ),
      _IdentityFixture(
        'canonical_node_token_v1.json',
        CanonicalHashDomain.nodeToken,
        'ec9896da10c709a13dc83bc7a7965acd7fbdde656e6e3f6cef7388e6615af03b',
        CanonicalNodeTokenV1.fromCanonicalBytes,
      ),
      _IdentityFixture(
        'code_identity_ledger_v1.json',
        CanonicalHashDomain.codeIdentity,
        '61b3af08454317b89768b71418c47b31ea91215198ccc5659fb71bf7dcbc1af9',
        CodeIdentityLedgerV1.fromCanonicalBytes,
      ),
    ];

    for (final fixture in fixtures) {
      final bytes = File(
        'test/fixtures/published_identity/${fixture.name}',
      ).readAsBytesSync();
      final decoded = fixture.decode(bytes);
      expect(decoded.hashDomain, fixture.domain, reason: fixture.name);
      expect(decoded.canonicalDigest.hex, fixture.expectedHash,
          reason: fixture.name);
      expect(decoded.canonicalBytes, bytes, reason: fixture.name);

      final json = decodeCanonicalObject(bytes);
      for (final invalid in <Map<String, Object?>>[
        {...json, 'unknown': true},
        {...json, 'schemaVersion': 2},
        {...json, 'kind': 'unknownPublishedIdentity'},
      ]) {
        expect(
          () => fixture.decode(CanonicalJsonCodec.encode(invalid)),
          throwsA(isA<CanonicalFormatException>()),
          reason: fixture.name,
        );
      }
    }

    expect(
      fixtures[0].expectedHash,
      isNot(fixtures[1].expectedHash),
      reason: 'closed kind values separate the shared surface hash domain',
    );
  });

  test('surface revision is published-only and seals the exact coordinate', () {
    final revision = PublishedSurfaceRevisionV1(
      revisionId: SurfaceRevisionId('surface.checkout.v1'),
      surfaceIdentity: surfaceIdentity,
      analyticsSurfaceKey: AnalyticsSurfaceKey('checkout'),
      deliverySurfaceType: DeliverySurfaceTypeId('paywall'),
      revisionOrdinal: 1,
      rootArtifactId: ArtifactId('artifact.checkout-root'),
      rootArtifactOccurrenceEdgeToken:
          ArtifactOccurrenceEdgeToken('edge.checkout-root'),
      artifactGraphHash: CanonicalDigest('a' * 64),
      measurementManifestHash: CanonicalDigest('b' * 64),
      measurementSchemaVersion: 1,
      minimumMeasurementClient: 1,
    );

    expect(revision.toJson(), isNot(contains('publicationState')));
    expect(revision.toJson(), isNot(contains('publishedAt')));
    expect(revision.minimumMeasurementClient, 1);
    expect(
      () => revision.copyWith(minimumMeasurementClient: 0),
      throwsArgumentError,
    );
    expect(
      () => revision.copyWith(
        minimumMeasurementClient: kMaximumPortableJsonInteger + 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => revision.copyWith(measurementSchemaVersion: 2),
      throwsArgumentError,
    );
    expect(
      () => PublishedSurfaceRevisionV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode({
          ...revision.toJson(),
          'measurementSchemaVersion': 2,
        }),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => PublishedSurfaceRevisionV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode({...revision.toJson(), 'publishedAt': 1}),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('registered surface and artifact kinds remain typed bounded IDs', () {
    expect(
        DeliverySurfaceTypeId('future-conforming').value, 'future-conforming');
    expect(ArtifactKindId('customer.inline-v2').value, 'customer.inline-v2');
    expect(() => DeliverySurfaceTypeId(''), throwsArgumentError);
    expect(() => ArtifactKindId('A' * 129), throwsArgumentError);
    const unknownAnalyticsKey = 'Checkout/特別-Offre_β';
    final analyticsKey = AnalyticsSurfaceKey(unknownAnalyticsKey);
    expect(analyticsKey.value, unknownAnalyticsKey);
    final revision = PublishedSurfaceRevisionV1(
      revisionId: SurfaceRevisionId('surface.checkout.v1'),
      surfaceIdentity: surfaceIdentity,
      analyticsSurfaceKey: analyticsKey,
      deliverySurfaceType: DeliverySurfaceTypeId('paywall'),
      revisionOrdinal: 1,
      rootArtifactId: ArtifactId('artifact.checkout-root'),
      rootArtifactOccurrenceEdgeToken:
          ArtifactOccurrenceEdgeToken('edge.checkout-root'),
      artifactGraphHash: CanonicalDigest('a' * 64),
      measurementManifestHash: CanonicalDigest('b' * 64),
      measurementSchemaVersion: 1,
      minimumMeasurementClient: 1,
    );
    expect(
      PublishedSurfaceRevisionV1.fromCanonicalBytes(revision.canonicalBytes)
          .analyticsSurfaceKey
          .value,
      unknownAnalyticsKey,
    );
    expect(() => AnalyticsSurfaceKey(''), throwsArgumentError);
    expect(() => AnalyticsSurfaceKey('é' * 65), throwsArgumentError);
    expect(
      () => AnalyticsSurfaceKey(String.fromCharCode(0xD800)),
      throwsArgumentError,
    );
  });

  test('graph admits repeated artifacts only through distinct incoming edges',
      () {
    final root = _artifactIdentity('root', 'a');
    final child = _artifactIdentity('child', 'b');
    final rootEdge = _edge('root', root);
    final firstChild = _edge('child-one', child, parent: rootEdge.edgeToken);
    final secondChild = _edge('child-two', child, parent: rootEdge.edgeToken);
    final graph = ExactArtifactGraphV1(
      surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
      rootEdgeToken: rootEdge.edgeToken,
      artifactIdentities: [root, child],
      occurrenceEdges: [rootEdge, firstChild, secondChild],
    );

    expect(
      graph.occurrenceEdges
          .where((edge) => edge.artifactId == child.artifactId),
      hasLength(2),
    );
    expect(
      ExactArtifactGraphV1.fromCanonicalBytes(graph.canonicalBytes)
          .canonicalBytes,
      graph.canonicalBytes,
    );
  });

  test('graph rejects invalid root, parent, cycle, edge, and closure shapes',
      () {
    final root = _artifactIdentity('root', 'a');
    final child = _artifactIdentity('child', 'b');
    final unused = _artifactIdentity('unused', 'c');
    final rootEdge = _edge('root', root);
    final childEdge = _edge('child', child, parent: rootEdge.edgeToken);

    ExactArtifactGraphV1 graph({
      ArtifactOccurrenceEdgeToken? rootToken,
      List<PublishedArtifactIdentityV1>? artifacts,
      List<ArtifactOccurrenceEdgeV1>? edges,
    }) =>
        ExactArtifactGraphV1(
          surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
          rootEdgeToken: rootToken ?? rootEdge.edgeToken,
          artifactIdentities: artifacts ?? [root, child],
          occurrenceEdges: edges ?? [rootEdge, childEdge],
        );

    for (final invalid in <ExactArtifactGraphV1 Function()>[
      () => graph(
            edges: [
              rootEdge,
              _edge('second-root', child),
            ],
          ),
      () => graph(
            edges: [
              rootEdge,
              _edge(
                'child',
                child,
                parent: ArtifactOccurrenceEdgeToken('edge.missing'),
              ),
            ],
          ),
      () => graph(edges: [rootEdge, childEdge, childEdge]),
      () => graph(artifacts: [root, child, unused]),
      () => graph(
            rootToken: ArtifactOccurrenceEdgeToken('edge.not-root'),
          ),
      () => graph(
            edges: [
              rootEdge,
              ArtifactOccurrenceEdgeV1(
                edgeToken: childEdge.edgeToken,
                parentEdgeToken: rootEdge.edgeToken,
                artifactId: child.artifactId,
                artifactIdentityHash: CanonicalDigest('f' * 64),
              ),
            ],
          ),
      () => graph(
            edges: [
              rootEdge,
              ArtifactOccurrenceEdgeV1(
                edgeToken: ArtifactOccurrenceEdgeToken('edge.cycle-a'),
                parentEdgeToken: ArtifactOccurrenceEdgeToken('edge.cycle-b'),
                artifactId: child.artifactId,
                artifactIdentityHash: child.canonicalDigest,
              ),
              ArtifactOccurrenceEdgeV1(
                edgeToken: ArtifactOccurrenceEdgeToken('edge.cycle-b'),
                parentEdgeToken: ArtifactOccurrenceEdgeToken('edge.cycle-a'),
                artifactId: child.artifactId,
                artifactIdentityHash: child.canonicalDigest,
              ),
            ],
          ),
    ]) {
      expect(invalid, throwsArgumentError);
    }
  });

  test('node-token ledger is sorted and strictly one-to-one', () {
    final first = CodeIdentityBindingV1(
      codeIdentityId: CodeIdentityId('code.first'),
      canonicalNodeTokenId: NodeTokenId('node.first'),
    );
    final second = CodeIdentityBindingV1(
      codeIdentityId: CodeIdentityId('code.second'),
      canonicalNodeTokenId: NodeTokenId('node.second'),
    );
    final ledger = CodeIdentityLedgerV1(
      surfaceIdentity: surfaceIdentity,
      bindings: [second, first],
    );

    expect(
      ledger.bindings.map((binding) => binding.codeIdentityId.value),
      ['code.first', 'code.second'],
    );
    expect(
      CodeIdentityLedgerV1.fromCanonicalBytes(ledger.canonicalBytes)
          .canonicalBytes,
      ledger.canonicalBytes,
    );
    expect(
      () => CodeIdentityLedgerV1(
        surfaceIdentity: surfaceIdentity,
        bindings: [first, first],
      ),
      throwsArgumentError,
    );
    expect(
      () => CodeIdentityLedgerV1(
        surfaceIdentity: surfaceIdentity,
        bindings: [
          first,
          CodeIdentityBindingV1(
            codeIdentityId: CodeIdentityId('code.other'),
            canonicalNodeTokenId: first.canonicalNodeTokenId,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('published artifact rejects identity and local-manifest disagreement',
      () {
    final bundle = _bundle(target, surfaceIdentity);
    final artifact = bundle.artifacts.single;
    final identity = artifact.identity;
    final local = artifact.localMeasurementManifest;

    for (final invalid in <PublishedArtifactV1 Function()>[
      () => PublishedArtifactV1(
            identity: PublishedArtifactIdentityV1(
              surfaceRevisionId: SurfaceRevisionId('surface.checkout.v2'),
              artifactId: identity.artifactId,
              artifactKind: identity.artifactKind,
              contentHash: identity.contentHash,
            ),
            childArtifactIds: artifact.childArtifactIds,
            localMeasurementManifest: local,
          ),
      () => PublishedArtifactV1(
            identity: PublishedArtifactIdentityV1(
              surfaceRevisionId: identity.surfaceRevisionId,
              artifactId: ArtifactId('artifact.other'),
              artifactKind: identity.artifactKind,
              contentHash: identity.contentHash,
            ),
            childArtifactIds: artifact.childArtifactIds,
            localMeasurementManifest: local,
          ),
      () => PublishedArtifactV1(
            identity: PublishedArtifactIdentityV1(
              surfaceRevisionId: identity.surfaceRevisionId,
              artifactId: identity.artifactId,
              artifactKind: identity.artifactKind,
              contentHash: CanonicalDigest('f' * 64),
            ),
            childArtifactIds: artifact.childArtifactIds,
            localMeasurementManifest: local,
          ),
      () => PublishedArtifactV1(
            identity: identity,
            childArtifactIds: [ArtifactId('artifact.child')],
            localMeasurementManifest: local,
          ),
    ]) {
      expect(invalid, throwsArgumentError);
    }

    final json = artifact.toJson();
    final identityJson = identity.toJson();
    final localJson = local.toJson();
    for (final invalid in <Map<String, Object?>>[
      {
        ...json,
        'identity': {
          ...identityJson,
          'surfaceRevisionId': 'surface.checkout.v2',
        },
      },
      {
        ...json,
        'identity': {...identityJson, 'artifactId': 'artifact.other'},
      },
      {
        ...json,
        'identity': {...identityJson, 'contentHash': 'f' * 64},
      },
      {
        ...json,
        'localMeasurementManifest': {
          ...localJson,
          'childArtifactIds': ['artifact.child'],
        },
      },
    ]) {
      expect(
        () => PublishedArtifactV1.fromJson(invalid),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('publication bundle validates graph, artifacts, and manifest joins', () {
    final bundle = _bundle(target, surfaceIdentity);

    expect(
      () => validatePublishedMeasurementBundleV1(
        surfaceRevision: bundle.surfaceRevision,
        artifactGraph: bundle.graph,
        publishedArtifacts: bundle.artifacts,
        completeManifest: bundle.completeManifest,
      ),
      returnsNormally,
    );
    expect(
      () => validatePublishedMeasurementBundleV1(
        surfaceRevision: bundle.surfaceRevision,
        artifactGraph: bundle.graph,
        publishedArtifacts: [
          bundle.artifacts.single,
          bundle.artifacts.single,
        ],
        completeManifest: bundle.completeManifest,
      ),
      throwsArgumentError,
      reason: 'equal repeated artifacts remain duplicate bundle entries',
    );
    expect(
      () => validatePublishedMeasurementBundleV1(
        surfaceRevision: bundle.surfaceRevision,
        artifactGraph: bundle.graph,
        publishedArtifacts: [
          bundle.artifacts.single.copyWith(
            childArtifactIds: [ArtifactId('artifact.missing-child')],
          ),
        ],
        completeManifest: bundle.completeManifest,
      ),
      throwsArgumentError,
      reason: 'artifact child definition closure must match graph edges',
    );
    expect(
      () => validatePublishedMeasurementBundleV1(
        surfaceRevision: bundle.surfaceRevision.copyWith(
          artifactGraphHash: CanonicalDigest('f' * 64),
        ),
        artifactGraph: bundle.graph,
        publishedArtifacts: bundle.artifacts,
        completeManifest: bundle.completeManifest,
      ),
      throwsArgumentError,
    );

    final point = bundle.completeManifest.points.single;
    final wrongEdgePoint = _copyOccurrence(
      point,
      artifactOccurrenceEdgeToken:
          ArtifactOccurrenceEdgeToken('edge.not-in-graph'),
    );
    final wrongLocal = _localManifest(
      wrongEdgePoint,
      artifactGraphHash: bundle.graph.canonicalDigest,
    );
    final wrongComplete = _completeManifest(
      target,
      surfaceIdentity.surfaceId,
      wrongEdgePoint.surfaceRevisionId,
      bundle.graph.canonicalDigest,
      [wrongLocal],
    );
    expect(
      () => validatePublishedMeasurementBundleV1(
        surfaceRevision: bundle.surfaceRevision.copyWith(
          measurementManifestHash: wrongComplete.canonicalDigest,
        ),
        artifactGraph: bundle.graph,
        publishedArtifacts: [
          PublishedArtifactV1(
            identity: bundle.artifacts.single.identity,
            childArtifactIds: const [],
            localMeasurementManifest: wrongLocal,
          ),
        ],
        completeManifest: wrongComplete,
      ),
      throwsArgumentError,
      reason: 'every manifest point edge resolves to exact artifact/content',
    );
  });
}

final class _IdentityFixture {
  const _IdentityFixture(
    this.name,
    this.domain,
    this.expectedHash,
    this.decode,
  );

  final String name;
  final CanonicalHashDomain domain;
  final String expectedHash;
  final CanonicalDocument Function(List<int>) decode;
}

final class _Bundle {
  const _Bundle({
    required this.surfaceRevision,
    required this.graph,
    required this.artifacts,
    required this.completeManifest,
  });

  final PublishedSurfaceRevisionV1 surfaceRevision;
  final ExactArtifactGraphV1 graph;
  final List<PublishedArtifactV1> artifacts;
  final CompleteMeasurementManifestV1 completeManifest;
}

_Bundle _bundle(
  TargetCoordinate target,
  PublishedSurfaceIdentityV1 surfaceIdentity,
) {
  final artifact = _artifactIdentity('root', 'a');
  final edge = _edge('root', artifact);
  final graph = ExactArtifactGraphV1(
    surfaceRevisionId: artifact.surfaceRevisionId,
    rootEdgeToken: edge.edgeToken,
    artifactIdentities: [artifact],
    occurrenceEdges: [edge],
  );
  final occurrence = MeasurementPointOccurrenceV1(
    target: target,
    surfaceRevisionId: artifact.surfaceRevisionId,
    artifactGraphHash: graph.canonicalDigest,
    artifactId: artifact.artifactId,
    artifactOccurrenceEdgeToken: edge.edgeToken,
    artifactContentHash: artifact.contentHash,
    canonicalNodeToken: NodeTokenId('node.root'),
    capabilityKind: MeasurementCapabilityKind.presented,
    privacyClass: MeasurementPrivacyClass.nonSensitive,
    semanticValueClass: SemanticValueClass.none,
    collectionClass: MeasurementCollectionClass.tier1KeepAll,
    lineageId: PointLineageId('lineage.root'),
    displayMetadataRef: DisplayMetadataRef('display.root'),
  );
  final local = _localManifest(
    occurrence,
    artifactGraphHash: graph.canonicalDigest,
  );
  final complete = _completeManifest(
    target,
    surfaceIdentity.surfaceId,
    artifact.surfaceRevisionId,
    graph.canonicalDigest,
    [local],
  );
  final publishedArtifact = PublishedArtifactV1(
    identity: artifact,
    childArtifactIds: const [],
    localMeasurementManifest: local,
  );
  final surfaceRevision = PublishedSurfaceRevisionV1(
    revisionId: artifact.surfaceRevisionId,
    surfaceIdentity: surfaceIdentity,
    analyticsSurfaceKey: AnalyticsSurfaceKey('checkout'),
    deliverySurfaceType: DeliverySurfaceTypeId('paywall'),
    revisionOrdinal: 1,
    rootArtifactId: artifact.artifactId,
    rootArtifactOccurrenceEdgeToken: edge.edgeToken,
    artifactGraphHash: graph.canonicalDigest,
    measurementManifestHash: complete.canonicalDigest,
    measurementSchemaVersion: 1,
    minimumMeasurementClient: 1,
  );
  return _Bundle(
    surfaceRevision: surfaceRevision,
    graph: graph,
    artifacts: [publishedArtifact],
    completeManifest: complete,
  );
}

PublishedArtifactIdentityV1 _artifactIdentity(String suffix, String digest) =>
    PublishedArtifactIdentityV1(
      surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
      artifactId: ArtifactId('artifact.$suffix'),
      artifactKind: ArtifactKindId('rfw.blob'),
      contentHash: CanonicalDigest(digest * 64),
    );

ArtifactOccurrenceEdgeV1 _edge(
  String suffix,
  PublishedArtifactIdentityV1 artifact, {
  ArtifactOccurrenceEdgeToken? parent,
}) =>
    ArtifactOccurrenceEdgeV1(
      edgeToken: ArtifactOccurrenceEdgeToken('edge.$suffix'),
      parentEdgeToken: parent,
      artifactId: artifact.artifactId,
      artifactIdentityHash: artifact.canonicalDigest,
    );

TargetCoordinate _target() => TargetCoordinate(
      organizationId: OrganizationId(11),
      appId: ApplicationId(23),
      environmentTargetId: EnvironmentTargetId(31),
      namedEnvironmentId: NamedEnvironmentId(37),
      runtimePlane: RuntimePlane.sandbox,
    );

LocalMeasurementManifestV1 _localManifest(
  MeasurementPointOccurrenceV1 occurrence, {
  required CanonicalDigest artifactGraphHash,
}) =>
    LocalMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.local'),
      target: occurrence.target,
      surfaceRevisionId: occurrence.surfaceRevisionId,
      artifactGraphHash: artifactGraphHash,
      artifactId: occurrence.artifactId,
      artifactContentHash: occurrence.artifactContentHash,
      childArtifactIds: const [],
      points: [occurrence],
      generatedReferences: const [],
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('budget.v1'),
    );

CompleteMeasurementManifestV1 _completeManifest(
  TargetCoordinate target,
  SurfaceId surfaceId,
  SurfaceRevisionId revisionId,
  CanonicalDigest graphHash,
  List<LocalMeasurementManifestV1> manifests,
) =>
    CompleteMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.complete'),
      target: target,
      surfaceId: surfaceId,
      surfaceRevisionId: revisionId,
      rootArtifactId: manifests.first.artifactId,
      artifactGraphHash: graphHash,
      localManifests: manifests,
      nodeAncestryIndex: _ancestryIndexForManifests(manifests),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId('budget.v1'),
    );

CanonicalNodeAncestryIndexV1 _ancestryIndexForManifests(
  List<LocalMeasurementManifestV1> manifests,
) {
  final points = [
    for (final manifest in manifests) ...manifest.points,
  ];
  final root = AncestryNodeRefV1(
    artifactOccurrenceEdgeToken: points.first.artifactOccurrenceEdgeToken,
    canonicalNodeToken: points.first.canonicalNodeToken,
  );
  return CanonicalNodeAncestryIndexV1(
    rootNode: root,
    directParentEdges: [
      CanonicalNodeParentEdgeV1(node: root),
      for (final point in points.skip(1))
        CanonicalNodeParentEdgeV1(
          node: AncestryNodeRefV1(
            artifactOccurrenceEdgeToken: point.artifactOccurrenceEdgeToken,
            canonicalNodeToken: point.canonicalNodeToken,
          ),
          parent: root,
        ),
    ],
  );
}

MeasurementPointOccurrenceV1 _copyOccurrence(
  MeasurementPointOccurrenceV1 source, {
  required ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
}) =>
    MeasurementPointOccurrenceV1(
      target: source.target,
      surfaceRevisionId: source.surfaceRevisionId,
      artifactGraphHash: source.artifactGraphHash,
      artifactId: source.artifactId,
      artifactOccurrenceEdgeToken: artifactOccurrenceEdgeToken,
      artifactContentHash: source.artifactContentHash,
      canonicalNodeToken: source.canonicalNodeToken,
      capabilityKind: source.capabilityKind,
      sourceEventIdentity: source.sourceEventIdentity,
      normalizedInteractionKind: source.normalizedInteractionKind,
      privacyClass: source.privacyClass,
      semanticValueClass: source.semanticValueClass,
      collectionClass: source.collectionClass,
      lineageId: source.lineageId,
      displayMetadataRef: source.displayMetadataRef,
    );
