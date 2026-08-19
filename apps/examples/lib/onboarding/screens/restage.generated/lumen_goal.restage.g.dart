part of '../lumen_goal.dart';

abstract final class LumenGoalScreenDescriptor {
  const LumenGoalScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'lumen_goal',
    artifactPath: 'lumen_goal.rfw',
    version: 1,
    minClient: 1,
  );
}
