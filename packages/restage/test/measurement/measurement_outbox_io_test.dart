import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox.dart';
import 'package:restage/src/measurement/measurement_outbox_io.dart'
    show MeasurementOutboxIoFileSystem;
import 'package:restage/src/measurement/measurement_outbox_stub.dart'
    as unsupported;
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'support/measurement_outbox_test_support.dart';

void main() {
  group('native measurement outbox recovery', () {
    test('discards torn temporary files without treating them as delivery',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      await journal.create(recursive: true);
      final temporary = File('${journal.path}/interrupted.tmp');
      await temporary.writeAsBytes(const <int>[1, 2, 3], flush: true);

      final store = _store(support);
      final result = await store.open();

      expect(result.outcome, MeasurementOutboxOpenOutcome.opened);
      expect(result.recovery.discardedTemporaryRecords, 1);
      expect(await temporary.exists(), isFalse);
      expect(await store.nextReady(), isNull);
    });

    test('quarantines an invalid ready file and never leases it', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      await journal.create(recursive: true);
      await File('${journal.path}/invalid.ready').writeAsBytes(
        const <int>[9, 9, 9],
        flush: true,
      );

      final store = _store(support);
      final result = await store.open();

      expect(result.outcome, MeasurementOutboxOpenOutcome.opened);
      expect(result.recovery.quarantinedReadyRecords, 1);
      expect(await store.nextReady(), isNull);
      final paths = await journal.list().map((entity) => entity.path).toList();
      expect(paths, contains(endsWith('.quarantine')));
    });

    test('restarts in same-session sequence order and rejects duplicates',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final first =
          _batch(sessionId: 'session.order', sequence: 1, body: 'one');
      final second =
          _batch(sessionId: 'session.order', sequence: 2, body: 'two');
      final other =
          _batch(sessionId: 'session.order.other', sequence: 1, body: 'one');

      expect((await store.commit(first)).outcome,
          MeasurementOutboxCommitOutcome.committed);
      expect((await store.commit(other)).outcome,
          MeasurementOutboxCommitOutcome.committed);
      expect((await store.commit(first)).outcome,
          MeasurementOutboxCommitOutcome.duplicate);
      expect(
        (await store.commit(
          _batch(sessionId: 'session.order', sequence: 1, body: 'different'),
        ))
            .outcome,
        MeasurementOutboxCommitOutcome.sequenceConflict,
      );
      expect((await store.commit(second)).outcome,
          MeasurementOutboxCommitOutcome.committed);
      // The later frame holds everything the earlier one did.
      expect((await store.commit(first)).outcome,
          MeasurementOutboxCommitOutcome.duplicate);

      final restarted = _store(support);
      await restarted.open();
      final lease = (await restarted.nextReady())!;
      expect(lease.record.batch.sessionId, 'session.order.other');
      await restarted.quarantine(
        lease,
        MeasurementOutboxQuarantineReason.permanentRejection,
      );
      // Only the later frame of the first session remains.
      final next = (await restarted.nextReady())!;
      expect(next.record.batch.sessionId, 'session.order');
      expect(next.record.batch.sequence, 2);
    });

    test('a quarantined frame holds back none of its session\'s later frames',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      await store.commit(_batch(sessionId: 'session.refused', sequence: 1));
      final refused = (await store.nextReady())!;
      expect(refused.record.batch.sequence, 1);
      // In flight, it is not superseded until its delivery ends.
      await store.commit(
          _batch(sessionId: 'session.refused', sequence: 2, body: 'final'));

      expect(
        (await store.quarantine(
          refused,
          MeasurementOutboxQuarantineReason.permanentRejection,
        ))
            .outcome,
        MeasurementOutboxStateOutcome.quarantined,
      );
      expect((await store.nextReady())!.record.batch.sequence, 2);
    });

    test('a held frame holds back none of its session\'s later records',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final frame = _batch(sessionId: 'session.held', sequence: 1);
      await store.commit(frame);
      final held = (await store.nextReady())!;
      expect(
        (await store.hold(
          held,
          MeasurementOutboxHoldReason.authenticationFailure,
        ))
            .outcome,
        MeasurementOutboxStateOutcome.held,
      );
      // A diagnostic does not supersede the frame; only ordering lets it go.
      await store.commit(_diagnostic(frame, sequence: 2));
      final next = (await store.nextReady())!;
      expect(next.record.batch.diagnosticSha256, isNotNull);
    });

    test('a later frame retires its session\'s earlier ones, unless in flight',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      // A held clock keeps the scheduled retry from coming due mid-test.
      final now = DateTime.now().toUtc();
      final store = _store(support, clock: () => now);
      await store.open();
      final early = (await store.commit(
        _batch(sessionId: 'session.retire', sequence: 1),
      ))
          .record!;
      final inFlight = (await store.nextReady())!;
      await store.commit(
        _batch(sessionId: 'session.retire', sequence: 2, body: 'two'),
      );
      // The leased frame stays until its delivery ends.
      expect(
        await File('${journal.path}/${early.fileStem}.ready').exists(),
        isTrue,
      );
      expect(await store.nextReady(), isNull);
      expect((await store.scheduleRetry(inFlight)).outcome,
          MeasurementOutboxRetryOutcome.scheduled);
      expect(
        await File('${journal.path}/${early.fileStem}.ready').exists(),
        isFalse,
      );
      final second = (await store.commit(
        _batch(sessionId: 'session.retire', sequence: 3, body: 'three'),
      ))
          .record!;
      // An unleased earlier frame leaves on commit.
      final remaining = await journal
          .list()
          .map((entity) => entity.path)
          .where((path) => path.endsWith('.ready'))
          .toList();
      expect(remaining, [endsWith('${second.fileStem}.ready')]);
    });

    test('a session id another launch used is neither refused nor retired',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final earlier = _batch(
        sessionId: 'measurement-host.1',
        sequence: 1,
        nonce: 'n.launch1',
      );
      await store.commit(earlier);
      expect(
        (await store.commit(_batch(
          sessionId: 'measurement-host.1',
          sequence: 1,
          body: 'next',
          nonce: 'n.launch2',
        )))
            .outcome,
        MeasurementOutboxCommitOutcome.committed,
      );
      expect(
        (await store.commit(_batch(
          sessionId: 'measurement-host.1',
          sequence: 2,
          body: 'last',
          nonce: 'n.launch2',
        )))
            .outcome,
        MeasurementOutboxCommitOutcome.committed,
      );
      final first = (await store.nextReady())!;
      expect(
          first.record.batch.captureSessionNonce, earlier.captureSessionNonce);
    });

    test('startup retires a frame a later one superseded before a crash',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal = await _journal(support);
      final early = await _write(journal, sequence: 1, body: 'early');
      final last = await _write(journal, sequence: 2, body: 'last');

      final store = _store(support);
      await store.open();

      expect(await File('${journal.path}/${early.fileStem}.ready').exists(),
          isFalse);
      expect(await File('${journal.path}/${last.fileStem}.ready').exists(),
          isTrue);
    });

    test(
        'a frame quarantined at startup supersedes none of its session\'s '
        'earlier ones', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal = await _journal(support);
      final early = await _write(journal, sequence: 1, body: 'early');
      final last = await _write(journal, sequence: 2, body: 'last');
      // The later frame's marker is corrupt, so recovery quarantines it.
      await File('${journal.path}/${last.fileStem}.hold')
          .writeAsBytes(const <int>[1, 2, 3], flush: true);

      final store = _store(support);
      final opened = await store.open();

      expect(opened.recovery.quarantinedReadyRecords, 1);
      final lease = (await store.nextReady())!;
      expect(lease.record.fileStem, early.fileStem);
    });

    test('an acknowledged later frame covers a re-commit of an earlier one',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final fileSystem = _FailingDeleteFileSystem();
      final store = createMeasurementOutboxStore(
        configuration: MeasurementOutboxConfiguration(
          applicationSupportPath: support.path,
          configurationFingerprint: 'config.test.v1',
        ),
        clock: null,
        fileSystem: fileSystem,
      );
      await store.open();
      await store.commit(
        _batch(sessionId: 'session.acked', sequence: 2, body: 'last'),
      );
      final lease = (await store.nextReady())!;
      // Delivered, but its files outlive the acknowledgement.
      fileSystem.failDeletes = true;
      final acknowledgement = MeasurementOutboxAcknowledgement.fromReceipt(
        record: lease.record,
        receipt: receiptForRecord(lease.record),
      )!;
      expect((await store.acknowledge(lease, acknowledgement)).outcome,
          MeasurementOutboxAcknowledgementOutcome.acknowledgedPendingCleanup);
      fileSystem.failDeletes = false;
      expect(
        (await store.commit(
          _batch(sessionId: 'session.acked', sequence: 1, body: 'early'),
        ))
            .outcome,
        MeasurementOutboxCommitOutcome.duplicate,
      );
    });

    test('quarantines duplicate ready coordinates found at startup', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      await journal.create(recursive: true);
      final first = _record(
        sessionId: 'session.recovery-duplicate',
        sequence: 1,
        body: 'one',
      );
      final second = _record(
        sessionId: 'session.recovery-duplicate',
        sequence: 1,
        body: 'two',
      );
      await File('${journal.path}/${first.fileStem}.ready').writeAsBytes(
        MeasurementOutboxRecordCodec.encode(first),
        flush: true,
      );
      await File('${journal.path}/${second.fileStem}.ready').writeAsBytes(
        MeasurementOutboxRecordCodec.encode(second),
        flush: true,
      );

      final store = _store(support);
      final opened = await store.open();

      expect(opened.recovery.quarantinedReadyRecords, 2);
      expect(await store.nextReady(), isNull);
    });

    test('exposes at most one lease even across independent sessions',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      // A held clock keeps the scheduled retry from coming due mid-test.
      final now = DateTime.now().toUtc();
      final store = _store(support, clock: () => now);
      await store.open();
      await store.commit(_batch(sessionId: 'session.lease.one'));
      await store.commit(_batch(sessionId: 'session.lease.two'));

      final firstLease = await store.nextReady();

      expect(firstLease, isNotNull);
      expect(await store.nextReady(), isNull);
      expect((await store.scheduleRetry(firstLease!)).outcome,
          MeasurementOutboxRetryOutcome.scheduled);
      expect((await store.nextReady())!.record.batch.sessionId,
          'session.lease.two');
    });

    test('converges a durable acknowledgement marker before ready deletion',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final committed = await store.commit(_batch());
      final record = committed.record!;
      final acknowledgement = acknowledgementForRecord(record);
      final marker = MeasurementOutboxMarkerCodec.encode(
        MeasurementOutboxMarker.acknowledgement(
          record: record,
          acknowledgement: acknowledgement,
        ),
      );
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      await File('${journal.path}/${record.fileStem}.acked').writeAsBytes(
        marker,
        flush: true,
      );

      final restarted = _store(support);
      final recovered = await restarted.open();

      expect(recovered.recovery.acknowledgedRecordsCleaned, 1);
      expect(await restarted.nextReady(), isNull);
      expect(await File('${journal.path}/${record.fileStem}.ready').exists(),
          isFalse);
    });

    test('quarantines a malformed acknowledgement marker on restart', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final record = (await store.commit(_batch())).record!;
      final journal =
          Directory('${support.path}/restage/measurement/outbox-v1');
      await File('${journal.path}/${record.fileStem}.acked').writeAsBytes(
        const <int>[1, 2, 3],
        flush: true,
      );

      final restarted = _store(support);
      final opened = await restarted.open();

      expect(opened.recovery.quarantinedReadyRecords, 1);
      expect(await restarted.nextReady(), isNull);
      expect(
        await File('${journal.path}/${record.fileStem}.quarantine').exists(),
        isTrue,
      );
    });
  });

  group('native measurement outbox bounds and lifecycle', () {
    test('keeps existing records when the exact eight-record cap saturates',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();

      for (var index = 0;
          index < kMeasurementOutboxMaximumPendingRecords;
          index += 1) {
        expect(
          (await store.commit(
            _batch(
                sessionId: 'session.count.$index', sequence: 1, body: '$index'),
          ))
              .outcome,
          MeasurementOutboxCommitOutcome.committed,
        );
      }
      expect(
        (await store.commit(
          _batch(
              sessionId: 'session.count.overflow',
              sequence: 1,
              body: 'overflow'),
        ))
            .outcome,
        MeasurementOutboxCommitOutcome.outboxSaturated,
      );
      expect(await store.nextReady(), isNotNull);
    });

    test('enforces the total all-state byte cap without eviction', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      var admitted = 0;
      MeasurementOutboxCommitResult? saturation;
      for (var index = 0;
          index < kMeasurementOutboxMaximumPendingRecords;
          index += 1) {
        final result = await store.commit(
          _batch(
            sessionId: 'session.bytes.$index',
            sequence: 1,
            body: 'large.$index',
            factCount: 1024,
          ),
        );
        if (result.outcome == MeasurementOutboxCommitOutcome.outboxSaturated) {
          saturation = result;
          break;
        }
        expect(result.outcome, MeasurementOutboxCommitOutcome.committed);
        admitted += 1;
      }

      expect(admitted, lessThan(kMeasurementOutboxMaximumPendingRecords));
      expect(
          saturation?.outcome, MeasurementOutboxCommitOutcome.outboxSaturated);
      expect(
          (await store.nextReady())!.record.batch.sessionId, 'session.bytes.0');
    });

    test('persists deterministic retry and expires unacknowledged data at 24h',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final clock = _MutableClock(DateTime.utc(2026, 8, 16, 12));
      final store = _store(support, clock: clock.call);
      await store.open();
      await store.commit(_batch());
      final firstLease = await store.nextReady();
      final firstRetry = await store.scheduleRetry(firstLease!);

      expect(firstRetry.outcome, MeasurementOutboxRetryOutcome.scheduled);
      expect(firstRetry.attempt, 0);
      expect(
          firstRetry.nextRetryUtcMicros,
          inInclusiveRange(clock.now.microsecondsSinceEpoch + 750000,
              clock.now.microsecondsSinceEpoch + 1250000));
      expect(await store.nextReady(), isNull);
      clock.advance(const Duration(milliseconds: 1250));
      final secondLease = await store.nextReady();
      expect(secondLease, isNotNull);
      final secondRetry = await store.scheduleRetry(secondLease!);
      expect(secondRetry.attempt, 1);
      expect(
          secondRetry.nextRetryUtcMicros,
          inInclusiveRange(clock.now.microsecondsSinceEpoch + 1500000,
              clock.now.microsecondsSinceEpoch + 2500000));

      clock.advance(kMeasurementOutboxMaximumRetention);
      final expired = await store.purgeExpired();
      expect(expired.outcome, MeasurementOutboxPurgeOutcome.retentionExpired);
      expect(expired.purgedRecordCount, 1);
      expect(await store.nextReady(), isNull);
    });

    test('schedules a retention wake for held unacknowledged state', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final clock = _MutableClock(DateTime.utc(2026, 8, 16, 12));
      final store = _store(support, clock: clock.call);
      await store.open();
      await store.commit(_batch());
      final lease = await store.nextReady();
      expect(lease, isNotNull);
      expect(
        (await store.hold(
          lease!,
          MeasurementOutboxHoldReason.authenticationFailure,
        ))
            .outcome,
        MeasurementOutboxStateOutcome.held,
      );

      final schedule = store as MeasurementOutboxRetrySchedule;
      expect(
        await schedule.nextReadyDelay(),
        kMeasurementOutboxMaximumRetention,
      );

      clock.advance(kMeasurementOutboxMaximumRetention);
      expect(
        (await store.purgeExpired()).purgedRecordCount,
        1,
      );
      expect(await schedule.nextReadyDelay(), isNull);
    });

    test('holds old configuration records until a truthful cutover purge',
        () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final oldStore = _store(support, fingerprint: 'config.old');
      await oldStore.open();
      await oldStore.commit(_batch());

      final newStore = _store(support, fingerprint: 'config.new');
      final opened = await newStore.open();

      expect(opened.recovery.configurationHeldRecords, 1);
      expect(await newStore.nextReady(), isNull);
      final purged = await newStore.purge(
        MeasurementOutboxPurgeReason.configurationReset,
      );
      expect(purged.outcome, MeasurementOutboxPurgeOutcome.configurationReset);
      expect(purged.purgedRecordCount, 1);
    });

    test('reports privacy reset as local unacknowledged removal', () async {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      await store.commit(_batch(sessionId: 'session.reset.one'));
      await store.commit(_batch(sessionId: 'session.reset.two'));

      final purged =
          await store.purge(MeasurementOutboxPurgeReason.privacyReset);

      expect(
        purged.outcome,
        MeasurementOutboxPurgeOutcome.purgedUnacknowledged,
      );
      expect(purged.purgedRecordCount, 2);
      expect(await store.nextReady(), isNull);
    });

    test('unsupported store fails closed without touching its filesystem seam',
        () async {
      final fileSystem = _RecordingFileSystem();
      final store = unsupported.createMeasurementOutboxStore(
        configuration: MeasurementOutboxConfiguration(
          applicationSupportPath: '/not-used',
          configurationFingerprint: 'config.stub',
        ),
        clock: () => DateTime.utc(2026, 8, 16),
        fileSystem: fileSystem,
      );

      expect((await store.open()).outcome,
          MeasurementOutboxOpenOutcome.unavailable);
      expect((await store.commit(_batch())).outcome,
          MeasurementOutboxCommitOutcome.unavailable);
      expect(fileSystem.operationCount, 0);
    });
  });
}

