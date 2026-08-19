part of 'plan_board_showcase.dart';

abstract final class PlanBoardShowcaseFlowDescriptor {
  const PlanBoardShowcaseFlowDescriptor._();

  static const SurfaceFlowRef<PlanBoardShowcaseResult> ref =
      SurfaceFlowRef<PlanBoardShowcaseResult>(
    id: 'plan_board_showcase',
    version: 1,
    minClient: 1,
    surface: Surface.onboarding,
    deliveryMode: FlowDeliveryMode.typed,
    decodeResult: PlanBoardShowcaseFlowDescriptor._decodeResult,
  );

  static PlanBoardShowcaseResult _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const PlanBoardShowcaseResult();
  }
}

final class PlanBoardShowcaseResult {
  const PlanBoardShowcaseResult();
}

final class PlanBoardShowcaseActions {
  const PlanBoardShowcaseActions();
}
