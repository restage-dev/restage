part of '../stride_goals.dart';

// ignore_for_file: type=lint

const strideGoalsScreenRef = NeutralFlowScreenRef(
  id: 'stride_goals',
  artifactPath: 'stride_goals.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use strideGoalsScreenRef')
abstract final class StrideGoalsScreenDescriptor {
  const StrideGoalsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideGoalsScreenRef;
}