Future<Directory> _temporarySupportDirectory() =>
    Directory.systemTemp.createTemp('restage-measurement-outbox-test-');

MeasurementOutboxStore _store(
  Directory support, {
  MeasurementOutboxClock? clock,
  String fingerprint = 'config.test.v1',
}) =>
    createMeasurementOutboxStore(
      configuration: MeasurementOutboxConfiguration(
        applicationSupportPath: support.path,
        configurationFingerprint: fingerprint,
      ),
      clock: clock,
    );

MeasurementOutboxPreparedBatch _batch({
  String sessionId = 'session.test',
  int sequence = 1,
  String body = 'body',
  int factCount = 1,
  String? nonce,
}) =>
    outboxPreparedBatch(
      sessionId: sessionId,
      sequence: sequence,
      variant: body,
      factCount: factCount,
      nonce: nonce ?? 'n.$sessionId',
    );

// The terminal diagnostic of [frame]'s session.
MeasurementOutboxPreparedBatch _diagnostic(
  MeasurementOutboxPreparedBatch frame, {
  required int sequence,
}) {
  final binding = MeasurementPublicationBindingReferenceV1.fromCanonicalBytes(
    frame.publicationBindingReferenceCanonicalBytes,
  );
  final request = MeasurementPresentationDiagnosticRequestV1.fromDiagnostic(
    const MeasurementPresentationDiagnosticV1(
      rootPresentationReports: MeasurementRootPresentationReportsV1.none,
      stepObserved: false,
      finishReason: MeasurementPresentationFinishReasonV1.paintFailed,
      captureIncomplete: true,
    ),
    captureSessionNonce: frame.captureSessionNonce,
    publicationBindingReference: binding,
    sequence: sequence,
  );
  return MeasurementOutboxPreparedBatch.fromWorkerPreparedDiagnosticBatch(
    MeasurementWorkerPreparedBatch(
      batchId: 'batch.diagnostic',
      sessionId: frame.sessionId,
      isFinal: true,
      sequence: sequence,
      canonicalFrameBytes: const [],
      frameSha256: '',
      canonicalRequestBytes: request.canonicalBytes,
      canonicalRequestBase64: request.canonicalRequestBase64,
      requestSha256: request.requestSha256,
      ownedByteCount: 1,
    ),
    captureSessionNonce: frame.captureSessionNonce,
    publicationBindingReferenceCanonicalBytes:
        frame.publicationBindingReferenceCanonicalBytes,
  );
}

