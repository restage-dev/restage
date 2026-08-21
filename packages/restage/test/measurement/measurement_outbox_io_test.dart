import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox.dart';
import 'package:restage/src/measurement/measurement_outbox_stub.dart'
    as unsupported;

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

      expect((await store.commit(first)).outcome,
          MeasurementOutboxCommitOutcome.committed);
      expect((await store.commit(second)).outcome,
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

      final restarted = _store(support);
      await restarted.open();
      expect((await restarted.nextReady())!.record.batch.sequence, 1);
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
      final store = _store(support);
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
      expect(firstRetry.nextRetryUtcMicros,
          clock.now.microsecondsSinceEpoch + 1000000);
      expect(await store.nextReady(), isNull);
      clock.advance(const Duration(seconds: 1));
      final secondLease = await store.nextReady();
      expect(secondLease, isNotNull);
      final secondRetry = await store.scheduleRetry(secondLease!);
      expect(secondRetry.attempt, 1);
      expect(secondRetry.nextRetryUtcMicros,
          clock.now.microsecondsSinceEpoch + 2000000);

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
}) =>
    outboxPreparedBatch(
      sessionId: sessionId,
      sequence: sequence,
      variant: body,
      factCount: factCount,
    );

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
