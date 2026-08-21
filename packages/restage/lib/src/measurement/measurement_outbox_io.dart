import 'dart:io';
import 'dart:typed_data';

import 'measurement_outbox_protocol.dart';

/// Builds the worker-owned native file journal for `dart:io` platforms.
MeasurementOutboxStore createMeasurementOutboxStore({
  required MeasurementOutboxConfiguration configuration,
  required MeasurementOutboxClock clock,
  MeasurementOutboxFileSystem? fileSystem,
}) =>
    _MeasurementFileOutboxStore(
      configuration: configuration,
      clock: clock,
      fileSystem: fileSystem ?? const MeasurementOutboxIoFileSystem(),
    );

/// Native `dart:io` filesystem implementation used only inside the worker.
final class MeasurementOutboxIoFileSystem
    implements MeasurementOutboxFileSystem {
  /// Creates the default native filesystem bridge.
  const MeasurementOutboxIoFileSystem();

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);

  @override
  Future<List<MeasurementOutboxFileEntry>> listDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return const <MeasurementOutboxFileEntry>[];
    final result = <MeasurementOutboxFileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        result.add(
          MeasurementOutboxFileEntry(
            path: entity.path,
            byteLength: await entity.length(),
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<Uint8List> readBytes(String path) async =>
      Uint8List.fromList(await File(path).readAsBytes());

  @override
  Future<void> writeAndFlush(String path, Uint8List bytes) async {
    final file = await File(path).open(mode: FileMode.write);
    try {
      await file.writeFrom(bytes);
      await file.flush();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> rename(String sourcePath, String destinationPath) =>
      File(sourcePath).rename(destinationPath);

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

final class _MeasurementFileOutboxStore
    implements MeasurementOutboxStore, MeasurementOutboxRetrySchedule {
  _MeasurementFileOutboxStore({
    required this.configuration,
    required MeasurementOutboxClock clock,
    required MeasurementOutboxFileSystem fileSystem,
  })  : _clock = clock,
        _fileSystem = fileSystem;

  final MeasurementOutboxConfiguration configuration;
  final MeasurementOutboxClock _clock;
  final MeasurementOutboxFileSystem _fileSystem;
  final Map<String, _StoredOutboxRecord> _records = {};
  final Set<String> _opaqueQuarantinePaths = {};

  MeasurementOutboxOpenResult? _openResult;
  bool _failed = false;
  int _quarantineSerial = 0;

  String get _directory => configuration.journalDirectory;

  bool get _isOpened =>
      _openResult?.outcome == MeasurementOutboxOpenOutcome.opened && !_failed;

  @override
  Future<MeasurementOutboxOpenResult> open() async {
    final current = _openResult;
    if (current != null) return current;
    try {
      await _fileSystem.createDirectory(_directory);
      var entries = await _sortedEntries();
      var discardedTemporaryRecords = 0;
      var quarantinedReadyRecords = 0;
      var acknowledgedRecordsCleaned = 0;
      var configurationHeldRecords = 0;

      for (final entry in entries.where(
        (entry) => _name(entry.path).endsWith('.tmp'),
      )) {
        await _fileSystem.delete(entry.path);
        discardedTemporaryRecords += 1;
      }
      entries = await _sortedEntries();

      for (final entry in entries.where(
        (entry) => _name(entry.path).endsWith('.ready'),
      )) {
        final record = await _decodeReady(entry.path);
        if (record == null ||
            _name(entry.path) != '${record.fileStem}.ready' ||
            _records.containsKey(record.fileStem)) {
          await _quarantineInvalidReady(entry.path);
          quarantinedReadyRecords += 1;
          continue;
        }
        _records[record.fileStem] = _StoredOutboxRecord(
          record: record,
          readyPath: entry.path,
        );
      }

      entries = await _sortedEntries();
      for (final entry in entries.where(
        (entry) => _name(entry.path).endsWith('.acked'),
      )) {
        final stem = _name(
          entry.path,
        ).substring(0, _name(entry.path).length - 6);
        final record = _records[stem];
        if (record == null) {
          await _fileSystem.delete(entry.path);
          continue;
        }
        final marker = await _decodeMarker(entry.path);
        if (marker == null ||
            marker.kind != MeasurementOutboxMarkerKind.acknowledged ||
            !marker.matches(record.record)) {
          await _enterQuarantine(
            record,
            MeasurementOutboxQuarantineReason.persistenceCorrupt,
          );
          await _fileSystem.delete(entry.path);
          quarantinedReadyRecords += 1;
          continue;
        }
        await _deleteAcknowledgedRecord(
          record,
          acknowledgementPath: entry.path,
        );
        _records.remove(stem);
        acknowledgedRecordsCleaned += 1;
      }

      entries = await _sortedEntries();
      final duplicateGroups = <String, List<_StoredOutboxRecord>>{};
      for (final record in _records.values) {
        duplicateGroups
            .putIfAbsent(
              _sequenceKey(record.record),
              () => <_StoredOutboxRecord>[],
            )
            .add(record);
      }
      for (final group in duplicateGroups.values.where(
        (group) => group.length > 1,
      )) {
        for (final record in group) {
          await _enterQuarantine(
            record,
            MeasurementOutboxQuarantineReason.duplicateSequence,
          );
          quarantinedReadyRecords += 1;
        }
      }

      for (final record in List<_StoredOutboxRecord>.from(_records.values)) {
        final stateResult = await _recoverState(record, entries);
        if (stateResult == _RecoveredState.invalid) {
          await _enterQuarantine(
            record,
            MeasurementOutboxQuarantineReason.persistenceCorrupt,
          );
          quarantinedReadyRecords += 1;
        }
        if (record.state == _StoredOutboxState.ready &&
            record.record.configurationFingerprint !=
                configuration.configurationFingerprint) {
          await _enterHold(
            record,
            MeasurementOutboxHoldReason.configurationMismatch,
          );
          configurationHeldRecords += 1;
        }
      }

      await _cleanupOrphanMarkers();
      final result = MeasurementOutboxOpenResult(
        outcome: MeasurementOutboxOpenOutcome.opened,
        recovery: MeasurementOutboxRecovery(
          discardedTemporaryRecords: discardedTemporaryRecords,
          quarantinedReadyRecords: quarantinedReadyRecords,
          acknowledgedRecordsCleaned: acknowledgedRecordsCleaned,
          configurationHeldRecords: configurationHeldRecords,
        ),
      );
      _openResult = result;
      return result;
    } on Object {
      _failed = true;
      return _failureOpenResult();
    }
  }

  @override
  Future<MeasurementOutboxCommitResult> commit(
    MeasurementOutboxPreparedBatch batch,
  ) async {
    if (!_isOpened) return _unavailableCommitResult();
    final sameSequence = _records.values.where(
      (record) =>
          record.record.batch.sessionId == batch.sessionId &&
          record.record.batch.sequence == batch.sequence,
    );
    if (sameSequence.isNotEmpty) {
      final existing = sameSequence.first.record;
      return MeasurementOutboxCommitResult(
        outcome: existing.batch.bodySha256 == batch.bodySha256
            ? MeasurementOutboxCommitOutcome.duplicate
            : MeasurementOutboxCommitOutcome.sequenceConflict,
        record: existing,
      );
    }

    final record = MeasurementOutboxRecord(
      batch: batch,
      createdAtUtcMicros: _nowUtcMicros(),
      configurationFingerprint: configuration.configurationFingerprint,
    );
    Uint8List encoded;
    try {
      encoded = MeasurementOutboxRecordCodec.encode(record);
    } on MeasurementOutboxCodecException {
      return const MeasurementOutboxCommitResult(
        outcome: MeasurementOutboxCommitOutcome.payloadTooLarge,
        record: null,
      );
    }
    if (encoded.length > kMeasurementOutboxMaximumRecordBytes) {
      return const MeasurementOutboxCommitResult(
        outcome: MeasurementOutboxCommitOutcome.payloadTooLarge,
        record: null,
      );
    }
    try {
      final currentBytes = await _physicalByteCount();
      final logicalRecords = _records.length + _opaqueQuarantinePaths.length;
      if (logicalRecords >= kMeasurementOutboxMaximumPendingRecords ||
          currentBytes +
                  encoded.length +
                  (logicalRecords + 1) *
                      kMeasurementOutboxMaximumReservedStateBytesPerRecord >
              kMeasurementOutboxMaximumPendingBytes) {
        return const MeasurementOutboxCommitResult(
          outcome: MeasurementOutboxCommitOutcome.outboxSaturated,
          record: null,
        );
      }
      final temporaryPath = _pathFor('${record.fileStem}.tmp');
      final readyPath = _pathFor('${record.fileStem}.ready');
      await _fileSystem.writeAndFlush(temporaryPath, encoded);
      final validated = MeasurementOutboxRecordCodec.decode(
        await _fileSystem.readBytes(temporaryPath),
      );
      if (!_sameRecord(validated, record)) {
        throw const MeasurementOutboxCodecException('temporary_record_changed');
      }
      await _fileSystem.rename(temporaryPath, readyPath);
      _records[record.fileStem] = _StoredOutboxRecord(
        record: record,
        readyPath: readyPath,
      );
      return MeasurementOutboxCommitResult(
        outcome: MeasurementOutboxCommitOutcome.committed,
        record: record,
      );
    } on Object {
      return const MeasurementOutboxCommitResult(
        outcome: MeasurementOutboxCommitOutcome.persistenceFailure,
        record: null,
      );
    }
  }

  @override
  Future<MeasurementOutboxLease?> nextReady() async {
    if (!_isOpened) return null;
    if (_records.values.any((record) => record.leased)) return null;
    final purged = await _purgeExpiredInternal();
    if (purged.failed) return null;
    final now = _nowUtcMicros();
    final candidates = _records.values
        .where(
          (record) =>
              record.state == _StoredOutboxState.ready &&
              !record.leased &&
              record.nextRetryUtcMicros <= now &&
              _isEarliestForSession(record),
        )
        .toList()
      ..sort(_compareReadyRecords);
    if (candidates.isEmpty) return null;
    final next = candidates.first;
    next.leased = true;
    return MeasurementOutboxLease(record: next.record);
  }

  @override
  Future<Duration?> nextReadyDelay() async {
    if (!_isOpened) return null;
    final expired = await _purgeExpiredInternal();
    if (expired.failed) return null;
    final now = _nowUtcMicros();
    int? earliestWakeAtUtcMicros;
    for (final stored in _records.values) {
      if (stored.state != _StoredOutboxState.acknowledged) {
        final retentionWakeAtUtcMicros = stored.record.createdAtUtcMicros +
            kMeasurementOutboxMaximumRetention.inMicroseconds;
        if (earliestWakeAtUtcMicros == null ||
            retentionWakeAtUtcMicros < earliestWakeAtUtcMicros) {
          earliestWakeAtUtcMicros = retentionWakeAtUtcMicros;
        }
      }
      if (stored.state == _StoredOutboxState.ready &&
          !stored.leased &&
          _isEarliestForSession(stored)) {
        final retryWakeAtUtcMicros = stored.nextRetryUtcMicros;
        if (earliestWakeAtUtcMicros == null ||
            retryWakeAtUtcMicros < earliestWakeAtUtcMicros) {
          earliestWakeAtUtcMicros = retryWakeAtUtcMicros;
        }
      }
    }
    if (earliestWakeAtUtcMicros == null) return null;
    final remaining = earliestWakeAtUtcMicros - now;
    return Duration(microseconds: remaining > 0 ? remaining : 0);
  }

  @override
  Future<MeasurementOutboxAcknowledgementResult> acknowledge(
    MeasurementOutboxLease lease,
    MeasurementOutboxAcknowledgement acknowledgement,
  ) async {
    if (!_isOpened) {
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.unavailable,
      );
    }
    final stored = _recordForLease(lease);
    if (stored == null) {
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.unknownLease,
      );
    }
    stored.leased = false;
    if (!acknowledgement.matches(stored.record)) {
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.acknowledgementMismatch,
      );
    }
    final acknowledgementPath = _pathFor('${stored.record.fileStem}.acked');
    try {
      await _writeMarker(
        path: acknowledgementPath,
        marker: MeasurementOutboxMarker.acknowledgement(
          record: stored.record,
          acknowledgement: acknowledgement,
        ),
      );
    } on Object {
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.persistenceFailure,
      );
    }
    stored.state = _StoredOutboxState.acknowledged;
    try {
      await _deleteAcknowledgedRecord(
        stored,
        acknowledgementPath: acknowledgementPath,
      );
      _records.remove(stored.record.fileStem);
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.delivered,
      );
    } on Object {
      return const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.acknowledgedPendingCleanup,
      );
    }
  }

  @override
  Future<MeasurementOutboxRetryResult> scheduleRetry(
    MeasurementOutboxLease lease,
  ) async {
    if (!_isOpened) return _unavailableRetryResult();
    final stored = _recordForLease(lease);
    if (stored == null || stored.state != _StoredOutboxState.ready) {
      return const MeasurementOutboxRetryResult(
        outcome: MeasurementOutboxRetryOutcome.unknownLease,
        attempt: null,
        nextRetryUtcMicros: null,
      );
    }
    stored.leased = false;
    if (_isExpired(stored.record)) {
      final result = await _purgeExpiredInternal();
      return MeasurementOutboxRetryResult(
        outcome: result.failed
            ? MeasurementOutboxRetryOutcome.persistenceFailure
            : MeasurementOutboxRetryOutcome.retentionExpired,
        attempt: null,
        nextRetryUtcMicros: null,
      );
    }
    final attempt = stored.retryAttempt + 1;
    if (attempt > kMeasurementOutboxMaximumRetryAttempt) {
      return const MeasurementOutboxRetryResult(
        outcome: MeasurementOutboxRetryOutcome.persistenceFailure,
        attempt: null,
        nextRetryUtcMicros: null,
      );
    }
    final nextRetryUtcMicros =
        _nowUtcMicros() + measurementOutboxRetryDelay(attempt).inMicroseconds;
    final path = _pathFor('${stored.record.fileStem}.retry.$attempt');
    try {
      await _writeMarker(
        path: path,
        marker: MeasurementOutboxMarker.retry(
          record: stored.record,
          attempt: attempt,
          nextRetryUtcMicros: nextRetryUtcMicros,
        ),
      );
      for (final oldPath in stored.retryPaths) {
        if (oldPath != path) await _fileSystem.delete(oldPath);
      }
      stored
        ..retryAttempt = attempt
        ..nextRetryUtcMicros = nextRetryUtcMicros
        ..retryPaths = <String>[path];
      return MeasurementOutboxRetryResult(
        outcome: MeasurementOutboxRetryOutcome.scheduled,
        attempt: attempt,
        nextRetryUtcMicros: nextRetryUtcMicros,
      );
    } on Object {
      return const MeasurementOutboxRetryResult(
        outcome: MeasurementOutboxRetryOutcome.persistenceFailure,
        attempt: null,
        nextRetryUtcMicros: null,
      );
    }
  }

  @override
  Future<MeasurementOutboxStateResult> hold(
    MeasurementOutboxLease lease,
    MeasurementOutboxHoldReason reason,
  ) async {
    if (!_isOpened) return _unavailableStateResult();
    final stored = _recordForLease(lease);
    if (stored == null || stored.state != _StoredOutboxState.ready) {
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.unknownLease,
      );
    }
    stored.leased = false;
    try {
      await _enterHold(stored, reason);
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.held,
      );
    } on Object {
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.persistenceFailure,
      );
    }
  }

  @override
  Future<MeasurementOutboxStateResult> quarantine(
    MeasurementOutboxLease lease,
    MeasurementOutboxQuarantineReason reason,
  ) async {
    if (!_isOpened) return _unavailableStateResult();
    final stored = _recordForLease(lease);
    if (stored == null || stored.state != _StoredOutboxState.ready) {
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.unknownLease,
      );
    }
    stored.leased = false;
    try {
      await _enterQuarantine(stored, reason);
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.quarantined,
      );
    } on Object {
      return const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.persistenceFailure,
      );
    }
  }

  @override
  Future<MeasurementOutboxPurgeResult> purge(
    MeasurementOutboxPurgeReason reason,
  ) async {
    if (!_isOpened) return _unavailablePurgeResult();
    return _purgeRecords(
      reason,
      (record) => record.state != _StoredOutboxState.acknowledged,
    );
  }

  @override
  Future<MeasurementOutboxPurgeResult> purgeExpired() async {
    if (!_isOpened) return _unavailablePurgeResult();
    final result = await _purgeExpiredInternal();
    return MeasurementOutboxPurgeResult(
      outcome: result.failed
          ? MeasurementOutboxPurgeOutcome.failed
          : MeasurementOutboxPurgeOutcome.retentionExpired,
      purgedRecordCount: result.purgedRecordCount,
    );
  }

  Future<_InternalPurgeResult> _purgeExpiredInternal() async {
    final result = await _purgeRecords(
      MeasurementOutboxPurgeReason.retentionExpired,
      (record) =>
          record.state != _StoredOutboxState.acknowledged &&
          _isExpired(record.record),
    );
    return _InternalPurgeResult(
      purgedRecordCount: result.purgedRecordCount,
      failed: result.outcome == MeasurementOutboxPurgeOutcome.failed,
    );
  }

  Future<MeasurementOutboxPurgeResult> _purgeRecords(
    MeasurementOutboxPurgeReason reason,
    bool Function(_StoredOutboxRecord record) shouldPurge,
  ) async {
    var purgedRecordCount = 0;
    var failed = false;
    for (final stored in List<_StoredOutboxRecord>.from(_records.values)) {
      if (!shouldPurge(stored)) continue;
      try {
        final deletedReady = await _deleteReadyAndState(stored);
        if (deletedReady) {
          _records.remove(stored.record.fileStem);
          purgedRecordCount += 1;
        }
      } on Object {
        failed = true;
      }
    }
    if (reason != MeasurementOutboxPurgeReason.retentionExpired) {
      for (final path in List<String>.from(_opaqueQuarantinePaths)) {
        try {
          await _fileSystem.delete(path);
          _opaqueQuarantinePaths.remove(path);
          purgedRecordCount += 1;
        } on Object {
          failed = true;
        }
      }
    }
    return MeasurementOutboxPurgeResult(
      outcome:
          failed ? MeasurementOutboxPurgeOutcome.failed : _purgeOutcome(reason),
      purgedRecordCount: purgedRecordCount,
    );
  }

  Future<MeasurementOutboxRecord?> _decodeReady(String path) async {
    try {
      return MeasurementOutboxRecordCodec.decode(
        await _fileSystem.readBytes(path),
      );
    } on Object {
      return null;
    }
  }

  Future<MeasurementOutboxMarker?> _decodeMarker(String path) async {
    try {
      return MeasurementOutboxMarkerCodec.decode(
        await _fileSystem.readBytes(path),
      );
    } on Object {
      return null;
    }
  }

  Future<_RecoveredState> _recoverState(
    _StoredOutboxRecord stored,
    List<MeasurementOutboxFileEntry> entries,
  ) async {
    final stem = stored.record.fileStem;
    final retryPaths = <String>[];
    var retryMarker = <MeasurementOutboxMarker>[];
    var holdMarkerSeen = false;
    var quarantineMarkerSeen = false;
    for (final entry in entries) {
      final name = _name(entry.path);
      if (name.startsWith('$stem.retry.')) {
        final parsedAttempt = int.tryParse(
          name.substring('$stem.retry.'.length),
        );
        final marker = await _decodeMarker(entry.path);
        if (parsedAttempt == null ||
            marker == null ||
            marker.kind != MeasurementOutboxMarkerKind.retry ||
            marker.attempt != parsedAttempt ||
            !marker.matches(stored.record)) {
          return _RecoveredState.invalid;
        }
        retryPaths.add(entry.path);
        retryMarker.add(marker);
      } else if (name == '$stem.hold') {
        final marker = await _decodeMarker(entry.path);
        if (marker == null ||
            marker.kind != MeasurementOutboxMarkerKind.held ||
            !marker.matches(stored.record)) {
          return _RecoveredState.invalid;
        }
        holdMarkerSeen = true;
      } else if (name == '$stem.quarantine') {
        final marker = await _decodeMarker(entry.path);
        if (marker == null ||
            marker.kind != MeasurementOutboxMarkerKind.quarantined ||
            !marker.matches(stored.record)) {
          return _RecoveredState.invalid;
        }
        quarantineMarkerSeen = true;
      }
    }
    if (holdMarkerSeen && quarantineMarkerSeen) return _RecoveredState.invalid;
    if (retryMarker.isNotEmpty) {
      retryMarker.sort((left, right) => left.attempt.compareTo(right.attempt));
      final latest = retryMarker.last;
      if (retryMarker.length > 1) {
        for (final path in retryPaths) {
          final marker = await _decodeMarker(path);
          if (marker!.attempt != latest.attempt) await _fileSystem.delete(path);
        }
      }
      stored
        ..retryAttempt = latest.attempt
        ..nextRetryUtcMicros = latest.nextRetryUtcMicros
        ..retryPaths = <String>[
          retryPaths.singleWhere(
            (path) => _name(path) == '$stem.retry.${latest.attempt}',
          ),
        ];
    }
    if (holdMarkerSeen) stored.state = _StoredOutboxState.held;
    if (quarantineMarkerSeen) stored.state = _StoredOutboxState.quarantined;
    return _RecoveredState.valid;
  }

  Future<void> _enterHold(
    _StoredOutboxRecord stored,
    MeasurementOutboxHoldReason reason,
  ) async {
    if (stored.state == _StoredOutboxState.held) return;
    if (stored.state != _StoredOutboxState.ready) {
      throw StateError('Cannot hold a non-ready outbox record');
    }
    await _writeMarker(
      path: _pathFor('${stored.record.fileStem}.hold'),
      marker: MeasurementOutboxMarker.hold(
        record: stored.record,
        reason: reason,
      ),
    );
    stored.state = _StoredOutboxState.held;
  }

  Future<void> _enterQuarantine(
    _StoredOutboxRecord stored,
    MeasurementOutboxQuarantineReason reason,
  ) async {
    if (stored.state == _StoredOutboxState.quarantined) return;
    if (stored.state == _StoredOutboxState.acknowledged) {
      throw StateError('Cannot quarantine an acknowledged outbox record');
    }
    final path = _pathFor('${stored.record.fileStem}.quarantine');
    // A corrupt or conflicting sidecar must not prevent the record itself
    // from being durably taken out of egress during recovery.
    await _fileSystem.delete(path);
    await _writeMarker(
      path: path,
      marker: MeasurementOutboxMarker.quarantine(
        record: stored.record,
        reason: reason,
      ),
    );
    stored.state = _StoredOutboxState.quarantined;
  }

  Future<void> _writeMarker({
    required String path,
    required MeasurementOutboxMarker marker,
  }) async {
    final temporaryPath = '$path.tmp';
    final bytes = MeasurementOutboxMarkerCodec.encode(marker);
    await _fileSystem.writeAndFlush(temporaryPath, bytes);
    final validated = MeasurementOutboxMarkerCodec.decode(
      await _fileSystem.readBytes(temporaryPath),
    );
    if (!_sameMarker(validated, marker)) {
      throw const MeasurementOutboxCodecException('temporary_marker_changed');
    }
    await _fileSystem.rename(temporaryPath, path);
  }

  Future<void> _deleteAcknowledgedRecord(
    _StoredOutboxRecord stored, {
    required String acknowledgementPath,
  }) async {
    await _fileSystem.delete(stored.readyPath);
    for (final path in await _statePaths(stored.record.fileStem)) {
      if (path != acknowledgementPath) await _fileSystem.delete(path);
    }
    await _fileSystem.delete(acknowledgementPath);
  }

  Future<bool> _deleteReadyAndState(_StoredOutboxRecord stored) async {
    await _fileSystem.delete(stored.readyPath);
    for (final path in await _statePaths(stored.record.fileStem)) {
      await _fileSystem.delete(path);
    }
    return true;
  }

  Future<List<String>> _statePaths(String stem) async {
    final result = <String>[];
    for (final entry in await _sortedEntries()) {
      final name = _name(entry.path);
      if (name == '$stem.acked' ||
          name == '$stem.hold' ||
          name == '$stem.quarantine' ||
          name.startsWith('$stem.retry.')) {
        result.add(entry.path);
      }
    }
    return result;
  }

  Future<void> _quarantineInvalidReady(String path) async {
    final bytes = await _fileSystem.readBytes(path);
    final digest = _safeFileDigest(bytes);
    final destination =
        '$path.invalid-$digest.${_quarantineSerial += 1}.quarantine';
    await _fileSystem.rename(path, destination);
    _opaqueQuarantinePaths.add(destination);
  }

  Future<void> _cleanupOrphanMarkers() async {
    for (final entry in await _sortedEntries()) {
      final name = _name(entry.path);
      final stem = _markerStem(name);
      if (stem == null || _records.containsKey(stem)) continue;
      if (name.endsWith('.quarantine')) {
        // Invalid ready files are intentionally renamed to an opaque
        // quarantine payload. A decodable marker with no ready record is only
        // stale state and can be removed; retaining it would falsely consume
        // a record slot and journal bytes indefinitely.
        final marker = await _decodeMarker(entry.path);
        if (marker == null) {
          _opaqueQuarantinePaths.add(entry.path);
          continue;
        }
      }
      await _fileSystem.delete(entry.path);
    }
  }

  Future<List<MeasurementOutboxFileEntry>> _sortedEntries() async {
    final entries = await _fileSystem.listDirectory(_directory);
    entries.sort((left, right) => left.path.compareTo(right.path));
    return entries;
  }

  Future<int> _physicalByteCount() async => (await _sortedEntries()).fold<int>(
        0,
        (total, entry) => total + entry.byteLength,
      );

  _StoredOutboxRecord? _recordForLease(MeasurementOutboxLease lease) {
    final stored = _records[lease.fileStem];
    if (stored == null || !_sameRecord(stored.record, lease.record)) {
      return null;
    }
    return stored;
  }

  bool _isEarliestForSession(_StoredOutboxRecord candidate) =>
      !_records.values.any(
        (other) =>
            other.record.batch.sessionId == candidate.record.batch.sessionId &&
            other.record.batch.sequence < candidate.record.batch.sequence &&
            other.state != _StoredOutboxState.acknowledged,
      );

  bool _isExpired(MeasurementOutboxRecord record) =>
      _nowUtcMicros() - record.createdAtUtcMicros >=
      kMeasurementOutboxMaximumRetention.inMicroseconds;

  int _nowUtcMicros() => _clock().toUtc().microsecondsSinceEpoch;

  String _pathFor(String name) => '$_directory/$name';
}

