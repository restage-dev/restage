import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/bundled_measurement_target_profile_loader.dart';
import 'package:restage/src/measurement/measurement_host_construction_owner.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage/src/resolver/resolved_variant.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a child screen is a step on its own route, never a second root',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(_host(attempt));
    await tester.pump();
    expect(attempt.presentedLineages, [_rootLineage]);

    attempt.construction.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );

    // The screen appended on its own route, and the root still reports once.
    expect(attempt.presentedLineages, [_rootLineage, _childLineage]);
    expect(
      attempt.construction.presentationAttemptSummary.rootPresentationReports,
      MeasurementRootPresentationReportsV1.one,
    );

    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // The attempt stayed healthy, so the committed frame is delivered and no
    // terminal summary is sent in addition to it.
    expect(attempt.harness.worker.deliveries,
        [MeasurementWorkerDeliveryKind.frame]);
    expect(attempt.harness.worker.terminalDiagnostics, isEmpty);
  });

  testWidgets(
      'a revisited child screen appends again and still reports one root',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(_host(attempt));
    await tester.pump();
    for (var visit = 0; visit < 3; visit += 1) {
      attempt.construction.recordLifecycle(
        MeasurementOccurrenceChannelV1.presentation,
        screenId: AdmittedBundledPublicationFixture.childScreenId,
      );
    }

    // Three visits are three occurrences on the screen's route; the root's own
    // presentation is recorded once however many times a screen is entered.
    expect(attempt.presentedLineages,
        [_rootLineage, _childLineage, _childLineage, _childLineage]);
    expect(
      attempt.construction.presentationAttemptSummary.rootPresentationReports,
      MeasurementRootPresentationReportsV1.one,
    );

    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unauthored screen appends nothing of its own',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);
    await tester.pumpWidget(_host(attempt));
    await tester.pump();

    attempt.construction.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: 'screen_the_publication_never_declared',
    );

    // Only the root's own presentation is on the edge; the undeclared screen
    // resolves to no published route and contributes nothing.
    expect(attempt.presentedLineages, [_rootLineage]);

    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a child screen alone reaches a step and never paints',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    await tester.runAsync(attempt.open);

    // No root subtree is ever mounted, so nothing paints; the screen still
    // reports, which is the rootless step-bearing attempt.
    attempt.construction.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );
    expect(attempt.presentedLineages, [_rootLineage, _childLineage]);

    await tester.runAsync(() => attempt.session.teardown());
    await _pumpForTerminalDiagnostics(tester, attempt.harness.worker);

    final summary = attempt.harness.worker.terminalDiagnostics.single;
    expect(
      summary.rootPresentationReports,
      MeasurementRootPresentationReportsV1.none,
    );
    expect(summary.stepObserved, isTrue);
  });

  testWidgets('two mounted roots report many even beside a child screen',
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
    attempt.construction.recordLifecycle(
      MeasurementOccurrenceChannelV1.presentation,
      screenId: AdmittedBundledPublicationFixture.childScreenId,
    );
    await tester.runAsync(() => attempt.session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForTerminalDiagnostics(tester, attempt.harness.worker);

    // The anomaly is the two mounted roots; the child screen never adds one.
    final summary = attempt.harness.worker.terminalDiagnostics.single;
    expect(
      summary.rootPresentationReports,
      MeasurementRootPresentationReportsV1.many,
    );
  });
}

const _rootLineage = 'lineage.bundled-left';
const _childLineage = 'lineage.bundled-right';

Widget _host(_Attempt attempt) => Directionality(
      textDirection: TextDirection.ltr,
      child: attempt.session.wrapRootSubtree(
        const SizedBox(width: 10, height: 10),
      ),
    );

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
  _Attempt() {
    harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () async =>
          BundledMeasurementTargetProfileLoadResult(
        target: fixture.target,
        bindingReadPort: fixture.port,
      ),
      presentationMetadataAdmitted: true,
    );
  }

  final fixture = AdmittedBundledPublicationFixture.build();
  late final AdmittedConstructionOwnerHostTestHarness harness;
  late MeasurementHostSessionController session;

  MeasurementHostConstructionSession get construction =>
      session.debugConstructionSession!;

  /// Lineage of every presentation appended to the capture edge, in order.
  List<String> get presentedLineages {
    final routes = harness.worker.registrations.single.routes;
    return [
      for (final record in harness.worker.appendRecords)
        if (record.value == MeasurementWorkerAppendValue.presentation)
          routes[record.routeIndex].lineageId,
    ];
  }

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
    );
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(session.debugConstructionSession, isNotNull);
  }

  Future<void> close() => harness.close();
}
