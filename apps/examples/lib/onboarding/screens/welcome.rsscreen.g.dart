part of 'welcome.dart';

abstract final class WelcomeScreenDescriptor {
  const WelcomeScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'welcome',
    artifactPath: 'welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
