import 'package:restage_codegen/src/measurement/measurement_rfw_presentation_discovery.dart';
import 'package:restage_codegen/src/measurement/measurement_rfw_route_composer.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_boundary.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_input.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test(
    'resolves frozen catalog calls and retains value-stable handles',
    () {
      final first = _discover(_topologySource());
      final changedValues = _discover(_topologySource(rootTitle: 'changed'));

      expect(
        first.occurrences.map((occurrence) => occurrence.constructorCall.name),
        unorderedEquals([
          'BuiltInCard',
          'BuiltInCard',
          'OpaqueBadge',
          'InlineBadge',
          'InlineBadge',
        ]),
      );
      expect(
        first.occurrences
            .where((occurrence) => occurrence.constructorCall.name == 'Card'),
        isEmpty,
      );
      expect(
        first.occurrences.where(
            (occurrence) => occurrence.constructorCall.name == 'Generic'),
        isEmpty,
      );
      expect(
        first.occurrences
            .where((occurrence) => occurrence.constructorCall.name == 'Dead'),
        isEmpty,
      );
      expect(
        first.localDeclarationAnchors
            .where((anchor) => anchor.localName == 'InlineBadge'),
        isEmpty,
      );
      expect(
        first.occurrences.where(
          (occurrence) =>
              occurrence.descriptor.renderEntryName == 'local:InlineBadge',
        ),
        isEmpty,
      );

      final root = first.occurrences.firstWhere(
        (occurrence) =>
            occurrence.constructorCall.name == 'BuiltInCard' &&
            occurrence.descriptor.parentStructuralOccurrenceKey == null,
      );
      final directChildren = first.occurrences.where(
        (occurrence) =>
            occurrence != root &&
            occurrence.descriptor.parentStructuralOccurrenceKey !=
                first.localDeclarationAnchors.single.structuralOccurrenceKey,
      );
      expect(
        directChildren.map(
          (occurrence) => occurrence.descriptor.parentStructuralOccurrenceKey,
        ),
        everyElement(root.descriptor.structuralOccurrenceKey),
      );

      final inline = first.occurrences
          .where(
              (occurrence) => occurrence.constructorCall.name == 'InlineBadge')
          .toList(growable: false);
      expect(
          inline.map((occurrence) => occurrence.handle).toSet(), hasLength(2));
      expect(
        changedValues.occurrences
            .map((occurrence) => occurrence.handle)
            .toSet(),
        first.occurrences.map((occurrence) => occurrence.handle).toSet(),
      );
    },
  );

  test(
    'materializes planned witnesses on exact final calls and rejects drift',
    () {
      final provisional = _discover(_topologySource());
      final publication = _publicationPlan(provisional);
      final finalLibrary = fmt.parseLibraryFile(
        _topologySource(rootTitle: 'final'),
        sourceIdentifier: 'presentation-final',
      );
      final materialization = publication.materializeArtifact(
        occurrenceSet: provisional,
        finalLibrary: finalLibrary,
        artifactOccurrenceEdgeToken: _edge,
      );

      expect(materialization.joins, hasLength(provisional.occurrences.length));
      for (final occurrence in provisional.occurrences) {
        final join = materialization.requirePresentationJoinForHandle(
          occurrence.handle,
        );
        final exactFinal = materialization.rebinding.requireBindingForHandle(
          occurrence.handle,
        );
        expect(join.constructorCall, same(exactFinal.constructorCall));
        expect(join.measurementSurfaceId, publication.routePlan.surfaceId);
        expect(join.routeDraftClosureDigest,
            publication.routePlan.routeDraftClosureDigest);
        expect(join.presentationRouteCarrier, join.presentationRoute.carrier);
        expect(
          join.presentationRouteFingerprint,
          join.presentationRoute.opaqueRouteToken,
        );
        expect(join.draftPresentationLineageId, join.presentationLineageId);
      }

      final composed = MeasurementRfwRouteComposer.composeMaterializedLibrary(
        routePlan: publication.routePlan,
        presentationMaterialization: materialization,
      );
      final rewritten = fmt.decodeLibraryBlob(composed.blob);
      expect(
        _constructorCalls(rewritten, 'MeasurementPresented'),
        hasLength(provisional.occurrences.length),
      );
      expect(
        composed.generatedPresentationReferences,
        publication.routePlan.presentationRoutes
            .map((route) => route.generatedPresentationReferenceId.value)
            .toSet(),
      );
      final boundary = MeasurementCompilerBoundary.produceBoundaryV1(
        _boundaryInput(publication.routePlan),
      );
      expect(boundary.disposition,
          MeasurementCompilerBoundaryDisposition.accepted);
      final finalManifest = boundary.completeMeasurementManifest!;
      final resolved =
          materialization.requireFinalizedPresentationReferenceForHandle(
        handle: provisional.occurrences.first.handle,
        completeManifest: finalManifest,
      );
      expect(
        resolved.referenceId,
        materialization.joins.first.presentationReferenceId,
      );

      expect(
        () => publication.materializeArtifact(
          occurrenceSet: provisional,
          finalLibrary: fmt.parseLibraryFile(
            _topologySource(includeOpaque: false),
            sourceIdentifier: 'presentation-missing',
          ),
          artifactOccurrenceEdgeToken: _edge,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => publication.materializeArtifact(
          occurrenceSet: provisional,
          finalLibrary: fmt.parseLibraryFile(
            _topologySource(extraOpaque: true),
            sourceIdentifier: 'presentation-extra',
          ),
          artifactOccurrenceEdgeToken: _edge,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => publication.materializeArtifact(
          occurrenceSet: provisional,
          finalLibrary: fmt.parseLibraryFile(
            _topologySource(remapInline: true),
            sourceIdentifier: 'presentation-remapped',
          ),
          artifactOccurrenceEdgeToken: _edge,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('rejects a forged presentation constructor before composition', () {
    final occurrenceSet = _discover(
      _topologySource(includeForgedConstructor: true),
    );
    final publication = _publicationPlan(occurrenceSet);
    final materialization = publication.materializeArtifact(
      occurrenceSet: occurrenceSet,
      finalLibrary: occurrenceSet.parsedLibrary,
      artifactOccurrenceEdgeToken: _edge,
    );

    expect(
      () => MeasurementRfwRouteComposer.composeMaterializedLibrary(
        routePlan: publication.routePlan,
        presentationMaterialization: materialization,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('planner reservation map contains only planned presentation keys', () {
    final occurrenceSet = _discover(_topologySource());
    final publication = _publicationPlan(occurrenceSet);
    final expected = <String, CodeIdentityId>{
      for (final occurrence in publication.occurrences)
        occurrence.structuralOccurrenceKey: occurrence.nodeCodeIdentityId,
    };

    expect(publication.codeIdentityByStructuralOccurrenceKey, expected);
    expect(
      publication.codeIdentityByStructuralOccurrenceKey.keys,
      isNot(contains(occurrenceSet.artifactAnchorStructuralOccurrenceKey)),
    );
    expect(
      publication.codeIdentityByStructuralOccurrenceKey,
      hasLength(publication.occurrences.length),
    );
  });

  test('rejects forged routes and duplicate descriptor or handle witnesses',
      () {
    final occurrenceSet = _discover(_topologySource());
    final publication = _publicationPlan(occurrenceSet);
    final first = publication.occurrences.first;
    final forgedEdge = ArtifactOccurrenceEdgeToken('edge.presentation.forged');
    final forgedCarrier =
        MeasurementPublicationRouteCarrierV1.derivePresentation(
      routeDraftClosureDigest: publication.routePlan.routeDraftClosureDigest,
      artifactOccurrenceEdgeToken: forgedEdge,
      generatedPresentationReferenceId: first.presentationReferenceId,
    );
    final forgedRoute = MeasurementPublicationDraftPresentationRouteV1(
      generatedPresentationReferenceId: first.presentationReferenceId,
      artifactOccurrenceEdgeToken: forgedEdge,
      carrier: forgedCarrier.value,
      opaqueRouteToken:
          OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(forgedCarrier.value),
    );
    final forgedWitnesses = [...publication.occurrences];
    forgedWitnesses[0] = _copyPlannedOccurrence(
      first,
      presentationRoute: forgedRoute,
    );
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey:
            publication.codeIdentityByStructuralOccurrenceKey,
        occurrences: forgedWitnesses,
      ),
      throwsArgumentError,
    );
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey:
            publication.codeIdentityByStructuralOccurrenceKey,
        occurrences: [...publication.occurrences, first],
      ),
      throwsArgumentError,
    );
    final duplicateHandleWitnesses = [...publication.occurrences];
    duplicateHandleWitnesses[1] = _copyPlannedOccurrence(
      duplicateHandleWitnesses[1],
      handle: first.handle,
    );
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey:
            publication.codeIdentityByStructuralOccurrenceKey,
        occurrences: duplicateHandleWitnesses,
      ),
      throwsArgumentError,
    );
    final second = publication.occurrences[1];
    final permutedWitnesses = [...publication.occurrences];
    permutedWitnesses[0] = _copyPlannedOccurrence(
      first,
      nodeCodeIdentityId: second.nodeCodeIdentityId,
      canonicalNodeTokenId: second.canonicalNodeTokenId,
      presentationLineageId: second.presentationLineageId,
      presentationReferenceId: second.presentationReferenceId,
      presentationDisplayMetadataRef: second.presentationDisplayMetadataRef,
      presentationRoute: second.presentationRoute,
    );
    permutedWitnesses[1] = _copyPlannedOccurrence(
      second,
      nodeCodeIdentityId: first.nodeCodeIdentityId,
      canonicalNodeTokenId: first.canonicalNodeTokenId,
      presentationLineageId: first.presentationLineageId,
      presentationReferenceId: first.presentationReferenceId,
      presentationDisplayMetadataRef: first.presentationDisplayMetadataRef,
      presentationRoute: first.presentationRoute,
    );
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey:
            publication.codeIdentityByStructuralOccurrenceKey,
        occurrences: permutedWitnesses,
      ),
      throwsArgumentError,
    );

    final extraKeyMap = <String, CodeIdentityId>{
      ...publication.codeIdentityByStructuralOccurrenceKey,
      occurrenceSet.artifactAnchorStructuralOccurrenceKey:
          CodeIdentityId('code.presentation.anchor'),
    };
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey: extraKeyMap,
        occurrences: publication.occurrences,
      ),
      throwsArgumentError,
    );

    final duplicateCodeIdentityMap = <String, CodeIdentityId>{
      ...publication.codeIdentityByStructuralOccurrenceKey
    };
    final duplicateCodeKey = duplicateCodeIdentityMap.keys.elementAt(1);
    duplicateCodeIdentityMap[duplicateCodeKey] =
        duplicateCodeIdentityMap.values.first;
    expect(
      () => MeasurementRfwPresentationPublicationPlan(
        routePlan: publication.routePlan,
        codeIdentityByStructuralOccurrenceKey: duplicateCodeIdentityMap,
        occurrences: publication.occurrences,
      ),
      throwsArgumentError,
    );
  });

  test('accepts the shared presentation reservation capacity', () {
    final occurrenceSet = _discoverCapacity(1023);
    final publication = _publicationPlan(occurrenceSet);

    expect(
      publication.occurrences,
      hasLength(kMaximumMeasurementPublicationPresentationRouteCount),
    );
    expect(
      publication.codeIdentityByStructuralOccurrenceKey,
      hasLength(kMaximumMeasurementPublicationPresentationRouteCount),
    );
  });

  test('rejects a presentation reservation beyond shared route capacity', () {
    expect(
      () => _publicationPlan(_discoverCapacity(1024)),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires exact origins for emitted generated definitions', () {
    final origin = fmt.RfwCatalogConstructorProvenance(
      constructorName: 'InlineBadge',
      catalogLibraryNamespace: 'example.presentation',
      catalogWidgetWireId: WireId('w0001'),
    );
    final missing = TranslationResult(
      dsl: 'InlineBadge()',
      issues: const [],
      widgetDefinitions: const {'InlineBadge': 'Generic()'},
    );
    final mismatched = TranslationResult(
      dsl: 'InlineBadge()',
      issues: const [],
      widgetDefinitions: const {'InlineBadge': 'Generic()'},
      rfwCatalogConstructorOrigins: [
        fmt.RfwCatalogConstructorProvenance(
          constructorName: 'OtherBadge',
          catalogLibraryNamespace: origin.catalogLibraryNamespace,
          catalogWidgetWireId: origin.catalogWidgetWireId,
        ),
      ],
    );
    expect(
      () => missing.rfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture.artifact',
        sourceLibraryIdentity: 'fixture.library',
        sourceDeclarationIdentity: 'fixture.declaration',
        renderEntryNames: const ['Paywall'],
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => mismatched.rfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture.artifact',
        sourceLibraryIdentity: 'fixture.library',
        sourceDeclarationIdentity: 'fixture.declaration',
        renderEntryNames: const ['Paywall'],
      ),
      throwsA(isA<StateError>()),
    );
  });
}

