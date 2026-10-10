import 'commerce_report_queue_stub.dart'
    if (dart.library.io) 'commerce_report_queue_io.dart' as implementation;
import 'commerce_report_queue_protocol.dart';

export 'commerce_report_queue_protocol.dart';

/// Creates the platform-selected durable commerce report queue.
Future<CommerceReportQueue> createCommerceReportQueue() =>
    implementation.createCommerceReportQueue();
