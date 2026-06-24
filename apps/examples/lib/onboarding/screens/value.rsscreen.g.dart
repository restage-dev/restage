part of 'value.dart';

abstract final class ValueScreenDescriptor {
  const ValueScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'value',
    artifactPath: 'value.rfw',
    version: 1,
    minClient: 1,
  );
}
