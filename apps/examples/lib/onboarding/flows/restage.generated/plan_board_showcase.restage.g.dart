part of '../plan_board_showcase.dart';

// ignore_for_file: type=lint

const planBoardShowcaseFlowRef = SurfaceFlowRef<
    PlanBoardShowcaseResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'plan_board_showcase',
  version: 1,
  minClient: 10,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodePlanBoardShowcaseFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"plan_board_showcase","initial":"plan_board_showcase","minClient":10,"outbound":{"customEvents":{"dismiss":{"fields":{}}}},"schemaVersion":1,"screenArtifacts":{"plan_board_showcase":{"contentHash":"sha256:1e28ee3181174cacc5fd0d5c4cf9067e98d2e5795facce0b4672f50ea23386d9","minClient":10,"path":"plan_board_showcase.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"plan_board_showcase":{"kind":"screen","on":{"act":{"target":"done","type":"goto"}},"screen":"plan_board_showcase"}},"version":1}',
    screens: {
      'plan_board_showcase': PlanBoardShowcaseScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '81c79b9908feb801ca535abd1b435a49ccb93bab2a76b3f344bb853690ef0ccc',
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

final _planBoardShowcaseFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: planBoardShowcaseFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'plan_board_showcase',
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
      'signals': <Object?>['dismiss'],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{'dismiss': <String, Object?>{}}
      }
    }
  },
  vocabulary: planBoardShowcaseFlowRef.vocabulary,
);

final planBoardShowcaseFlowPlacementDefinition =
    () => _planBoardShowcaseFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class PlanBoardShowcaseFlowSurface
    extends RestageFlowGraph<PlanBoardShowcaseResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const PlanBoardShowcaseFlowSurface({
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
        super(flow: planBoardShowcaseFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [PlanBoardShowcaseFlowSurface] for the default placement; no name is needed.
  const PlanBoardShowcaseFlowSurface.atPlacement(
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
        super(flow: planBoardShowcaseFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: planBoardShowcaseFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
