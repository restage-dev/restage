import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_capture_edge.dart';
import 'package:restage/src/measurement/measurement_point_identity.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage/src/measurement/measurement_runtime_capture.dart';
import 'package:restage/src/measurement/measurement_worker.dart';
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

void main() {
  test('ordered capture retains explicit channels without assignment witnesses',
      () {
    final fixture = _fixture(ordered: true);
    var micros = 10;
    final session = _session(fixture,
        bounds: MeasurementFactFrameBounds(
            maximumCounterValue: 4,
            maximumPresentedPoints: 2,
            maximumInteractionCounters: 2,
            maximumMissingnessEntries: 1),
        monotonicMicrosSource: () => micros);
    session.recordInteraction(fixture.interaction);
    session.recordInteraction(fixture.interaction);
    final pending = session.checkpoint().validatedIngestFrameV1;
    expect(pending.orderedCaptureIncompleteV1, isFalse);
    micros = 20;
    session.recordDeclaredOccurrence(
        fixture.interaction, MeasurementOccurrenceChannelV1.completion);
    final finalFrame = session.teardown().validatedIngestFrameV1;
    expect(
        finalFrame.facts.single.timedOccurrencesV1!
            .map((value) => value.ordinal),
        [1, 2, 3, 4]);
    expect(finalFrame.facts.single.timedOccurrencesV1!.last.channel,
        MeasurementOccurrenceChannelV1.completion);
    expect(finalFrame.frameElapsedMicros, 20);
    expect(finalFrame.experimentAssignment, isNull);
  });

  test('capture retains the opaque assignment through cumulative snapshots',
      () {
    final fixture = _fixture();
    var micros = 20;
    final session = _session(
      fixture,
      bounds: MeasurementFactFrameBounds(
        maximumCounterValue: 4,
        maximumPresentedPoints: 2,
        maximumInteractionCounters: 2,
        maximumMissingnessEntries: 1,
      ),
      monotonicMicrosSource: () => micros,
      experimentAssignment: const MeasurementExperimentAssignmentV1(
        outcomeLinkCarrier: 'AQID',
      ),
    );
    session.recordPresentation(fixture.interaction);
    final first = session.checkpoint();
    expect(
        first.validatedIngestFrameV1.experimentAssignment!.outcomeLinkCarrier,
        'AQID');
    expect(identical(first, session.checkpoint()), isTrue);
    micros = 60;
    session.recordInteraction(fixture.interaction);
    micros = 100;
    session.recordInteraction(fixture.interaction);
    final last = session.teardown().validatedIngestFrameV1;
    expect(last.experimentAssignment!.outcomeLinkCarrier, 'AQID');
    expect(last.facts.single.interactionCount!.value, 2);
    expect(first.validatedIngestFrameV1.frameElapsedMicros, 20);
    expect(last.frameElapsedMicros, 100);
    expect(
        first.validatedIngestFrameV1.facts.single
            .presentationFirstOccurrenceMicros,
        20);
    expect(
        first.validatedIngestFrameV1.facts.single
            .interactionFirstOccurrenceMicros,
        isNull);
    expect(last.facts.single.presentationFirstOccurrenceMicros, 20);
    expect(last.facts.single.interactionFirstOccurrenceMicros, 60);
  });

  test('capture refuses nonmonotonic and unbounded occurrence witnesses', () {
    final fixture = _fixture();
    var micros = 10;
    final session = _session(
      fixture,
      bounds: MeasurementFactFrameBounds(
          maximumCounterValue: 4,
          maximumPresentedPoints: 2,
          maximumInteractionCounters: 2,
          maximumMissingnessEntries: 1),
      experimentAssignment:
          const MeasurementExperimentAssignmentV1(outcomeLinkCarrier: 'AQID'),
      monotonicMicrosSource: () => micros,
    );
    session.recordPresentation(fixture.interaction);
    final checkpoint = session.checkpoint();
    for (final invalid in [
      -1,
      9,
      measurementIngestMaximumOutcomeWitnessMicros + 1
    ]) {
      micros = invalid;
      expect(() => session.recordInteraction(fixture.interaction),
          throwsStateError);
      expect(identical(checkpoint, session.checkpoint()), isTrue);
    }
    micros = 11;
    session.recordInteraction(fixture.interaction);
    final finalFrame = session.teardown().validatedIngestFrameV1;
    expect(finalFrame.facts.single.interactionCount!.value, 1);
    expect(finalFrame.facts.single.interactionFirstOccurrenceMicros, 11);
  });

  test('painted source routes retain zero before an interaction value', () {
    final fixture = _fixture();
    final session = _session(
      fixture,
      bounds: MeasurementFactFrameBounds(
        maximumCounterValue: 4,
        maximumPresentedPoints: 2,
        maximumInteractionCounters: 2,
        maximumMissingnessEntries: 1,
      ),
    );

    expect(fixture.presentation.capabilityKind,
        MeasurementCapabilityKind.presented);
    expect(fixture.interaction.capabilityKind,
        MeasurementCapabilityKind.sourceInteraction);
    expect(
      () => session.recordInteraction(fixture.presentation),
      throwsArgumentError,
    );
    expect(
      session.recordPresentation(fixture.presentation),
      MeasurementCaptureWriteDisposition.recorded,
    );
    expect(
      session.recordPresentation(fixture.interaction),
      MeasurementCaptureWriteDisposition.recorded,
    );
    final beforeInteraction = decodeCanonicalObject(
      session.checkpoint().canonicalBytes,
    );
    final zeroFact = _factFor(
      beforeInteraction['facts']! as List<Object?>,
      'lineage.runtime.interaction',
    );
    expect(zeroFact['interactionState'], 'observedZero');
    expect(
      zeroFact['interactionCount'],
      const {'saturated': false, 'value': 0},
    );
    expect(
      session.recordInteraction(fixture.interaction),
      MeasurementCaptureWriteDisposition.recorded,
    );

    final frame = decodeCanonicalObject(session.teardown().canonicalBytes);
    final facts = frame['facts']! as List<Object?>;
    final presented = _factFor(facts, 'lineage.runtime.presented');
    final interaction = _factFor(facts, 'lineage.runtime.interaction');

    expect(presented['interactionState'], 'observedZero');
    expect(
      presented['interactionCount'],
      const {'saturated': false, 'value': 0},
    );
    expect(interaction['interactionState'], 'observedValue');
    expect(
      interaction['interactionCount'],
      const {'saturated': false, 'value': 1},
    );
  });

  test('presentation routes retain typed truncation at fixed frame bounds', () {
    final fixture = _fixture();
    final session = _session(
      fixture,
      bounds: MeasurementFactFrameBounds(
        maximumCounterValue: 4,
        maximumPresentedPoints: 1,
        maximumInteractionCounters: 0,
        maximumMissingnessEntries: 1,
      ),
    );

    expect(
      session.recordPresentation(fixture.presentation),
      MeasurementCaptureWriteDisposition.truncated,
    );
    expect(
      session.recordPresentation(fixture.interaction),
      MeasurementCaptureWriteDisposition.truncated,
    );

    final frame = decodeCanonicalObject(session.teardown().canonicalBytes);
    final facts = frame['facts']! as List<Object?>;
    final presented = _factFor(facts, 'lineage.runtime.presented');
    final truncation = frame['truncation']! as Map<String, Object?>;
    final interactionCounters =
        truncation['interactionCounters']! as Map<String, Object?>;
    final presentedPoints =
        truncation['presentedPoints']! as Map<String, Object?>;

    expect(facts, hasLength(1));
    expect(presented['interactionState'], 'transportTruncated');
    expect(presented, isNot(contains('interactionCount')));
    expect(interactionCounters, const {'droppedCount': 1, 'truncated': true});
    expect(presentedPoints, const {'droppedCount': 1, 'truncated': true});
  });

  testWidgets(
    'nested source and presentation wrappers bind exact routes independently',
    (tester) async {
      final fixture = _dualRouteFixture();
      late final MeasurementWorkerRuntime worker;
      late final MeasurementWorkerSession workerSession;
      await tester.runAsync(() async {
        final started = await MeasurementWorkerRuntime.start(
          configuration: const MeasurementWorkerRuntimeConfiguration(
            maximumSessions: 1,
            maximumInFlightAppends: 8,
            maximumRetainedPreparedBatches: 1,
          ),
        );
        expect(started.outcome, MeasurementWorkerRuntimeStartOutcome.started);
        worker = started.runtime!;
        final opened = await worker.openSession(
          _dualRouteWorkerRegistration(fixture),
        );
        expect(opened.outcome, MeasurementWorkerOpenSessionOutcome.opened);
        workerSession = opened.session!;
      });
      final binder = _DualRouteBinder(
        mountedContext: fixture.mountedContext,
        routeTable: fixture.table,
        workerSession: workerSession,
      );
      final runtime = Runtime()
        ..update(
          const LibraryName(<String>['restage', 'core']),
          restage_core.buildCoreWidgetLibrary(),
        )
        ..update(
          kMeasurementRfwPresentationLibrary,
          buildMeasurementRfwPresentationLocalWidgetLibrary(),
        )
        ..update(
          _dualRouteLibrary,
          parseLibraryFile(_dualRouteSource(fixture)),
        );

      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MeasurementRfwPresentationBinderScope(
              binder: binder,
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(
                  _dualRouteLibrary,
                  'Root',
                ),
                onEvent: (_, arguments) {
                  final carrier = arguments[_measurementRouteArgumentKey];
                  if (carrier is String) {
                    binder.recordInteractionCarrier(carrier);
                  }
                },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.text('dual-routed'), findsOneWidget);
        expect(
          binder.calls
              .map(
                (call) =>
                    '${call.pointTokens.single}:${call.routeCarriers.single}',
              )
              .toSet(),
          <String>{
            '${fixture.sourceToken}:${fixture.sourceCarrier}',
            '${fixture.presentedToken}:${fixture.presentedCarrier}',
          },
        );

        await tester.tap(find.text('dual-routed'));
        await tester.pump(const Duration(milliseconds: 1));

        late final MeasurementWorkerBatchResult finalization;
        await tester.runAsync(() async {
          finalization = await workerSession.teardown();
        });
        expect(finalization.outcome, MeasurementWorkerBatchOutcome.prepared);
        final frame = decodeCanonicalObject(
          finalization.batch!.canonicalFrameBytes,
        );
        final facts = frame['facts']! as List<Object?>;
        expect(facts, hasLength(2));
        final source = _factFor(facts, fixture.sourceRoute.lineageId.value);
        final presented = _factFor(
          facts,
          fixture.presentedRoute.lineageId.value,
        );
        expect(source['interactionState'], 'observedValue');
        expect(
          source['interactionCount'],
          const {'saturated': false, 'value': 1},
        );
        expect(presented['interactionState'], 'observedZero');
        expect(
          presented['interactionCount'],
          const {'saturated': false, 'value': 0},
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        runtime.dispose();
        await tester.runAsync(() async {
          await worker.shutdown();
        });
      }
    },
  );

  test('shared route capacity accepts 1024 and rejects every 1025 mix', () {
    final fixture = _fixture();
    final table = MeasurementRuntimeRouteTable(
      mountedArtifactContext: fixture.mountedContext,
      routes: _sourceRoutes(kMaximumMeasurementRuntimeRouteCount - 1),
      presentationRoutes: [_presentationRoute(0)],
    );

    expect(table.routes, hasLength(kMaximumMeasurementRuntimeRouteCount));
    expect(
      () => MeasurementRuntimeRouteTable(
        mountedArtifactContext: fixture.mountedContext,
        routes: _sourceRoutes(kMaximumMeasurementRuntimeRouteCount),
        presentationRoutes: [_presentationRoute(0)],
      ),
      throwsArgumentError,
    );
  });
}

