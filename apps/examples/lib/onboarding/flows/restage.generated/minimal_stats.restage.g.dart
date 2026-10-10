part of '../minimal_stats.dart';

// ignore_for_file: type=lint

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
        '{"flow":"minimal_stats","initial":"starter_stats","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"starter_stats":{"contentHash":"sha256:c383a951687aedfb9936f5da8d9e7d9087254a9fcee7a9e66e235fb29d3f6470","minClient":1,"path":"starter_stats.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"starter_stats":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"starter_stats"}},"version":1}',
    screens: {
      'starter_stats': StarterStatsScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '71b5c5a598883ccbd630eef12554d02bd2129e8e14eed783d7aca66bc3e53111',
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