Future<Directory> _journal(Directory support) =>
    Directory('${support.path}/restage/measurement/outbox-v1')
        .create(recursive: true);

// A record of one session as a crashed run left it in [journal].
Future<MeasurementOutboxRecord> _write(
  Directory journal, {
  required int sequence,
  required String body,
}) async {
  final record = MeasurementOutboxRecord(
    batch: _batch(sessionId: 'session.crash', sequence: sequence, body: body),
    createdAtUtcMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
    configurationFingerprint: 'config.test.v1',
  );
  await File('${journal.path}/${record.fileStem}.ready').writeAsBytes(
    MeasurementOutboxRecordCodec.encode(record),
    flush: true,
  );
  return record;
}

MeasurementOutboxRecord _record({
  required String sessionId,
  required int sequence,
  required String body,
}) =>
    MeasurementOutboxRecord(
      batch: _batch(sessionId: sessionId, sequence: sequence, body: body),
      createdAtUtcMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
      configurationFingerprint: 'config.test.v1',
    );

final class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

// The native filesystem, with deletes that fail while [failDeletes] is set.
final class _FailingDeleteFileSystem implements MeasurementOutboxFileSystem {
  final _io = const MeasurementOutboxIoFileSystem();
  bool failDeletes = false;

  @override
  Future<void> createDirectory(String path) => _io.createDirectory(path);

