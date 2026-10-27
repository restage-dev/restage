part of '../tally_onboarding.dart';

// ignore_for_file: type=lint

const tallyOnboardingFlowRef = SurfaceFlowRef<
    TallyOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'tally_onboarding',
  version: 1,
  minClient: 17,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeTallyOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"tally_onboarding","flowState":{"goal":{"classification":"internal","type":"string"}},"initial":"tally_welcome","minClient":17,"schemaVersion":1,"screenArtifacts":{"tally_debt":{"contentHash":"sha256:ce612eb88d0ea09c9e3afd80289eebefcd2f0a17a08b687a699245c0fa53f95c","minClient":17,"path":"tally_debt.rfw","schemaVersion":1,"version":1},"tally_goal":{"contentHash":"sha256:9af17cfc85658e3b22a841f4f9dfba7102ab1dae4d42f75841cc94614202a8d5","minClient":17,"path":"tally_goal.rfw","schemaVersion":1,"version":1},"tally_invest":{"contentHash":"sha256:e7cd4cf4263dd03569b58d23cb879460c9da38648fc2da2f079af1cad5512cfa","minClient":17,"path":"tally_invest.rfw","schemaVersion":1,"version":1},"tally_recap_debt":{"contentHash":"sha256:fe85f1597d5022f38a86beaea88094fcee29bbf18576c72d29586cab3d4cbfdb","minClient":17,"path":"tally_recap_debt.rfw","schemaVersion":1,"version":1},"tally_recap_invest":{"contentHash":"sha256:ec8b716a6b777768d74bf5ee6228e6d6ffc948f314f1d42797a141d8a715f0ea","minClient":17,"path":"tally_recap_invest.rfw","schemaVersion":1,"version":1},"tally_recap_savings":{"contentHash":"sha256:c0d1f09a8caacf415ff7509f4ba303772bd9d5c370fa3f1e7d2dd2c5a90a2836","minClient":17,"path":"tally_recap_savings.rfw","schemaVersion":1,"version":1},"tally_savings":{"contentHash":"sha256:74f7785a550f176b8a278235ccfba18e58d603b32cd226a74b51c799f2752966","minClient":17,"path":"tally_savings.rfw","schemaVersion":1,"version":1},"tally_welcome":{"contentHash":"sha256:87f39e36cef1886a206a54ef3acfc9613498d8f646443c567a5de6347f3d30d4","minClient":17,"path":"tally_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"route":{"branches":[{"goto":"tally_recap_debt","when":{"goal":{"eq":{"literal":"debt","type":"string"}}}},{"goto":"tally_recap_savings","when":{"goal":{"eq":{"literal":"savings","type":"string"}}}}],"default":{"goto":"tally_recap_invest"},"kind":"decision"},"tally_debt":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_debt"},"tally_goal":{"kind":"screen","on":{"debt":{"set":{"goal":{"type":"string","value":{"literal":"debt","type":"string"}}},"target":"tally_debt","type":"goto"},"invest":{"set":{"goal":{"type":"string","value":{"literal":"invest","type":"string"}}},"target":"tally_invest","type":"goto"},"savings":{"set":{"goal":{"type":"string","value":{"literal":"savings","type":"string"}}},"target":"tally_savings","type":"goto"}},"screen":"tally_goal"},"tally_invest":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_invest"},"tally_recap_debt":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_debt"},"tally_recap_invest":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_invest"},"tally_recap_savings":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_savings"},"tally_savings":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_savings"},"tally_welcome":{"kind":"screen","on":{"start":{"target":"tally_goal","type":"goto"}},"screen":"tally_welcome"}},"version":1}',
    screens: {
      'tally_welcome': TallyWelcomeScreen.new,
      'tally_goal': TallyGoalScreen.new,
      'tally_debt': TallyDebtScreen.new,
      'tally_savings': TallySavingsScreen.new,
      'tally_invest': TallyInvestScreen.new,
      'tally_recap_debt': TallyRecapDebtScreen.new,
      'tally_recap_savings': TallyRecapSavingsScreen.new,
      'tally_recap_invest': TallyRecapInvestScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '0ee4786a4271d506035ecfa17facdfb7e53f8944e40d7f55e2c8a850f347066f',
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
        0xf520: IconData(0xf520, fontFamily: 'MaterialIcons'),
        0xf59e: IconData(0xf59e, fontFamily: 'MaterialIcons'),
        0xf5ca: IconData(0xf5ca, fontFamily: 'MaterialIcons'),
        0xf768: IconData(0xf768, fontFamily: 'MaterialIcons'),
        0xf847: IconData(0xf847, fontFamily: 'MaterialIcons'),
        0xf888: IconData(0xf888, fontFamily: 'MaterialIcons'),
        0xf009a: IconData(0xf009a, fontFamily: 'MaterialIcons'),
        0xf0128: IconData(0xf0128, fontFamily: 'MaterialIcons'),
        0xf02e0: IconData(0xf02e0, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63b: IconData(0xf63b,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
        0xf0174: IconData(0xf0174,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
        0xf0252: IconData(0xf0252,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
        0xf0254: IconData(0xf0254,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

TallyOnboardingResult _decodeTallyOnboardingFlowResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const TallyOnboardingResult();
}

@Deprecated('Use tallyOnboardingFlowRef')
abstract final class TallyOnboardingFlowDescriptor {
  const TallyOnboardingFlowDescriptor._();

  static const SurfaceFlowRef<TallyOnboardingResult> ref =
      tallyOnboardingFlowRef;
}

final class TallyOnboardingResult {
  const TallyOnboardingResult();
}

final class TallyOnboardingActions {
  const TallyOnboardingActions();
}

final _tallyOnboardingFlowPlacementDefinitionValue =
    RestageFlowGraph.generatedPlacementDefinition(
  defaultSurface: tallyOnboardingFlowRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'onboarding',
    'slug': 'tally_onboarding',
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
  vocabulary: tallyOnboardingFlowRef.vocabulary,
);

final tallyOnboardingFlowPlacementDefinition =
    () => _tallyOnboardingFlowPlacementDefinitionValue;

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class TallyOnboardingFlowSurface
    extends RestageFlowGraph<TallyOnboardingResult> {
  /// Mounts this flow at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const TallyOnboardingFlowSurface({
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
        super(flow: tallyOnboardingFlowRef);

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [TallyOnboardingFlowSurface] for the default placement; no name is needed.
  const TallyOnboardingFlowSurface.atPlacement(
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
        super(flow: tallyOnboardingFlowRef);

  final String? _restagePlacementName;

  @override
  get placementBinding => RestageFlowGraph.generatedPlacementBinding(
        definition: tallyOnboardingFlowPlacementDefinition,
        name: _restagePlacementName,
      );
}
