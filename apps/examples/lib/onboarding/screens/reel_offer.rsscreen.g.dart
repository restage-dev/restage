part of 'reel_offer.dart';

abstract final class ReelOfferScreenDescriptor {
  const ReelOfferScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'reel_offer',
    artifactPath: 'reel_offer.rfw',
    version: 1,
    minClient: 1,
  );
}
