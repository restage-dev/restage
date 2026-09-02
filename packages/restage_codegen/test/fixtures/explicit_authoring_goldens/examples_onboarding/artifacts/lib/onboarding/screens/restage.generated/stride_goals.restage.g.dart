part of '../stride_goals.dart';

const strideGoalsScreenRef = NeutralFlowScreenRef(
  id: 'stride_goals',
  artifactPath: 'stride_goals.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use strideGoalsScreenRef')
abstract final class StrideGoalsScreenDescriptor {
  const StrideGoalsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideGoalsScreenRef;
}