final class _StoredOutboxRecord {
  _StoredOutboxRecord({required this.record, required this.readyPath});

  final MeasurementOutboxRecord record;
  final String readyPath;
  bool leased = false;
  _StoredOutboxState state = _StoredOutboxState.ready;
  int retryAttempt = -1;
  int nextRetryUtcMicros = 0;
  List<String> retryPaths = <String>[];
}

enum _StoredOutboxState { ready, held, quarantined, acknowledged }

enum _RecoveredState { valid, invalid }

final class _InternalPurgeResult {
  const _InternalPurgeResult({
    required this.purgedRecordCount,
    required this.failed,
  });

  final int purgedRecordCount;
  final bool failed;
}

MeasurementOutboxOpenResult _failureOpenResult() =>
    const MeasurementOutboxOpenResult(
      outcome: MeasurementOutboxOpenOutcome.persistenceFailure,
      recovery: MeasurementOutboxRecovery(
        discardedTemporaryRecords: 0,
        quarantinedReadyRecords: 0,
        acknowledgedRecordsCleaned: 0,
        configurationHeldRecords: 0,
      ),
    );

MeasurementOutboxCommitResult _unavailableCommitResult() =>
    const MeasurementOutboxCommitResult(
      outcome: MeasurementOutboxCommitOutcome.unavailable,
      record: null,
    );

