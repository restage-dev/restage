part of '../minimal_onboarding.dart';

const minimalOnboardingFlowRef = SurfaceFlowRef<
    MinimalOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'minimal_onboarding',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMinimalOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"minimal_onboarding\",\"flowState\":{\"mode\":{\"classification\":\"internal\",\"type\":\"string\"}},\"initial\":\"starter_welcome\",\"minClient\":6,\"schemaVersion\":1,\"screenArtifacts\":{\"starter_done_explore\":{\"contentHash\":\"sha256:3f55567729dd070f23165cab249d3ce64f97f248752c425897c5b5e9bf6d2075\",\"minClient\":6,\"path\":\"starter_done_explore.rfw\",\"schemaVersion\":1,\"version\":1},\"starter_done_guided\":{\"contentHash\":\"sha256:85bfcfaf303fc288895eefec50ab2c710a50ab284f90a00441995df97345be2d\",\"minClient\":6,\"path\":\"starter_done_guided.rfw\",\"schemaVersion\":1,\"version\":1},\"starter_question\":{\"contentHash\":\"sha256:ffc20e541da9b8e1b032778fd3d5b0f1b229c6ab68ea3d29b95dfb217c39053e\",\"minClient\":6,\"path\":\"starter_question.rfw\",\"schemaVersion\":1,\"version\":1},\"starter_welcome\":{\"contentHash\":\"sha256:dbaec3956568856cc4b227f054688f830a6ec09fa193e63106dd2bcc620a9da4\",\"minClient\":1,\"path\":\"starter_welcome.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"route\":{\"branches\":[{\"goto\":\"starter_done_guided\",\"when\":{\"mode\":{\"eq\":{\"literal\":\"guided\",\"type\":\"string\"}}}}],\"default\":{\"goto\":\"starter_done_explore\"},\"kind\":\"decision\"},\"starter_done_explore\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"starter_done_explore\"},\"starter_done_guided\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"starter_done_guided\"},\"starter_question\":{\"kind\":\"screen\",\"on\":{\"explore\":{\"set\":{\"mode\":{\"type\":\"string\",\"value\":{\"literal\":\"explore\",\"type\":\"string\"}}},\"target\":\"route\",\"type\":\"goto\"},\"guided\":{\"set\":{\"mode\":{\"type\":\"string\",\"value\":{\"literal\":\"guided\",\"type\":\"string\"}}},\"target\":\"route\",\"type\":\"goto\"}},\"screen\":\"starter_question\"},\"starter_welcome\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"starter_question\",\"type\":\"goto\"}},\"screen\":\"starter_welcome\"}},\"version\":1}",
    screens: {
      "starter_welcome": StarterWelcomeScreen.new,
      "starter_question": StarterQuestionScreen.new,
      "starter_done_guided": StarterDoneGuidedScreen.new,
      "starter_done_explore": StarterDoneExploreScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '81abf650f0ed90ef73b8d54a84b9432cc1091f04b2c5e13de643fea3662b829b',
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MinimalOnboardingFlowSurface
    extends RestageFlowGraph<MinimalOnboardingResult> {
  const MinimalOnboardingFlowSurface({
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
  }) : super(flow: minimalOnboardingFlowRef);
}
