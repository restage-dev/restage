import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage/src/measurement/measurement_worker_delivery_unsupported.dart'
    as unsupported;
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  group('MeasurementWorkerOwnedDeliveryRuntime', () {
    test('admission denial performs no path lookup or native delivery startup',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-denial-',
      );
      addTearDown(() => support.delete(recursive: true));

      for (final testCase in <_AdmissionCase>[
        const _AdmissionCase(
          name: 'no endpoint',
          admission: MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: false,
            analyticsEnabled: true,
            policySupported: true,
            measurementClassAdmitted: true,
            budgetAvailable: true,
          ),
          endpoint: null,
          denial: MeasurementWorkerOwnedDeliveryAdmissionDenial.noEndpoint,
        ),
        const _AdmissionCase(
          name: 'analytics disabled',
          admission: MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: true,
            analyticsEnabled: false,
            policySupported: true,
            measurementClassAdmitted: true,
            budgetAvailable: true,
          ),
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          denial:
              MeasurementWorkerOwnedDeliveryAdmissionDenial.analyticsDisabled,
        ),
        const _AdmissionCase(
          name: 'unsupported policy',
          admission: MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: true,
            analyticsEnabled: true,
            policySupported: false,
            measurementClassAdmitted: true,
            budgetAvailable: true,
          ),
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          denial:
              MeasurementWorkerOwnedDeliveryAdmissionDenial.unsupportedPolicy,
        ),
        const _AdmissionCase(
          name: 'class denied',
          admission: MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: true,
            analyticsEnabled: true,
            policySupported: true,
            measurementClassAdmitted: false,
            budgetAvailable: true,
          ),
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          denial: MeasurementWorkerOwnedDeliveryAdmissionDenial.classDenied,
        ),
        const _AdmissionCase(
          name: 'budget exhausted',
          admission: MeasurementWorkerOwnedDeliveryAdmission(
            hasEndpoint: true,
            analyticsEnabled: true,
            policySupported: true,
            measurementClassAdmitted: true,
            budgetAvailable: false,
          ),
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          denial: MeasurementWorkerOwnedDeliveryAdmissionDenial.budgetExhausted,
        ),
      ]) {
        final resolver = _CountingPathResolver(support.path);

        final started = await MeasurementWorkerOwnedDeliveryRuntime.start(
          configuration: _configuration(
            admission: testCase.admission,
            endpoint: testCase.endpoint,
          ),
          pathResolver: resolver,
        );

        expect(
          started.outcome,
          MeasurementWorkerOwnedDeliveryStartOutcome.notAdmitted,
          reason: testCase.name,
        );
        expect(started.denial, testCase.denial, reason: testCase.name);
        expect(resolver.calls, 0, reason: testCase.name);
        expect(await support.list().isEmpty, isTrue, reason: testCase.name);
      }

      final facade = File(
        'lib/src/measurement/measurement_worker_delivery.dart',
      ).readAsStringSync();
      expect(
        facade.indexOf('final denial = configuration.admission.denial;'),
        lessThan(facade
            .indexOf('implementation.startMeasurementWorkerOwnedDelivery')),
      );
    });

    test(
        'uses one long-lived worker for primitive UI handoff and worker-owned IO',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-flow-',
      );
      addTearDown(() => support.delete(recursive: true));
      final received = <Uint8List>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          final body = await _readRequest(request);
          received.add(body);
          await _respondAccepted(request, body);
        }),
      );

      final runtime = await _start(
        support: support,
        endpoint: _endpointFor(server),
        debugTracing: true,
      );
      addTearDown(runtime.shutdown);
      final trace = <MeasurementWorkerOwnedDeliveryDebugEvent>[];
      final traceSubscription = runtime.debugEvents.listen(trace.add);
      addTearDown(traceSubscription.cancel);
      final session = await _open(runtime, 'session.worker-owned-flow');

      expect(runtime.debugWorkerSpawnCount, 1);
      final acknowledgement = runtime.appendAcknowledgements.first;
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await acknowledgement;
      final result = await session.checkpoint();

      expect(
        result.outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.delivered,
      );
      expect(result.sequence, 1);
      expect(runtime.debugWorkerSpawnCount, 1);
      expect(received, hasLength(1));
      await _eventually(
        () => trace.map((event) => event.stage).toSet().containsAll({
          MeasurementWorkerOwnedDeliveryDebugStage.canonicalized,
          MeasurementWorkerOwnedDeliveryDebugStage.hashedAndPrepared,
          MeasurementWorkerOwnedDeliveryDebugStage.journal,
          MeasurementWorkerOwnedDeliveryDebugStage.http,
        }),
      );
      expect(runtime.debugWorkerIsolateId, isNotNull);
      expect(runtime.debugWorkerIsolateId, isNot(Isolate.current.hashCode));
      expect(
        trace.map((event) => event.workerIsolateId),
        everyElement(runtime.debugWorkerIsolateId),
      );

      final finalization = await session.teardown();
      expect(finalization.isFinal, isTrue);
    });

    test('discards an uncommitted session without a frame or HTTP request',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-discard-',
      );
      addTearDown(() => support.delete(recursive: true));
      final received = <Uint8List>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          received.add(await _readRequest(request));
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }),
      );

      final runtime = await _start(
        support: support,
        endpoint: _endpointFor(server),
      );
      addTearDown(runtime.shutdown);
      final session = await _open(runtime, 'session.worker-owned-discard');

      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      final discarded = await session.discard();

      expect(
        discarded.outcome,
        MeasurementWorkerOwnedDeliveryDiscardOutcome.discarded,
      );
      expect(await session.teardown(),
          isA<MeasurementWorkerOwnedDeliveryCheckpointResult>());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(received, isEmpty);
      expect(
        (await _outboxDirectory(support).exists())
            ? await _outboxDirectory(support).list().toList()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('bounds the synchronous UI handoff at 256 without per-event spawning',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-handoff-',
      );
      addTearDown(() => support.delete(recursive: true));
      final runtime = await _start(
        support: support,
        endpoint: 'https://example.invalid/sdk/v1/measurement',
      );
      addTearDown(runtime.debugKillWorkerForTesting);
      final session = await _open(runtime, 'session.worker-owned-handoff');

      for (var index = 0; index < 256; index += 1) {
        expect(
          session.append(
            MeasurementWorkerAppendRecord(
              routeIndex: 0,
              monotonicTimestampMicros: index,
              value: MeasurementWorkerAppendValue.presentation,
            ),
          ),
          MeasurementWorkerAppendOutcome.accepted,
        );
      }
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 256,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.saturated,
      );
      expect(runtime.debugWorkerSpawnCount, 1);

      final native = File(
        'lib/src/measurement/measurement_worker_native.dart',
      ).readAsStringSync();
      final append = _section(
        native,
        'MeasurementWorkerAppendOutcome append(\n'
            '    _NativeWorkerOwnedDeliverySessionState session,',
        '  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> '
            'requestCheckpoint(',
      );
      expect(append, isNot(contains('async')));
      expect(append, isNot(contains('await')));
      expect(append, contains('kMeasurementOutboxMaximumHandoffMessages'));
      expect(append, contains('MeasurementWorkerOwnedDeliveryProtocol.append'));
    });

    test('restarts and replays the exact persisted HTTP body byte-for-byte',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-replay-',
      );
      addTearDown(() => support.delete(recursive: true));
      final received = <Uint8List>[];
      var shouldAcknowledge = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          final body = await _readRequest(request);
          received.add(body);
          if (shouldAcknowledge) {
            await _respondAccepted(request, body);
          } else {
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
          }
        }),
      );

      final first =
          await _start(support: support, endpoint: _endpointFor(server));
      final firstSession = await _open(first, 'session.worker-owned-replay');
      final acknowledgement = first.appendAcknowledgements.first;
      expect(
        firstSession.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await acknowledgement;
      expect(
        (await firstSession.checkpoint()).outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.retryScheduled,
      );
      expect(received, hasLength(1));

      first.debugKillWorkerForTesting();
      await _eventually(() => !first.isAvailable);
      shouldAcknowledge = true;
      final second =
          await _start(support: support, endpoint: _endpointFor(server));
      addTearDown(second.shutdown);

      await _eventually(() => received.length == 2,
          timeout: const Duration(seconds: 4));
      expect(received[1], orderedEquals(received[0]));
      await _eventually(
        () =>
            !_outboxDirectory(support).existsSync() ||
            _outboxDirectory(support)
                .listSync()
                .every((entity) => !entity.path.endsWith('.ready')),
      );
    });

    test(
        'malformed receipt retains the ready record and never reports delivery',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-malformed-',
      );
      addTearDown(() => support.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.ok
            ..write('{}');
          await request.response.close();
        }),
      );
      final runtime =
          await _start(support: support, endpoint: _endpointFor(server));
      addTearDown(runtime.shutdown);
      final session = await _open(runtime, 'session.worker-owned-malformed');
      final acknowledgement = runtime.appendAcknowledgements.first;
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await acknowledgement;

      expect(
        (await session.checkpoint()).outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.held,
      );
      final files = _outboxDirectory(support).listSync();
      expect(files.where((file) => file.path.endsWith('.ready')), hasLength(1));
      expect(files.where((file) => file.path.endsWith('.hold')), hasLength(1));
    });

    test('worker death is typed unavailable with no UI-isolate fallback',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-death-',
      );
      addTearDown(() => support.delete(recursive: true));
      final runtime = await _start(
        support: support,
        endpoint: 'https://example.invalid/sdk/v1/measurement',
      );
      final session = await _open(runtime, 'session.worker-owned-death');

      runtime.debugKillWorkerForTesting();
      await _eventually(() => !runtime.isAvailable);
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.unavailable,
      );
      expect(
        (await session.checkpoint()).outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
      );
    });

    test('cutover disables the old generation before it purges old records',
        () async {
      final support = await Directory.systemTemp.createTemp(
        'restage-worker-owned-delivery-cutover-',
      );
      addTearDown(() => support.delete(recursive: true));
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          requests += 1;
          await request.drain<void>();
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
        }),
      );
      final runtime =
          await _start(support: support, endpoint: _endpointFor(server));
      final session = await _open(runtime, 'session.worker-owned-cutover');
      final acknowledgement = runtime.appendAcknowledgements.first;
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 1,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await acknowledgement;
      expect(
        (await session.checkpoint()).outcome,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.retryScheduled,
      );
      expect(requests, 1);

      final reset = await runtime.reset(
        MeasurementOutboxPurgeReason.configurationReset,
      );
      expect(reset.outcome, MeasurementWorkerOwnedDeliveryResetOutcome.purged);
      expect(reset.purgedRecordCount, 1);
      expect(runtime.isAvailable, isFalse);
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 2,
            value: MeasurementWorkerAppendValue.interaction,
          ),
        ),
        MeasurementWorkerAppendOutcome.unavailable,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(requests, 1);
      final outboxDirectory = _outboxDirectory(support);
      expect(
        !outboxDirectory.existsSync() || outboxDirectory.listSync().isEmpty,
        isTrue,
      );
    });

    test('path startup failure is typed unavailable before worker creation',
        () async {
      final resolver = _ThrowingPathResolver();

      final started = await MeasurementWorkerOwnedDeliveryRuntime.start(
        configuration: _configuration(
          endpoint: 'https://example.invalid/sdk/v1/measurement',
        ),
        pathResolver: resolver,
      );

      expect(
        started.outcome,
        MeasurementWorkerOwnedDeliveryStartOutcome.unavailable,
      );
      expect(started.runtime, isNull);
      expect(started.unavailableReason, 'application_support_path_unavailable');
      expect(resolver.calls, 1);
    });
  });

  test('unsupported web/no-isolate stub fails closed before path lookup',
      () async {
    final resolver = _CountingPathResolver('/not/used');
    final result = await unsupported.startMeasurementWorkerOwnedDelivery(
      configuration: _configuration(
        endpoint: 'https://example.invalid/sdk/v1/measurement',
      ),
      pathResolver: resolver,
    );

    expect(result.state, isNull);
    expect(
        result.unavailableReason, 'native_worker_owned_delivery_unsupported');
    expect(resolver.calls, 0);
  });

  test('UI protocol handoff contains only bounded compact primitive values',
      () {
    final wire = MeasurementWorkerOwnedDeliveryProtocol.append(
      sessionId: 'session.protocol',
      record: MeasurementWorkerAppendRecord(
        routeIndex: 3,
        monotonicTimestampMicros: 9,
        value: MeasurementWorkerAppendValue.interaction,
      ),
    );

    _expectClosedWire(wire);
    expect(wire, hasLength(6));
    expect(wire.whereType<Map<Object?, Object?>>(), isEmpty);
    expect(
      MeasurementWorkerOwnedDeliveryProtocol.decodeInbound(wire),
      isA<MeasurementWorkerOwnedDeliveryAppendMessage>(),
    );
  });
}