MeasurementRfwPresentationPlannedOccurrence _copyPlannedOccurrence(
  MeasurementRfwPresentationPlannedOccurrence occurrence, {
  MeasurementPresentationOccurrenceHandle? handle,
  CodeIdentityId? nodeCodeIdentityId,
  NodeTokenId? canonicalNodeTokenId,
  PointLineageId? presentationLineageId,
  GeneratedPresentationReferenceId? presentationReferenceId,
  DisplayMetadataRef? presentationDisplayMetadataRef,
  MeasurementPublicationDraftPresentationRouteV1? presentationRoute,
}) =>
    MeasurementRfwPresentationPlannedOccurrence(
      handle: handle ?? occurrence.handle,
      structuralOccurrenceKey: occurrence.structuralOccurrenceKey,
      measurementSurfaceId: occurrence.measurementSurfaceId,
      routeDraftClosureDigest: occurrence.routeDraftClosureDigest,
      nodeCodeIdentityId: nodeCodeIdentityId ?? occurrence.nodeCodeIdentityId,
      canonicalNodeTokenId:
          canonicalNodeTokenId ?? occurrence.canonicalNodeTokenId,
      artifactOccurrenceEdgeToken: occurrence.artifactOccurrenceEdgeToken,
      presentationLineageId:
          presentationLineageId ?? occurrence.presentationLineageId,
      presentationReferenceId:
          presentationReferenceId ?? occurrence.presentationReferenceId,
      presentationDisplayMetadataRef: presentationDisplayMetadataRef ??
          occurrence.presentationDisplayMetadataRef,
      presentationRoute: presentationRoute ?? occurrence.presentationRoute,
    );

