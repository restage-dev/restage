import 'package:flutter/foundation.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// SDK-internal hosted implementation of the exact binding read port.
///
/// Host lifecycle composition remains separate: this adapter exists so that
/// composition can call [MeasurementPublicationBindingReadPort.readExact]
/// with the exact delivery-carried reference without adding developer-facing
/// configuration or a synthetic callback.
@internal
final class HostedMeasurementPublicationBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  /// Composes the existing authenticated SDK RPC client into the read port.
  const HostedMeasurementPublicationBindingReadPort({
    required RestageRpcClient client,
  }) : _client = client;

  final RestageRpcClient _client;

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) async {
    try {
      final outcome = await _client.readMeasurementPublicationBindingExact(
        bindingReference,
      );
      return switch (outcome) {
        MeasurementPublicationBindingReadRpcAccepted(
          :final binding,
          :final registeredPublicationAttestation,
        ) =>
          MeasurementPublicationBindingReadAccepted(
            reference: bindingReference,
            binding: binding,
            registeredPublicationAttestation: registeredPublicationAttestation,
          ),
        MeasurementPublicationBindingReadRpcAbsent() =>
          const MeasurementPublicationBindingAbsent(),
        MeasurementPublicationBindingReadRpcUnsupportedFuture() =>
          const MeasurementPublicationBindingUnsupportedFuture(),
        MeasurementPublicationBindingReadRpcMismatched() =>
          const MeasurementPublicationBindingMismatched(),
        MeasurementPublicationBindingReadRpcUnavailable() =>
          const MeasurementPublicationBindingTransportUnavailable(),
      };
    } on Object {
      // Exact read failures never trigger local/bundled fallback from this
      // hosted adapter. The runtime receives only the closed unavailable arm.
      return const MeasurementPublicationBindingTransportUnavailable();
    }
  }
}
