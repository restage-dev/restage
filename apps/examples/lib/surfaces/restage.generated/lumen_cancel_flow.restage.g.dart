part of '../lumen_cancel_flow.dart';

const lumenCancelRef = SurfaceFlowRef<
    LumenCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_cancel',
  version: 1,
  minClient: 1,
  surface: Surface.survey,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenCancelResult,
  measurementPublicationDraftDigest:
      '543896d6d889c996e85931909ea0d48a8796ebf0937b09c235801f54abc3173c',
);

LumenCancelResult _decodeLumenCancelResult(Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey("reason")) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final reason = result["reason"];
  if (reason is! String) {
    throw const FormatException('Expected result field reason to be String.');
  }
  return LumenCancelResult(reason: reason);
}

final class LumenCancelResult {
  const LumenCancelResult({required this.reason});

  final String reason;
}
