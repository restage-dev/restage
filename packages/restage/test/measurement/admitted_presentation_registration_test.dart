import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/bundled_measurement_target_profile_loader.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/presentation_commit.dart';
import 'package:restage/src/resolver/resolved_variant.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';
import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a bundled measured presentation registers its device with one read',
      () async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await attempt.open();

    expect(attempt.context, {
      'kind': 'measurementPresentationContext',
      'schemaVersion': 1,
      'presentationCountry': 'SE',
      'platform': 'ios',
      'appBuildOrdinal': 42,
      'deviceClass': 'phone',
    });
    expect(attempt.reads, 1);
  });

  test('registration and a later request share one device reading', () async {
    final ambientCarrier = const SurfaceDeliveryObservations(
      presentationCountry: 'SE',
      platform: 'ios',
      appBuildOrdinal: 42,
      deviceClass: 'phone',
      sdkApiLevel: 2,
    ).canonicalBuiltInsBase64()!;
    SurfaceCanonicalCarrierProvider.installBuiltIns(() async => ambientCarrier);
    addTearDown(SurfaceCanonicalCarrierProvider.clear);
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await attempt.open();
    final delivery = HostedArtifactFixture();
    late Map<String, dynamic> sent;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: delivery.client((request) async {
        sent = (jsonDecode(request.body) as Map).cast();
        return http.Response(
            jsonEncode(delivery.describeRaw(
              surfaceType: Surface.paywall,
              surfaceSlug: 'pro_upgrade',
              version: 1,
              publishedAt: DateTime.utc(2026),
              content: const [1, 2, 3],
            )),
            200);
      }),
    );
    await withSurfaceDeliveryObservations(
      cell: attempt.cell,
      resolve: () => client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      ),
    );
    final carrier = sent['sdkBuiltInsCanonicalBase64'] as String;
    final requestContext = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(carrier))),
    ) as Map;
    final registrationContext = attempt.context;
    expect(registrationContext['presentationCountry'], 'SE');
    expect(requestContext['country'], 'se');
    // The request deliberately folds the region to its lowercase value id.
    expect(requestContext['country'],
        (registrationContext['presentationCountry']! as String).toLowerCase());
    for (final key in ['platform', 'appBuildOrdinal', 'deviceClass']) {
      expect(requestContext[key], registrationContext[key]);
    }
    expect(requestContext['sdkApiLevel'], 3);
    expect(attempt.reads, 1);
  });

  test('an unpainted attempt emits a summary only when metadata is admitted',
      () async {
    for (final admitted in [true, false]) {
      final attempt = _Attempt(metadataAdmitted: admitted);
      try {
        await attempt.open();
        expect(attempt.harness.worker.registrations, hasLength(1));
        expect(
            attempt.harness.worker.registrations.single
                .presentationContextCanonicalBytes,
            admitted ? isNotNull : isNull);
        await attempt.session.teardown();
        expect(attempt.harness.worker.terminalDiagnostics,
            hasLength(admitted ? 1 : 0));
        if (admitted) {
          expect(attempt.harness.worker.terminalDiagnostics.single.finishReason,
              MeasurementPresentationFinishReasonV1.abandoned);
        }
        expect(attempt.harness.worker.discardCalls, 1);
        expect(attempt.reads, 1);
      } finally {
        await attempt.close();
      }
    }
  });

  testWidgets('a failed paint reports one paintFailed diagnostic',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    final construction = attempt.session.debugConstructionSession!;
    final handle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision:
          attempt.fixture.binding.publishedSurfaceRevision,
      captureSink: _RejectCapture(),
      observer: construction.presentationAttemptObserver,
      onUncommittedAbort: construction.abortBeforeSuccessfulPaint,
    );
    // Drive directly because the framework absorbs a child's paint exception before the boundary observes it.
    handle.rejectFailedPaintForTest();
    await _pumpForTerminalDiagnostics(tester, attempt.harness.worker);
    await tester.runAsync(() => attempt.session.teardown());

    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    expect(attempt.harness.worker.terminalDiagnostics.single.finishReason,
        MeasurementPresentationFinishReasonV1.paintFailed);
    expect(attempt.harness.worker.discardCalls, 1);
  });

  testWidgets('a rejected capture reports one captureRejected diagnostic',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    final construction = attempt.session.debugConstructionSession!;
    final handle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision:
          attempt.fixture.binding.publishedSurfaceRevision,
      captureSink: _RejectCapture(),
      observer: construction.presentationAttemptObserver,
      onUncommittedAbort: construction.abortBeforeSuccessfulPaint,
    );
    await tester.pumpWidget(MeasurementPresentationCommitHook(
      routeHandle: handle,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 10, height: 10),
      ),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForTerminalDiagnostics(tester, attempt.harness.worker);
    await tester.runAsync(() => attempt.session.teardown());

    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    expect(attempt.harness.worker.terminalDiagnostics.single.finishReason,
        MeasurementPresentationFinishReasonV1.captureRejected);
    expect(attempt.harness.worker.discardCalls, 1);
  });

  testWidgets(
      'a subtree unmounted before paint reports one abandoned diagnostic',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(Offstage(
      child: attempt.session.wrapRootSubtree(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 10, height: 10),
        ),
      ),
    ));
    expect(attempt.harness.worker.terminalDiagnostics, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForTerminalDiagnostics(tester, attempt.harness.worker);
    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    await tester.runAsync(() => attempt.session.teardown());

    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    expect(attempt.harness.worker.terminalDiagnostics.single.finishReason,
        MeasurementPresentationFinishReasonV1.abandoned);
    expect(attempt.harness.worker.discardCalls, 1);
  });

  testWidgets('a healthy painted attempt sends no terminal summary',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    expect(attempt.context['presentationCountry'], 'SE');
    await tester.pumpWidget(attempt.session.wrapRootSubtree(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 10, height: 10),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());

    expect(attempt.harness.worker.finalizationCalls, 1);
    expect(attempt.harness.worker.discardCalls, 0);
    expect(attempt.harness.worker.terminalDiagnostics, isEmpty);
    expect(attempt.reads, 1);
  });

  testWidgets('a committed attempt with two roots still delivers its frame',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        attempt.session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
        attempt.session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
      ]),
    ));
    await tester.pump();
    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());

    // The committed frame is finalized and delivered first, and the summary
    // follows it rather than taking its place.
    expect(attempt.harness.worker.finalizationCalls, 1);
    expect(attempt.harness.worker.discardCalls, 0);
    expect(attempt.harness.worker.deliveries, [
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.diagnostic,
    ]);
    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    expect(attempt.harness.worker.terminalDiagnostics.single.finishReason,
        MeasurementPresentationFinishReasonV1.committed);
    expect(
        attempt
            .harness.worker.terminalDiagnostics.single.rootPresentationReports,
        MeasurementRootPresentationReportsV1.many);
  });

  testWidgets('a finalized session refuses a second terminal summary',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        attempt.session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
        attempt.session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
      ]),
    ));
    await tester.pump();
    await tester.runAsync(() => attempt.session.teardown());
    final summary = attempt.harness.worker.terminalDiagnostics.single;
    await tester.runAsync(
      () => attempt.harness.worker.lastSession!
          .reportTerminalDiagnostic(summary.canonicalBytes),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(attempt.harness.worker.terminalDiagnostics, hasLength(1));
    expect(attempt.harness.worker.deliveries, [
      MeasurementWorkerDeliveryKind.frame,
      MeasurementWorkerDeliveryKind.diagnostic,
    ]);
  });
}

