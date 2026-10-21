part of '../tally_onboarding.dart';

// ignore_for_file: type=lint

const tallyOnboardingFlowRef = SurfaceFlowRef<
    TallyOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'tally_onboarding',
  version: 1,
  minClient: 12,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeTallyOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"tally_onboarding","flowState":{"goal":{"classification":"internal","type":"string"}},"initial":"tally_welcome","minClient":12,"schemaVersion":1,"screenArtifacts":{"tally_debt":{"contentHash":"sha256:34252c015a40606654a1c24f2267379ecc62d656d40b051ce320f11c1d0b54b7","minClient":12,"path":"tally_debt.rfw","schemaVersion":1,"version":1},"tally_goal":{"contentHash":"sha256:212c275906a3a7490194a06dbb493e9f6590caaa1f7d769ec3783026943665eb","minClient":12,"path":"tally_goal.rfw","schemaVersion":1,"version":1},"tally_invest":{"contentHash":"sha256:e089f8d92febdcf5d42ba291d323342ca9cbd2ec859d4020bd71ea5a6b466353","minClient":12,"path":"tally_invest.rfw","schemaVersion":1,"version":1},"tally_recap_debt":{"contentHash":"sha256:55941df2f6e45cb776b223e491b9de63688cf138e1ee99c055cc3f906377f40e","minClient":12,"path":"tally_recap_debt.rfw","schemaVersion":1,"version":1},"tally_recap_invest":{"contentHash":"sha256:2da19051bbdc5e4eb9a7693c31c74752d4c79d817bd44de8eed025553f9a03b1","minClient":12,"path":"tally_recap_invest.rfw","schemaVersion":1,"version":1},"tally_recap_savings":{"contentHash":"sha256:e943a20eec0748545d148ff629cfa945f6c54fdbca12e9188f398d641eb08f62","minClient":12,"path":"tally_recap_savings.rfw","schemaVersion":1,"version":1},"tally_savings":{"contentHash":"sha256:1d871f3d7c810e8debf89304f3c281b18f22a5e859d67a1c1c5cae6d57ac8462","minClient":12,"path":"tally_savings.rfw","schemaVersion":1,"version":1},"tally_welcome":{"contentHash":"sha256:1fcacc5dc900eb91facefb21b330ea1dfbde7b5c0faafbbcf3f739f7eaec0b6e","minClient":12,"path":"tally_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"route":{"branches":[{"goto":"tally_recap_debt","when":{"goal":{"eq":{"literal":"debt","type":"string"}}}},{"goto":"tally_recap_savings","when":{"goal":{"eq":{"literal":"savings","type":"string"}}}}],"default":{"goto":"tally_recap_invest"},"kind":"decision"},"tally_debt":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_debt"},"tally_goal":{"kind":"screen","on":{"debt":{"set":{"goal":{"type":"string","value":{"literal":"debt","type":"string"}}},"target":"tally_debt","type":"goto"},"invest":{"set":{"goal":{"type":"string","value":{"literal":"invest","type":"string"}}},"target":"tally_invest","type":"goto"},"savings":{"set":{"goal":{"type":"string","value":{"literal":"savings","type":"string"}}},"target":"tally_savings","type":"goto"}},"screen":"tally_goal"},"tally_invest":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_invest"},"tally_recap_debt":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_debt"},"tally_recap_invest":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_invest"},"tally_recap_savings":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_savings"},"tally_savings":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_savings"},"tally_welcome":{"kind":"screen","on":{"start":{"target":"tally_goal","type":"goto"}},"screen":"tally_welcome"}},"version":1}',
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
      '6a1f1fb52016bca14e26f32dc914023ecac9ae4c9fe5780482973b45af0395be',
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
