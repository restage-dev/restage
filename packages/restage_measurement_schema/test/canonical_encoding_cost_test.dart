@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  // A published context the size a real surface carries: a tree of artifacts
  // with measured points on the ones a developer instrumented.
  final bundle = _publishedBundle(
    artifacts: 140,
    measuredArtifacts: 46,
    pointsPerArtifact: 1,
  );
  final manifestBytes = bundle.manifest.canonicalBytes.length;
  final bindingBytes = bundle.binding.canonicalBytes.length;

  test('the fixture is a published context of the size a real surface has', () {
    expect(bundle.graph.artifactIdentities.length, 141);
    expect(bundle.manifest.points.length, 46);
    expect(bundle.manifest.localManifests.length, 141);
    expect(manifestBytes, greaterThan(180 * 1024));
    expect(manifestBytes, lessThan(200 * 1024));
  });

  test('every document the cross-check reads holds its encoding', () {
    expect(bundle.revision, isA<ImmutableCanonicalDocument>());
    expect(bundle.graph, isA<ImmutableCanonicalDocument>());
    expect(bundle.manifest, isA<ImmutableCanonicalDocument>());
    expect(bundle.binding, isA<ImmutableCanonicalDocument>());
  });

  test(
      'comparing held digests reaches the same verdict as comparing the whole '
      'documents', () {
    // What the strict decode holds: a binding decoded from its own bytes, and
    // the revision, graph and manifest decoded from theirs.
    final binding = MeasurementPublicationBindingV1.fromCanonicalBytes(
      bundle.binding.canonicalBytes,
    );
    final revision = PublishedSurfaceRevisionV1.fromCanonicalBytes(
      bundle.revision.canonicalBytes,
    );
    final graph = ExactArtifactGraphV1.fromCanonicalBytes(
      bundle.graph.canonicalBytes,
    );
    final manifest = CompleteMeasurementManifestV1.fromCanonicalBytes(
      bundle.manifest.canonicalBytes,
    );
    final reference = bundle.binding.reference;

    expect(
      _wholeDocumentChain(binding, reference, revision, graph, manifest),
      isFalse,
    );
    expect(
      _heldDigestChain(binding, reference, revision, graph, manifest),
      isFalse,
    );

    // One document swapped for another surface's: both chains refuse, and
    // they refuse on the same document.
    final other = _publishedBundle(
      artifacts: 3,
      measuredArtifacts: 2,
      pointsPerArtifact: 1,
    );
    expect(
      _wholeDocumentChain(binding, reference, revision, graph, other.manifest),
      isTrue,
    );
    expect(
      _heldDigestChain(binding, reference, revision, graph, other.manifest),
      isTrue,
    );
    expect(
      _wholeDocumentChain(binding, reference, revision, other.graph, manifest),
      isTrue,
    );
    expect(
      _heldDigestChain(binding, reference, revision, other.graph, manifest),
      isTrue,
    );
    expect(
      _wholeDocumentChain(binding, reference, other.revision, graph, manifest),
      isTrue,
    );
    expect(
      _heldDigestChain(binding, reference, other.revision, graph, manifest),
      isTrue,
    );
  });

  test(
      'a document that holds its encoding encodes once, whatever is read from '
      'it', () {
    final payload = bundle.manifest.toJson();

    _encodes = 0;
    final holding = _HoldingDocument(payload);
    final heldReads = _readBytesAndDigest(holding, times: 10);
    final heldEncodes = _encodes;

    _encodes = 0;
    final reEncoding = _ReEncodingDocument(payload);
    final freshReads = _readBytesAndDigest(reEncoding, times: 10);
    final freshEncodes = _encodes;

    expect(heldEncodes, 1);
    expect(freshEncodes, 20);
    expect(heldReads, freshReads);
    expect(holding.canonicalDigest, reEncoding.canonicalDigest);
  });

  test(
      'the cross-check encodes nothing once its documents hold their '
      'encodings', () {
    final payloads = <Map<String, Object?>>[
      bundle.binding.toJson(),
      bundle.revision.toJson(),
      bundle.graph.toJson(),
      bundle.manifest.toJson(),
    ];

    final held = _crossCheckEncodes(payloads, holdsItsEncoding: true);
    final fresh = _crossCheckEncodes(payloads, holdsItsEncoding: false);

    // Decoding reads each document once, which is where a document that
    // holds its encoding takes it.
    expect(held.decode, 7);
    expect(held.wholeDocuments, 0);
    expect(held.heldDigests, 0);

    expect(fresh.decode, 7);
    expect(fresh.wholeDocuments, 7);
    expect(fresh.heldDigests, 7);

    // One warm encode of each document the cross-check reads, measured.
    final bindingEncode = _encodeMicros(bundle.binding.toJson());
    final revisionEncode = _encodeMicros(bundle.revision.toJson());
    final graphEncode = _encodeMicros(bundle.graph.toJson());
    final manifestEncode = _encodeMicros(bundle.manifest.toJson());
    final before =
        bindingEncode + 2 * (revisionEncode + graphEncode + manifestEncode);
    final comparedBefore = 2 *
        (bundle.revision.canonicalBytes.length +
            bundle.graph.canonicalBytes.length +
            manifestBytes);

    // The measured figures belong beside the counts, and a test reports
    // them the only way it can.
    // ignore: avoid_print
    print(
      'CANONICAL manifest=$manifestBytes/${_ms(manifestEncode)}ms '
      'binding=$bindingBytes/${_ms(bindingEncode)}ms '
      'graph=${bundle.graph.canonicalBytes.length}/${_ms(graphEncode)}ms '
      'revision=${bundle.revision.canonicalBytes.length}'
      '/${_ms(revisionEncode)}ms '
      'before=${fresh.wholeDocuments}encodes/${_ms(before)}ms'
      '/${comparedBefore}bytesCompared '
      'after=${held.heldDigests}encodes/192bytesCompared',
    );
  });
}

