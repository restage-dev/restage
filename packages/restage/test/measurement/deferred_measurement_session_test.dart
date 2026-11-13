import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/bundled_measurement_target_profile_loader.dart';
import 'package:restage/src/measurement/measurement_capture_edge.dart'
    show MeasurementCaptureMonotonicClock;
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_ingest_transport.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart'
    show attachMeasurementPublicationBindingReference;
import 'package:restage/src/measurement/measurement_worker_delivery_protocol.dart'
    show MeasurementWorkerOwnedDeliveryDiscardOutcome;
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage/src/resolver/resolved_variant.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart'
    show SurfaceDeliveryObservations;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart'
    show MeasurementIngestRpcOutcome, MeasurementIngestRpcRejected;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a disabled deferred session is disabled at once',
      (tester) async {
    Restage.configure(measurementEnabled: false);
    addTearDown(Restage.debugReset);
    final session = MeasurementHostSessionController.openDeferred(_resolved());
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
  });

  testWidgets('the surface paints before the session opens', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    expect(find.byKey(_painted), findsOneWidget);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);
    expect(attempt.presentedLineages, isEmpty);
    await attempt.release(tester);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a held first paint commits exactly once when the session opens',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();

    await attempt.release(tester);
    await tester.pump();

    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(attempt.presentedLineages, [_rootLineage]);
    expect(
      session.debugConstructionSession!.presentationAttemptSummary
          .rootPresentationReports,
      MeasurementRootPresentationReportsV1.one,
    );
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('events recorded before the session opens are replayed in order',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );

    await attempt.release(tester);
    await tester.pump();

    expect(attempt.presentedLineages, [_rootLineage, _childLineage]);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a surface torn down before the session opens is still recorded',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());

    await attempt.release(tester);
    await tester.runAsync(() => teardown);
    await tester.pump();

    expect(attempt.presentedLineages, [_rootLineage]);
    expect(attempt.harness.worker.deliveries,
        [MeasurementWorkerDeliveryKind.frame]);
  });

  testWidgets(
      'a session that opens late still delivers its paint, held events '
      'and frames', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );
    await tester.pump(_lateOpen);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);

    await attempt.release(tester);
    final worker = attempt.harness.worker;
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(attempt.presentedLineages, [_rootLineage, _childLineage]);
    expect(
      session.debugConstructionSession!.presentationAttemptSummary
          .rootPresentationReports,
      MeasurementRootPresentationReportsV1.one,
    );

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(worker.checkpointCalls, 1);

    attempt.harness.lifecycle.emit(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(worker.checkpointCalls, 2);
    attempt.harness.lifecycle.emit(AppLifecycleState.resumed);

    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
    expect(worker.finalizationCalls, 1);
    expect(worker.deliveries, [
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.frame,
    ]);
    expect(worker.terminalDiagnostics, isEmpty);
    expect(worker.discardOutcomes,
        [MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized]);
    expect(attempt.presentedLineages, [_rootLineage, _childLineage]);
  });

  testWidgets(
      'a surface torn down before a late open sends only its last frame',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(_lateOpen);

    await attempt.release(tester);
    await tester.runAsync(() => teardown.timeout(_settle));

    final worker = attempt.harness.worker;
    expect(attempt.presentedLineages, [_rootLineage]);
    expect(worker.deliveries, [MeasurementWorkerDeliveryKind.frame]);
    expect(worker.finalizationCalls, 1);
    expect(worker.terminalDiagnostics, isEmpty);
  });

  testWidgets(
      'a session that fails to open after its surface closed drops what it '
      'held, sends nothing, and says so', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());

    final logs = await _capturingLogs(() => attempt.fail(tester));
    expect(await tester.runAsync(() => teardown.timeout(_settle)), isNull);

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.harness.worker.registrations, isEmpty);
    expect(attempt.harness.worker.deliveries, isEmpty);
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), [
      '[restage] measurement session did not open; this presentation is not '
          'measured',
    ]);
  });

  testWidgets('a session that holds nothing fails to open without a log line',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();

    final logs = await _capturingLogs(() => attempt.fail(tester));

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), isEmpty);
  });

  testWidgets(
      'an open stuck loading its profile fails at the bound, and the outcome '
      'flush resolves', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    var flushed = false;
    unawaited(session.flushForOutcome().then((_) => flushed = true));

    final logs = await _capturingLogs(() async {
      await tester.pump(_lateOpen);
      expect(session.debugState, MeasurementHostSessionDebugState.pending);
      await tester.pump(MeasurementHostSessionController.openFailureBound);
    });
    await tester.pump();

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(flushed, isTrue);
    expect(
        logs.where((m) => m?.startsWith('[restage]') ?? false), hasLength(1));
    expect(attempt.harness.worker.registrations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'an open stuck in the worker fails at the bound and discards the late '
      'session', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final workerOpen = Completer<void>();
    attempt.harness.worker.openBarrier = workerOpen.future;
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);
    var flushed = false;
    unawaited(session.flushForOutcome().then((_) => flushed = true));

    await tester.pump(MeasurementHostSessionController.openFailureBound);
    await tester.pump();
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(flushed, isTrue);

    workerOpen.complete();
    await attempt.settle(tester);
    final worker = attempt.harness.worker;
    expect(worker.registrations, hasLength(1));
    expect(worker.deliveries,
        isNot(contains(MeasurementWorkerDeliveryKind.frame)));
    expect(worker.discardOutcomes,
        [MeasurementWorkerOwnedDeliveryDiscardOutcome.discarded]);
    final diagnostic = worker.terminalDiagnostics.single;
    expect(
        diagnostic.finishReason, MeasurementPresentationFinishReasonV1.unknown);
    expect(diagnostic.rootPresentationReports,
        MeasurementRootPresentationReportsV1.none);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a whole open is bounded once, not per step', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    attempt.harness.worker.openBarrier = Completer<void>().future;
    final session = attempt.openDeferred(
      presentationObservations: () =>
          Completer<SurfaceDeliveryObservations?>().future,
    );
    await tester.pumpWidget(_host(session));
    var flushed = false;
    unawaited(session.flushForOutcome().then((_) => flushed = true));
    await tester
        .pump(MeasurementHostSessionController.openFailureBound - _oneSecond);

    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);
    await tester.pump(_oneSecond);
    await attempt.settle(tester);

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(flushed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an open goes on without observations that are not ready',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred(
      presentationObservations: () =>
          Completer<SurfaceDeliveryObservations?>().future,
    );
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);

    await tester
        .pump(MeasurementHostSessionController.presentationObservationsWait);
    await attempt.settle(tester);

    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(attempt.presentedLineages, [_rootLineage]);
    expect(
      attempt.harness.worker.registrations.single
          .presentationContextCanonicalBytes,
      isNull,
    );
    await tester.runAsync(() => session.teardown().timeout(_settle));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a presentation painted before a reset is not filed under the new '
      'session when its open finishes after the reset', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.runAsync(() async => Restage.reset());

    final logs = await _capturingLogs(() => attempt.release(tester));

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.harness.worker.registrations, isEmpty);
    expect(attempt.harness.worker.deliveries, isEmpty);
    expect(
        logs.where((m) => m?.startsWith('[restage]') ?? false), hasLength(1));
    expect(await tester.runAsync(() => session.teardown().timeout(_settle)),
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a capture-session presentation painted before a reset is not adopted '
      'after it', (tester) async {
    final fixture = AdmittedBundledPublicationFixture.build();
    final ingest = _RecordingIngest();
    final profile = Completer<BundledMeasurementTargetProfileLoadResult>();
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forTesting(
        transport: MeasurementIngestTransport.adapter(ingest),
        nonceBytesSource: () => List<int>.filled(32, 3),
        bundledTargetProfileLoader: () => profile.future,
      ),
    );
    addTearDown(restore);
    Restage.configure(apiKey: 'rs_pk_capture_session');
    addTearDown(Restage.debugReset);
    final session = MeasurementHostSessionController.openDeferred(
      attachMeasurementBundledGeneratedSourceCarrier(
        _resolved(),
        MeasurementBundledGeneratedSourceCarrier(
          measurementPublicationDraftDigest: fixture
              .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
        ),
      ),
    );
    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.runAsync(() async => Restage.reset());

    profile.complete(BundledMeasurementTargetProfileLoadResult(
      target: fixture.target,
      bindingReadPort: fixture.port,
    ));
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => session.teardown().timeout(_settle));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ingest.requests, isEmpty);
  });

  testWidgets(
      'an open whose deadline passes during the observations wait never '
      'opens a worker session', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred(
      presentationObservations: () =>
          Completer<SurfaceDeliveryObservations?>().future,
    );
    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.pump(MeasurementHostSessionController.openFailureBound -
        const Duration(seconds: 3));
    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);

    final logs = await _capturingLogs(() async {
      await tester.pump(const Duration(seconds: 3));
      await attempt.settle(tester);
      await tester
          .pump(MeasurementHostSessionController.presentationObservationsWait);
      await attempt.settle(tester);
    });

    final worker = attempt.harness.worker;
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(worker.registrations, isEmpty);
    expect(worker.deliveries, isEmpty);
    expect(worker.terminalDiagnostics, isEmpty);
    expect(
        logs.where((m) => m?.startsWith('[restage]') ?? false), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('a measured surface that cannot open logs its lost paint', () {
    Future<void> expectOneLine(
      WidgetTester tester,
      _DeferredAttempt attempt,
      MeasurementHostSessionController session, {
      Completer<void>? read,
    }) async {
      await tester.pumpWidget(_host(session));
      await tester.pump();
      final logs = await _capturingLogs(() {
        read?.complete();
        return attempt.release(tester);
      });
      expect(session.debugState, MeasurementHostSessionDebugState.disabled);
      expect(attempt.harness.worker.deliveries,
          isNot(contains(MeasurementWorkerDeliveryKind.frame)));
      expect(logs.where((m) => m?.startsWith('[restage]') ?? false), [
        '[restage] measurement session did not open; this presentation is '
            'not measured',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets('when the worker is unavailable', (tester) async {
      final attempt = _DeferredAttempt();
      addTearDown(() => unawaited(attempt.close()));
      attempt.harness.worker.debugKillWorkerForTesting();
      await expectOneLine(tester, attempt, attempt.openDeferred());
    });

    testWidgets('when the worker is saturated', (tester) async {
      final attempt = _DeferredAttempt(maximumSessions: 1);
      addTearDown(attempt.close);
      final first = attempt.openDeferred();
      await attempt.release(tester);
      expect(first.debugState, MeasurementHostSessionDebugState.active);
      final gate = Completer<void>();
      attempt.harness.worker.openBarrier = gate.future;
      await expectOneLine(tester, attempt, attempt.openDeferred(), read: gate);
      expect(attempt.harness.worker.registrations, hasLength(2));
      await tester.runAsync(() => first.teardown().timeout(_settle));
    });

    testWidgets('when the owner closed without a reset', (tester) async {
      final attempt = _DeferredAttempt();
      addTearDown(attempt.close);
      final session = attempt.openDeferred();
      await tester.runAsync(() => attempt.harness.owner.close());
      await expectOneLine(tester, attempt, session);
      expect(attempt.harness.worker.registrations, isEmpty);
    });

    testWidgets('when the hosted binding read is unavailable', (tester) async {
      final read = Completer<void>();
      final attempt = _DeferredAttempt(hostedPort: _UnavailablePort(read));
      addTearDown(attempt.close);
      final session = MeasurementHostSessionController.openDeferred(
        attachMeasurementPublicationBindingReference(
          _resolved(),
          attempt.fixture.publicationContextRef.bindingReference,
        ),
      );
      await expectOneLine(tester, attempt, session, read: read);
      expect(attempt.harness.worker.registrations, isEmpty);
    });
  });

  testWidgets('an unmeasured surface that painted drops without a log line',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = MeasurementHostSessionController.openDeferred(_resolved());
    await tester.pumpWidget(_host(session));
    await tester.pump();

    final logs = await _capturingLogs(() => attempt.release(tester));

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.harness.worker.registrations, isEmpty);
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unmeasured surface that opens before paint logs nothing',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final logs = await _capturingLogs(() async {
      final session =
          MeasurementHostSessionController.openDeferred(_resolved());
      await attempt.release(tester);
      expect(session.debugState, MeasurementHostSessionDebugState.disabled);
      await tester.pumpWidget(_host(session));
      await tester.pump();
    });
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a surface declined by policy drops without a log line',
      (tester) async {
    final attempt = _DeferredAttempt(remainingSessionBudget: 0);
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();

    final logs = await _capturingLogs(() => attempt.release(tester));

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.harness.worker.registrations, isEmpty);
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a surface backgrounded before a late open sends its background frame '
      'on open', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    attempt.harness.lifecycle.emit(AppLifecycleState.inactive);
    attempt.harness.lifecycle.emit(AppLifecycleState.hidden);
    attempt.harness.lifecycle.emit(AppLifecycleState.paused);
    attempt.harness.lifecycle.emit(AppLifecycleState.inactive);
    await tester.pump(_lateOpen);

    await attempt.release(tester);
    final worker = attempt.harness.worker;
    expect(attempt.presentedLineages, [_rootLineage]);
    expect(worker.checkpointCalls, 1);
    expect(worker.deliveries, [MeasurementWorkerDeliveryKind.frame]);

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay * 2);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(worker.checkpointCalls, 1);
    attempt.harness.lifecycle.emit(AppLifecycleState.resumed);
    await tester.runAsync(() => session.teardown().timeout(_settle));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(worker.deliveries, [
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.frame,
    ]);
    expect(worker.finalizationCalls, 1);
  });

  testWidgets(
      'a surface backgrounded and resumed before a late open sends its '
      'early frame after the delay', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    attempt.harness.lifecycle.emit(AppLifecycleState.paused);
    attempt.harness.lifecycle.emit(AppLifecycleState.inactive);
    attempt.harness.lifecycle.emit(AppLifecycleState.resumed);

    await attempt.release(tester);
    final worker = attempt.harness.worker;
    expect(worker.checkpointCalls, 0);
    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(worker.checkpointCalls, 1);
    await tester.runAsync(() => session.teardown().timeout(_settle));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a deferred session reads the host clock, counted from mount',
      (tester) async {
    final clock = _ManualClock()..micros = 7000000;
    final attempt = _DeferredAttempt(monotonicClock: clock);
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    clock.micros += 1000;
    await tester.pumpWidget(_host(session));
    await tester.pump();
    clock.micros += 2000;
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );
    clock.micros += 4000;
    await attempt.release(tester);
    clock.micros += 8000;
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );

    expect(attempt.presentedLineages,
        [_rootLineage, _childLineage, _childLineage]);
    expect([
      for (final record in attempt.harness.worker.appendRecords)
        if (record.value == MeasurementWorkerAppendValue.presentation)
          record.monotonicTimestampMicros,
    ], [
      1000,
      3000,
      15000
    ]);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final held in [true, false]) {
    testWidgets(
        'a deferred session reads no clock of its own, with the child '
        '${held ? 'held' : 'after the open'}', (tester) async {
      final clock = _TickClock();
      final attempt = _DeferredAttempt(monotonicClock: clock);
      addTearDown(attempt.close);
      final session = attempt.openDeferred();
      await tester.pumpWidget(_host(session));
      await tester.pump();
      void child() => session.recordLifecycle(
            MeasurementOccurrenceChannelV1.presentation,
            screenId: AdmittedBundledPublicationFixture.childScreenId,
          );
      if (held) child();
      await attempt.release(tester);
      child();
      if (!held) child();

      expect([
        for (final record in attempt.harness.worker.appendRecords)
          if (record.value == MeasurementWorkerAppendValue.presentation)
            record.monotonicTimestampMicros,
      ], [
        1000,
        2000,
        3000
      ]);
      await tester.runAsync(() => session.teardown());
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'an entry held before the first paint replays before it, so a late '
      'open keeps every append in time order', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );
    await tester.runAsync(() => Future<void>.delayed(_heldGap));
    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(_heldGap));
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );

    await attempt.release(tester);
    session.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );

    final worker = attempt.harness.worker;
    expect(worker.rejectedAppends, isEmpty);
    final stamps = [
      for (final record in worker.appendRecords)
        record.monotonicTimestampMicros,
    ];
    expect(stamps, orderedEquals([...stamps]..sort()));
    expect(attempt.presentedLineages,
        [_rootLineage, _childLineage, _childLineage, _childLineage]);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a deferred root observes the app lifecycle once, before and after '
      'its late open', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final lifecycle = attempt.harness.lifecycle;
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump(_lateOpen);
    expect(lifecycle.registrations, 1);

    await attempt.release(tester);
    expect(lifecycle.registrations, 1);
    expect(lifecycle.unregistrations, 0);
    lifecycle.emit(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1,
        reason: 'the one observation reaches the opened session');

    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
    expect(lifecycle.registrations, 1);
    expect(lifecycle.unregistrations, 1);
  });

  testWidgets('a failed deferred open releases its one lifecycle observation',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await attempt.fail(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.harness.lifecycle.registrations, 1);
    expect(attempt.harness.lifecycle.unregistrations, 1);
  });

  group('the early frame after a late open is not stamped with a held time',
      () {
    Future<void> expectEarlyFrameAccepted(
        WidgetTester tester, _DeferredAttempt attempt) async {
      await tester
          .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      final worker = attempt.harness.worker;
      expect(worker.rejectedAppends, isEmpty);
      expect(worker.refusedFrameElapsed, isEmpty);
      expect(worker.checkpointCalls, 1);
      expect(worker.deliveries, [MeasurementWorkerDeliveryKind.frame]);
    }

    testWidgets('with an entry held after the paint', (tester) async {
      final attempt = _DeferredAttempt();
      addTearDown(attempt.close);
      final session = attempt.openDeferred();
      await tester.pumpWidget(_host(session));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      session.recordLifecycle(
        MeasurementOccurrenceChannelV1.presentation,
        screenId: AdmittedBundledPublicationFixture.childScreenId,
      );
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      await attempt.release(tester);
      await expectEarlyFrameAccepted(tester, attempt);
      await tester.runAsync(() => session.teardown().timeout(_settle));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with a live append after the open', (tester) async {
      final attempt = _DeferredAttempt();
      addTearDown(attempt.close);
      final session = attempt.openDeferred();
      await tester.pumpWidget(_host(session));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      await attempt.release(tester);
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      session.recordLifecycle(
        MeasurementOccurrenceChannelV1.presentation,
        screenId: AdmittedBundledPublicationFixture.childScreenId,
      );
      await expectEarlyFrameAccepted(tester, attempt);
      await tester.runAsync(() => session.teardown().timeout(_settle));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('on the capture-session path, where it is submitted',
        (tester) async {
      final fixture = AdmittedBundledPublicationFixture.build();
      final ingest = _RecordingIngest();
      final profile = Completer<BundledMeasurementTargetProfileLoadResult>();
      final restore = MeasurementHostSessionConstructionRegistry.installForTest(
        MeasurementHostSessionConstructionAuthority.forTesting(
          transport: MeasurementIngestTransport.adapter(ingest),
          nonceBytesSource: () => List<int>.filled(32, 3),
          bundledTargetProfileLoader: () => profile.future,
        ),
      );
      addTearDown(restore);
      final session = MeasurementHostSessionController.openDeferred(
        attachMeasurementBundledGeneratedSourceCarrier(
          _resolved(),
          MeasurementBundledGeneratedSourceCarrier(
            measurementPublicationDraftDigest: fixture.entry.candidateProof
                .measurementPublicationDraft.canonicalDigest,
          ),
        ),
      );
      await tester.pumpWidget(_host(session));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      session.recordLifecycle(
        MeasurementOccurrenceChannelV1.presentation,
        screenId: AdmittedBundledPublicationFixture.childScreenId,
      );
      await tester.runAsync(() => Future<void>.delayed(_heldGap));
      profile.complete(BundledMeasurementTargetProfileLoadResult(
        target: fixture.target,
        bindingReadPort: fixture.port,
      ));
      for (var i = 0; i < 20; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(session.debugState, MeasurementHostSessionDebugState.active);
      await tester
          .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(ingest.requests, hasLength(1));
      await tester.runAsync(() => session.teardown().timeout(_settle));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('the pending buffer keeps the first 256 entries', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    final logs = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    try {
      for (var i = 0; i < 300; i += 1) {
        session.recordLifecycle(
          MeasurementOccurrenceChannelV1.presentation,
          screenId: AdmittedBundledPublicationFixture.childScreenId,
        );
      }
    } finally {
      debugPrint = previous;
    }
    expect(session.debugPendingEntryCount, 256);
    expect(
      logs.where((m) => m?.contains('measurement') ?? false),
      hasLength(1),
    );
    await attempt.release(tester);
    await tester.runAsync(() => session.teardown());
  });

  testWidgets(
      'a surface left on screen sends its frame once, shortly after '
      'its first paint', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    expect(attempt.presentedLineages, [_rootLineage]);
    expect(attempt.harness.worker.checkpointCalls, 0);

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1);

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay * 4);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1);
    expect(attempt.harness.worker.finalizationCalls, 0);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a surface closed while its early frame uploads waits for it, '
      'then sends its last frame', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    final upload = Completer<void>();
    attempt.harness.worker.deliveryBarrier = upload.future;

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1);
    var flushed = false;
    final flush = session.flushForOutcome().then((_) => flushed = true);
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(flushed, isFalse, reason: 'the outcome waits for the frame');
    expect(attempt.harness.worker.finalizationCalls, 0);

    upload.complete();
    await tester.runAsync(() => Future.wait([teardown, flush]));
    expect(attempt.harness.worker.deliveries, [
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.frame,
    ]);
    expect(attempt.harness.worker.finalizationCalls, 1);
    expect(attempt.harness.worker.discardOutcomes,
        [MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized]);
  });

  Future<MeasurementHostSessionController> heldEarlyFrame(WidgetTester tester,
      _DeferredAttempt attempt, Completer<void> upload) async {
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    attempt.harness.worker.deliveryBarrier = upload.future;
    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1);
    return session;
  }

  Future<void> closeAndExpectFinal(
      WidgetTester tester,
      _DeferredAttempt attempt,
      MeasurementHostSessionController session,
      Completer<void> upload) async {
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    upload.complete();
    await tester.runAsync(() => teardown);
    final worker = attempt.harness.worker;
    expect(worker.finalizationCalls, 1);
    expect(worker.discardOutcomes,
        [MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized]);
    expect(attempt.harness.owner.debugWorkerHealthy, isTrue);
  }

  testWidgets(
      'a flush during the early frame shares it, then the close sends '
      'the last frame', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final upload = Completer<void>();
    final session = await heldEarlyFrame(tester, attempt, upload);
    var flushed = false;
    unawaited(session.flushForOutcome().then((_) => flushed = true));
    for (var i = 0; i < 3; i += 1) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(flushed, isFalse, reason: 'the flush waits for the early frame');
    await closeAndExpectFinal(tester, attempt, session, upload);
  });

  testWidgets(
      'a background during the early frame shares it, then the close '
      'sends the last frame', (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final upload = Completer<void>();
    final session = await heldEarlyFrame(tester, attempt, upload);
    attempt.harness.lifecycle.emit(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // The background shares the early frame's checkpoint.
    expect(attempt.harness.worker.checkpointCalls, 1);
    attempt.harness.lifecycle.emit(AppLifecycleState.resumed);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await closeAndExpectFinal(tester, attempt, session, upload);
  });

  testWidgets('a surface backgrounded before the delay sends no early frame',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    attempt.harness.lifecycle.emit(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1,
        reason: 'backgrounding sends the frame itself');
    attempt.harness.lifecycle.emit(AppLifecycleState.resumed);

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay * 2);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(attempt.harness.worker.checkpointCalls, 1);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a surface torn down before the delay sends only its last frame',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // Only the terminal frame: the teardown cancelled the early one.
    expect(attempt.harness.worker.deliveries,
        [MeasurementWorkerDeliveryKind.frame]);
    expect(attempt.harness.worker.finalizationCalls, 1);
  });

  testWidgets(
      'a capture-session surface also sends its frame once, shortly '
      'after its first paint', (tester) async {
    final fixture = AdmittedBundledPublicationFixture.build();
    final ingest = _RecordingIngest();
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forTesting(
        transport: MeasurementIngestTransport.adapter(ingest),
        nonceBytesSource: () => List<int>.filled(32, 3),
        bundledTargetProfileLoader: () async =>
            BundledMeasurementTargetProfileLoadResult(
          target: fixture.target,
          bindingReadPort: fixture.port,
        ),
      ),
    );
    addTearDown(restore);
    Restage.configure(apiKey: 'rs_pk_capture_session');
    addTearDown(Restage.debugReset);
    final session = MeasurementHostSessionController.openDeferred(
      attachMeasurementBundledGeneratedSourceCarrier(
        _resolved(),
        MeasurementBundledGeneratedSourceCarrier(
          measurementPublicationDraftDigest: fixture
              .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
        ),
      ),
    );
    await tester.pumpWidget(_host(session));
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(ingest.requests, isEmpty);

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(ingest.requests, hasLength(1));

    await tester
        .pump(MeasurementHostSessionController.firstPaintCheckpointDelay * 4);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(ingest.requests, hasLength(1));
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ingest.requests, hasLength(2));
  });

  testWidgets('outcome flush waits for opening and the first frame delivery',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    var flushed = false;
    final flush = session.flushForOutcome().then((_) => flushed = true);
    await tester.pump();
    expect(flushed, isFalse);
    final delivery = Completer<void>();
    attempt.harness.worker.deliveryBarrier = delivery.future;
    await attempt.release(tester);
    expect(attempt.harness.worker.checkpointCalls, 1);
    expect(flushed, isFalse);
    delivery.complete();
    await tester.runAsync(() => flush);
    expect(flushed, isTrue);
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('outcome flush waits for an unmounted presentation delivery',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();
    await attempt.release(tester);
    final delivery = Completer<void>();
    attempt.harness.worker.deliveryBarrier = delivery.future;
    final teardown = session.teardown();
    await tester.pumpWidget(const SizedBox.shrink());
    var flushed = false;
    final flush = session.flushForOutcome().then((_) => flushed = true);
    await tester.pump();
    expect(flushed, isFalse);
    expect(attempt.harness.worker.finalizationCalls, 1);
    delivery.complete();
    await tester.runAsync(() => Future.wait([teardown, flush]));
    expect(flushed, isTrue);
    expect(attempt.harness.worker.checkpointCalls, 1);
  });
}

