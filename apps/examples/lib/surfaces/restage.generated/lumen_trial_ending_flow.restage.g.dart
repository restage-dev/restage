part of '../lumen_trial_ending_flow.dart';

const lumenTrialOfferRef = SurfaceFlowRef<LumenTrialOfferResult>(
  id: 'lumen_trial_offer',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenTrialOfferResult,
);

LumenTrialOfferResult _decodeLumenTrialOfferResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const LumenTrialOfferResult();
}

final class LumenTrialOfferResult {
  const LumenTrialOfferResult();
}
