part of 'lumen_recap.dart';

abstract final class LumenRecapScreenDescriptor {
  const LumenRecapScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'lumen_recap',
    artifactPath: 'lumen_recap.rfw',
    version: 1,
    minClient: 1,
  );
}
