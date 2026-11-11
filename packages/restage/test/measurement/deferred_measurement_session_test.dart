import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/bundled_measurement_target_profile_loader.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_ingest_transport.dart';
import 'package:restage/src/measurement/measurement_worker_delivery_protocol.dart'
    show MeasurementWorkerOwnedDeliveryDiscardOutcome;
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage/src/resolver/resolved_variant.dart';
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

  testWidgets('a session that opens after the background bound is dropped',
      (tester) async {
    final attempt = _DeferredAttempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump(MeasurementHostSessionController.openBudget);
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);

    await attempt.release(tester);
    await tester.pump();

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(attempt.presentedLineages, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
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
  _DeferredAttempt() {
    harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () => _profile.future,
      presentationMetadataAdmitted: true,
    );
  }

  final fixture = AdmittedBundledPublicationFixture.build();
  final _profile = Completer<BundledMeasurementTargetProfileLoadResult>();
  late final AdmittedConstructionOwnerHostTestHarness harness;

  MeasurementHostSessionController openDeferred() {
    final resolved = attachMeasurementBundledGeneratedSourceCarrier(
      _resolved(),
      MeasurementBundledGeneratedSourceCarrier(
        measurementPublicationDraftDigest: fixture
            .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
      ),
    );
    return MeasurementHostSessionController.openDeferred(resolved);
  }

  /// Lets the session open and waits for it to settle.
  Future<void> release(WidgetTester tester) async {
    _profile.complete(BundledMeasurementTargetProfileLoadResult(
      target: fixture.target,
      bindingReadPort: fixture.port,
    ));
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