/// The comparison the strict decode ran before: three whole documents.
bool _wholeDocumentChain(
  MeasurementPublicationBindingV1 binding,
  MeasurementPublicationBindingReferenceV1 bindingReference,
  PublishedSurfaceRevisionV1 revision,
  ExactArtifactGraphV1 graph,
  CompleteMeasurementManifestV1 manifest,
) =>
    binding.reference != bindingReference ||
    binding.publishedSurfaceRevision != revision ||
    binding.exactArtifactGraph != graph ||
    binding.completeMeasurementManifest != manifest;

/// The comparison it runs now: three held digests.
bool _heldDigestChain(
  MeasurementPublicationBindingV1 binding,
  MeasurementPublicationBindingReferenceV1 bindingReference,
  PublishedSurfaceRevisionV1 revision,
  ExactArtifactGraphV1 graph,
  CompleteMeasurementManifestV1 manifest,
) =>
    binding.reference != bindingReference ||
    binding.publishedSurfaceRevision.canonicalDigest !=
        revision.canonicalDigest ||
    binding.exactArtifactGraph.canonicalDigest != graph.canonicalDigest ||
    binding.completeMeasurementManifest.canonicalDigest !=
        manifest.canonicalDigest;

/// Encodes performed while the documents are decoded, and while each
/// comparison chain runs over them.
typedef _CrossCheckEncodes = ({
  int decode,
  int wholeDocuments,
  int heldDigests,
});

/// Runs both chains over documents carrying [payloads] — the binding first,
/// then the revision, graph and manifest — and counts what each encodes.
_CrossCheckEncodes _crossCheckEncodes(
  List<Map<String, Object?>> payloads, {
  required bool holdsItsEncoding,
}) {
  CanonicalDocument document(Map<String, Object?> payload) => holdsItsEncoding
      ? _HoldingDocument(payload)
      : _ReEncodingDocument(payload);

  // The digest the row carries for the binding, taken outside the count.
  final bindingDigest = canonicalSha256(
    CanonicalHashDomain.completeManifest,
    CanonicalJsonCodec.encode(payloads.first),
  );

  _encodes = 0;
  final binding = document(payloads.first);
  final carried = [for (final payload in payloads.skip(1)) document(payload)];
  final stored = [for (final payload in payloads.skip(1)) document(payload)];
  // Every decode proves its own round trip, which reads the bytes once.
  for (final one in [binding, ...carried, ...stored]) {
    one.canonicalBytes;
  }
  final decode = _encodes;

  _encodes = 0;
  final wholeVerdict = binding.canonicalDigest != bindingDigest ||
      carried[0] != stored[0] ||
      carried[1] != stored[1] ||
      carried[2] != stored[2];
  final wholeDocuments = _encodes;

  _encodes = 0;
  final digestVerdict = binding.canonicalDigest != bindingDigest ||
      carried[0].canonicalDigest != stored[0].canonicalDigest ||
      carried[1].canonicalDigest != stored[1].canonicalDigest ||
      carried[2].canonicalDigest != stored[2].canonicalDigest;
  final heldDigests = _encodes;

  if (wholeVerdict || digestVerdict) {
    throw StateError('Matching documents must not diverge');
  }
  return (
    decode: decode,
    wholeDocuments: wholeDocuments,
    heldDigests: heldDigests,
  );
}