final _edge = ArtifactOccurrenceEdgeToken('edge.presentation.fixture');

fmt.ResolvedRfwCatalogOccurrenceSet _discover(String source) {
  final library = fmt.parseLibraryFile(
    source,
    sourceIdentifier: 'presentation-fixture',
  );
  return fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
    parsedLibrary: library,
    input: _input(
      includeForgedConstructor: source.contains('widget MeasurementPresented'),
    ),
  );
}

fmt.ResolvedRfwCatalogOccurrenceSet _discoverCapacity(int opaqueCount) {
  final source = _capacityTopologySource(opaqueCount);
  final library = fmt.parseLibraryFile(
    source,
    sourceIdentifier: 'presentation-capacity',
  );
  return fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
    parsedLibrary: library,
    input: _input(includeSupportLocals: false),
  );
}

fmt.RfwCatalogOccurrenceResolutionInput _input({
  bool includeForgedConstructor = false,
  bool includeSupportLocals = true,
}) {
  const custom = WidgetLibrary.custom('example.presentation');
  final builtIn = fmt.RfwCatalogConstructorProvenance(
    constructorName: 'BuiltInCard',
    catalogLibraryNamespace: WidgetLibrary.core.namespace,
    catalogWidgetWireId: WireId('w0001'),
  );
  final opaque = fmt.RfwCatalogConstructorProvenance(
    constructorName: 'OpaqueBadge',
    catalogLibraryNamespace: custom.namespace,
    catalogWidgetWireId: WireId('w0001'),
  );
  final inline = fmt.RfwCatalogConstructorProvenance(
    constructorName: 'InlineBadge',
    catalogLibraryNamespace: custom.namespace,
    catalogWidgetWireId: WireId('w0002'),
  );
  final card = fmt.RfwCatalogConstructorProvenance(
    constructorName: 'Card',
    catalogLibraryNamespace: WidgetLibrary.core.namespace,
    catalogWidgetWireId: WireId('w0002'),
  );
  return fmt.RfwCatalogOccurrenceResolutionInput(
    artifactProvenance: 'fixture.paywall.presentation.root',
    sourceLibraryIdentity: 'package:fixture/presentation.dart',
    sourceDeclarationIdentity: 'package:fixture/presentation.dart#paywall',
    renderEntryNames: const ['Paywall'],
    catalogConstructors: [builtIn, opaque, inline, card],
    localSymbols: [
      fmt.RfwCatalogLocalSymbol(name: 'Paywall'),
      if (includeSupportLocals) ...[
        fmt.RfwCatalogLocalSymbol(
          name: 'InlineBadge',
          generatedCatalogOrigin: inline,
        ),
        fmt.RfwCatalogLocalSymbol(name: 'Card'),
        fmt.RfwCatalogLocalSymbol(name: 'Dead'),
      ],
      if (includeForgedConstructor)
        fmt.RfwCatalogLocalSymbol(name: 'MeasurementPresented'),
    ],
  );
}

