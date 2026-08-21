part of '../reel_frequency.dart';

const reelFrequencyScreenRef = NeutralFlowScreenRef(
  id: 'reel_frequency',
  artifactPath: 'reel_frequency.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use reelFrequencyScreenRef')
abstract final class ReelFrequencyScreenDescriptor {
  const ReelFrequencyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelFrequencyScreenRef;
}
