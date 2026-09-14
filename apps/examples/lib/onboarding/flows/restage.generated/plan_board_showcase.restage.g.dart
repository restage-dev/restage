part of '../plan_board_showcase.dart';

const planBoardShowcaseFlowRef = SurfaceFlowRef<
    PlanBoardShowcaseResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'plan_board_showcase',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodePlanBoardShowcaseFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"plan_board_showcase\",\"initial\":\"plan_board_showcase\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"dismiss\":{\"fields\":{}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"plan_board_showcase\":{\"contentHash\":\"sha256:dca048ce170c22dc0826dd651575293d1263575c5bea403fc118c0e56c6a5f10\",\"minClient\":6,\"path\":\"plan_board_showcase.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"plan_board_showcase\":{\"kind\":\"screen\",\"on\":{\"act\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"plan_board_showcase\"}},\"version\":1}",
    screens: {
      "plan_board_showcase": PlanBoardShowcaseScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'ee595086c370f1448c45e4e29729037e86ebf551d33c7e8bd45c0f1116bf1de1',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'IconButton': buildIconButton,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class PlanBoardShowcaseFlowSurface
    extends RestageFlowGraph<PlanBoardShowcaseResult> {
  const PlanBoardShowcaseFlowSurface({
    super.key,
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.unavailable = const FlowUnavailablePolicy.hide(),
  }) : super(flow: planBoardShowcaseFlowRef);
}