MeasurementRfwPresentationPublicationPlan _publicationPlan(
  fmt.ResolvedRfwCatalogOccurrenceSet occurrenceSet,
) {
  final codes = <String, CodeIdentityId>{
    occurrenceSet.artifactAnchorStructuralOccurrenceKey:
        CodeIdentityId('code.presentation.anchor'),
    for (var index = 0;
        index < occurrenceSet.localDeclarationAnchors.length;
        index += 1)
      occurrenceSet.localDeclarationAnchors[index].structuralOccurrenceKey:
          CodeIdentityId('code.presentation.local.$index'),
    for (var index = 0; index < occurrenceSet.occurrences.length; index += 1)
      occurrenceSet.occurrences[index].descriptor.structuralOccurrenceKey:
          CodeIdentityId('code.presentation.$index'),
  };
  final tokens = <String, NodeTokenId>{};
  var tokenIndex = 0;
  for (final key in codes.keys) {
    tokens[key] = NodeTokenId('node.presentation.${tokenIndex++}');
  }
  final presentations = [
    for (var index = 0; index < occurrenceSet.occurrences.length; index += 1)
      MeasurementPublicationDraftPresentationV1(
        nodeCodeIdentityId: codes[occurrenceSet
            .occurrences[index].descriptor.structuralOccurrenceKey]!,
        lineageId: PointLineageId('lineage.presentation.$index'),
        generatedPresentationReferenceId: GeneratedPresentationReferenceId(
          'reference.presentation.$index',
        ),
        displayMetadataRef: DisplayMetadataRef('display.presentation.$index'),
        privacyClass: MeasurementPrivacyClass.nonSensitive,
        collectionClass: MeasurementCollectionClass.tier2Coalesced,
      ),
  ];
  final routePlan = MeasurementPublicationRoutePlanV1(
    surfaceId: SurfaceId('surface.presentation.fixture'),
    analyticsSurfaceKey: AnalyticsSurfaceKey('presentation-fixture'),
    deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
    minimumMeasurementClient: 2,
    completeManifestId: MeasurementManifestId('manifest.presentation.fixture'),
    privacyPolicyRevisionId:
        AuthorityRevisionId('privacy.presentation.fixture'),
    collectionBudgetRevisionId:
        AuthorityRevisionId('budget.presentation.fixture'),
    artifacts: [
      MeasurementPublicationRouteArtifactV1(
        artifactId: ArtifactId('artifact.presentation.fixture'),
        artifactKind: ArtifactKindId('rfw.blob'),
        occurrenceEdgeToken: _edge,
        localManifestId: MeasurementManifestId('manifest.presentation.local'),
      ),
    ],
    codeIdentityBindings: [
      for (final entry in codes.entries)
        CodeIdentityBindingV1(
          codeIdentityId: entry.value,
          canonicalNodeTokenId: tokens[entry.key]!,
        ),
    ],
    nodes: [
      MeasurementPublicationDraftNodeV1(
        codeIdentityId:
            codes[occurrenceSet.artifactAnchorStructuralOccurrenceKey]!,
        artifactOccurrenceEdgeToken: _edge,
      ),
      for (final localAnchor in occurrenceSet.localDeclarationAnchors)
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: codes[localAnchor.structuralOccurrenceKey]!,
          artifactOccurrenceEdgeToken: _edge,
          parentCodeIdentityId:
              codes[occurrenceSet.artifactAnchorStructuralOccurrenceKey],
        ),
      for (final occurrence in occurrenceSet.occurrences)
        MeasurementPublicationDraftNodeV1(
          codeIdentityId: codes[occurrence.descriptor.structuralOccurrenceKey]!,
          artifactOccurrenceEdgeToken: _edge,
          parentCodeIdentityId:
              codes[occurrence.descriptor.parentStructuralOccurrenceKey] ??
                  codes[occurrenceSet.artifactAnchorStructuralOccurrenceKey],
        ),
    ],
    events: const [],
    routeSeeds: const [],
    presentations: presentations,
    presentationRouteSeeds: [
      for (final presentation in presentations)
        MeasurementPublicationDraftPresentationRouteSeedV1(
          generatedPresentationReferenceId:
              presentation.generatedPresentationReferenceId,
          artifactOccurrenceEdgeToken: _edge,
        ),
    ],
    lineageIntents: const [],
  );
  final routesByReference = {
    for (final route in routePlan.presentationRoutes)
      route.generatedPresentationReferenceId.value: route,
  };
  return MeasurementRfwPresentationPublicationPlan(
    routePlan: routePlan,
    codeIdentityByStructuralOccurrenceKey: {
      for (final occurrence in occurrenceSet.occurrences)
        occurrence.descriptor.structuralOccurrenceKey:
            codes[occurrence.descriptor.structuralOccurrenceKey]!,
    },
    occurrences: [
      for (var index = 0; index < occurrenceSet.occurrences.length; index += 1)
        MeasurementRfwPresentationPlannedOccurrence(
          handle: occurrenceSet.occurrences[index].handle,
          structuralOccurrenceKey: occurrenceSet
              .occurrences[index].descriptor.structuralOccurrenceKey,
          measurementSurfaceId: routePlan.surfaceId,
          routeDraftClosureDigest: routePlan.routeDraftClosureDigest,
          nodeCodeIdentityId: codes[occurrenceSet
              .occurrences[index].descriptor.structuralOccurrenceKey]!,
          canonicalNodeTokenId: tokens[occurrenceSet
              .occurrences[index].descriptor.structuralOccurrenceKey]!,
          artifactOccurrenceEdgeToken: _edge,
          presentationLineageId: presentations[index].lineageId,
          presentationReferenceId:
              presentations[index].generatedPresentationReferenceId,
          presentationDisplayMetadataRef:
              presentations[index].displayMetadataRef,
          presentationRoute: routesByReference[
              presentations[index].generatedPresentationReferenceId.value]!,
        ),
    ],
  );
}