Future<MeasurementWorkerOwnedDeliveryRuntime> _start({
  required Directory support,
  required String endpoint,
  bool debugTracing = false,
}) async {
  final started = await MeasurementWorkerOwnedDeliveryRuntime.start(
    configuration:
        _configuration(endpoint: endpoint, debugTracing: debugTracing),
    pathResolver: _CountingPathResolver(support.path),
  );
  expect(started.outcome, MeasurementWorkerOwnedDeliveryStartOutcome.started);
  return started.runtime!;
}

Future<MeasurementWorkerOwnedDeliverySession> _open(
  MeasurementWorkerOwnedDeliveryRuntime runtime,
  String sessionId,
) async {
  final opened = await runtime.openSession(_registration(sessionId));
  expect(opened.outcome, MeasurementWorkerOpenSessionOutcome.opened);
  return opened.session!;
}

MeasurementWorkerOwnedDeliveryConfiguration _configuration({
  MeasurementWorkerOwnedDeliveryAdmission admission =
      const MeasurementWorkerOwnedDeliveryAdmission(
    hasEndpoint: true,
    analyticsEnabled: true,
    policySupported: true,
    measurementClassAdmitted: true,
    budgetAvailable: true,
  ),
  required String? endpoint,
  bool debugTracing = false,
}) =>
    MeasurementWorkerOwnedDeliveryConfiguration(
      admission: admission,
      endpoint: endpoint,
      configurationFingerprint: 'measurement.worker-owned.v1',
      maximumSessions: 4,
      debugTracing: debugTracing,
    );

