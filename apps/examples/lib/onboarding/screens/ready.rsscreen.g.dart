part of 'ready.dart';

abstract final class ReadyScreenDescriptor {
  const ReadyScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'ready',
    artifactPath: 'ready.rfw',
    version: 1,
    minClient: 1,
  );
}
