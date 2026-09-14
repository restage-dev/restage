import 'measurement_worker_delivery_protocol.dart';

/// Fails closed on web and other platforms without a native isolate/file worker.
Future<MeasurementWorkerOwnedDeliveryRuntimeLaunchResult>
    startMeasurementWorkerOwnedDelivery({
  required MeasurementWorkerOwnedDeliveryConfiguration configuration,
  MeasurementWorkerOwnedDeliveryPathResolver? pathResolver,
  MeasurementWorkerOwnedDeliveryCancellation? cancellation,
}) async =>
        MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
          'native_worker_owned_delivery_unsupported',
        );

/// Unsupported builds own no native persisted measurement records.
Future<void> purgeMeasurementWorkerOwnedDelivery({
  MeasurementWorkerOwnedDeliveryPathResolver? pathResolver,
}) async {}
