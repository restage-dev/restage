import 'commerce_report_queue_protocol.dart';

/// Builds a fail-closed queue where native application storage is unavailable.
Future<CommerceReportQueue> createCommerceReportQueue() async =>
    const _UnavailableCommerceReportQueue();

final class _UnavailableCommerceReportQueue implements CommerceReportQueue {
  const _UnavailableCommerceReportQueue();

  Never _unavailable() =>
      throw UnsupportedError('Commerce report storage is unavailable');

  @override
  Future<void> acknowledge(String reportId) async => _unavailable();

  @override
  Future<List<CommerceReportRecord>> due() async => _unavailable();

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) async =>
      _unavailable();

  @override
  Future<List<CommerceReportRecord>> open() async => _unavailable();

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) async =>
      _unavailable();
}
