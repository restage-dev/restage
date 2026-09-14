import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

final class AdmittedBundledPublicationFixture {
  AdmittedBundledPublicationFixture._(this.binding, this.entry, this.port);

  static const artifactBytes = <int>[1, 2, 3];

  factory AdmittedBundledPublicationFixture.build() {
    final target = TargetCoordinate(
      organizationId: OrganizationId(101),
      appId: ApplicationId(202),
      environmentTargetId: EnvironmentTargetId(303),
      namedEnvironmentId: NamedEnvironmentId(404),
      runtimePlane: RuntimePlane.sandbox,
    );
    final surfaceId = SurfaceId('$kMintedSurfaceIdPrefix${'a' * 64}');
    final surfaceRevisionId =
        SurfaceRevisionId('$kMintedSurfaceRevisionIdPrefix${'b' * 64}');
    final artifactId = ArtifactId('artifact.bundled-root');
    final artifactContentHash =
        CanonicalDigest(crypto.sha256.convert(artifactBytes).toString());
    final artifactIdentity = PublishedArtifactIdentityV1(
      surfaceRevisionId: surfaceRevisionId,
      artifactId: artifactId,
      artifactKind: ArtifactKindId('rfw.blob'),
      contentHash: artifactContentHash,
    );
    final rootEdgeToken = ArtifactOccurrenceEdgeToken('edge.bundled-root');
    final graph = ExactArtifactGraphV1(
      surfaceRevisionId: surfaceRevisionId,
      rootEdgeToken: rootEdgeToken,
      artifactIdentities: [artifactIdentity],
      occurrenceEdges: [
        ArtifactOccurrenceEdgeV1(
          edgeToken: rootEdgeToken,
          artifactId: artifactId,
          artifactIdentityHash: artifactIdentity.canonicalDigest,
        ),
      ],
    );

    MeasurementPointOccurrenceV1 occurrence({
      required String nodeToken,
      required String lineageId,
      required String displayRef,
    }) =>
        MeasurementPointOccurrenceV1(
          target: target,
          surfaceRevisionId: surfaceRevisionId,
          artifactGraphHash: graph.canonicalDigest,
          artifactId: artifactId,
          artifactOccurrenceEdgeToken: rootEdgeToken,
          artifactContentHash: artifactContentHash,
          canonicalNodeToken: NodeTokenId(nodeToken),
          capabilityKind: MeasurementCapabilityKind.sourceInteraction,
          sourceEventIdentity: SourceEventIdentity('onPressed'),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
          lineageId: PointLineageId(lineageId),
          displayMetadataRef: DisplayMetadataRef(displayRef),
        );

    final leftOccurrence = occurrence(
      nodeToken: 'node.bundled-left',
      lineageId: 'lineage.bundled-left',
      displayRef: 'display.bundled-left',
    );
    final rightOccurrence = occurrence(
      nodeToken: 'node.bundled-right',
      lineageId: 'lineage.bundled-right',
      displayRef: 'display.bundled-right',
    );
    final localManifest = LocalMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.bundled-local'),
      target: target,
      surfaceRevisionId: surfaceRevisionId,
      artifactGraphHash: graph.canonicalDigest,
      artifactId: artifactId,
      artifactContentHash: artifactContentHash,
      childArtifactIds: const [],
      points: [leftOccurrence, rightOccurrence],
      generatedReferences: [
        GeneratedPointReferenceV1(
          referenceId: GeneratedReferenceId('reference.bundled-left'),
          target: target,
          surfaceRevisionId: surfaceRevisionId,
          artifactGraphHash: graph.canonicalDigest,
          occurrenceId: leftOccurrence.occurrenceId,
          lineageId: leftOccurrence.lineageId,
          sourceEventIdentity: leftOccurrence.sourceEventIdentity!,
          dartSymbol: GeneratedDartSymbol('leftOnPressed'),
        ),
        GeneratedPointReferenceV1(
          referenceId: GeneratedReferenceId('reference.bundled-right'),
          target: target,
          surfaceRevisionId: surfaceRevisionId,
          artifactGraphHash: graph.canonicalDigest,
          occurrenceId: rightOccurrence.occurrenceId,
          lineageId: rightOccurrence.lineageId,
          sourceEventIdentity: rightOccurrence.sourceEventIdentity!,
          dartSymbol: GeneratedDartSymbol('rightOnPressed'),
        ),
      ],
      generatedPresentationReferences: const [],
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.fixture.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId(
        'budget.fixture.v1',
      ),
    );
    final leftNode = AncestryNodeRefV1(
      artifactOccurrenceEdgeToken: rootEdgeToken,
      canonicalNodeToken: leftOccurrence.canonicalNodeToken,
    );
    final rightNode = AncestryNodeRefV1(
      artifactOccurrenceEdgeToken: rootEdgeToken,
      canonicalNodeToken: rightOccurrence.canonicalNodeToken,
    );
    final completeManifest = CompleteMeasurementManifestV1(
      manifestId: MeasurementManifestId('manifest.bundled-complete'),
      target: target,
      surfaceId: surfaceId,
      surfaceRevisionId: surfaceRevisionId,
      rootArtifactId: artifactId,
      artifactGraphHash: graph.canonicalDigest,
      localManifests: [localManifest],
      nodeAncestryIndex: CanonicalNodeAncestryIndexV1(
        rootNode: leftNode,
        directParentEdges: [
          CanonicalNodeParentEdgeV1(node: leftNode),
          CanonicalNodeParentEdgeV1(node: rightNode, parent: leftNode),
        ],
      ),
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.fixture.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId(
        'budget.fixture.v1',
      ),
    );
    final publishedRevision = PublishedSurfaceRevisionV1(
      revisionId: surfaceRevisionId,
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      analyticsSurfaceKey: AnalyticsSurfaceKey('bundled-fixture'),
      deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
      revisionOrdinal: 2,
      rootArtifactId: artifactId,
      rootArtifactOccurrenceEdgeToken: rootEdgeToken,
      artifactGraphHash: graph.canonicalDigest,
      measurementManifestHash: completeManifest.canonicalDigest,
      measurementSchemaVersion: 1,
      minimumMeasurementClient: 1,
    );

