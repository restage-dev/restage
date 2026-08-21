part of '../reel_kept.dart';

const reelKeptScreenRef = NeutralFlowScreenRef(
  id: 'reel_kept',
  artifactPath: 'reel_kept.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use reelKeptScreenRef')
abstract final class ReelKeptScreenDescriptor {
  const ReelKeptScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelKeptScreenRef;
}
