part of 'tally_onboarding.dart';

abstract final class TallyOnboardingFlowDescriptor {
  const TallyOnboardingFlowDescriptor._();

  static const OnboardingFlowRef<TallyOnboardingResult> ref =
      OnboardingFlowRef<TallyOnboardingResult>(
    id: 'tally_onboarding',
    version: 1,
    minClient: 1,
    decodeResult: TallyOnboardingFlowDescriptor._decodeResult,
  );

  static TallyOnboardingResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const TallyOnboardingResult();
  }
}

final class TallyOnboardingResult {
  const TallyOnboardingResult();
}

final class TallyOnboardingActions {
  const TallyOnboardingActions();
}
