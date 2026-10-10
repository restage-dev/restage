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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a tap on a completing route latches completion until another '
      'interaction replaces it', (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await tester.pump();

    // Held while pending, then replayed in order once the session opens.
    session.sanitizeAndRecordEvent(_tap(completing: true));
    await attempt.release(tester);
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    expect(session.debugLastInteractionCompletes, isTrue);

    session.sanitizeAndRecordEvent(_tap(completing: false));
    expect(session.debugLastInteractionCompletes, isFalse);

    session.sanitizeAndRecordEvent(_tap(completing: true));
    expect(session.debugLastInteractionCompletes, isTrue);

    // An event with no measured route leaves the latch as it was.
    session.sanitizeAndRecordEvent(const <String, Object?>{'plan': 'annual'});
    expect(session.debugLastInteractionCompletes, isTrue);

    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('typing after a completing tap still closes as completion',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);

    session.sanitizeAndRecordEvent(_tap(completing: true));
    session.sanitizeAndRecordEvent(const <String, Object?>{'value': 'SAVE10'});
    session.sanitizeAndRecordEvent('SAVE10');
    expect(session.debugLastInteractionCompletes, isTrue);

    // Closing now records completion: the surface end reads this latch.
    await tester.runAsync(() => session.teardown());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an event before any tap leaves the surface dismissed',
      (tester) async {
    final attempt = _Attempt();
    addTearDown(attempt.close);
    final session = attempt.openDeferred();
    await tester.pumpWidget(_host(session));
    await attempt.release(tester);
    expect(session.debugLastInteractionCompletes, isFalse);
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
    for (var i = 0; i < 400 && harness.worker.registrations.isEmpty; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 5; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> close() => harness.close();
}
