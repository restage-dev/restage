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
      'd5d55a65ab108bc98da375d216eb2ff7beb1e48f187c793539332e2110517269',
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
