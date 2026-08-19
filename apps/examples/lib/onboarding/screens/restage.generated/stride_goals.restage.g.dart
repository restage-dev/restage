part of '../stride_goals.dart';

abstract final class StrideGoalsScreenDescriptor {
  const StrideGoalsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'stride_goals',
    artifactPath: 'stride_goals.rfw',
    version: 1,
    minClient: 1,
  );
}