/// Pumps until a reported terminal summary reaches the worker.
Future<void> _pumpForTerminalDiagnostics(
  WidgetTester tester,
  DeterministicMeasurementDeliveryWorker worker,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (worker.terminalDiagnostics.isNotEmpty) return;
    await tester.pump();
  }
}

final class _Attempt {
  _Attempt({bool metadataAdmitted = true}) {
    harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () async =>
          BundledMeasurementTargetProfileLoadResult(
        target: fixture.target,
        bindingReadPort: fixture.port,
      ),
      presentationMetadataAdmitted: metadataAdmitted,
    );
  }

  final fixture = AdmittedBundledPublicationFixture.build();
  late final AdmittedConstructionOwnerHostTestHarness harness;
  late final SurfaceDeliveryObservationCell cell =
      SurfaceDeliveryObservationCell(() async {
    reads += 1;
    return const SurfaceDeliveryObservations(
      presentationCountry: 'SE',
      platform: 'ios',
      appBuildOrdinal: 42,
      deviceClass: 'phone',
      sdkApiLevel: 3,
    );
  });
  var reads = 0;
  late MeasurementHostSessionController session;

  Future<void> open() async {
    final bytes =
        Uint8List.fromList(AdmittedBundledPublicationFixture.artifactBytes);
    final resolved = attachMeasurementBundledGeneratedSourceCarrier(
      ResolvedVariant(
        bytes: bytes,
        paywallId: 'fixture-artifact',
        surfaceVersion: FlowContentHash.compute(bytes).value,
      ),
      MeasurementBundledGeneratedSourceCarrier(
        measurementPublicationDraftDigest: fixture
            .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
      ),
    );
    session = await MeasurementHostSessionController.openForResolvedArtifact(
      resolved,
      presentationObservations: cell.read,
    );
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(session.debugConstructionSession, isNotNull);
    expect(harness.worker.registrations, hasLength(1));
  }

  Map<String, Object?> get context => (CanonicalJsonCodec.decode(harness.worker
          .registrations.single.presentationContextCanonicalBytes!) as Map)
      .cast<String, Object?>();

  Future<void> close() => harness.close();
}

final class _RejectCapture implements MeasurementPresentationCaptureSink {
  @override
  void recordSuccessfulPresentation(
      MeasurementSuccessfulPresentationFact fact) {
    throw StateError('capture unavailable');
  }
}
