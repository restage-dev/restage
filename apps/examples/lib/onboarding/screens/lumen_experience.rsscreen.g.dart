part of 'lumen_experience.dart';

abstract final class LumenExperienceScreenDescriptor {
  const LumenExperienceScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'lumen_experience',
    artifactPath: 'lumen_experience.rfw',
    version: 1,
    minClient: 1,
  );
}