List<MeasurementRuntimeRouteDeclaration> _sourceRoutes(int count) =>
    List<MeasurementRuntimeRouteDeclaration>.generate(
      count,
      (index) => MeasurementRuntimeRouteDeclaration(
        token: OpaqueMeasurementEventSlotToken('route.runtime.source.$index'),
        occurrenceId: CanonicalDigest(
          (index + 1).toRadixString(16).padLeft(64, '0'),
        ),
        lineageId: PointLineageId('lineage.runtime.source.$index'),
      ),
    );

MeasurementRuntimePresentationRouteDeclaration _presentationRoute(int index) =>
    MeasurementRuntimePresentationRouteDeclaration(
      token: OpaqueMeasurementEventSlotToken(
        'route.runtime.presentation.$index',
      ),
      occurrenceId: CanonicalDigest(
        (index + kMaximumMeasurementRuntimeRouteCount + 1)
            .toRadixString(16)
            .padLeft(64, '0'),
      ),
      lineageId: PointLineageId('lineage.runtime.presentation.$index'),
    );

_RouteFixture _fixture({bool ordered = false}) {
  final mountedContext = MeasurementMountedArtifactContext(
    artifactGraphHash: CanonicalDigest('a' * 64),
    artifactId: ArtifactId('artifact.runtime'),
    artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.runtime'),
    measurementManifestHash: CanonicalDigest('b' * 64),
    surfaceRevisionId: SurfaceRevisionId('surface.runtime.v2'),
  );
  final interactionToken = OpaqueMeasurementEventSlotToken(
    'route.runtime.interaction',
  );
  final presentationToken = OpaqueMeasurementEventSlotToken(
    'route.runtime.presented',
  );
  final table = MeasurementRuntimeRouteTable(
    mountedArtifactContext: mountedContext,
    orderedCaptureV1: ordered
        ? MeasurementOrderedCaptureV1(routes: [
            MeasurementOrderedCaptureRouteV1(
              occurrenceId: CanonicalDigest('c' * 64),
              lineageId: PointLineageId('lineage.runtime.interaction'),
              channels: MeasurementOccurrenceChannelV1.values,
            )
          ])
        : null,
    routes: [
      MeasurementRuntimeRouteDeclaration(
        token: interactionToken,
        occurrenceId: CanonicalDigest('c' * 64),
        lineageId: PointLineageId('lineage.runtime.interaction'),
      ),
    ],
    presentationRoutes: [
      MeasurementRuntimePresentationRouteDeclaration(
        token: presentationToken,
        occurrenceId: CanonicalDigest('d' * 64),
        lineageId: PointLineageId('lineage.runtime.presented'),
      ),
    ],
  );
  return _RouteFixture(
    mountedContext: mountedContext,
    table: table,
    interaction: table.resolveOpaqueRoute(
      context: mountedContext,
      token: interactionToken,
    )!,
    presentation: table.resolveOpaqueRoute(
      context: mountedContext,
      token: presentationToken,
    )!,
  );
}

