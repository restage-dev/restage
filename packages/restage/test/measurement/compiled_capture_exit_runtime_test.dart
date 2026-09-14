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
  testWidgets(
      'compiled exit emits its actual skipped or dismissed worker request',
      (tester) async {
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
      support = await Directory.systemTemp.createTemp('capture-exit-worker-');
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
            sdkRuntimeSessionAdmitted: true,
            policyStatus: MeasurementHostConstructionPolicyStatus.supported,
            measurementClassAdmitted: true,
            remainingSessionBudget: 16,
            deliveryAdapterAvailable: true,
            configurationFingerprint: 'actual-compiled-exit-runtime.v1')),
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
    var unmounted = false;
    var skipped = false;
    var visible = true;
    late StateSetter updateHost;
    final skip = input['skip'] as bool;
    final eventSubscription = Restage.events.listen((event) {
      if (event is FlowCustomEvent && event.eventName == 'skip') {
        skipped = true;
        if (skip) updateHost(() => visible = false);
      }
    });
    try {
      stage('mounting compiled flow');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        updateHost = setState;
        if (!visible) return const SizedBox.shrink();
        return RestageFlowGraph<Map<String, Object?>>(
            flow: const SurfaceFlowRef(
                id: 'capture_exit',
                version: 1,
                minClient: 3,
                surface: Surface.survey,
                decodeResult: _decode),
            resolver: StaticFlowResolver(resolved),
            unavailable: FlowUnavailablePolicy.fallback(builder: (_, error) {
              stage('flow unavailable: $error');
              return Text('unavailable:${error.reason}');
            }),
            onComplete: (_) {
              completed = true;
            });
      }))));
      await _settleReal(
          tester,
          () =>
              owner.debugActiveSessionCount == 1 &&
              find.text('Continue').evaluate().isNotEmpty);
      // An element can exist during the screen's enter animation before its
      // guarded descendant paints. Complete that normal animation/paint before
      // disposal; uncommitted roots are deliberately discarded by teardown.
      await tester.pumpAndSettle();
      expect(owner.debugActiveSessionCount, 1);
      expect(owner.debugWorkerHealthy, isTrue);
      stage('active session and settled first-screen paint');
      if (skip) {
        stage('tapping authored Skip custom-event destination');
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        if (!skipped) await _settleReal(tester, () => skipped);
        expect(skipped, isTrue);
        expect(visible, isFalse);
        expect(find.text('Skip'), findsNothing);
      }
      // The custom-event handler removes the skipped flow in its event frame.
      // The other journey disposes its first rendered screen directly. Neither
      // path takes the completion transition.
      stage('host closes rendered flow');
      await tester.pumpWidget(const SizedBox.shrink());
      unmounted = true;
      await _settleReal(
          tester,
          () => observed.any((raw) =>
              MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal));
      expect(completed, isFalse);
      expect(skipped, skip);
      final raw = observed.lastWhere((raw) =>
          MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal);
      final request = MeasurementIngestRequestV1.fromBase64(raw);
      expect(
          request.sdkRuntimeSessionNonce, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(request.reportedSdkVersion, isNotNull);
      File(input['outputPath'] as String)
          .writeAsStringSync(jsonEncode({'canonicalRequestBase64': raw}));
    } finally {
      stage('disposing flow');
      if (!unmounted) await tester.pumpWidget(const SizedBox.shrink());
      stage(
          'flow unmounted; waiting for session release: ${owner.debugActiveSessionCount}');
      // Observing HTTP bytes precedes the worker's teardown acknowledgement.
      // Finish that existing FakeAsync-owned teardown before starting native
      // owner shutdown in runAsync.
      if (owner.debugActiveSessionCount != 0) {
        await _settleReal(tester, () => owner.debugActiveSessionCount == 0);
      }
      expect(owner.debugActiveSessionCount, 0);
      stage('session released; closing owner');
      restore();
      await tester.runAsync(() async {
        try {
          await eventSubscription.cancel();
          await owner.close();
          stage('owner closed; closing observer');
        } finally {
          await server.close(force: true);
          await support.delete(recursive: true);
        }
      });
      stage('observer closed');
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
