import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';
import '../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a tap never completes the surface, even on a completing route',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);

    session.sanitizeAndRecordEvent(_tap(completing: true));
    expect(session.debugCompleted, isFalse);

    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a completion noted before the session opens is replayed and stays, '
      'whatever is tapped afterwards', (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();

    session.noteCompletion();
    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(session.debugCompleted, isTrue);

    session.sanitizeAndRecordEvent(_tap(completing: false));
    session.sanitizeAndRecordEvent('SAVE10');
    expect(session.debugCompleted, isTrue);

    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Map<String, Object?> _tap({required bool completing}) {
  final edge =
      base64UrlEncode(utf8.encode('edge.bundled-root')).replaceAll('=', '');
  return <String, Object?>{
    kMeasurementPublicationRouteArgumentKeyV1:
        'mrv1.$edge.${(completing ? 'B' : 'A') * 32}',
  };
}

Widget _host(MeasurementHostSessionController session) => Directionality(
      textDirection: TextDirection.ltr,
      child: session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
    );

final class _Attempt {
  _Attempt() {
    harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () => _profile.future,
      presentationMetadataAdmitted: true,
    );
  }

  final fixture = AdmittedBundledPublicationFixture.build(completingTap: true);
  final _profile = Completer<BundledMeasurementTargetProfileLoadResult>();
  late final AdmittedConstructionOwnerHostTestHarness harness;

  MeasurementHostSessionController openDeferred() {
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
    return MeasurementHostSessionController.openDeferred(resolved);
  }

  Future<void> release(WidgetTester tester) async {
    _profile.complete(BundledMeasurementTargetProfileLoadResult(
      target: fixture.target,
      bindingReadPort: fixture.port,
    ));
    // The session opens on real async work; wait for its worker registration.
    await pumpUntil(
      tester,
      () => harness.worker.registrations.isNotEmpty,
      reason: 'a worker registration',
    );
    for (var i = 0; i < 5; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> close() => harness.close();
}