/// Reads the bytes and the digest [times] over, answering what was read so
/// the reads cannot be taken for dead code.
int _readBytesAndDigest(CanonicalDocument document, {required int times}) {
  var read = 0;
  for (var pass = 0; pass < times; pass += 1) {
    read +=
        document.canonicalBytes.length + document.canonicalDigest.hex.length;
  }
  return read;
}

int _encodeMicros(Map<String, Object?> payload) {
  final watch = Stopwatch()..start();
  for (var run = 0; run < 10; run += 1) {
    CanonicalJsonCodec.encode(payload);
  }
  watch.stop();
  return watch.elapsedMicroseconds ~/ 10;
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

/// Encodes counted across the documents below.
int _encodes = 0;

/// A document whose content is fixed, so it encodes once and holds it.
final class _HoldingDocument extends CanonicalDocument
    implements ImmutableCanonicalDocument {
  _HoldingDocument(this._payload);

  final Map<String, Object?> _payload;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.completeManifest;

  @override
  Map<String, Object?> toJson() {
    _encodes += 1;
    return _payload;
  }
}

/// A document that does not declare its content fixed, so every read of its
/// bytes encodes it again.
final class _ReEncodingDocument extends CanonicalDocument {
  _ReEncodingDocument(this._payload);

  final Map<String, Object?> _payload;

  @override
  CanonicalHashDomain get hashDomain => CanonicalHashDomain.completeManifest;

  @override
  Map<String, Object?> toJson() {
    _encodes += 1;
    return _payload;
  }
}

final _target = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(37),
  runtimePlane: RuntimePlane.sandbox,
);

/// One published surface with its graph, manifest and binding.
final class _PublishedBundle {
  const _PublishedBundle({
    required this.revision,
    required this.graph,
    required this.manifest,
    required this.binding,
  });

  final PublishedSurfaceRevisionV1 revision;
  final ExactArtifactGraphV1 graph;
  final CompleteMeasurementManifestV1 manifest;
  final MeasurementPublicationBindingV1 binding;
}

String _hex(int value) => value.toRadixString(16).padLeft(64, '0');

String _ordinal(int index) => index.toString().padLeft(4, '0');

String _carrier(ArtifactOccurrenceEdgeToken edge, int index) {
  final localToken = Uint8List(24);
  for (var byte = 0; byte < localToken.length; byte += 1) {
    localToken[byte] = (index * 7 + byte * 31 + 1) & 0xff;
  }
  final edgePart =
      base64Url.encode(utf8.encode(edge.value)).replaceAll('=', '');
  final tokenPart = base64Url.encode(localToken).replaceAll('=', '');
  return 'mrv1.$edgePart.$tokenPart';
}

