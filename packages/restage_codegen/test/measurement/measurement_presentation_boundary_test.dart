import 'package:restage_codegen/src/measurement/measurement_compiler_boundary.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_input.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('materializes only explicit RFW-derived presentation inputs', () {
    final result = MeasurementCompilerBoundary.produceBoundaryV1(_input());

    expect(result.disposition, MeasurementCompilerBoundaryDisposition.accepted);
    final manifest = result.completeMeasurementManifest!;
    final points = manifest.points
        .where(
          (point) =>
              point.capabilityKind == MeasurementCapabilityKind.presented,
        )
        .toList(growable: false);
    expect(points, hasLength(2));
    expect(
      points.map((point) => point.canonicalNodeToken.value).toSet(),
      {
        'node.rfw.catalog-one',
        'node.rfw.catalog-two',
      },
    );
    expect(
      points.map((point) => point.canonicalNodeToken.value),
      isNot(contains('node.source-event')),
    );
    expect(
      points.map((point) => point.canonicalNodeToken.value),
      isNot(contains('node.rfw-anchor')),
    );
    expect(manifest.generatedPresentationReferences, hasLength(2));
    expect(
      manifest.generatedPresentationReferences
          .map((reference) => reference.occurrenceId)
          .toSet(),
      points.map((point) => point.occurrenceId).toSet(),
    );
  });

  test('does not infer presentation points from generic nodes', () {
    final result = MeasurementCompilerBoundary.produceBoundaryV1(
      _input(includePresentations: false),
    );

    expect(result.disposition, MeasurementCompilerBoundaryDisposition.accepted);
    expect(
      result.completeMeasurementManifest!.points.where(
        (point) => point.capabilityKind == MeasurementCapabilityKind.presented,
      ),
      isEmpty,
    );
    expect(
      result.completeMeasurementManifest!.generatedPresentationReferences,
      isEmpty,
    );
  });

  test('explicit presentation witnesses ignore nonidentity publication data',
      () {
    final first = MeasurementCompilerBoundary.produceBoundaryV1(_input());
    final second = MeasurementCompilerBoundary.produceBoundaryV1(
      _input(
        analyticsSurfaceKey: 'presentation-boundary-renamed',
        minimumMeasurementClient: 3,
      ),
    );

    expect(
      _presentationWitnesses(first.completeMeasurementManifest!),
      _presentationWitnesses(second.completeMeasurementManifest!),
    );
  });
}

List<String> _presentationWitnesses(CompleteMeasurementManifestV1 manifest) {
  final witnesses = [
    for (final reference in manifest.generatedPresentationReferences)
      '${reference.referenceId.value}\u0000'
          '${reference.lineageId.value}\u0000'
          '${reference.displayMetadataRef.value}\u0000'
          '${reference.occurrenceId.hex}',
  ]..sort();
  return witnesses;
}