    final publicationArtifacts = [
      MeasurementPublicationDraftArtifactV1(
        artifactId: artifactId,
        artifactKind: ArtifactKindId('rfw.blob'),
        contentHash: artifactContentHash,
        occurrenceEdgeToken: rootEdgeToken,
        localManifestId: localManifest.manifestId,
      ),
    ];
    final publicationRoutePlan = MeasurementPublicationRoutePlanV1(
      surfaceId: surfaceId,
      analyticsSurfaceKey: AnalyticsSurfaceKey('bundled-fixture'),
      deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
      minimumMeasurementClient: 1,
      completeManifestId: completeManifest.manifestId,
      privacyPolicyRevisionId: AuthorityRevisionId('privacy.fixture.v1'),
      collectionBudgetRevisionId: AuthorityRevisionId(
        'budget.fixture.v1',
      ),
      artifacts: [
        MeasurementPublicationRouteArtifactV1(
          artifactId: artifactId,
          artifactKind: ArtifactKindId('rfw.blob'),
          occurrenceEdgeToken: rootEdgeToken,
          localManifestId: localManifest.manifestId,
        ),
      ],
      codeIdentityBindings: [
        CodeIdentityBindingV1(
          codeIdentityId: CodeIdentityId('code.bundled-left'),
          canonicalNodeTokenId: leftOccurrence.canonicalNodeToken,
        ),
        CodeIdentityBindingV1(
          codeIdentityId: CodeIdentityId('code.bundled-right'),
          canonicalNodeTokenId: rightOccurrence.canonicalNodeToken,
        ),
      ],
      nodes: [
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: CodeIdentityId('code.bundled-left'),
          artifactOccurrenceEdgeToken: rootEdgeToken,
        ),
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: CodeIdentityId('code.bundled-right'),
          artifactOccurrenceEdgeToken: rootEdgeToken,
          parentCodeIdentityId: CodeIdentityId('code.bundled-left'),
        ),
      ],
      events: [
        MeasurementPublicationDraftEventV1(
          nodeCodeIdentityId: CodeIdentityId('code.bundled-left'),
          sourceEventIdentity: leftOccurrence.sourceEventIdentity!,
          lineageId: leftOccurrence.lineageId,
          generatedReferenceId: GeneratedReferenceId('reference.bundled-left'),
          dartSymbol: GeneratedDartSymbol('leftOnPressed'),
          displayMetadataRef: leftOccurrence.displayMetadataRef,
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
        MeasurementPublicationDraftEventV1(
          nodeCodeIdentityId: CodeIdentityId('code.bundled-right'),
          sourceEventIdentity: rightOccurrence.sourceEventIdentity!,
          lineageId: rightOccurrence.lineageId,
          generatedReferenceId: GeneratedReferenceId('reference.bundled-right'),
          dartSymbol: GeneratedDartSymbol('rightOnPressed'),
          displayMetadataRef: rightOccurrence.displayMetadataRef,
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
      ],
      routeSeeds: [
        MeasurementPublicationDraftRouteSeedV1(
          generatedReferenceId: GeneratedReferenceId('reference.bundled-left'),
          artifactOccurrenceEdgeToken: rootEdgeToken,
        ),
        MeasurementPublicationDraftRouteSeedV1(
          generatedReferenceId: GeneratedReferenceId('reference.bundled-right'),
          artifactOccurrenceEdgeToken: rootEdgeToken,
        ),
      ],
      presentations: const [],
      presentationRouteSeeds: const [],
      lineageIntents: [
        MeasurementPublicationLineageIntentV1(
          transitionId: LineageTransitionId('transition.bundled-draft-left'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementPublicationCurrentEndpointIntentV1(
              generatedReferenceId:
                  GeneratedReferenceId('reference.bundled-left'),
              lineageId: leftOccurrence.lineageId,
            ),
          ],
        ),
        MeasurementPublicationLineageIntentV1(
          transitionId: LineageTransitionId('transition.bundled-draft-right'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementPublicationCurrentEndpointIntentV1(
              generatedReferenceId:
                  GeneratedReferenceId('reference.bundled-right'),
              lineageId: rightOccurrence.lineageId,
            ),
          ],
        ),
      ],
    );
    final publicationDraft = MeasurementPublicationDraftV1(
      routePlan: publicationRoutePlan,
      artifacts: publicationArtifacts,
    );

    final tuple = MeasurementPublicationCandidateArtifactTupleV1(
      canonicalTupleBytes: CanonicalJsonCodec.encode({
        'byteLength': artifactBytes.length,
        'id': 'fixture-artifact',
        'kind': 'restageSurfacePublicationDeclaredArtifactTuple',
        'path': 'screen.rfw',
        'role': SurfacePublicationArtifactRole.screenBlob.wireName,
        'schemaVersion': 1,
        'sha256': crypto.sha256.convert(artifactBytes).toString(),
      }),
    );
    final preimage = BytesBuilder(copy: false)
      ..add(utf8.encode(
          'restage-surface-publication-declared-artifact-bytes-v1\u0000'))
      ..add(CanonicalJsonCodec.encode({
        'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
        'schemaVersion': 1,
        'tuples': [CanonicalJsonCodec.decode(tuple.canonicalTupleBytes)],
      }));
    final proof = MeasurementPublicationCandidateProofV1(
      selectedPublicationManifestCanonicalBytes: CanonicalJsonCodec.encode({
        'kind': 'fixtureSelectedManifest',
        'schemaVersion': 1,
      }),
      declaredArtifactTuples: [tuple],
      declaredArtifactBytesDigest: CanonicalDigest(
        crypto.sha256.convert(preimage.takeBytes()).toString(),
      ),
      assembledPublicationUploadCanonicalBytes: CanonicalJsonCodec.encode({
        'kind': 'fixtureAssembledUpload',
        'schemaVersion': 1,
      }),
      measurementPublicationDraft: publicationDraft,
    );
    final binding = MeasurementPublicationBindingV1(
      publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
        authorityId: MeasurementPublicationAuthorityId('authority.fixture.v1'),
        externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
        candidateReference: proof.reference,
        immutablePublicationDigest: CanonicalDigest('d' * 64),
        declaredArtifactBytesDigest: proof.declaredArtifactBytesDigest,
      ),
      publishedSurfaceRevision: publishedRevision,
      exactArtifactGraph: graph,
      publishedArtifacts: [
        PublishedArtifactV1(
          identity: artifactIdentity,
          childArtifactIds: const [],
          localMeasurementManifest: localManifest,
        )
      ],
      completeMeasurementManifest: completeManifest,
      mountedArtifactRoutes: [
        MeasurementPublicationMountedArtifactRoutesV1(
          artifactOccurrenceEdgeToken: rootEdgeToken,
          routes: [
            for (final point in [leftOccurrence, rightOccurrence])
              MeasurementPublicationRouteV1(
                opaqueRouteToken:
                    OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
                  'mrv1.${base64UrlEncode(utf8.encode(rootEdgeToken.value)).replaceAll('=', '')}.${(point == leftOccurrence ? 'A' : 'B') * 32}',
                ),
                occurrenceId: point.occurrenceId,
                lineageId: point.lineageId,
              ),
          ],
        )
      ],
      mountedArtifactPresentationRoutes: const [],
    );
    final entry = MeasurementPublicationBundledRegistryEntryV1(
      generatedPublicationLocator:
          MeasurementBundledGeneratedPublicationLocatorV1(
        assembledPublicationUploadDigest:
            proof.reference.assembledPublicationUploadDigest,
        declaredArtifactBytesDigest: proof.declaredArtifactBytesDigest,
        selectedPublicationManifestDigest:
            proof.reference.selectedPublicationManifestDigest,
      ),
      candidateProof: proof,
      candidateReference: proof.reference,
      declaredArtifactBytesDigest: proof.declaredArtifactBytesDigest,
      reference: binding.reference,
      binding: binding,
      registeredPublicationAttestation: RegisteredPublicationAttestationV1(
        bindingReference: binding.reference,
        attestationDigest: CanonicalDigest('f' * 64),
      ),
    );
    return AdmittedBundledPublicationFixture._(
      binding,
      entry,
      BundledMeasurementPublicationBindingReadPort(
        target: target,
        registry: MeasurementPublicationBundledRegistryV1(
            target: target, entries: [entry]),
        verifiedBundles: [
          RestageBundle(
            packageName: 'fixture',
            authoredLibraryPath: 'lib/app.dart',
            entries: [
              RestageBundleEntry(
                logicalPath: 'screen.rfw',
                role: RestageBundleEntryRole.screenBlob,
                bytes: artifactBytes,
              )
            ],
          )
        ],
      ),
    );
  }

  final MeasurementPublicationBindingV1 binding;
  final MeasurementPublicationBundledRegistryEntryV1 entry;
  final BundledMeasurementPublicationBindingReadPort port;
  TargetCoordinate get target => binding.completeMeasurementManifest.target;
  ExactMeasurementPublicationContextRefV1 get publicationContextRef =>
      ExactMeasurementPublicationContextRefV1(
        bindingReference: binding.reference,
        surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
        surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
        artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
        measurementManifestHash:
            binding.completeMeasurementManifest.canonicalDigest,
      );
}
