part of '../reel_reason.dart';

// ignore_for_file: type=lint

const reelReasonScreenRef = NeutralFlowScreenRef(
  id: 'reel_reason',
  artifactPath: 'reel_reason.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use reelReasonScreenRef')
abstract final class ReelReasonScreenDescriptor {
  const ReelReasonScreenDescriptor._();

  static const NeutralFlowScreenRef ref = reelReasonScreenRef;
}
