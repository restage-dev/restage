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
      '7d35ab196db9179fd8d21c14e2f35675100ddc0ba925058d7b97fd14b1826fae',
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
