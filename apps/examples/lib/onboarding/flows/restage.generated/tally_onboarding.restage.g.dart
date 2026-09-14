part of '../tally_onboarding.dart';

const tallyOnboardingFlowRef = SurfaceFlowRef<
    TallyOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'tally_onboarding',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeTallyOnboardingFlowResult,
  measurementPublicationDraftDigest:
      '0dae0211aaa5d48188dddb6e2e6fe1cdce159bba8ec4aa31de3ffb03dd3c621e',
);

TallyOnboardingResult _decodeTallyOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const TallyOnboardingResult();
}

@Deprecated('Use tallyOnboardingFlowRef')
abstract final class TallyOnboardingFlowDescriptor {
  const TallyOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<TallyOnboardingResult> ref =
      tallyOnboardingFlowRef;
}

final class TallyOnboardingResult {
  const TallyOnboardingResult();
}

final class TallyOnboardingActions {
  const TallyOnboardingActions();
}
