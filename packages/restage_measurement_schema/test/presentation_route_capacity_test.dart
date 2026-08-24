import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('shared route capacity accepts an exact 1024-route mix', () {
    final plan = _routePlan(sourceRouteCount: 1023, presentationRouteCount: 1);
    final draft = MeasurementPublicationDraftV1(
      routePlan: plan,
      artifacts: [
        MeasurementPublicationDraftArtifactV1(
          artifactId: ArtifactId('artifact.capacity'),
          artifactKind: ArtifactKindId('rfw.blob'),
          contentHash: CanonicalDigest('a' * 64),
          occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.capacity'),
          localManifestId: MeasurementManifestId('manifest.capacity.local'),
        ),
      ],
    );

    expect(plan.routes.length + plan.presentationRoutes.length, 1024);
    expect(draft.routes.length + draft.presentationRoutes.length, 1024);
  });

  test('every 1025 source and presentation mix fails before draft output', () {
    for (final mix in <(int, int)>[(1024, 1), (1, 1024)]) {
      expect(
        () => _routePlan(
          sourceRouteCount: mix.$1,
          presentationRouteCount: mix.$2,
        ),
        throwsArgumentError,
      );
    }
  });

  test('route-plan and draft decoders reject a raw 1025-route mix', () {
    final plan = _routePlan(sourceRouteCount: 1023, presentationRouteCount: 1);
    final planJson = plan.toJson();
    expect(
      () => MeasurementPublicationRoutePlanV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode(<String, Object?>{
          ...planJson,
          'routeSeeds': [
            ...(planJson['routeSeeds']! as List<Object?>),
            (planJson['routeSeeds']! as List<Object?>).first,
          ],
        }),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );

    final draft = MeasurementPublicationDraftV1(
      routePlan: plan,
      artifacts: [
        MeasurementPublicationDraftArtifactV1(
          artifactId: ArtifactId('artifact.capacity'),
          artifactKind: ArtifactKindId('rfw.blob'),
          contentHash: CanonicalDigest('a' * 64),
          occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.capacity'),
          localManifestId: MeasurementManifestId('manifest.capacity.local'),
        ),
      ],
    );
    final draftJson = draft.toJson();
    expect(
      () => MeasurementPublicationDraftV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode(<String, Object?>{
          ...draftJson,
          'routes': [
            ...(draftJson['routes']! as List<Object?>),
            (draftJson['routes']! as List<Object?>).first,
          ],
        }),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
  });
}

MeasurementPublicationRoutePlanV1 _routePlan({
  required int sourceRouteCount,
  required int presentationRouteCount,
}) {
  final edge = ArtifactOccurrenceEdgeToken('edge.capacity');
  final rootCode = CodeIdentityId('code.capacity.root');
  final sourceCodes = <CodeIdentityId>[
    for (var index = 0; index < sourceRouteCount; index += 1)
      CodeIdentityId('code.capacity.source.$index'),
  ];
  final presentationCodes = <CodeIdentityId>[
    for (var index = 0; index < presentationRouteCount; index += 1)
      CodeIdentityId('code.capacity.presentation.$index'),
  ];
  return MeasurementPublicationRoutePlanV1(
    surfaceId: SurfaceId('surface.capacity'),
    analyticsSurfaceKey: AnalyticsSurfaceKey('capacity'),
    deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
    minimumMeasurementClient: 2,
    completeManifestId: MeasurementManifestId('manifest.capacity'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.capacity'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.capacity'),
    artifacts: [
      MeasurementPublicationRouteArtifactV1(
        artifactId: ArtifactId('artifact.capacity'),
        artifactKind: ArtifactKindId('rfw.blob'),
        occurrenceEdgeToken: edge,
        localManifestId: MeasurementManifestId('manifest.capacity.local'),
      ),
    ],
    codeIdentityBindings: [
      CodeIdentityBindingV1(
        codeIdentityId: rootCode,
        canonicalNodeTokenId: NodeTokenId('node.capacity.root'),
      ),
      for (var index = 0; index < sourceCodes.length; index += 1)
        CodeIdentityBindingV1(
          codeIdentityId: sourceCodes[index],
          canonicalNodeTokenId: NodeTokenId('node.capacity.source.$index'),
        ),
      for (var index = 0; index < presentationCodes.length; index += 1)
        CodeIdentityBindingV1(
          codeIdentityId: presentationCodes[index],
          canonicalNodeTokenId:
              NodeTokenId('node.capacity.presentation.$index'),
        ),
    ],
    nodes: [
      MeasurementPublicationDraftNodeV1(
        codeIdentityId: rootCode,
        artifactOccurrenceEdgeToken: edge,
      ),
      for (final code in sourceCodes)
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: code,
          artifactOccurrenceEdgeToken: edge,
          parentCodeIdentityId: rootCode,
        ),
      for (final code in presentationCodes)
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: code,
          artifactOccurrenceEdgeToken: edge,
          parentCodeIdentityId: rootCode,
        ),
    ],
    events: [
      for (var index = 0; index < sourceCodes.length; index += 1)
        MeasurementPublicationDraftEventV1(
          nodeCodeIdentityId: sourceCodes[index],
          sourceEventIdentity: SourceEventIdentity('onTap$index'),
          lineageId: PointLineageId('lineage.capacity.source.$index'),
          generatedReferenceId: GeneratedReferenceId(
            'reference.capacity.source.$index',
          ),
          dartSymbol: GeneratedDartSymbol('capacitySource$index'),
          displayMetadataRef:
              DisplayMetadataRef('display.capacity.source.$index'),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier2Coalesced,
        ),
    ],
    routeSeeds: [
      for (var index = 0; index < sourceCodes.length; index += 1)
        MeasurementPublicationDraftRouteSeedV1(
          generatedReferenceId: GeneratedReferenceId(
            'reference.capacity.source.$index',
          ),
          artifactOccurrenceEdgeToken: edge,
        ),
    ],
    presentations: [
      for (var index = 0; index < presentationCodes.length; index += 1)
        MeasurementPublicationDraftPresentationV1(
          nodeCodeIdentityId: presentationCodes[index],
          lineageId: PointLineageId('lineage.capacity.presentation.$index'),
          generatedPresentationReferenceId: GeneratedPresentationReferenceId(
            'presentation-reference.capacity.$index',
          ),
          displayMetadataRef:
              DisplayMetadataRef('display.capacity.presentation.$index'),
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          collectionClass: MeasurementCollectionClass.tier2Coalesced,
        ),
    ],
    presentationRouteSeeds: [
      for (var index = 0; index < presentationCodes.length; index += 1)
        MeasurementPublicationDraftPresentationRouteSeedV1(
          generatedPresentationReferenceId: GeneratedPresentationReferenceId(
            'presentation-reference.capacity.$index',
          ),
          artifactOccurrenceEdgeToken: edge,
        ),
    ],
    lineageIntents: [
      for (var index = 0; index < sourceCodes.length; index += 1)
        MeasurementPublicationLineageIntentV1(
          transitionId:
              LineageTransitionId('transition.capacity.source.$index'),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementPublicationCurrentEndpointIntentV1(
              generatedReferenceId: GeneratedReferenceId(
                'reference.capacity.source.$index',
              ),
              lineageId: PointLineageId('lineage.capacity.source.$index'),
            ),
          ],
        ),
    ],
  );
}