const _rootLineage = 'lineage.bundled-left';
const _lateOpen = Duration(seconds: 10);
const _heldGap = Duration(milliseconds: 20);
const _settle = Duration(seconds: 5);
const _oneSecond = Duration(seconds: 1);

Future<List<String?>> _capturingLogs(Future<void> Function() body) async {
  final logs = <String?>[];
  final previous = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message);
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return logs;
}

const _childLineage = 'lineage.bundled-right';
const _painted = ValueKey<String>('painted');

Widget _host(MeasurementHostSessionController session) => Directionality(
      textDirection: TextDirection.ltr,
      child: session.wrapRootSubtree(
        const SizedBox(key: _painted, width: 10, height: 10),
      ),
    );

ResolvedVariant _resolved() {
  final bytes =
      Uint8List.fromList(AdmittedBundledPublicationFixture.artifactBytes);
  return ResolvedVariant(
    bytes: bytes,
    paywallId: 'fixture-artifact',
    surfaceVersion: FlowContentHash.compute(bytes).value,
  );
}

final class _DeferredAttempt {
  _DeferredAttempt({
    int remainingSessionBudget = 16,
    int maximumSessions = 16,
    MeasurementPublicationBindingReadPort? hostedPort,
    MeasurementCaptureMonotonicClock? monotonicClock,
  }) {
    harness = AdmittedConstructionOwnerHostTestHarness.install(
      monotonicClock: monotonicClock,
      publicationContext: fixture.publicationContextRef,
      hostedBindingReadPortLookup: hostedPort == null ? null : () => hostedPort,
      bundledTargetProfileLoader: () => _profile.future,
      presentationMetadataAdmitted: true,
      remainingSessionBudget: remainingSessionBudget,
      maximumSessions: maximumSessions,
    );
  }

