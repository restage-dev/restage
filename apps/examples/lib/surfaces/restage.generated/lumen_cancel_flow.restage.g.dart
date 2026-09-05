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
      '8b4e5acb107899415344d330a231927669dc5f47c6e2b00506bf07c4d445e800',
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
