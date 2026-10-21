import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _assignment = SurfaceAssignment(
  experimentId: 'experiment.checkout',
  experimentRevisionId: 'revision.checkout.1',
  experimentEpochId: 'epoch.checkout.1',
  variantId: 'arm.treatment',
);

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  for (final deferred in [false, true]) {
    testWidgets(
        'worker receipts emit deduplicated reset-safe events (deferred: $deferred)',
        (tester) async {
      final binding = _fixtureBinding();
      final hold = deferred ? Completer<void>() : null;
      final readPort = _AcceptedBindingReadPort(binding, hold: hold);
      final context = ExactMeasurementPublicationContextRefV1(
        bindingReference: binding.reference,
        surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
        surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
        artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
        measurementManifestHash:
            binding.completeMeasurementManifest.canonicalDigest,
      );
      final harness = AdmittedConstructionOwnerHostTestHarness.install(
        publicationContext: context,
        hostedBindingReadPortLookup: () => readPort,
      );
      addTearDown(() {
        unawaited(harness.close());
      });
      Restage.configure(
        apiKey: 'rs_pk_point_receipts',
        baseUrl: 'http://127.0.0.1:1',
      );
      final events = <RestageEvent>[];
      final localEvents = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(() {
        unawaited(subscription.cancel());
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RestagePaywall(
            id: 'checkout',
            resolver: _AssignedResolver(binding),
            onEvent: localEvents.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (hold != null) {
        expect(events.whereType<SurfacePointPresented>(), isEmpty);
        expect(Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
            _assignment);
        hold.complete();
      }
      for (var i = 0;
          i < 80 && harness.worker.activeSessionIds.isEmpty;
          i += 1) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pump();

      harness.lifecycle.emit(AppLifecycleState.inactive);
      await tester.pump();

      await tester.tap(find.text('Measure'));
      await tester.pump();

      final interactionCountBeforeCapacityReceipt =
          events.whereType<SurfacePointInteracted>().length;
      final activeSessionId = harness.worker.activeSessionIds.single;
      final fixtureRoutes = binding.mountedArtifactRoutes.single.routes;
      final capacityRouteIndex = fixtureRoutes.indexWhere(
        (route) =>
            route.opaqueRouteToken !=
            OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
                _carrierFor(binding)),
      );
      expect(capacityRouteIndex, isNonNegative);
      harness.worker.emitForgedAcknowledgement(
        sessionId: activeSessionId,
        routeIndex: capacityRouteIndex,
        outcome: MeasurementWorkerAppendAcknowledgementOutcome.truncated,
      );
      await tester.pump();
      expect(
        events.whereType<SurfacePointInteracted>(),
        hasLength(interactionCountBeforeCapacityReceipt),
      );
      expect(events.whereType<SurfacePointPresented>(), hasLength(2));

      final pointEventCountBeforeForgery =
          events.whereType<SurfacePointInteracted>().length;
      harness.worker.emitForgedAcknowledgement(
        sessionId: activeSessionId,
        routeIndex: -1,
      );
      harness.worker.emitForgedAcknowledgement(
        sessionId: activeSessionId,
        routeIndex: 99,
      );
      harness.worker.emitForgedAcknowledgement(
        sessionId: 'unknown.session',
        routeIndex: 0,
      );
      await tester.pump();

      Restage.reset();
      final assignmentAfterReset =
          Restage.assignmentFor('checkout', surfaceType: Surface.paywall);
      await tester.tap(find.text('Measure'));
      await tester.pump();
      final globalPointsWhileMounted = events
          .where((event) =>
              event is SurfacePointPresented || event is SurfacePointInteracted)
          .toList();
      final localPointsWhileMounted = localEvents
          .where((event) =>
              event is SurfacePointPresented || event is SurfacePointInteracted)
          .toList();
      expect(
          localPointsWhileMounted, hasLength(globalPointsWhileMounted.length));
      for (var index = 0; index < globalPointsWhileMounted.length; index += 1) {
        expect(
          identical(
            localPointsWhileMounted[index],
            globalPointsWhileMounted[index],
          ),
          isTrue,
        );
      }
      final admittedRoute = fixtureRoutes.singleWhere(
        (route) =>
            route.opaqueRouteToken ==
            OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
                _carrierFor(binding)),
      );
      final presented = events.whereType<SurfacePointPresented>().singleWhere(
            (event) => event.occurrenceId == admittedRoute.occurrenceId.hex,
          );
      expect(presented.surfaceId, 'checkout');
      expect(presented.surfaceType, Surface.paywall);
      expect(presented.surfaceVersion, 'served-version-42');
      expect(presented.assignment, _assignment);
      expect(presented.occurrenceId, admittedRoute.occurrenceId.hex);
      expect(presented.lineageId, admittedRoute.lineageId.value);
      expect(events.whereType<SurfacePointPresented>(), hasLength(2));

      final firstInteraction = events.whereType<SurfacePointInteracted>().first;
      expect(firstInteraction.assignment, _assignment);
      expect(pointEventCountBeforeForgery, 1);
      expect(events.whereType<SurfacePointInteracted>(), hasLength(2));
      expect(assignmentAfterReset, isNull);
      final afterReset = events.whereType<SurfacePointInteracted>().last;
      expect(afterReset.surfaceId, 'checkout');
      expect(afterReset.surfaceVersion, isNull);
      expect(afterReset.assignment, isNull);
      final localPointCountBeforeUnmount = localEvents
          .where((event) =>
              event is SurfacePointPresented || event is SurfacePointInteracted)
          .length;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      harness.worker.emitForgedAcknowledgement(
        sessionId: activeSessionId,
        routeIndex: 0,
      );
      await tester.pump();
      expect(
        localEvents
            .where((event) =>
                event is SurfacePointPresented ||
                event is SurfacePointInteracted)
            .length,
        localPointCountBeforeUnmount,
      );
    });
  }

  test('deterministic worker establishes membership on first interaction',
      () async {
    final binding = _fixtureBinding();
    final route = binding.mountedArtifactRoutes.single.routes.singleWhere(
      (candidate) =>
          candidate.opaqueRouteToken ==
          OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(
              _carrierFor(binding)),
    );
    final context = ExactMeasurementPublicationContextRefV1(
      bindingReference: binding.reference,
      surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
      surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
      artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
      measurementManifestHash:
          binding.completeMeasurementManifest.canonicalDigest,
    );
    final worker = DeterministicMeasurementDeliveryWorker()
      ..start(
        MeasurementWorkerOwnedDeliveryConfiguration(
          admission: const MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: true,
            analyticsEnabled: true,
            policySupported: true,
            measurementClassAdmitted: true,
            budgetAvailable: true,
          ),
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          configurationFingerprint: 'point-receipt-worker.v1',
          maximumSessions: 1,
        ),
      );
    addTearDown(worker.shutdown);
    final opened = await worker.openSession(
      MeasurementWorkerSessionRegistration(
        sessionId: 'point-receipt-session',
        captureSessionNonce: 'point-receipt-nonce',
        publicationContextCanonicalBytes: context.canonicalBytes,
        routes: [
          MeasurementWorkerRouteIdentity(
            occurrenceId: route.occurrenceId.hex,
            lineageId: route.lineageId.value,
          ),
        ],
        limits: const MeasurementWorkerSessionLimits(
          maximumCounterValue: 8,
          maximumPresentedPoints: 1,
          maximumInteractionCounters: 1,
          maximumMissingnessEntries: 0,
        ),
        firstSequence: 1,
      ),
    );
    final session = opened.session!;
    final receipts = <MeasurementWorkerAppendAcknowledgement>[];
    final subscription = worker.appendAcknowledgements.listen(receipts.add);
    addTearDown(subscription.cancel);

    expect(
      session.append(
        MeasurementWorkerAppendRecord(
          routeIndex: 0,
          monotonicTimestampMicros: 1,
          value: MeasurementWorkerAppendValue.interaction,
        ),
      ),
      MeasurementWorkerAppendOutcome.accepted,
    );
    expect(
      session.append(
        MeasurementWorkerAppendRecord(
          routeIndex: 0,
          monotonicTimestampMicros: 2,
          value: MeasurementWorkerAppendValue.interaction,
        ),
      ),
      MeasurementWorkerAppendOutcome.accepted,
    );
    await Future<void>.delayed(Duration.zero);

    expect(receipts, hasLength(2));
    expect(receipts.first.emitsPresentationEvent, isTrue);
    expect(receipts.last.emitsPresentationEvent, isFalse);
  });

  testWidgets('discarded failed-paint sessions emit no point event',
      (tester) async {
    final binding = _fixtureBinding();
    final readPort = _AcceptedBindingReadPort(binding);
    final context = ExactMeasurementPublicationContextRefV1(
      bindingReference: binding.reference,
      surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
      surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
      artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
      measurementManifestHash:
          binding.completeMeasurementManifest.canonicalDigest,
    );
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: context,
      hostedBindingReadPortLookup: () => readPort,
    );
    addTearDown(() {
      unawaited(harness.close());
    });
    Restage.configure(
      apiKey: 'rs_pk_failed_point_receipt',
      baseUrl: 'http://127.0.0.1:1',
    );
    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom('acme.throwing'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Throwing',
          builder: (_, __) => const _ThrowingWidget(),
        ),
      ],
    );
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(() {
      unawaited(subscription.cancel());
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'checkout',
          resolver: _AssignedResolver(binding, failPaint: true),
          errorBuilder: (_, __) => const Text('failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    for (var i = 0; i < 80 && harness.worker.discardCalls == 0; i += 1) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final failureReplacementCount = find.text('failed').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(failureReplacementCount, 1);
    expect(harness.worker.appendRecords, isEmpty);
    expect(harness.worker.discardCalls, 1);
    expect(events.whereType<SurfacePointPresented>(), isEmpty);
    expect(
      Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
      isNull,
    );
  });
}