MeasurementCompilerBoundaryInput _boundaryInput(
  MeasurementPublicationRoutePlanV1 routePlan,
) {
  final target = TargetCoordinate(
    organizationId: OrganizationId(101),
    appId: ApplicationId(103),
    environmentTargetId: EnvironmentTargetId(107),
    namedEnvironmentId: NamedEnvironmentId(109),
    runtimePlane: RuntimePlane.sandbox,
  );
  return MeasurementCompilerBoundaryInput(
    target: target,
    surfaceId: routePlan.surfaceId,
    surfaceRevisionId: SurfaceRevisionId('surface.presentation.fixture.v2'),
    revisionOrdinal: 2,
    analyticsSurfaceKey: routePlan.analyticsSurfaceKey,
    deliverySurfaceType: routePlan.deliverySurfaceType,
    minimumMeasurementClient: routePlan.minimumMeasurementClient,
    completeManifestId: routePlan.completeManifestId,
    privacyPolicyRevisionId: routePlan.privacyPolicyRevisionId,
    collectionBudgetRevisionId: routePlan.collectionBudgetRevisionId,
    artifacts: [
      for (final artifact in routePlan.artifacts)
        MeasurementArtifactInput(
          artifactId: artifact.artifactId,
          artifactKind: artifact.artifactKind,
          contentHash: CanonicalDigest('a' * 64),
          occurrenceEdgeToken: artifact.occurrenceEdgeToken,
          localManifestId: artifact.localManifestId,
          parentOccurrenceEdgeToken: artifact.parentOccurrenceEdgeToken,
        ),
    ],
    codeIdentityLedger: CodeIdentityLedgerV1(
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: routePlan.surfaceId,
      ),
      bindings: routePlan.codeIdentityBindings,
    ),
    nodes: [
      for (final node in routePlan.nodes)
        MeasurementCompilerNodeInput(
          codeIdentityId: node.codeIdentityId,
          artifactOccurrenceEdgeToken: node.artifactOccurrenceEdgeToken,
          parentCodeIdentityId: node.parentCodeIdentityId,
        ),
    ],
    events: const [],
    presentations: [
      for (final presentation in routePlan.presentations)
        MeasurementCompilerPresentationInput(
          nodeCodeIdentityId: presentation.nodeCodeIdentityId,
          lineageId: presentation.lineageId,
          generatedPresentationReferenceId:
              presentation.generatedPresentationReferenceId,
          displayMetadataRef: presentation.displayMetadataRef,
          privacyClass: presentation.privacyClass,
          collectionClass: presentation.collectionClass,
        ),
    ],
    priorActiveLedger: PriorActiveLineageLedgerV1(
      surfaceId: routePlan.surfaceId,
      surfaceRevisionId: SurfaceRevisionId('surface.presentation.fixture.v1'),
      endpoints: const [],
    ),
    lineageTransitions: const [],
  );
}

