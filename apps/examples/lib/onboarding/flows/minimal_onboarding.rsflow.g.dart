part of 'minimal_onboarding.dart';

abstract final class MinimalOnboardingFlowDescriptor {
  const MinimalOnboardingFlowDescriptor._();

  static const OnboardingFlowRef<MinimalOnboardingResult> ref =
      OnboardingFlowRef<MinimalOnboardingResult>(
    id: 'minimal_onboarding',
    version: 1,
    minClient: 1,
    decodeResult: MinimalOnboardingFlowDescriptor._decodeResult,
  );

  static MinimalOnboardingResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const MinimalOnboardingResult();
  }
}

final class MinimalOnboardingResult {
  const MinimalOnboardingResult();
}

final class MinimalOnboardingActions {
  const MinimalOnboardingActions();
}
