part of '../plan_board_showcase.dart';

// ignore_for_file: type=lint

const planBoardShowcaseScreenRef = NeutralFlowScreenRef(
  id: 'plan_board_showcase',
  artifactPath: 'plan_board_showcase.rfw',
  version: 1,
  minClient: 9,
);

@Deprecated('Use planBoardShowcaseScreenRef')
abstract final class PlanBoardShowcaseScreenDescriptor {
  const PlanBoardShowcaseScreenDescriptor._();

  static const NeutralFlowScreenRef ref = planBoardShowcaseScreenRef;
}
