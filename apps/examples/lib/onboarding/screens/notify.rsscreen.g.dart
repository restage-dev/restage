part of 'notify.dart';

abstract final class NotifyScreenDescriptor {
  const NotifyScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'notify',
    artifactPath: 'notify.rfw',
    version: 1,
    minClient: 1,
  );
}