String _topologySource({
  String rootTitle = 'first',
  bool includeOpaque = true,
  bool extraOpaque = false,
  bool remapInline = false,
  bool includeForgedConstructor = false,
}) {
  final opaque = includeOpaque ? 'OpaqueBadge(),' : '';
  final extra = extraOpaque ? 'OpaqueBadge(),' : '';
  final inline = remapInline ? 'OpaqueBadge()' : 'InlineBadge()';
  return '''
widget InlineBadge = BuiltInCard(title: "implementation");
widget Card = BuiltInCard(title: "shadow");
widget Dead = BuiltInCard(title: "unused");
${includeForgedConstructor ? 'widget MeasurementPresented = Generic();' : ''}
widget Paywall = BuiltInCard(
  title: "$rootTitle",
  children: [$opaque $extra $inline, InlineBadge(), Card(), Generic()],
);
''';
}

String _capacityTopologySource(int opaqueCount) {
  final opaqueCalls = List.filled(opaqueCount, 'OpaqueBadge()').join(', ');
  return '''
widget Paywall = BuiltInCard(children: [$opaqueCalls]);
''';
}

List<fmt.ConstructorCall> _constructorCalls(Object? value, String name) {
  final result = <fmt.ConstructorCall>[];

  void visit(Object? node) {
    switch (node) {
      case final fmt.RemoteWidgetLibrary library:
        library.widgets.forEach(visit);
      case final fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case final fmt.ConstructorCall call:
        if (call.name == name) result.add(call);
        visit(call.arguments);
      case final fmt.EventHandler handler:
        visit(handler.eventArguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch switchNode:
        visit(switchNode.input);
        switchNode.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  visit(value);
  return result;
}
