import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

import 'commerce_report_queue_protocol.dart';

/// Builds the native commerce report queue under application support storage.
Future<CommerceReportQueue> createCommerceReportQueue() async {
  final supportDirectory = await path_provider.getApplicationSupportDirectory();
  return CommerceFileReportQueue(
    directoryPath: '${supportDirectory.path}/restage/commerce/reports-v1',
  );
}

/// A commerce-specific native file journal.
final class CommerceFileReportQueue implements CommerceReportQueue {
  CommerceFileReportQueue({
    required this.directoryPath,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (directoryPath.isEmpty) {
      throw ArgumentError.value(
        directoryPath,
        'directoryPath',
        'must not be empty',
      );
    }
  }

  final String directoryPath;
  final DateTime Function() _clock;
  final Map<String, CommerceReportRecord> _records =
      <String, CommerceReportRecord>{};
  Future<void> _serial = Future<void>.value();
  bool _opened = false;

  String get _readyPath => '$directoryPath/reports.json';
  String get _temporaryPath => '$directoryPath/reports.json.tmp';

  @override
  Future<List<CommerceReportRecord>> open() => _run(() async {
        await _ensureOpened();
        return _records.values.toList(growable: false);
      });

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) =>
      _run(() async {
        await _ensureOpened();
        final matchingId = _records[record.reportId];
        if (matchingId != null) {
          if (!matchingId.hasSameProviderIdentity(record)) {
            throw ArgumentError.value(
              record.reportId,
              'record.reportId',
              'is already bound to another provider transaction',
            );
          }
          return matchingId;
        }
        for (final existing in _records.values) {
          if (existing.hasSameProviderIdentity(record)) return existing;
        }
        final next = Map<String, CommerceReportRecord>.of(_records)
          ..[record.reportId] = record;
        await _persist(next);
        _replace(next);
        return record;
      });

  @override
  Future<List<CommerceReportRecord>> due() => _run(() async {
        await _ensureOpened();
        final now = _clock().toUtc();
        return _records.values
            .where((record) => !record.nextRetryAt.isAfter(now))
            .toList(growable: false);
      });

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) =>
      _run(() async {
        await _ensureOpened();
        final current = _records[reportId];
        if (current == null) return null;
        final updated = current.retryAt(
          _clock().toUtc().add(commerceReportRetryDelay(current.retryAttempt)),
        );
        final next = Map<String, CommerceReportRecord>.of(_records)
          ..[reportId] = updated;
        // Already-admitted evidence remains durable. Keep its effective backoff
        // in process even if saving the new retry schedule fails.
        _replace(next);
        await _persist(next);
        return updated;
      });

  @override
  Future<void> acknowledge(String reportId) => _run(() async {
        await _ensureOpened();
        if (!_records.containsKey(reportId)) return;
        final next = Map<String, CommerceReportRecord>.of(_records)
          ..remove(reportId);
        await _persist(next);
        _replace(next);
      });

  Future<void> _ensureOpened() async {
    if (_opened) return;
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final temporary = File(_temporaryPath);
    if (await temporary.exists()) await temporary.delete();
    final ready = File(_readyPath);
    if (await ready.exists()) {
      _records.addAll(_decode(await ready.readAsString()));
    }
    _opened = true;
  }

  Future<void> _persist(Map<String, CommerceReportRecord> records) async {
    final encoded = jsonEncode(<String, Object?>{
      'version': 2,
      'records': records.values.map((record) => record.toJson()).toList(),
    });
    final temporary = File(_temporaryPath);
    final handle = await temporary.open(mode: FileMode.write);
    try {
      await handle.writeFrom(utf8.encode(encoded));
      await handle.flush();
    } finally {
      await handle.close();
    }
    final validated = _decode(await temporary.readAsString());
    if (!_sameRecords(validated, records)) {
      throw StateError('Commerce report journal validation failed');
    }
    await temporary.rename(_readyPath);
  }

  Map<String, CommerceReportRecord> _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map ||
        decoded['version'] != 2 ||
        decoded['records'] is! List) {
      throw const FormatException('Invalid persisted commerce report queue');
    }
    final records = <String, CommerceReportRecord>{};
    for (final value in decoded['records'] as List<Object?>) {
      if (value is! Map) {
        throw const FormatException('Invalid persisted commerce report queue');
      }
      final record = CommerceReportRecord.fromJson(
        value.cast<String, Object?>(),
      );
      if (records.containsKey(record.reportId)) {
        throw const FormatException('Duplicate persisted commerce report');
      }
      records[record.reportId] = record;
    }
    return records;
  }

  void _replace(Map<String, CommerceReportRecord> records) {
    _records
      ..clear()
      ..addAll(records);
  }

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}

bool _sameRecords(
  Map<String, CommerceReportRecord> first,
  Map<String, CommerceReportRecord> second,
) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    final other = second[entry.key];
    if (other == null || !entry.value.hasSameContents(other)) return false;
  }
  return true;
}
