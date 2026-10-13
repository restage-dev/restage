part of '../reel_offer.dart';

// ignore_for_file: type=lint

const reelOfferScreenRef = NeutralFlowScreenRef(
  id: 'reel_offer',
  artifactPath: 'reel_offer.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use reelOfferScreenRef')
abstract final class ReelOfferScreenDescriptor {
  const ReelOfferScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelOfferScreenRef;
}
