part of '../reel_frequency.dart';

// ignore_for_file: type=lint

const reelFrequencyScreenRef = NeutralFlowScreenRef(
  id: 'reel_frequency',
  artifactPath: 'reel_frequency.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use reelFrequencyScreenRef')
abstract final class ReelFrequencyScreenDescriptor {
  const ReelFrequencyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelFrequencyScreenRef;
}
