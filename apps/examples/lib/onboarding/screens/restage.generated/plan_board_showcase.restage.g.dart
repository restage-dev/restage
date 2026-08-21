part of '../plan_board_showcase.dart';

const planBoardShowcaseScreenRef = NeutralFlowScreenRef(
  id: 'plan_board_showcase',
  artifactPath: 'plan_board_showcase.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use planBoardShowcaseScreenRef')
abstract final class PlanBoardShowcaseScreenDescriptor {
  const PlanBoardShowcaseScreenDescriptor._();

  static const NeutralFlowScreenRef ref = planBoardShowcaseScreenRef;
}
