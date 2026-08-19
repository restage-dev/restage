part of '../reel_reason.dart';

abstract final class ReelReasonScreenDescriptor {
  const ReelReasonScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'reel_reason',
    artifactPath: 'reel_reason.rfw',
    version: 1,
    minClient: 1,
  );
}
