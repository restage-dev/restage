part of '../tally_goal.dart';

// ignore_for_file: type=lint

const tallyGoalScreenRef = NeutralFlowScreenRef(
  id: 'tally_goal',
  artifactPath: 'tally_goal.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use tallyGoalScreenRef')
abstract final class TallyGoalScreenDescriptor {
  const TallyGoalScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyGoalScreenRef;
}
