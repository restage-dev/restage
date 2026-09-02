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
      '0941571daa2feb5e4d4a3de7124143a4e44506de6946c675835eff7884905667',
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
