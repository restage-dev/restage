part of 'crave_ready.dart';

abstract final class CraveReadyScreenDescriptor {
  const CraveReadyScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'crave_ready',
    artifactPath: 'crave_ready.rfw',
    version: 1,
    minClient: 1,
  );
}
