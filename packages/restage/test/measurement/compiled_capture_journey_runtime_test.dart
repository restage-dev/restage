import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_capture_edge.dart';
import 'package:restage/src/measurement/measurement_host_construction_owner.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_test_support.dart' show StaticFlowResolver;
import '../support/restage_runtime_test_support.dart';

/// Invoked by the persisted backend proof with its actual accepted publication.
/// The only handoff is canonical input/output files; no occurrences are authored
/// here. Real generated controls, host callbacks and the native worker collect.
void main() {
  installRestageRuntimeTestSupport();
  final inputPath = Platform.environment['MEASUREMENT_RUNTIME_INPUT'];
  testWidgets('compiled journey emits the real worker request', (tester) async {
    final input = jsonDecode(File(inputPath!).readAsStringSync()) as Map;
    void stage(String value) => File('${input['outputPath']}.progress')
        .writeAsStringSync('$value\n', mode: FileMode.append);
    stage('decoding actual publication');
    final publication = MeasurementPublicationBindingV1.fromCanonicalBytes(
        base64Decode(input['bindingBase64'] as String));
    final attestation = RegisteredPublicationAttestationV1.fromCanonicalBytes(
        base64Decode(input['attestationBase64'] as String));
    final context = ExactMeasurementPublicationContextRefV1.fromCanonicalBytes(
        base64Decode(input['contextBase64'] as String));
    final payload =
        SurfacePayload.decode(base64Decode(input['payloadBase64'] as String))
            as FlowSurfacePayload;
    final accepted = MeasurementPublicationBindingReadAccepted(
        reference: attestation.bindingReference,
        binding: publication,
        registeredPublicationAttestation: attestation);
    final resolved = attachMeasurementPublicationBindingReference(
        ResolvedFlow(
            document: payload.flowDocument,
            screenBlobs: payload.screenBlobs,
            cacheHit: false),
        attestation.bindingReference);
    final observed = <String>[];
    late Zone realZone;
    late HttpServer server;
    late Directory support;
    await tester.runAsync(() async {
      realZone = Zone.current;
      support =
          await Directory.systemTemp.createTemp('capture-journey-worker-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final raw = body['canonicalRequestBase64'] as String;
        observed.add(raw);
        stage(
            "worker request observed: final=${MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal}");
        // This observer is not the ingest authority. The backend forwards these
        // exact bytes to authenticated ingest and obtains its actual receipt.
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
    });
    final owner = MeasurementHostConstructionOwner.forTesting(
        profileReadPort: _Profile(MeasurementHostConstructionProfile(
            publicationContext: context,
            endpoint: 'http://127.0.0.1:${server.port}/sdk/v1/measurement',
            analyticsEnabled: true,
            policyStatus: MeasurementHostConstructionPolicyStatus.supported,
            measurementClassAdmitted: true,
            remainingSessionBudget: 16,
            deliveryAdapterAvailable: true,
            configurationFingerprint: 'actual-compiled-journey-runtime.v1')),
        pathResolver: _Path(support.path),
        monotonicClock: _Clock(),
        workerRuntimeStarter: (
                {required configuration, required pathResolver}) =>
            realZone.run(() async {
              stage('starting native worker');
              final result = await MeasurementWorkerOwnedDeliveryRuntime.start(
                  configuration: configuration, pathResolver: pathResolver);
              stage('native worker started: ${result.outcome}');
              return result.runtime;
            }));
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
        MeasurementHostSessionConstructionAuthority
            .forWorkerOwnedDeliveryTesting(
                constructionOwner: owner,
                nonceBytesSource:
                    MeasurementHostSessionConstructionAuthority.production(
                            constructionOwner: owner)
                        .takeNonceBytes,
                hostedBindingReadPortLookup: () => _Binding(accepted)));
    var completed = false;
    try {
      stage('mounting compiled flow');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageFlowGraph<Map<String, Object?>>(
                  flow: const SurfaceFlowRef(
                      id: 'capture_journey',
                      version: 1,
                      minClient: 3,
                      surface: Surface.survey,
                      decodeResult: _decode),
                  resolver: StaticFlowResolver(resolved),
                  unavailable:
                      FlowUnavailablePolicy.fallback(builder: (_, error) {
                    stage('flow unavailable: $error');
                    return Text('unavailable:${error.reason}');
                  }),
                  onComplete: (_) {
                    completed = true;
                  }))));
      await _settleReal(
          tester, () => find.text('Continue').evaluate().isNotEmpty);
      stage('tapping rendered Continue');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      Finder finalControl() => find.text('Finish').evaluate().isNotEmpty
          ? find.text('Finish')
          : find.text('Continue');
      await _settleReal(tester, () => finalControl().evaluate().isNotEmpty);
      stage('tapping rendered terminal control');
      await tester.tap(finalControl());
      await tester.pumpAndSettle();
      await _settleReal(
          tester,
          () =>
              completed &&
              observed.any((raw) => MeasurementIngestRequestV1.fromBase64(raw)
                  .factFrame
                  .isFinal));
      final raw = observed.lastWhere((raw) =>
          MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal);
      final frame = MeasurementIngestRequestV1.fromBase64(raw).factFrame;
      final answers = [
        for (final fact in frame.facts)
          for (final occurrence in fact.timedOccurrencesV1 ?? [])
            if (occurrence.answerValueV1 != null)
              occurrence.answerValueV1!.toJson(),
      ];
      expect(
          answers,
          unorderedEquals([
            {'kind': 'category', 'value': 'alpha'},
            {'kind': 'scaledDecimal', 'coefficient': '3', 'scale': 0},
          ]));
      File(input['outputPath'] as String)
          .writeAsStringSync(jsonEncode({'canonicalRequestBase64': raw}));
    } finally {
      stage('disposing flow');
      await tester.pumpWidget(const SizedBox.shrink());
      restore();
      var closed = false;
      final closing = owner.close().whenComplete(() {
        closed = true;
      });
      await _settleReal(tester, () => closed);
      await closing;
      await tester.runAsync(() async {
        await server.close(force: true);
        await support.delete(recursive: true);
      });
    }
  }, skip: inputPath == null);
}

Map<String, Object?> _decode(Map<String, Object?> value) => value;
Future<void> _settleReal(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!ready()) debugDumpApp();
  expect(ready(), isTrue,
      reason: 'Actual flow/worker did not reach next source boundary');
}

final class _Clock implements MeasurementCaptureMonotonicClock {
  int micros = 0;
  @override
  int readMicros() => micros += 1000;
}

final class _Path implements MeasurementWorkerOwnedDeliveryPathResolver {
  _Path(this.path);
  final String path;
  @override
  Future<String> resolveApplicationSupportPath() async => path;
}

final class _Profile implements MeasurementHostConstructionProfileReadPort {
  _Profile(this.profile);
  final MeasurementHostConstructionProfile profile;
  @override
  Future<MeasurementHostConstructionProfileReadResult> readExact(
      ExactMeasurementPublicationContextRefV1 context) async {
    expect(context, profile.publicationContext);
    return MeasurementHostConstructionProfileReadAccepted(profile);
  }
}

final class _Binding implements MeasurementPublicationBindingReadPort {
  _Binding(this.accepted);
  final MeasurementPublicationBindingReadAccepted accepted;
  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
      MeasurementPublicationBindingReferenceV1 reference) async {
    expect(reference, accepted.reference);
    return accepted;
  }
}