MeasurementRuntimeCaptureSession _session(
  _RouteFixture fixture, {
  required MeasurementFactFrameBounds bounds,
  MeasurementExperimentAssignmentV1? experimentAssignment,
  int Function()? monotonicMicrosSource,
}) =>
    MeasurementRuntimeCaptureSession.testOnlySuccessfulPresentation(
      bounds: bounds,
      experimentAssignment: experimentAssignment,
      monotonicMicrosSource: monotonicMicrosSource,
      captureSessionNonce: MeasurementCaptureSessionNonce('runtime-route'),
      publicationContextRef: ExactMeasurementPublicationContextRefV1(
        bindingReference: _bindingReference(),
        surfaceIdentity: PublishedSurfaceIdentityV1(
          target: TargetCoordinate(
            organizationId: OrganizationId(1),
            appId: ApplicationId(2),
            environmentTargetId: EnvironmentTargetId(3),
            namedEnvironmentId: NamedEnvironmentId(4),
            runtimePlane: RuntimePlane.sandbox,
          ),
          surfaceId: SurfaceId('surface.runtime'),
        ),
        surfaceRevisionId: fixture.mountedContext.surfaceRevisionId,
        artifactGraphHash: fixture.mountedContext.artifactGraphHash,
        measurementManifestHash: fixture.mountedContext.measurementManifestHash,
      ),
      routeTable: fixture.table,
      sequence: 1,
    );