MeasurementCompilerBoundaryInput _input({
  String analyticsSurfaceKey = 'presentation-boundary',
  int minimumMeasurementClient = 2,
  bool includePresentations = true,
}) {
  final target = TargetCoordinate(
    organizationId: OrganizationId(101),
    appId: ApplicationId(103),
    environmentTargetId: EnvironmentTargetId(107),
    namedEnvironmentId: NamedEnvironmentId(109),
    runtimePlane: RuntimePlane.sandbox,
  );
  final surfaceId = SurfaceId('surface.presentation-boundary');
  final revision = SurfaceRevisionId('surface.presentation-boundary.v2');
  final rootEdge = ArtifactOccurrenceEdgeToken('edge.presentation-boundary');
  final sourceEventCode = CodeIdentityId('code.source-event');
  final anchorCode = CodeIdentityId('code.rfw-anchor');
  final catalogOneCode = CodeIdentityId('code.rfw.catalog-one');
  final catalogTwoCode = CodeIdentityId('code.rfw.catalog-two');
  final artifact = MeasurementArtifactInput(
    artifactId: ArtifactId('artifact.presentation-boundary'),
    artifactKind: ArtifactKindId('rfw.blob'),
    contentHash: CanonicalDigest('a' * 64),
    occurrenceEdgeToken: rootEdge,
    localManifestId: MeasurementManifestId(
      'manifest.presentation-boundary.local',
    ),
  );
  return MeasurementCompilerBoundaryInput(
    target: target,
    surfaceId: surfaceId,
    surfaceRevisionId: revision,
    revisionOrdinal: 2,
    analyticsSurfaceKey: AnalyticsSurfaceKey(analyticsSurfaceKey),
    deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
    minimumMeasurementClient: minimumMeasurementClient,
    completeManifestId: MeasurementManifestId('manifest.presentation-boundary'),
    privacyPolicyRevisionId:
        AuthorityRevisionId('privacy.presentation-boundary'),
    collectionBudgetRevisionId: AuthorityRevisionId(
      'budget.presentation-boundary',
    ),
    artifacts: [artifact],
    codeIdentityLedger: CodeIdentityLedgerV1(
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      bindings: [
        CodeIdentityBindingV1(
          codeIdentityId: sourceEventCode,
          canonicalNodeTokenId: NodeTokenId('node.source-event'),
        ),
        CodeIdentityBindingV1(
          codeIdentityId: anchorCode,
          canonicalNodeTokenId: NodeTokenId('node.rfw-anchor'),
        ),
        CodeIdentityBindingV1(
          codeIdentityId: catalogOneCode,
          canonicalNodeTokenId: NodeTokenId('node.rfw.catalog-one'),
        ),
        CodeIdentityBindingV1(
          codeIdentityId: catalogTwoCode,
          canonicalNodeTokenId: NodeTokenId('node.rfw.catalog-two'),
        ),
      ],
    ),
    nodes: [
      MeasurementCompilerNodeInput(
        codeIdentityId: sourceEventCode,
        artifactOccurrenceEdgeToken: rootEdge,
      ),
      MeasurementCompilerNodeInput(
        codeIdentityId: anchorCode,
        artifactOccurrenceEdgeToken: rootEdge,
        parentCodeIdentityId: sourceEventCode,
      ),
      MeasurementCompilerNodeInput(
        codeIdentityId: catalogOneCode,
        artifactOccurrenceEdgeToken: rootEdge,
        parentCodeIdentityId: anchorCode,
      ),
      MeasurementCompilerNodeInput(
        codeIdentityId: catalogTwoCode,
        artifactOccurrenceEdgeToken: rootEdge,
        parentCodeIdentityId: anchorCode,
      ),
    ],
    events: const [],
    presentations: [
      if (includePresentations)
        MeasurementCompilerPresentationInput(
          nodeCodeIdentityId: catalogOneCode,
          lineageId: PointLineageId('lineage.rfw.catalog-one'),
          generatedPresentationReferenceId: GeneratedPresentationReferenceId(
            'reference.rfw.catalog-one',
          ),
          displayMetadataRef: DisplayMetadataRef('display.rfw.catalog-one'),
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          collectionClass: MeasurementCollectionClass.tier2Coalesced,
        ),
      if (includePresentations)
        MeasurementCompilerPresentationInput(
          nodeCodeIdentityId: catalogTwoCode,
          lineageId: PointLineageId('lineage.rfw.catalog-two'),
          generatedPresentationReferenceId: GeneratedPresentationReferenceId(
            'reference.rfw.catalog-two',
          ),
          displayMetadataRef: DisplayMetadataRef('display.rfw.catalog-two'),
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          collectionClass: MeasurementCollectionClass.tier2Coalesced,
        ),
    ],
    priorActiveLedger: PriorActiveLineageLedgerV1(
      surfaceId: surfaceId,
      surfaceRevisionId: SurfaceRevisionId('surface.presentation-boundary.v1'),
      endpoints: const [],
    ),
    lineageTransitions: const [],
  );
}