  @override
  Future<void> delete(String path) => failDeletes
      ? Future.error(const FileSystemException('held'))
      : _io.delete(path);

  @override
  Future<List<MeasurementOutboxFileEntry>> listDirectory(String path) =>
      _io.listDirectory(path);

  @override
  Future<Uint8List> readBytes(String path) => _io.readBytes(path);

  @override
  Future<void> rename(String sourcePath, String destinationPath) =>
      _io.rename(sourcePath, destinationPath);

  @override
  Future<void> writeAndFlush(String path, Uint8List bytes) =>
      _io.writeAndFlush(path, bytes);
}

final class _RecordingFileSystem implements MeasurementOutboxFileSystem {
  int operationCount = 0;

  Never _unexpected() {
    operationCount += 1;
    throw StateError('Unsupported outbox must not perform I/O');
  }

  @override
  Future<void> createDirectory(String path) async => _unexpected();

  @override
  Future<void> delete(String path) async => _unexpected();

  @override
  Future<List<MeasurementOutboxFileEntry>> listDirectory(String path) async =>
      _unexpected();

  @override
  Future<Uint8List> readBytes(String path) async => _unexpected();

  @override
  Future<void> rename(String sourcePath, String destinationPath) async =>
      _unexpected();

  @override
  Future<void> writeAndFlush(String path, Uint8List bytes) async =>
      _unexpected();
}
