part of '../reel_offer.dart';

const reelOfferScreenRef = NeutralFlowScreenRef(
  id: 'reel_offer',
  artifactPath: 'reel_offer.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use reelOfferScreenRef')
abstract final class ReelOfferScreenDescriptor {
  const ReelOfferScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelOfferScreenRef;
}