MeasurementOutboxRetryResult _unavailableRetryResult() =>
    const MeasurementOutboxRetryResult(
      outcome: MeasurementOutboxRetryOutcome.unavailable,
      attempt: null,
      nextRetryUtcMicros: null,
    );

MeasurementOutboxStateResult _unavailableStateResult() =>
    const MeasurementOutboxStateResult(
      MeasurementOutboxStateOutcome.unavailable,
    );

MeasurementOutboxPurgeResult _unavailablePurgeResult() =>
    const MeasurementOutboxPurgeResult(
      outcome: MeasurementOutboxPurgeOutcome.unavailable,
      purgedRecordCount: 0,
    );

MeasurementOutboxPurgeOutcome _purgeOutcome(
  MeasurementOutboxPurgeReason reason,
) =>
    switch (reason) {
      MeasurementOutboxPurgeReason.privacyReset =>
        MeasurementOutboxPurgeOutcome.purgedUnacknowledged,
      MeasurementOutboxPurgeReason.configurationReset =>
        MeasurementOutboxPurgeOutcome.configurationReset,
      MeasurementOutboxPurgeReason.retentionExpired =>
        MeasurementOutboxPurgeOutcome.retentionExpired,
    };

int _compareReadyRecords(_StoredOutboxRecord left, _StoredOutboxRecord right) {
  final byCreated = left.record.createdAtUtcMicros.compareTo(
    right.record.createdAtUtcMicros,
  );
  if (byCreated != 0) return byCreated;
  final bySession = left.record.batch.sessionId.compareTo(
    right.record.batch.sessionId,
  );
  if (bySession != 0) return bySession;
  return left.record.batch.sequence.compareTo(right.record.batch.sequence);
}

