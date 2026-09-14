part of '../minimal_notice.dart';

const minimalNoticeFlowRef = SurfaceFlowRef<
    MinimalNoticeResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_notice',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalNoticeFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"minimal_notice\",\"initial\":\"starter_notice\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"dismiss\":{\"fields\":{}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"starter_notice\":{\"contentHash\":\"sha256:88977fc783c7bb02de481a4581e7e4c93242bce9d11a3466e72b00c2a1cabd29\",\"minClient\":6,\"path\":\"starter_notice.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"starter_notice\":{\"kind\":\"screen\",\"on\":{\"act\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"starter_notice\"}},\"version\":1}",
    screens: {
      "starter_notice": StarterNoticeScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '976a662218898fade44905ece05aab1c6281c14f55892dd31833b2f61626183b',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Padding': buildPadding,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'IconButton': buildIconButton,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf614: IconData(0xf614, fontFamily: 'MaterialIcons'),
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

MinimalNoticeResult _decodeMinimalNoticeFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalNoticeResult();
}

@Deprecated('Use minimalNoticeFlowRef')
abstract final class MinimalNoticeFlowDescriptor {
  const MinimalNoticeFlowDescriptor._();

  static const SurfaceFlowRef<MinimalNoticeResult> ref = minimalNoticeFlowRef;
}

final class MinimalNoticeResult {
  const MinimalNoticeResult();
}

final class MinimalNoticeActions {
  const MinimalNoticeActions();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalNoticeFlowSurface
    extends RestageFlowGraph<MinimalNoticeResult> {
  const MinimalNoticeFlowSurface({
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
  }) : super(flow: minimalNoticeFlowRef);
}
