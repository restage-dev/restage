part of '../plan_board_showcase.dart';

const planBoardShowcaseFlowRef = SurfaceFlowRef<
    PlanBoardShowcaseResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'plan_board_showcase',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodePlanBoardShowcaseFlowResult,
  measurementPublicationDraftDigest:
      'cd02b7863cad4dec75aaea893697ab61c6c364ae4f05b07eb052c201c31639f7',
);

PlanBoardShowcaseResult _decodePlanBoardShowcaseFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const PlanBoardShowcaseResult();
}

@Deprecated('Use planBoardShowcaseFlowRef')
abstract final class PlanBoardShowcaseFlowDescriptor {
  const PlanBoardShowcaseFlowDescriptor._();

  static const SurfaceFlowRef<PlanBoardShowcaseResult> ref =
      planBoardShowcaseFlowRef;
}

final class PlanBoardShowcaseResult {
  const PlanBoardShowcaseResult();
}

final class PlanBoardShowcaseActions {
  const PlanBoardShowcaseActions();
}
