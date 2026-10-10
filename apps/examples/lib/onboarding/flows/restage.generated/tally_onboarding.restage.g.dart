part of '../tally_onboarding.dart';

// ignore_for_file: type=lint

const tallyOnboardingFlowRef = SurfaceFlowRef<
    TallyOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'tally_onboarding',
  version: 1,
  minClient: 9,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeTallyOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"tally_onboarding","flowState":{"goal":{"classification":"internal","type":"string"}},"initial":"tally_welcome","minClient":9,"schemaVersion":1,"screenArtifacts":{"tally_debt":{"contentHash":"sha256:63acb8af9426ad92e4a7db89e4c626d5ef1379287f3b1d8ecc809a56900cb736","minClient":9,"path":"tally_debt.rfw","schemaVersion":1,"version":1},"tally_goal":{"contentHash":"sha256:533f408c23b4e91c7253cec82fcb3dbadb39021b918208acf8b96bf2425b5471","minClient":9,"path":"tally_goal.rfw","schemaVersion":1,"version":1},"tally_invest":{"contentHash":"sha256:7d3ea5c3f3ef8f66cf358c6e8c8b492ed6feeaccb0fa693118c8750864f9a7ec","minClient":9,"path":"tally_invest.rfw","schemaVersion":1,"version":1},"tally_recap_debt":{"contentHash":"sha256:266efb03a1847224281cd9ef6d1bcc4b2894a6cfc36f43e6c8af597b5c1591ea","minClient":9,"path":"tally_recap_debt.rfw","schemaVersion":1,"version":1},"tally_recap_invest":{"contentHash":"sha256:a9fa3db4e020fed779d02fd49e3659a7766c8dec63e701d77c57329846895e73","minClient":9,"path":"tally_recap_invest.rfw","schemaVersion":1,"version":1},"tally_recap_savings":{"contentHash":"sha256:9df1f9fffda2f18da1c7c2e3c83ab669bf3db5a8f7e1b434e3dbf10431479fd1","minClient":9,"path":"tally_recap_savings.rfw","schemaVersion":1,"version":1},"tally_savings":{"contentHash":"sha256:38791b89d9330484ef26141ed54a8c4c795c8e78912d3d5f3ea74ee447da59fe","minClient":9,"path":"tally_savings.rfw","schemaVersion":1,"version":1},"tally_welcome":{"contentHash":"sha256:27ab6887dcf5a9770c3037cbcda0d2d456bdddb55da3cb78afc76a485bc7e834","minClient":9,"path":"tally_welcome.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"route":{"branches":[{"goto":"tally_recap_debt","when":{"goal":{"eq":{"literal":"debt","type":"string"}}}},{"goto":"tally_recap_savings","when":{"goal":{"eq":{"literal":"savings","type":"string"}}}}],"default":{"goto":"tally_recap_invest"},"kind":"decision"},"tally_debt":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_debt"},"tally_goal":{"kind":"screen","on":{"debt":{"set":{"goal":{"type":"string","value":{"literal":"debt","type":"string"}}},"target":"tally_debt","type":"goto"},"invest":{"set":{"goal":{"type":"string","value":{"literal":"invest","type":"string"}}},"target":"tally_invest","type":"goto"},"savings":{"set":{"goal":{"type":"string","value":{"literal":"savings","type":"string"}}},"target":"tally_savings","type":"goto"}},"screen":"tally_goal"},"tally_invest":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_invest"},"tally_recap_debt":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_debt"},"tally_recap_invest":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_invest"},"tally_recap_savings":{"kind":"screen","on":{"finish":{"target":"done","type":"goto"}},"screen":"tally_recap_savings"},"tally_savings":{"kind":"screen","on":{"next":{"target":"route","type":"goto"}},"screen":"tally_savings"},"tally_welcome":{"kind":"screen","on":{"start":{"target":"tally_goal","type":"goto"}},"screen":"tally_welcome"}},"version":1}',
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
      '12ebd8be5b6893470d62523b56b99cca464c0b7fae31ef39a79cccbe02654976',
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
