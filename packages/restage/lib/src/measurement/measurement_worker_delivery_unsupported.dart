import 'measurement_worker_delivery_protocol.dart';

/// Fails closed on web and other platforms without a native isolate/file worker.
Future<MeasurementWorkerOwnedDeliveryRuntimeLaunchResult>
    startMeasurementWorkerOwnedDelivery({
  required MeasurementWorkerOwnedDeliveryConfiguration configuration,
  MeasurementWorkerOwnedDeliveryPathResolver? pathResolver,
}) async =>
        MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
          'native_worker_owned_delivery_unsupported',
        );