  final fixture = AdmittedBundledPublicationFixture.build();
  final _profile = Completer<BundledMeasurementTargetProfileLoadResult>();
  late final AdmittedConstructionOwnerHostTestHarness harness;

  MeasurementHostSessionController openDeferred({
    Future<SurfaceDeliveryObservations?> Function()? presentationObservations,
  }) {
    final resolved = attachMeasurementBundledGeneratedSourceCarrier(
      _resolved(),
      MeasurementBundledGeneratedSourceCarrier(
        measurementPublicationDraftDigest: fixture
            .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
      ),
    );
    return MeasurementHostSessionController.openDeferred(
      resolved,
      presentationObservations: presentationObservations,
    );
  }

  /// Lets the session open and waits for it to settle.
  Future<void> release(WidgetTester tester) async {
    if (_profile.isCompleted) return settle(tester);
    _profile.complete(BundledMeasurementTargetProfileLoadResult(
      target: fixture.target,
      bindingReadPort: fixture.port,
    ));
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  /// Lets pending asynchronous work finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  /// Fails the open and waits for the session to settle.
  Future<void> fail(WidgetTester tester) async {
    _profile.completeError(StateError('profile unavailable'));
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  List<String> get presentedLineages {
    if (harness.worker.registrations.isEmpty) return const <String>[];
    final routes = harness.worker.registrations.single.routes;
    return [
      for (final record in harness.worker.appendRecords)
        if (record.value == MeasurementWorkerAppendValue.presentation)
          routes[record.routeIndex].lineageId,
    ];
  }

  Future<void> close() => harness.close();
}

final class _UnavailablePort implements MeasurementPublicationBindingReadPort {
  _UnavailablePort(this._read);

  final Completer<void> _read;

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) async {
    await _read.future;
    return const MeasurementPublicationBindingTransportUnavailable();
  }
}

final class _RecordingIngest implements MeasurementIngestRpcAdapter {
  final requests = <String>[];

  @override
  Future<MeasurementIngestRpcOutcome> submit(String canonicalRequestBase64) {
    requests.add(canonicalRequestBase64);
    return Future<MeasurementIngestRpcOutcome>.value(
      const MeasurementIngestRpcRejected(),
    );
  }
}

final class _ManualClock implements MeasurementCaptureMonotonicClock {
  int micros = 0;

  @override
  int readMicros() => micros;
}

final class _TickClock implements MeasurementCaptureMonotonicClock {
  int _micros = 0;

  @override
  int readMicros() => _micros += 1000;
}