MeasurementPublicationBindingV1 _fixtureBinding() =>
    AdmittedBundledPublicationFixture.build(includeOrderedCapture: false)
        .binding;

String _carrierFor(MeasurementPublicationBindingV1 binding) {
  final edge = base64UrlEncode(utf8.encode(
    binding.exactArtifactGraph.rootEdgeToken.value,
  )).replaceAll('=', '');
  return 'mrv1.$edge.$_token';
}

final class _AssignedResolver implements VariantResolver {
  _AssignedResolver(this.binding, {this.failPaint = false});

  final MeasurementPublicationBindingV1 binding;
  final bool failPaint;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile('''
          import restage.core;
          import restage.measurement;
          ${failPaint ? 'import acme.throwing;' : ''}
          widget Paywall = MeasurementSourcePresented(
            pointTokens: ["$_token"],
            carriers: ["${_carrierFor(binding)}"],
            child: ${failPaint ? 'Throwing()' : '''GestureDetector(
              onTap: event "measured" {
                __restage_measurement_route_v1: "${_carrierFor(binding)}"
              },
              child: Text(text: "Measure")
            )'''}
          );
        '''),
      ),
    );
    final canonicalAssignment = CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1(_assignment.experimentId),
      experimentRevisionId:
          ExperimentPublicRevisionIdV1(_assignment.experimentRevisionId),
      experimentEpochId:
          ExperimentPublicEpochIdV1(_assignment.experimentEpochId),
      armId: ExperimentPublicArmIdV1(_assignment.variantId),
      outcomeLinkCarrier: 'Y2Fub25pY2FsLWFzc2lnbm1lbnQ',
    );
    final variant = attachMeasurementPublicationBindingReference(
      ResolvedVariant(
        bytes: bytes,
        surfaceVersion: 'served-version-42',
        paywallId: id,
        paywallPublishedVersion: 42,
        assignment: _assignment,
      ),
      binding.reference,
      canonicalExperimentAssignment: canonicalAssignment,
    );
    return variant;
  }
}

final class _ThrowingWidget extends StatelessWidget {
  const _ThrowingWidget();

  @override
  Widget build(BuildContext context) => throw StateError('failed paint');
}

final class _AcceptedBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  _AcceptedBindingReadPort(this.binding, {this.hold});

  final Completer<void>? hold;

  final MeasurementPublicationBindingV1 binding;

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) async {
    await hold?.future;
    return MeasurementPublicationBindingReadAccepted(
      reference: binding.reference,
      binding: binding,
      registeredPublicationAttestation: RegisteredPublicationAttestationV1(
        bindingReference: binding.reference,
        attestationDigest: CanonicalDigest('9' * 64),
      ),
    );
  }
}
