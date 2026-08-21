import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_worker.dart';
import 'package:restage/src/measurement/measurement_worker_unsupported.dart'
    as unsupported;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  group('MeasurementWorkerRuntime', () {
    test('uses one long-lived isolate and never spawns for individual appends',
        () async {
      final runtime = await _startRuntime(
        maximumInFlightAppends: 16,
        maximumRetainedPreparedBatches: 4,
      );
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.one-worker', routeCount: 4),
      );

      expect(runtime.debugWorkerSpawnCount, 1);
      for (var index = 0; index < 8; index += 1) {
        expect(
          session.append(
            MeasurementWorkerAppendRecord(
              routeIndex: index % 4,
              monotonicTimestampMicros: 100 + index,
              value: index.isEven
                  ? MeasurementWorkerAppendValue.presentation
                  : MeasurementWorkerAppendValue.interaction,
            ),
          ),
          MeasurementWorkerAppendOutcome.accepted,
        );
      }

      final checkpoint = await session.checkpoint();
      expect(checkpoint.outcome, MeasurementWorkerBatchOutcome.prepared);
      expect(runtime.debugWorkerSpawnCount, 1);
    });

    test('orders checkpoint barriers after append aggregation', () async {
      final runtime = await _startRuntime();
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.ordering'),
      );

      final firstAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 10,
            value: MeasurementWorkerAppendValue.presentation,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await firstAcknowledgement;
      final first = await session.checkpoint();
      expect(first.outcome, MeasurementWorkerBatchOutcome.prepared);

      final secondAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
        session.append(
          MeasurementWorkerAppendRecord(
            routeIndex: 0,
            monotonicTimestampMicros: 11,
            value: MeasurementWorkerAppendValue.interaction,
          ),
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await secondAcknowledgement;
      final second = await session.checkpoint();
      expect(second.outcome, MeasurementWorkerBatchOutcome.prepared);

      final firstFrame = _frame(first.batch!);
      final secondFrame = _frame(second.batch!);
      expect(firstFrame.sequence, 1);
      expect(secondFrame.sequence, 2);
      expect(firstFrame.facts.single.interactionState.wireName, 'observedZero');
      expect(
        secondFrame.facts.single.interactionState.wireName,
        'observedValue',
      );
      expect(secondFrame.facts.single.interactionCount!.value, 1);
    });

    test('bounds the UI send-port backlog with credits', () async {
      final runtime = await _startRuntime(maximumInFlightAppends: 1);
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.backlog'),
      );

      final acknowledgement = runtime.appendAcknowledgements.first;
      final first = _append(session, timestamp: 1);
      final second = _append(
        session,
        timestamp: 2,
        value: MeasurementWorkerAppendValue.interaction,
      );

      expect(first, MeasurementWorkerAppendOutcome.accepted);
      expect(second, MeasurementWorkerAppendOutcome.saturated);
      await acknowledgement;
      expect(
        _append(
          session,
          timestamp: 2,
          value: MeasurementWorkerAppendValue.interaction,
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
    });

    test('keeps multi-session route identities and aggregates isolated',
        () async {
      final runtime = await _startRuntime(maximumSessions: 2);
      addTearDown(runtime.shutdown);
      final alpha = await _open(
        runtime,
        _registration(sessionId: 'session.alpha', occurrenceOffset: 1),
      );
      final beta = await _open(
        runtime,
        _registration(sessionId: 'session.beta', occurrenceOffset: 9),
      );

      final overflow = await runtime.openSession(
        _registration(sessionId: 'session.capacity'),
      );
      expect(overflow.outcome, MeasurementWorkerOpenSessionOutcome.saturated);

      final alphaAcknowledgement = runtime.appendAcknowledgements.first;
      expect(_append(alpha, timestamp: 1),
          MeasurementWorkerAppendOutcome.accepted);
      await alphaAcknowledgement;
      final betaAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
        _append(
          beta,
          timestamp: 1,
          value: MeasurementWorkerAppendValue.interaction,
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await betaAcknowledgement;

      final alphaFrame = _frame((await alpha.checkpoint()).batch!);
      final betaFrame = _frame((await beta.checkpoint()).batch!);
      expect(alphaFrame.facts.single.occurrenceId, _occurrence(1));
      expect(betaFrame.facts.single.occurrenceId, _occurrence(9));
      expect(alphaFrame.facts.single.interactionCount!.value, 0);
      expect(betaFrame.facts.single.interactionCount!.value, 1);
    });

    test('saturates prepared-batch retention without dropping active state',
        () async {
      final runtime = await _startRuntime(maximumRetainedPreparedBatches: 1);
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.prepared-saturation'),
      );

      final firstAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
        _append(session, timestamp: 1),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await firstAcknowledgement;
      final first = await session.checkpoint();
      expect(first.outcome, MeasurementWorkerBatchOutcome.prepared);

      final secondAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
        _append(
          session,
          timestamp: 2,
          value: MeasurementWorkerAppendValue.interaction,
        ),
        MeasurementWorkerAppendOutcome.accepted,
      );
      await secondAcknowledgement;
      final saturated = await session.checkpoint();
      expect(saturated.outcome, MeasurementWorkerBatchOutcome.saturated);

      expect(
        (await runtime.releasePreparedBatch(first.batch!.batchId)).outcome,
        MeasurementWorkerReleaseOutcome.released,
      );
      final recovered = await session.checkpoint();
      expect(recovered.outcome, MeasurementWorkerBatchOutcome.prepared);
      expect(_frame(recovered.batch!).sequence, 2);
      expect(_frame(recovered.batch!).facts.single.interactionCount!.value, 1);
    });

    test('finalizes, retries exact bytes, and releases worker ownership',
        () async {
      final runtime = await _startRuntime(maximumRetainedPreparedBatches: 2);
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.finality'),
      );

      final acknowledgement = runtime.appendAcknowledgements.first;
      expect(_append(session, timestamp: 1),
          MeasurementWorkerAppendOutcome.accepted);
      await acknowledgement;
      final checkpoint = await session.checkpoint();
      expect(checkpoint.outcome, MeasurementWorkerBatchOutcome.prepared);
      final finalization = await session.teardown();
      expect(finalization.outcome, MeasurementWorkerBatchOutcome.prepared);
      final batch = finalization.batch!;
      expect(batch.isFinal, isTrue);
      expect(batch.sequence, 2);
      expect(
        _append(
          session,
          timestamp: 2,
          value: MeasurementWorkerAppendValue.interaction,
        ),
        MeasurementWorkerAppendOutcome.finalized,
      );

      final retry = await runtime.retryPreparedBatch(batch.batchId);
      expect(retry.outcome, MeasurementWorkerBatchOutcome.prepared);
      expect(
        retry.batch!.canonicalFrameBytes,
        orderedEquals(batch.canonicalFrameBytes),
      );
      expect(
        retry.batch!.canonicalRequestBytes,
        orderedEquals(batch.canonicalRequestBytes),
      );
      expect(retry.batch!.requestSha256, batch.requestSha256);
      expect(runtime.workerOwnedByteCount, greaterThan(0));

      expect(
        (await runtime.releasePreparedBatch(checkpoint.batch!.batchId)).outcome,
        MeasurementWorkerReleaseOutcome.released,
      );
      final release = await runtime.releasePreparedBatch(batch.batchId);
      expect(release.outcome, MeasurementWorkerReleaseOutcome.released);
      expect(release.workerOwnedByteCount, 0);
      expect(runtime.workerOwnedByteCount, 0);
      final missingRetry = await runtime.retryPreparedBatch(batch.batchId);
      expect(missingRetry.outcome, MeasurementWorkerBatchOutcome.unknownBatch);
    });

    test('propagates a worker crash as a fail-closed unavailable runtime',
        () async {
      final runtime = await _startRuntime();
      addTearDown(runtime.shutdown);
      final session = await _open(
        runtime,
        _registration(sessionId: 'session.failure'),
      );

      runtime.debugKillWorkerForTesting();
      await _eventually(() => !runtime.isAvailable);
      expect(_append(session, timestamp: 1),
          MeasurementWorkerAppendOutcome.unavailable);
      final checkpoint = await session.checkpoint();
      expect(checkpoint.outcome, MeasurementWorkerBatchOutcome.unavailable);
    });

    test('shutdown runs final barriers in deterministic session-id order',
        () async {
      final runtime = await _startRuntime(
        maximumSessions: 2,
        maximumRetainedPreparedBatches: 4,
      );
      final zulu = await _open(
        runtime,
        _registration(sessionId: 'session.zulu'),
      );
      final alpha = await _open(
        runtime,
        _registration(sessionId: 'session.alpha-shutdown'),
      );

      final firstAcknowledgement = runtime.appendAcknowledgements.first;
      expect(
          _append(zulu, timestamp: 1), MeasurementWorkerAppendOutcome.accepted);
      await firstAcknowledgement;
      final secondAcknowledgement = runtime.appendAcknowledgements.first;
      expect(_append(alpha, timestamp: 1),
          MeasurementWorkerAppendOutcome.accepted);
      await secondAcknowledgement;

      final shutdown = await runtime.shutdown();
      expect(shutdown.outcome, MeasurementWorkerShutdownOutcome.closed);
      expect(
        shutdown.preparedBatches.map((batch) => batch.sessionId),
        ['session.alpha-shutdown', 'session.zulu'],
      );
      expect(runtime.isAvailable, isFalse);
      expect(_append(alpha, timestamp: 2),
          MeasurementWorkerAppendOutcome.finalized);
    });
  });

  test(
      'unsupported isolate implementation fails closed instead of using UI work',
      () async {
    final result = await unsupported.startMeasurementWorkerRuntime(
      configuration: _configuration(),
    );

    expect(result.state, isNull);
    expect(result.unavailableReason, 'native_isolate_worker_unsupported');
  });

  test('protocol messages are closed primitive and typed-data values', () {
    final registration = _registration(sessionId: 'session.protocol');
    final register = MeasurementWorkerProtocol.register(
      requestId: 1,
      registration: registration,
    );
    final append = MeasurementWorkerProtocol.append(
      sessionId: registration.sessionId,
      record: MeasurementWorkerAppendRecord(
        routeIndex: 0,
        monotonicTimestampMicros: 1,
        value: MeasurementWorkerAppendValue.presentation,
      ),
    );
    final shutdownAcknowledged =
        MeasurementWorkerProtocol.shutdownAcknowledged(requestId: 1);

    _expectClosedWire(register);
    _expectClosedWire(append);
    _expectClosedWire(shutdownAcknowledged);
    expect(MeasurementWorkerProtocol.decodeInbound(register),
        isA<MeasurementWorkerRegisterMessage>());
    expect(MeasurementWorkerProtocol.decodeInbound(append),
        isA<MeasurementWorkerAppendMessage>());
    expect(
      MeasurementWorkerProtocol.decodeInbound(shutdownAcknowledged),
      isA<MeasurementWorkerShutdownAcknowledgedMessage>(),
    );
    expect(
      () => MeasurementWorkerProtocol.decodeInbound(const <Object?>[]),
      throwsA(isA<MeasurementWorkerProtocolException>()),
    );
  });

  test(
      'UI append path contains no codec, hash, isolate, or identifier validation work',
      () {
    final dispatcher =
        File('lib/src/measurement/measurement_worker.dart').readAsStringSync();
    final native = File('lib/src/measurement/measurement_worker_native.dart')
        .readAsStringSync();
    final protocol =
        File('lib/src/measurement/measurement_worker_protocol.dart')
            .readAsStringSync();
    final runtimeAppend = _section(
      native,
      'MeasurementWorkerAppendOutcome append(\n',
      '  Future<MeasurementWorkerBatchResult> requestSessionBarrier',
    );
    final sessionAppend = _section(
      native,
      'MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record)',
      '  @override\n  Future<MeasurementWorkerBatchResult> checkpoint',
    );
    final hotRecord = _section(
      protocol,
      'final class MeasurementWorkerAppendRecord {',
      '/// Fixed limits for one worker-owned capture session.',
    );
    final publicAppend = _section(
      protocol,
      'MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>',
      '  /// Orders a nonterminal checkpoint after prior appends.',
    );
    final protocolAppend = _section(
      protocol,
      'static List<Object?> append({',
      '  /// Builds one ordered checkpoint barrier.',
    );

    expect(
      dispatcher,
      contains("if (dart.library.io) 'measurement_worker_native.dart'"),
    );
    expect(native, contains('CanonicalJsonCodec.encode'));
    expect(native, contains('MeasurementIngestRequestV1.fromFactFrame'));
    // The runtime keeps the original capture worker and adds one separately bounded
    // outbox/upload worker. Each runtime is long-lived; neither is spawned by
    // an append path (which the scoped checks below enforce).
    expect(RegExp(r'Isolate\.spawn').allMatches(native), hasLength(2));
    for (final section in [runtimeAppend, sessionAppend, publicAppend]) {
      for (final forbidden in const [
        'CanonicalJsonCodec',
        'MeasurementIngestRequestV1',
        'MeasurementFactFrameV1',
        'sha256',
        'hash',
        'jsonEncode',
        'compute(',
        'Isolate.spawn',
        'async',
        'await',
        'Timer',
        'Map<',
      ]) {
        expect(section, isNot(contains(forbidden)), reason: forbidden);
      }
    }
    for (final section in [
      hotRecord,
      publicAppend,
      sessionAppend,
      protocolAppend
    ]) {
      for (final forbidden in const [
        'RegExp',
        '_isOpaqueIdentifier',
        '_requireString',
        'record.sessionId',
        '.hasMatch(',
      ]) {
        expect(section, isNot(contains(forbidden)), reason: forbidden);
      }
    }
    expect(hotRecord, isNot(contains('sessionId')));
    expect(hotRecord, isNot(contains('String')));
    expect(publicAppend, isNot(contains('sessionId')));
    expect(sessionAppend, isNot(contains('sessionId')));
    expect(
        runtimeAppend,
        contains(
            '_pendingAppendCount >= _configuration.maximumInFlightAppends'));
    expect(runtimeAppend, contains('MeasurementWorkerProtocol.append('));
    expect(runtimeAppend, contains('sessionId: session.sessionId'));
  });
}

