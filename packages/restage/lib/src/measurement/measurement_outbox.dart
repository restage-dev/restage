import 'measurement_outbox_stub.dart'
    if (dart.library.io) 'measurement_outbox_io.dart' as implementation;
import 'measurement_outbox_protocol.dart';

export 'measurement_outbox_protocol.dart';

/// Creates the platform-selected durable measurement outbox.
///
/// The caller must pass a path already resolved on the root isolate. On an
/// unsupported platform this returns a fail-closed store and performs no I/O.
MeasurementOutboxStore createMeasurementOutboxStore({
  required MeasurementOutboxConfiguration configuration,
  MeasurementOutboxClock? clock,
  MeasurementOutboxFileSystem? fileSystem,
}) =>
    implementation.createMeasurementOutboxStore(
      configuration: configuration,
      clock: clock ?? measurementOutboxSystemClock,
      fileSystem: fileSystem,
    );
