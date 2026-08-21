import 'measurement_upload_client_stub.dart'
    if (dart.library.io) 'measurement_upload_client_io.dart' as implementation;
import 'measurement_upload_client_protocol.dart';

export 'measurement_upload_client_protocol.dart';

/// Creates a worker-local platform-selected exact-byte upload client.
MeasurementUploadClient createMeasurementUploadClient({
  required MeasurementUploadConfiguration configuration,
}) =>
    implementation.createMeasurementUploadClient(configuration: configuration);
