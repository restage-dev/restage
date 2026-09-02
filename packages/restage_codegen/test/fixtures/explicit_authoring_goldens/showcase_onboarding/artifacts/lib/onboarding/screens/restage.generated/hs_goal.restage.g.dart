part of '../hs_goal.dart';

const hsGoalScreenRef = NeutralFlowScreenRef(
  id: 'hs_goal',
  artifactPath: 'hs_goal.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use hsGoalScreenRef')
abstract final class HsGoalScreenDescriptor {
  const HsGoalScreenDescriptor._();

  static const NeutralFlowScreenRef ref = hsGoalScreenRef;
}
