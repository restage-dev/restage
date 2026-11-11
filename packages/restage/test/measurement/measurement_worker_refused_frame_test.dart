import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  for (final first in const [
    (
      name: 'refused',
      status: HttpStatus.badRequest,
      body: '{"error":"refused","reason":"outcome_link_not_issued"}',
      outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.quarantined,
    ),
    (
      name: 'answered with a page',
      status: HttpStatus.ok,
      body: '<html>portal</html>',
      outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.held,
    ),
    (
      name: 'denied',
      status: HttpStatus.forbidden,
      body: '{"error":"hosted_access_denied"}',
      outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.held,
    ),
  ]) {
    test(
        'a session whose pending frame was ${first.name} still uploads its '
        'final frame', () async {
      final received = <Uint8List>[];
      final runtime = await _start((request, body) {
        received.add(body);
        if (received.length == 1) {
          request.response
            ..statusCode = first.status
            ..write(first.body);
        } else {
          // Later uploads are retried, never acknowledged.
          request.response.statusCode = HttpStatus.serviceUnavailable;
        }
      });
      final session = await _present(runtime, 'session.q');

      final checkpoint = await session.checkpoint(frameElapsedMicros: 2);
      expect(checkpoint.outcome, first.outcome);
      expect(received, hasLength(1));

      final teardown = await session.teardown(frameElapsedMicros: 3);
      expect(teardown.isFinal, isTrue);
      for (var waited = 0;
          waited < 100 && !received.skip(1).any((body) => _frame(body).isFinal);
          waited++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
          received.map((body) => _frame(body).isFinal).take(2), [false, true]);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  test('offline, the outbox keeps eight presentations that sent an early frame',
      () async {
    final runtime = await _start((request, body) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
    }, maximumSessions: 16);
    final saturated = <int>[];
    for (var presentation = 1; presentation <= 9; presentation += 1) {
      final session = await _present(runtime, 'measurement-host.$presentation');
      final early = await session.checkpoint(frameElapsedMicros: 2);
      final last = await session.teardown(frameElapsedMicros: 3);
      await session.discard();
      if (early.outcome ==
              MeasurementWorkerOwnedDeliveryCheckpointOutcome.outboxSaturated ||
          last.outcome ==
              MeasurementWorkerOwnedDeliveryCheckpointOutcome.outboxSaturated) {
        saturated.add(presentation);
      }
    }
    // Each presentation's last frame replaces its early one.
    expect(saturated, [9]);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a session id another launch used keeps both launches\' frames',
      () async {
    final support =
        await Directory.systemTemp.createTemp('restage-refused-frame-');
    addTearDown(() => support.delete(recursive: true));
    final seen = <String>[];
    Future<MeasurementWorkerOwnedDeliveryRuntime> launch() =>
        _start((request, body) {
          final frame = _frame(body);
          seen.add('${frame.captureSessionNonce} ${frame.sequence}');
          if (seen.length == 1) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('{"error":"refused","reason":"outcome_link_not_issued"}');
          } else {
            request.response.statusCode = HttpStatus.serviceUnavailable;
          }
        }, support: support);

    // The first launch's early frame is refused and kept.
    final first = await launch();
    final early = await (await _present(
      first,
      'measurement-host.1',
      nonce: 'nonce.launch1',
    ))
        .checkpoint(frameElapsedMicros: 2);
    expect(early.outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.quarantined);
    await first.shutdown();

    // The next launch reuses the per-process session id for a new session.
    final second = await launch();
    final session =
        await _present(second, 'measurement-host.1', nonce: 'nonce.launch2');
    final next = await session.checkpoint(frameElapsedMicros: 2);
    expect(
        next.outcome,
        isNot(MeasurementWorkerOwnedDeliveryCheckpointOutcome
            .persistenceFailure));
    expect(next.sequence, 1);
    final last = await session.teardown(frameElapsedMicros: 3);
    expect(last.isFinal, isTrue);
    for (var waited = 0;
        waited < 100 && !seen.contains('nonce.launch2 2');
        waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(seen.first, 'nonce.launch1 1');
    expect(seen, containsAll(['nonce.launch2 1', 'nonce.launch2 2']));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

MeasurementFactFrameV1 _frame(Uint8List body) =>
    MeasurementIngestRequestV1.fromBase64(
      (jsonDecode(utf8.decode(body))
          as Map<Object?, Object?>)['canonicalRequestBase64'] as String,
    ).factFrame;

// A runtime that delivers to a local server answering with [respond].
Future<MeasurementWorkerOwnedDeliveryRuntime> _start(
  void Function(HttpRequest request, Uint8List body) respond, {
  int maximumSessions = 4,
  Directory? support,
}) async {
  final directory = support ??
      await Directory.systemTemp.createTemp('restage-refused-frame-');
  if (support == null) {
    addTearDown(() => directory.delete(recursive: true));
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  unawaited(server.forEach((request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    respond(request, builder.takeBytes());
    await request.response.close();
  }));
  final started = await MeasurementWorkerOwnedDeliveryRuntime.start(
    configuration: MeasurementWorkerOwnedDeliveryConfiguration(
      admission: const MeasurementWorkerOwnedDeliveryAdmission(
        hasEndpoint: true,
        analyticsEnabled: true,
        policySupported: true,
        measurementClassAdmitted: true,
        budgetAvailable: true,
      ),
      endpoint:
          'http://${server.address.host}:${server.port}/sdk/v1/measurement',
      configurationFingerprint: 'measurement.worker-owned.v1',
      maximumSessions: maximumSessions,
    ),
    pathResolver: _PathResolver(directory.path),
  );
  expect(started.outcome, MeasurementWorkerOwnedDeliveryStartOutcome.started);
  final runtime = started.runtime!;
  addTearDown(runtime.shutdown);
  return runtime;
}

// An open session whose surface has been presented.
Future<MeasurementWorkerOwnedDeliverySession> _present(
  MeasurementWorkerOwnedDeliveryRuntime runtime,
  String sessionId, {
  String? nonce,
}) async {
  final opened = await runtime.openSession(
    _registration(sessionId, nonce: nonce ?? 'nonce.$sessionId'),
  );
  expect(opened.outcome, MeasurementWorkerOpenSessionOutcome.opened);
  final session = opened.session!;
  final acknowledgement = runtime.appendAcknowledgements.first;
  expect(
    session.append(MeasurementWorkerAppendRecord(
      routeIndex: 0,
      monotonicTimestampMicros: 1,
      value: MeasurementWorkerAppendValue.presentation,
    )),
    MeasurementWorkerAppendOutcome.accepted,
  );
  await acknowledgement;
  return session;
}

final class _PathResolver
    implements MeasurementWorkerOwnedDeliveryPathResolver {
  _PathResolver(this.path);
  final String path;
  @override
  Future<String> resolveApplicationSupportPath() async => path;
}

MeasurementWorkerSessionRegistration _registration(
  String sessionId, {
  required String nonce,
}) {
  final context = ExactMeasurementPublicationContextRefV1(
    bindingReference: _bindingReference,
    surfaceIdentity: PublishedSurfaceIdentityV1(
      target: TargetCoordinate(
        organizationId: OrganizationId(1),
        appId: ApplicationId(2),
        environmentTargetId: EnvironmentTargetId(3),
        namedEnvironmentId: NamedEnvironmentId(4),
        runtimePlane: RuntimePlane.sandbox,
      ),
      surfaceId: SurfaceId('surface.$sessionId'),
    ),
    surfaceRevisionId: SurfaceRevisionId('revision.$sessionId'),
    artifactGraphHash: CanonicalDigest('a' * 64),
    measurementManifestHash: CanonicalDigest('b' * 64),
  );
  return MeasurementWorkerSessionRegistration(
    sessionId: sessionId,
    captureSessionNonce: nonce,
    experimentAssignmentCanonicalBytes: CanonicalJsonCodec.encode(
      const MeasurementExperimentAssignmentV1(
        outcomeLinkCarrier: 'Y2Fycmllcg',
      ).toJson(),
    ),
    registrationFingerprint: null,
    orderedCaptureCanonicalBytesV1: null,
    publicationContextCanonicalBytes: context.canonicalBytes,
    routes: [
      MeasurementWorkerRouteIdentity(
        occurrenceId: '1'.padLeft(64, '0'),
        lineageId: 'lineage.worker-owned.0',
      ),
    ],
    limits: const MeasurementWorkerSessionLimits(
      maximumCounterValue: 8,
      maximumPresentedPoints: 4,
      maximumInteractionCounters: 4,
      maximumMissingnessEntries: 0,
    ),
    firstSequence: 1,
  );
}

final _bindingReference = MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId('authority.worker-owned'),
    externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
    candidateReference: MeasurementPublicationCandidateReferenceV1(
      candidateDigest: CanonicalDigest('c' * 64),
      selectedPublicationManifestDigest: CanonicalDigest('d' * 64),
      declaredArtifactBytesDigest: CanonicalDigest('e' * 64),
      assembledPublicationUploadDigest: CanonicalDigest('f' * 64),
      measurementPublicationDraftDigest: CanonicalDigest('1' * 64),
    ),
    immutablePublicationDigest: CanonicalDigest('2' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('e' * 64),
  ),
  bindingDigest: CanonicalDigest('3' * 64),
);