Future<MeasurementWorkerRuntime> _startRuntime({
  int maximumSessions = 4,
  int maximumInFlightAppends = 8,
  int maximumRetainedPreparedBatches = 8,
}) async {
  final started = await MeasurementWorkerRuntime.start(
    configuration: _configuration(
      maximumSessions: maximumSessions,
      maximumInFlightAppends: maximumInFlightAppends,
      maximumRetainedPreparedBatches: maximumRetainedPreparedBatches,
    ),
  );
  expect(started.outcome, MeasurementWorkerRuntimeStartOutcome.started);
  return started.runtime!;
}

MeasurementWorkerRuntimeConfiguration _configuration({
  int maximumSessions = 4,
  int maximumInFlightAppends = 8,
  int maximumRetainedPreparedBatches = 8,
}) =>
    MeasurementWorkerRuntimeConfiguration(
      maximumSessions: maximumSessions,
      maximumInFlightAppends: maximumInFlightAppends,
      maximumRetainedPreparedBatches: maximumRetainedPreparedBatches,
    );

Future<MeasurementWorkerSession> _open(
  MeasurementWorkerRuntime runtime,
  MeasurementWorkerSessionRegistration registration,
) async {
  final opened = await runtime.openSession(registration);
  expect(opened.outcome, MeasurementWorkerOpenSessionOutcome.opened);
  return opened.session!;
}

