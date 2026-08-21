import 'measurement_outbox_protocol.dart';
import 'measurement_upload_client_protocol.dart';

/// Builds an unsupported upload client without constructing an HTTP client.
MeasurementUploadClient createMeasurementUploadClient({
  required MeasurementUploadConfiguration configuration,
}) =>
    const _UnsupportedMeasurementUploadClient();

final class _UnsupportedMeasurementUploadClient
    implements MeasurementUploadClient {
  const _UnsupportedMeasurementUploadClient();

  @override
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease) async =>
      const MeasurementUploadOutcome.unavailable();
}
