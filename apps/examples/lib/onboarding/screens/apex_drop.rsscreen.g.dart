part of 'apex_drop.dart';

abstract final class ApexDropScreenDescriptor {
  const ApexDropScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'apex_drop',
    artifactPath: 'apex_drop.rfw',
    version: 1,
    minClient: 1,
  );
}