MeasurementWorkerAppendOutcome _append(
  MeasurementWorkerSession session, {
  required int timestamp,
  MeasurementWorkerAppendValue value =
      MeasurementWorkerAppendValue.presentation,
}) =>
    session.append(
      MeasurementWorkerAppendRecord(
        routeIndex: 0,
        monotonicTimestampMicros: timestamp,
        value: value,
      ),
    );

MeasurementFactFrameV1 _frame(MeasurementWorkerPreparedBatch batch) =>
    MeasurementFactFrameV1.fromCanonicalBytes(batch.canonicalFrameBytes);

MeasurementWorkerSessionRegistration _registration({
  required String sessionId,
  int routeCount = 2,
  int occurrenceOffset = 0,
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
    captureSessionNonce: 'nonce.$sessionId',
    publicationContextCanonicalBytes: context.canonicalBytes,
    routes: [
      for (var index = 0; index < routeCount; index += 1)
        MeasurementWorkerRouteIdentity(
          occurrenceId: _occurrence(occurrenceOffset + index),
          lineageId: 'lineage.$sessionId.$index',
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

String _occurrence(int index) => index.toRadixString(16).padLeft(64, '0');

final _bindingReference = MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId('authority.worker'),
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

String _section(String source, String startNeedle, String endNeedle) {
  final start = source.indexOf(startNeedle);
  final end = source.indexOf(endNeedle, start);
  expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
  expect(end, greaterThan(start), reason: endNeedle);
  return source.substring(start, end);
}

Future<void> _eventually(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for asynchronous worker state');
}