MeasurementPublicationBindingReferenceV1 _bindingReference() {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest('e' * 64),
    selectedPublicationManifestDigest: CanonicalDigest('f' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('1' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('2' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('3' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId('authority.runtime'),
      externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('4' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('5' * 64),
  );
}

Map<String, Object?> _factFor(List<Object?> facts, String lineageId) => facts
    .cast<Map<String, Object?>>()
    .singleWhere((fact) => fact['lineageId'] == lineageId);

final class _RouteFixture {
  const _RouteFixture({
    required this.mountedContext,
    required this.table,
    required this.interaction,
    required this.presentation,
  });

  final MeasurementMountedArtifactContext mountedContext;
  final MeasurementRuntimeRouteTable table;
  final MeasurementCaptureRouteHandle interaction;
  final MeasurementCaptureRouteHandle presentation;
}

const _dualRouteLibrary = LibraryName(<String>['test', 'dual-route']);
const _measurementRouteArgumentKey = '__restage_measurement_route_v1';

_DualRouteFixture _dualRouteFixture() {
  final mountedContext = MeasurementMountedArtifactContext(
    artifactGraphHash: CanonicalDigest('6' * 64),
    artifactId: ArtifactId('artifact.dual-route'),
    artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.dual-route'),
    measurementManifestHash: CanonicalDigest('7' * 64),
    surfaceRevisionId: SurfaceRevisionId('surface.dual-route.v1'),
  );
  final sourceCarrier = MeasurementPublicationRouteCarrierV1.derive(
    routeDraftClosureDigest: CanonicalDigest('8' * 64),
    artifactOccurrenceEdgeToken: mountedContext.artifactOccurrenceEdgeToken,
    generatedReferenceId: GeneratedReferenceId('reference.dual-source'),
  ).value;
  final presentedCarrier =
      MeasurementPublicationRouteCarrierV1.derivePresentation(
    routeDraftClosureDigest: CanonicalDigest('8' * 64),
    artifactOccurrenceEdgeToken: mountedContext.artifactOccurrenceEdgeToken,
    generatedPresentationReferenceId: GeneratedPresentationReferenceId(
      'reference.dual-presented',
    ),
  ).value;
  final table = MeasurementRuntimeRouteTable(
    mountedArtifactContext: mountedContext,
    routes: <MeasurementRuntimeRouteDeclaration>[
      MeasurementRuntimeRouteDeclaration(
        token: OpaqueMeasurementEventSlotToken(sourceCarrier),
        occurrenceId: CanonicalDigest('9' * 64),
        lineageId: PointLineageId('lineage.dual-source'),
      ),
    ],
    presentationRoutes: <MeasurementRuntimePresentationRouteDeclaration>[
      MeasurementRuntimePresentationRouteDeclaration(
        token: OpaqueMeasurementEventSlotToken(presentedCarrier),
        occurrenceId: CanonicalDigest('a' * 64),
        lineageId: PointLineageId('lineage.dual-presented'),
      ),
    ],
  );
  final sourceRoute = table.resolveOpaqueRoute(
    context: mountedContext,
    token: OpaqueMeasurementEventSlotToken(sourceCarrier),
  )!;
  final presentedRoute = table.resolveOpaqueRoute(
    context: mountedContext,
    token: OpaqueMeasurementEventSlotToken(presentedCarrier),
  )!;
  return _DualRouteFixture(
    mountedContext: mountedContext,
    table: table,
    sourceCarrier: sourceCarrier,
    sourceToken: _pointToken(sourceCarrier),
    sourceRoute: sourceRoute,
    presentedCarrier: presentedCarrier,
    presentedToken: _pointToken(presentedCarrier),
    presentedRoute: presentedRoute,
  );
}

String _pointToken(String carrier) =>
    carrier.substring(carrier.lastIndexOf('.') + 1);

MeasurementWorkerSessionRegistration _dualRouteWorkerRegistration(
  _DualRouteFixture fixture,
) =>
    MeasurementWorkerSessionRegistration(
      sessionId: 'dual-route',
      captureSessionNonce: 'dual-route-nonce',
      publicationContextCanonicalBytes: ExactMeasurementPublicationContextRefV1(
        bindingReference: _bindingReference(),
        surfaceIdentity: PublishedSurfaceIdentityV1(
          target: TargetCoordinate(
            organizationId: OrganizationId(1),
            appId: ApplicationId(2),
            environmentTargetId: EnvironmentTargetId(3),
            namedEnvironmentId: NamedEnvironmentId(4),
            runtimePlane: RuntimePlane.sandbox,
          ),
          surfaceId: SurfaceId('surface.dual-route'),
        ),
        surfaceRevisionId: fixture.mountedContext.surfaceRevisionId,
        artifactGraphHash: fixture.mountedContext.artifactGraphHash,
        measurementManifestHash: fixture.mountedContext.measurementManifestHash,
      ).canonicalBytes,
      routes: <MeasurementWorkerRouteIdentity>[
        MeasurementWorkerRouteIdentity(
          occurrenceId: fixture.sourceRoute.occurrenceId.hex,
          lineageId: fixture.sourceRoute.lineageId.value,
        ),
        MeasurementWorkerRouteIdentity(
          occurrenceId: fixture.presentedRoute.occurrenceId.hex,
          lineageId: fixture.presentedRoute.lineageId.value,
        ),
      ],
      limits: const MeasurementWorkerSessionLimits(
        maximumCounterValue: 4,
        maximumPresentedPoints: 2,
        maximumInteractionCounters: 2,
        maximumMissingnessEntries: 1,
      ),
      firstSequence: 1,
    );

String _dualRouteSource(_DualRouteFixture fixture) => '''
import restage.core;
import restage.measurement;
widget Root = MeasurementPresented(
  carriers: ["${fixture.presentedCarrier}"],
  pointTokens: ["${fixture.presentedToken}"],
  child: MeasurementSourcePresented(
    carriers: ["${fixture.sourceCarrier}"],
    pointTokens: ["${fixture.sourceToken}"],
    child: GestureDetector(
      onTap: event "tap" {
        $_measurementRouteArgumentKey: "${fixture.sourceCarrier}"
      },
      child: Text(text: "dual-routed"),
    ),
  ),
);
''';

final class _DualRouteFixture {
  const _DualRouteFixture({
    required this.mountedContext,
    required this.table,
    required this.sourceCarrier,
    required this.sourceToken,
    required this.sourceRoute,
    required this.presentedCarrier,
    required this.presentedToken,
    required this.presentedRoute,
  });

  final MeasurementMountedArtifactContext mountedContext;
  final MeasurementRuntimeRouteTable table;
  final String sourceCarrier;
  final String sourceToken;
  final MeasurementCaptureRouteHandle sourceRoute;
  final String presentedCarrier;
  final String presentedToken;
  final MeasurementCaptureRouteHandle presentedRoute;
}

final class _DualRouteBinder
    implements MeasurementRfwPresentationCaptureBinder {
  _DualRouteBinder({
    required this.mountedContext,
    required this.routeTable,
    required this.workerSession,
  });

  final MeasurementMountedArtifactContext mountedContext;
  final MeasurementRuntimeRouteTable routeTable;
  final MeasurementWorkerSession workerSession;
  final _IncrementingClock _clock = _IncrementingClock();
  final Map<String, _BoundRoute> _routesByCarrier = <String, _BoundRoute>{};
  final calls = <_DualRouteBindingCall>[];

  @override
  MeasurementCaptureEdge? bindPresentation({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  }) {
    if (pointTokens.isEmpty || pointTokens.length != routeCarriers.length) {
      return null;
    }
    final preboundTokens = <MeasurementPreboundPointToken>[];
    for (var index = 0; index < routeCarriers.length; index += 1) {
      final route = routeTable.resolveOpaqueRoute(
        context: mountedContext,
        token: OpaqueMeasurementEventSlotToken(routeCarriers[index]),
      );
      if (route == null) return null;
      preboundTokens.add(
        MeasurementPreboundPointToken(
          compactToken: pointTokens[index],
          route: route,
        ),
      );
    }
    final identities = MeasurementPointIdentityTable.fromPreboundTokens(
      tokens: preboundTokens,
    );
    final edge = MeasurementCaptureEdge(
      pointIdentityTable: identities,
      workerSession: workerSession,
      monotonicClock: _clock,
    );
    for (var index = 0; index < routeCarriers.length; index += 1) {
      final identity = identities.resolve(pointTokens[index]);
      if (identity == null) return null;
      _routesByCarrier[routeCarriers[index]] = _BoundRoute(
        edge: edge,
        identity: identity,
      );
    }
    calls.add(
      _DualRouteBindingCall(
        pointTokens: pointTokens,
        routeCarriers: routeCarriers,
      ),
    );
    return edge;
  }

  void recordInteractionCarrier(String rawCarrier) {
    final route = _routesByCarrier[rawCarrier];
    if (route == null) return;
    route.edge.appendInteractionIdentity(route.identity);
  }
}

final class _DualRouteBindingCall {
  _DualRouteBindingCall({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  })  : pointTokens = List<String>.unmodifiable(pointTokens),
        routeCarriers = List<String>.unmodifiable(routeCarriers);

  final List<String> pointTokens;
  final List<String> routeCarriers;
}

final class _BoundRoute {
  const _BoundRoute({required this.edge, required this.identity});

  final MeasurementCaptureEdge edge;
  final MeasurementPointIdentity identity;
}

final class _IncrementingClock implements MeasurementCaptureMonotonicClock {
  var _micros = 0;

  @override
  int readMicros() => _micros++;
}
