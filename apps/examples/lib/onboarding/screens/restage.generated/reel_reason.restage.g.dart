part of '../reel_reason.dart';

const reelReasonScreenRef = NeutralFlowScreenRef(
  id: 'reel_reason',
  artifactPath: 'reel_reason.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use reelReasonScreenRef')
abstract final class ReelReasonScreenDescriptor {
  const ReelReasonScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelReasonScreenRef;
}