MeasurementWorkerSessionRegistration _registration(String sessionId) {
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
    captureSessionNonce: 'nonce.$sessionId',
    publicationContextCanonicalBytes: context.canonicalBytes,
    routes: const [
      MeasurementWorkerRouteIdentity(
        occurrenceId:
            '0000000000000000000000000000000000000000000000000000000000000001',
        lineageId: 'lineage.worker-owned',
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

String _endpointFor(HttpServer server) =>
    'http://${server.address.host}:${server.port}/sdk/v1/measurement';

Directory _outboxDirectory(Directory support) =>
    Directory('${support.path}/restage/measurement/outbox-v1');

Future<Uint8List> _readRequest(HttpRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> _respondAccepted(HttpRequest request, Uint8List exactBody) async {
  final envelope = jsonDecode(utf8.decode(exactBody, allowMalformed: false));
  expect(envelope, isA<Map<Object?, Object?>>());
  final carrier = (envelope as Map<Object?, Object?>)['canonicalRequestBase64'];
  expect(carrier, isA<String>());
  final ingest = MeasurementIngestRequestV1.fromBase64(carrier! as String);
  final frame = ingest.factFrame;
  final receipt = MeasurementIngestReceiptV1.accepted(
    acceptedObservationCount: 0,
    captureSessionNonce: frame.captureSessionNonce,
    factFrameSha256: ingest.factFrameSha256,
    isFinal: frame.isFinal,
    persistedAtMicros: 4100000,
    publicationBindingReference: frame.publishedContext.bindingReference,
    receiptId: 'receipt.worker-owned.0001',
    requestSha256: ingest.requestSha256,
    rootObservationUnitKey: 'root.worker-owned.0001',
    sequence: frame.sequence,
  );
  request.response
    ..statusCode = HttpStatus.ok
    ..write('{"receiptCanonicalBase64":"${receipt.canonicalReceiptBase64}"}');
  await request.response.close();
}

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for worker-owned delivery state');
}

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative, reason: 'Missing start: $start');
  final endIndex = source.indexOf(end, startIndex);
  expect(endIndex, isNonNegative, reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void _expectClosedWire(Object? value) {
  switch (value) {
    case int() || bool() || String() || Uint8List() || null:
      return;
    case List():
      for (final item in value) {
        _expectClosedWire(item);
      }
      return;
    default:
      fail('Unexpected worker wire value ${value.runtimeType}');
  }
}

final class _CountingPathResolver
    implements MeasurementWorkerOwnedDeliveryPathResolver {
  _CountingPathResolver(this.path);

  final String path;
  int calls = 0;

  @override
  Future<String> resolveApplicationSupportPath() async {
    calls += 1;
    return path;
  }
}

final class _ThrowingPathResolver
    implements MeasurementWorkerOwnedDeliveryPathResolver {
  int calls = 0;

  @override
  Future<String> resolveApplicationSupportPath() async {
    calls += 1;
    throw StateError('path unavailable');
  }
}

final class _AdmissionCase {
  const _AdmissionCase({
    required this.name,
    required this.admission,
    required this.endpoint,
    required this.denial,
  });

  final String name;
  final MeasurementWorkerOwnedDeliveryAdmission admission;
  final String? endpoint;
  final MeasurementWorkerOwnedDeliveryAdmissionDenial denial;
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
