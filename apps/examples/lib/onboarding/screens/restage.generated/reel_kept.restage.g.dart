part of '../reel_kept.dart';

// ignore_for_file: type=lint

const reelKeptScreenRef = NeutralFlowScreenRef(
  id: 'reel_kept',
  artifactPath: 'reel_kept.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use reelKeptScreenRef')
abstract final class ReelKeptScreenDescriptor {
  const ReelKeptScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelKeptScreenRef;
}
