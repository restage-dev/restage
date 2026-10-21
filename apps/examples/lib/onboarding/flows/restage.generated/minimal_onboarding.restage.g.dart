part of '../minimal_onboarding.dart';

// ignore_for_file: type=lint

const minimalOnboardingFlowRef = SurfaceFlowRef<
    MinimalOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_onboarding',
  version: 1,
  minClient: 12,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"minimal_onboarding","flowState":{"mode":{"classification":"internal","type":"string"}},"initial":"starter_welcome","minClient":12,"schemaVersion":1,"screenArtifacts":{"starter_done_explore":{"contentHash":"sha256:8c705fc8a2b9b20a8b1272a5b85bad1d415eea6bbe6301b1b9ff903f30e06747","minClient":12,"path":"starter_done_explore.rfw","schemaVersion":1,"version":1},"starter_done_guided":{"contentHash":"sha256:0bb6a6162150206f05405badc247a756c12b1b08f56e2e6bd065282925a082ee","minClient":12,"path":"starter_done_guided.rfw","schemaVersion":1,"version":1},"starter_question":{"contentHash":"sha256:60e9e8f1236add85c406caed49f2cfaf6d566f975b817447204f63e49098c7b6","minClient":12,"path":"starter_question.rfw","schemaVersion":1,"version":1},"starter_welcome":{"contentHash":"sha256:a0b8884f9ae6149518d379f87c7423b080693c4108db2d9b56bfb6774714f94d","minClient":12,"path":"starter_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"route":{"branches":[{"goto":"starter_done_guided","when":{"mode":{"eq":{"literal":"guided","type":"string"}}}}],"default":{"goto":"starter_done_explore"},"kind":"decision"},"starter_done_explore":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"starter_done_explore"},"starter_done_guided":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"starter_done_guided"},"starter_question":{"kind":"screen","on":{"explore":{"set":{"mode":{"type":"string","value":{"literal":"explore","type":"string"}}},"target":"route","type":"goto"},"guided":{"set":{"mode":{"type":"string","value":{"literal":"guided","type":"string"}}},"target":"route","type":"goto"}},"screen":"starter_question"},"starter_welcome":{"kind":"screen","on":{"next":{"target":"starter_question","type":"goto"}},"screen":"starter_welcome"}},"version":1}',
    screens: {
      'starter_welcome': StarterWelcomeScreen.new,
      'starter_question': StarterQuestionScreen.new,
      'starter_done_guided': StarterDoneGuidedScreen.new,
      'starter_done_explore': StarterDoneExploreScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'da91616e46a328761a09262cf62a0e6e877e675dceb6d2669afa53c686c1baef',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
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
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf724: IconData(0xf724, fontFamily: 'MaterialIcons'),
        0xf0377: IconData(0xf0377, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63b: IconData(0xf63b,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

MinimalOnboardingResult _decodeMinimalOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MinimalOnboardingResult();
}

@Deprecated('Use minimalOnboardingFlowRef')
abstract final class MinimalOnboardingFlowDescriptor {
  const MinimalOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<MinimalOnboardingResult> ref =
      minimalOnboardingFlowRef;
}

final class MinimalOnboardingResult {
  const MinimalOnboardingResult();
}

final class MinimalOnboardingActions {
  const MinimalOnboardingActions();
}

final _minimalOnboardingFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: minimalOnboardingFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'minimal_onboarding',
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
  vocabulary: minimalOnboardingFlowRef.vocabulary,
);

final minimalOnboardingFlowPlacementDefinition =
    () => _minimalOnboardingFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalOnboardingFlowSurface
    extends RestageFlowGraph<MinimalOnboardingResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MinimalOnboardingFlowSurface({
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
        super(flow: minimalOnboardingFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [MinimalOnboardingFlowSurface] for the default placement; no name is needed.
  const MinimalOnboardingFlowSurface.atPlacement(
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
        super(flow: minimalOnboardingFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: minimalOnboardingFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
