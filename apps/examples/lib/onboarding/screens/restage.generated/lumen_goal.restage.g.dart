part of '../lumen_goal.dart';

// ignore_for_file: type=lint

const lumenGoalScreenRef = NeutralFlowScreenRef(
  id: 'lumen_goal',
  artifactPath: 'lumen_goal.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use lumenGoalScreenRef')
abstract final class LumenGoalScreenDescriptor {
  const LumenGoalScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenGoalScreenRef;
}
