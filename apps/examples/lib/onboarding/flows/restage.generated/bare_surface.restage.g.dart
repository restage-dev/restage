part of '../bare_surface.dart';

// ignore_for_file: type=lint

const bareSurfaceFlowRef = SurfaceFlowRef<
    BareSurfaceResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'bare_surface',
  version: 1,
  minClient: 10,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeBareSurfaceFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"bare_surface","initial":"starter_bare_surface","minClient":10,"outbound":{},"schemaVersion":1,"screenArtifacts":{"starter_bare_surface":{"contentHash":"sha256:ba21b35bda002f8c682f5397c6b8033e057ce288777162718b13a1cf31153494","minClient":10,"path":"starter_bare_surface.rfw","schemaVersion":1,"version":1}},"states":{"starter_bare_surface":{"kind":"screen","on":{},"screen":"starter_bare_surface"}},"version":1}',
    screens: {
      'starter_bare_surface': StarterBareSurfaceScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '0f0fae07bdf278925fdd222008fe07acee0374664e4d61dd6a7582524c363036',
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

final _bareSurfaceFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: bareSurfaceFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'bare_surface',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{}
      }
    }
  },
  vocabulary: bareSurfaceFlowRef.vocabulary,
);

final bareSurfaceFlowPlacementDefinition =
    () => _bareSurfaceFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class BareSurfaceFlowSurface extends RestageFlowGraph<BareSurfaceResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const BareSurfaceFlowSurface({
    super.key,
    String? placement,
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
  })  : _restagePlacementName = placement,
        super(flow: bareSurfaceFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [BareSurfaceFlowSurface] for the default placement; no name is needed.
  const BareSurfaceFlowSurface.atPlacement(
    String restagePlacementId, {
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
  })  : _restagePlacementName = restagePlacementId,
        super(flow: bareSurfaceFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: bareSurfaceFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