_PublishedBundle _publishedBundle({
  required int artifacts,
  required int measuredArtifacts,
  required int pointsPerArtifact,
}) {
  final surfaceId = SurfaceId('surface.published');
  final surfaceRevisionId = SurfaceRevisionId('surface.published.v1');
  final rootArtifactId = ArtifactId('artifact.root');
  final rootEdgeToken = ArtifactOccurrenceEdgeToken('edge.root');
  final privacyPolicyRevisionId = AuthorityRevisionId('privacy.published.v1');
  final collectionBudgetRevisionId = AuthorityRevisionId('budget.published.v1');

  final rootIdentity = PublishedArtifactIdentityV1(
    surfaceRevisionId: surfaceRevisionId,
    artifactId: rootArtifactId,
    artifactKind: ArtifactKindId('flutter.scaffold'),
    contentHash: CanonicalDigest(_hex(0)),
  );
  final rootEdge = ArtifactOccurrenceEdgeV1(
    edgeToken: rootEdgeToken,
    artifactId: rootArtifactId,
    artifactIdentityHash: rootIdentity.canonicalDigest,
  );

  final leafIdentities = <PublishedArtifactIdentityV1>[];
  final leafEdges = <ArtifactOccurrenceEdgeV1>[];
  for (var index = 0; index < artifacts; index += 1) {
    final identity = PublishedArtifactIdentityV1(
      surfaceRevisionId: surfaceRevisionId,
      artifactId: ArtifactId('artifact.${_ordinal(index)}'),
      artifactKind: ArtifactKindId('flutter.button'),
      contentHash: CanonicalDigest(_hex(index + 1)),
    );
    leafIdentities.add(identity);
    leafEdges.add(
      ArtifactOccurrenceEdgeV1(
        edgeToken: ArtifactOccurrenceEdgeToken('edge.${_ordinal(index)}'),
        parentEdgeToken: rootEdgeToken,
        artifactId: identity.artifactId,
        artifactIdentityHash: identity.canonicalDigest,
      ),
    );
  }

  final graph = ExactArtifactGraphV1(
    surfaceRevisionId: surfaceRevisionId,
    rootEdgeToken: rootEdgeToken,
    artifactIdentities: [rootIdentity, ...leafIdentities],
    occurrenceEdges: [rootEdge, ...leafEdges],
  );
  final artifactGraphHash = graph.canonicalDigest;

  final rootNode = AncestryNodeRefV1(
    artifactOccurrenceEdgeToken: rootEdgeToken,
    canonicalNodeToken: NodeTokenId('node.root'),
  );
  final parentEdges = <CanonicalNodeParentEdgeV1>[
    CanonicalNodeParentEdgeV1(node: rootNode),
  ];
  final localManifests = <LocalMeasurementManifestV1>[];
  final publishedArtifacts = <PublishedArtifactV1>[];
  final mountedRoutes = <MeasurementPublicationMountedArtifactRoutesV1>[];
  var routeIndex = 0;

  for (var index = 0; index < artifacts; index += 1) {
    final identity = leafIdentities[index];
    final edge = leafEdges[index];
    final points = <MeasurementPointOccurrenceV1>[];
    final references = <GeneratedPointReferenceV1>[];
    final routes = <MeasurementPublicationRouteV1>[];
    // Only the artifacts a surface actually measures carry points; the rest
    // are ordinary widgets in the same published tree, each of which still
    // has its own canonical node under the root.
    final measured = index < measuredArtifacts ? pointsPerArtifact : 0;
    final rootNodeOfArtifact = AncestryNodeRefV1(
      artifactOccurrenceEdgeToken: edge.edgeToken,
      canonicalNodeToken: NodeTokenId('node.${_ordinal(index)}.0'),
    );
    parentEdges.add(
      CanonicalNodeParentEdgeV1(node: rootNodeOfArtifact, parent: rootNode),
    );

    for (var position = 0; position < measured; position += 1) {
      final node = position == 0
          ? rootNodeOfArtifact
          : AncestryNodeRefV1(
              artifactOccurrenceEdgeToken: edge.edgeToken,
              canonicalNodeToken: NodeTokenId(
                'node.${_ordinal(index)}.$position',
              ),
            );
      if (position > 0) {
        parentEdges.add(
          CanonicalNodeParentEdgeV1(node: node, parent: rootNodeOfArtifact),
        );
      }
      final point = MeasurementPointOccurrenceV1(
        target: _target,
        surfaceRevisionId: surfaceRevisionId,
        artifactGraphHash: artifactGraphHash,
        artifactId: identity.artifactId,
        artifactOccurrenceEdgeToken: edge.edgeToken,
        artifactContentHash: identity.contentHash,
        canonicalNodeToken: node.canonicalNodeToken,
        capabilityKind: MeasurementCapabilityKind.sourceInteraction,
        sourceEventIdentity: SourceEventIdentity('onPressed'),
        normalizedInteractionKind: NormalizedInteractionKind.activate,
        privacyClass: MeasurementPrivacyClass.nonSensitive,
        semanticValueClass: SemanticValueClass.activityOnly,
        collectionClass: MeasurementCollectionClass.tier1KeepAll,
        lineageId: PointLineageId('lineage.${_ordinal(index)}.$position'),
        displayMetadataRef: DisplayMetadataRef(
          'display.${_ordinal(index)}.$position',
        ),
      );
      points.add(point);
      references.add(
        GeneratedPointReferenceV1(
          referenceId: GeneratedReferenceId(
            'reference.${_ordinal(index)}.$position',
          ),
          target: _target,
          surfaceRevisionId: surfaceRevisionId,
          artifactGraphHash: artifactGraphHash,
          occurrenceId: point.occurrenceId,
          lineageId: point.lineageId,
          sourceEventIdentity: point.sourceEventIdentity!,
          dartSymbol: GeneratedDartSymbol(
            'onPressed${_ordinal(index)}$position',
          ),
        ),
      );
      routes.add(
        MeasurementPublicationRouteV1(
          opaqueRouteToken: OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
            _carrier(edge.edgeToken, routeIndex),
          ),
          occurrenceId: point.occurrenceId,
          lineageId: point.lineageId,
        ),
      );
      routeIndex += 1;
    }

    final local = LocalMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.${_ordinal(index)}'),
      target: _target,
      surfaceRevisionId: surfaceRevisionId,
      artifactGraphHash: artifactGraphHash,
      artifactId: identity.artifactId,
      artifactContentHash: identity.contentHash,
      childArtifactIds: const [],
      points: points,
      generatedReferences: references,
      generatedPresentationReferences: const [],
      privacyPolicyRevisionId: privacyPolicyRevisionId,
      collectionBudgetRevisionId: collectionBudgetRevisionId,
    );
    localManifests.add(local);
    publishedArtifacts.add(
      PublishedArtifactV1(
        identity: identity,
        childArtifactIds: const [],
        localMeasurementManifest: local,
      ),
    );
    if (routes.isNotEmpty) {
      mountedRoutes.add(
        MeasurementPublicationMountedArtifactRoutesV1(
          artifactOccurrenceEdgeToken: edge.edgeToken,
          routes: routes,
        ),
      );
    }
  }

  final childArtifactIds = [
    for (final identity in leafIdentities) identity.artifactId,
  ];
  final rootLocal = LocalMeasurementManifestV1(
    manifestId: MeasurementManifestId('manifest.root'),
    target: _target,
    surfaceRevisionId: surfaceRevisionId,
    artifactGraphHash: artifactGraphHash,
    artifactId: rootArtifactId,
    artifactContentHash: rootIdentity.contentHash,
    childArtifactIds: childArtifactIds,
    points: const [],
    generatedReferences: const [],
    generatedPresentationReferences: const [],
    privacyPolicyRevisionId: privacyPolicyRevisionId,
    collectionBudgetRevisionId: collectionBudgetRevisionId,
  );
  localManifests.add(rootLocal);
  publishedArtifacts.add(
    PublishedArtifactV1(
      identity: rootIdentity,
      childArtifactIds: childArtifactIds,
      localMeasurementManifest: rootLocal,
    ),
  );

  final manifest = CompleteMeasurementManifestV1(
    manifestId: MeasurementManifestId('manifest.published.complete'),
    target: _target,
    surfaceId: surfaceId,
    surfaceRevisionId: surfaceRevisionId,
    rootArtifactId: rootArtifactId,
    artifactGraphHash: artifactGraphHash,
    localManifests: localManifests,
    nodeAncestryIndex: CanonicalNodeAncestryIndexV1(
      rootNode: rootNode,
      directParentEdges: parentEdges,
    ),
    privacyPolicyRevisionId: privacyPolicyRevisionId,
    collectionBudgetRevisionId: collectionBudgetRevisionId,
  );

  final revision = PublishedSurfaceRevisionV1(
    revisionId: surfaceRevisionId,
    surfaceIdentity: PublishedSurfaceIdentityV1(
      target: _target,
      surfaceId: surfaceId,
    ),
    analyticsSurfaceKey: AnalyticsSurfaceKey('published-surface'),
    deliverySurfaceType: DeliverySurfaceTypeId('published.surface'),
    revisionOrdinal: 1,
    rootArtifactId: rootArtifactId,
    rootArtifactOccurrenceEdgeToken: rootEdgeToken,
    artifactGraphHash: artifactGraphHash,
    measurementManifestHash: manifest.canonicalDigest,
    measurementSchemaVersion: 1,
    minimumMeasurementClient: 1,
  );

  final binding = MeasurementPublicationBindingV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId('authority.published'),
      externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
      candidateReference: MeasurementPublicationCandidateReferenceV1(
        candidateDigest: CanonicalDigest('c' * 64),
        selectedPublicationManifestDigest: CanonicalDigest('a' * 64),
        declaredArtifactBytesDigest: CanonicalDigest('b' * 64),
        assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
        measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
      ),
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: CanonicalDigest('b' * 64),
    ),
    publishedSurfaceRevision: revision,
    exactArtifactGraph: graph,
    publishedArtifacts: publishedArtifacts,
    completeMeasurementManifest: manifest,
    mountedArtifactRoutes: mountedRoutes,
    mountedArtifactPresentationRoutes: const [],
  );

  return _PublishedBundle(
    revision: revision,
    graph: graph,
    manifest: manifest,
    binding: binding,
  );
}
