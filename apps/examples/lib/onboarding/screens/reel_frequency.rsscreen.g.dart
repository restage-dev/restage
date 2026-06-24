part of 'reel_frequency.dart';

abstract final class ReelFrequencyScreenDescriptor {
  const ReelFrequencyScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'reel_frequency',
    artifactPath: 'reel_frequency.rfw',
    version: 1,
    minClient: 1,
  );
}
