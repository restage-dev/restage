import 'measurement_worker_protocol.dart';

/// Fails closed on platforms without dart:isolate support.
Future<MeasurementWorkerRuntimeLaunchResult> startMeasurementWorkerRuntime({
  required MeasurementWorkerRuntimeConfiguration configuration,
}) async =>
    MeasurementWorkerRuntimeLaunchResult.unavailable(
      'native_isolate_worker_unsupported',
    );
