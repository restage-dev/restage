part of 'lumen_welcome.dart';

abstract final class LumenWelcomeScreenDescriptor {
  const LumenWelcomeScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'lumen_welcome',
    artifactPath: 'lumen_welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
