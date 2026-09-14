part of '../minimal_stats.dart';

const minimalStatsFlowRef = SurfaceFlowRef<
    MinimalStatsResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_stats',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalStatsFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"minimal_stats\",\"initial\":\"starter_stats\",\"minClient\":1,\"outbound\":{},\"schemaVersion\":1,\"screenArtifacts\":{\"starter_stats\":{\"contentHash\":\"sha256:2777691fff0e1ec65303ee2fdd5a5307dd246c8585b30871b458cf84a57c6119\",\"minClient\":1,\"path\":\"starter_stats.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"starter_stats\":{\"kind\":\"screen\",\"on\":{\"done\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"starter_stats\"}},\"version\":1}",
    screens: {
      "starter_stats": StarterStatsScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '8dd3ac89fbfb467374089e8554a33c281a7189c490b719e9fdf0d5b481938154',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Scaffold': buildScaffold,
      },
    ),
  ),
);

MinimalStatsResult _decodeMinimalStatsFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalStatsResult();
}

@Deprecated('Use minimalStatsFlowRef')
abstract final class MinimalStatsFlowDescriptor {
  const MinimalStatsFlowDescriptor._();

  static const SurfaceFlowRef<MinimalStatsResult> ref = minimalStatsFlowRef;
}

final class MinimalStatsResult {
  const MinimalStatsResult();
}

final class MinimalStatsActions {
  const MinimalStatsActions();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalStatsFlowSurface
    extends RestageFlowGraph<MinimalStatsResult> {
  const MinimalStatsFlowSurface({
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
  }) : super(flow: minimalStatsFlowRef);
}