String _sequenceKey(MeasurementOutboxRecord record) =>
    '${record.batch.sessionId}\u0000${record.batch.sequence}';

bool _sameRecord(MeasurementOutboxRecord left, MeasurementOutboxRecord right) =>
    left.batch.sessionId == right.batch.sessionId &&
    left.batch.sequence == right.batch.sequence &&
    left.batch.isFinal == right.batch.isFinal &&
    left.batch.bodySha256 == right.batch.bodySha256 &&
    left.batch.captureSessionNonce == right.batch.captureSessionNonce &&
    left.batch.requestSha256 == right.batch.requestSha256 &&
    left.batch.factFrameSha256 == right.batch.factFrameSha256 &&
    _sameBytes(
      left.batch.publicationBindingReferenceCanonicalBytes,
      right.batch.publicationBindingReferenceCanonicalBytes,
    ) &&
    left.createdAtUtcMicros == right.createdAtUtcMicros &&
    left.configurationFingerprint == right.configurationFingerprint &&
    _sameBytes(left.batch.exactRequestBytes, right.batch.exactRequestBytes);

bool _sameMarker(MeasurementOutboxMarker left, MeasurementOutboxMarker right) =>
    left.kind == right.kind &&
    left.sessionId == right.sessionId &&
    left.sequence == right.sequence &&
    left.bodySha256 == right.bodySha256 &&
    left.attempt == right.attempt &&
    left.nextRetryUtcMicros == right.nextRetryUtcMicros &&
    left.reasonCode == right.reasonCode &&
    left.receiptSha256 == right.receiptSha256;

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _name(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  return path.substring((slash > backslash ? slash : backslash) + 1);
}

String? _markerStem(String name) {
  if (name.endsWith('.acked')) return name.substring(0, name.length - 6);
  if (name.endsWith('.hold')) return name.substring(0, name.length - 5);
  if (name.endsWith('.quarantine')) {
    return name.substring(0, name.length - '.quarantine'.length);
  }
  final retry = name.lastIndexOf('.retry.');
  if (retry > 0) return name.substring(0, retry);
  return null;
}

String _safeFileDigest(List<int> bytes) {
  var value = 2166136261;
  for (final byte in bytes) {
    value ^= byte;
    value = (value * 16777619) & 0xffffffff;
  }
  return value.toRadixString(16).padLeft(8, '0');
}
