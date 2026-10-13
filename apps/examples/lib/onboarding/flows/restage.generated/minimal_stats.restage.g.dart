part of '../minimal_stats.dart';

// ignore_for_file: type=lint

const minimalStatsFlowRef = SurfaceFlowRef<
    MinimalStatsResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_stats',
  version: 1,
  minClient: 10,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalStatsFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"minimal_stats","initial":"starter_stats","minClient":10,"outbound":{},"schemaVersion":1,"screenArtifacts":{"starter_stats":{"contentHash":"sha256:99869ee5758011d38c00c300f22ad3edeb37895adee89ef74fee150a7b445013","minClient":10,"path":"starter_stats.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"starter_stats":{"kind":"screen","on":{"done":{"target":"done","type":"goto"}},"screen":"starter_stats"}},"version":1}',
    screens: {
      'starter_stats': StarterStatsScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '6f759a5094cc3c33368fbc8e9d649436e0807138c447beb7464e122fdd8d9635',
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

final _minimalStatsFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: minimalStatsFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'minimal_stats',
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
  vocabulary: minimalStatsFlowRef.vocabulary,
);

final minimalStatsFlowPlacementDefinition =
    () => _minimalStatsFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalStatsFlowSurface
    extends RestageFlowGraph<MinimalStatsResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MinimalStatsFlowSurface({
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
        super(flow: minimalStatsFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [MinimalStatsFlowSurface] for the default placement; no name is needed.
  const MinimalStatsFlowSurface.atPlacement(
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
        super(flow: minimalStatsFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: minimalStatsFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
