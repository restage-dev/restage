part of '../minimal_onboarding.dart';

const minimalOnboardingFlowRef = SurfaceFlowRef<
    MinimalOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_onboarding',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalOnboardingFlowResult,
  measurementPublicationDraftDigest:
      '69dff3ce71f051e2ad1f1e9158c2db39533638ce27d6ee407dc861eda7985a54',
);

MinimalOnboardingResult _decodeMinimalOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalOnboardingResult();
}

@Deprecated('Use minimalOnboardingFlowRef')
abstract final class MinimalOnboardingFlowDescriptor {
  const MinimalOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<MinimalOnboardingResult> ref =
      minimalOnboardingFlowRef;
}

final class MinimalOnboardingResult {
  const MinimalOnboardingResult();
}

final class MinimalOnboardingActions {
  const MinimalOnboardingActions();
}
