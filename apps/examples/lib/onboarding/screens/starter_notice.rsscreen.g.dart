part of 'starter_notice.dart';

abstract final class StarterNoticeScreenDescriptor {
  const StarterNoticeScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'starter_notice',
    artifactPath: 'starter_notice.rfw',
    version: 1,
    minClient: 1,
  );
}
