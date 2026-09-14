part of '../bare_surface.dart';

const bareSurfaceFlowRef = SurfaceFlowRef<
    BareSurfaceResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'bare_surface',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeBareSurfaceFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"bare_surface\",\"initial\":\"starter_bare_surface\",\"minClient\":6,\"outbound\":{},\"schemaVersion\":1,\"screenArtifacts\":{\"starter_bare_surface\":{\"contentHash\":\"sha256:fc3d3f58933885aadc75119444fd3f80f62c816d6f2486168470ebf1d6fa700e\",\"minClient\":6,\"path\":\"starter_bare_surface.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"starter_bare_surface\":{\"kind\":\"screen\",\"on\":{},\"screen\":\"starter_bare_surface\"}},\"version\":1}",
    screens: {
      "starter_bare_surface": StarterBareSurfaceScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '48adf8f9e6555e8608fb561805e434f43761004c4978888bbd957204c475e31d',
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
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf157: IconData(0xf157, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

BareSurfaceResult _decodeBareSurfaceFlowResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const BareSurfaceResult();
}

@Deprecated('Use bareSurfaceFlowRef')
abstract final class BareSurfaceFlowDescriptor {
  const BareSurfaceFlowDescriptor._();

  static const SurfaceFlowRef<BareSurfaceResult> ref = bareSurfaceFlowRef;
}

final class BareSurfaceResult {
  const BareSurfaceResult();
}

final class BareSurfaceActions {
  const BareSurfaceActions();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class BareSurfaceFlowSurface extends RestageFlowGraph<BareSurfaceResult> {
  const BareSurfaceFlowSurface({
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
  }) : super(flow: bareSurfaceFlowRef);
}
