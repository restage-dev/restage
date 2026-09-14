part of '../tally_onboarding.dart';

const tallyOnboardingFlowRef = SurfaceFlowRef<
    TallyOnboardingResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'tally_onboarding',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeTallyOnboardingFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"tally_onboarding\",\"flowState\":{\"goal\":{\"classification\":\"internal\",\"type\":\"string\"}},\"initial\":\"tally_welcome\",\"minClient\":6,\"schemaVersion\":1,\"screenArtifacts\":{\"tally_debt\":{\"contentHash\":\"sha256:a98bf6cdb6e8b2466f6ae3686dda50883a6d61fe8f0ae1241a303ae562c1737e\",\"minClient\":6,\"path\":\"tally_debt.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_goal\":{\"contentHash\":\"sha256:e1e7b3bbd12fe7f2a6a43497fcf40324a7da1bc05cbfff809ef9019c38a1c151\",\"minClient\":6,\"path\":\"tally_goal.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_invest\":{\"contentHash\":\"sha256:f6992909827b9d1e1c5fa6ec78362bde9a3306d44ce1779965fc68ed808488ad\",\"minClient\":6,\"path\":\"tally_invest.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_recap_debt\":{\"contentHash\":\"sha256:30db90148dec752849700ad503d05eaccd3ad80ed50abf60b3cb1f2f0232cca7\",\"minClient\":6,\"path\":\"tally_recap_debt.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_recap_invest\":{\"contentHash\":\"sha256:63a85d5931aa73ff8d9d4e705e61a4a070e0deecef2e2898c9d3da7a135549dc\",\"minClient\":6,\"path\":\"tally_recap_invest.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_recap_savings\":{\"contentHash\":\"sha256:8fce5d4e78492b545f59448f509a99089949faa7f79684c9c992b1653313aa68\",\"minClient\":6,\"path\":\"tally_recap_savings.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_savings\":{\"contentHash\":\"sha256:fc3912968cb81ab0d2c6f72bbeb0e661b4cd85c21c31e8c4f3ec7fb752058287\",\"minClient\":6,\"path\":\"tally_savings.rfw\",\"schemaVersion\":1,\"version\":1},\"tally_welcome\":{\"contentHash\":\"sha256:b1118e7080b74182da7a662ab143303ad5da47d46740aa79bf8011bd138e6157\",\"minClient\":6,\"path\":\"tally_welcome.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"route\":{\"branches\":[{\"goto\":\"tally_recap_debt\",\"when\":{\"goal\":{\"eq\":{\"literal\":\"debt\",\"type\":\"string\"}}}},{\"goto\":\"tally_recap_savings\",\"when\":{\"goal\":{\"eq\":{\"literal\":\"savings\",\"type\":\"string\"}}}}],\"default\":{\"goto\":\"tally_recap_invest\"},\"kind\":\"decision\"},\"tally_debt\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"route\",\"type\":\"goto\"}},\"screen\":\"tally_debt\"},\"tally_goal\":{\"kind\":\"screen\",\"on\":{\"debt\":{\"set\":{\"goal\":{\"type\":\"string\",\"value\":{\"literal\":\"debt\",\"type\":\"string\"}}},\"target\":\"tally_debt\",\"type\":\"goto\"},\"invest\":{\"set\":{\"goal\":{\"type\":\"string\",\"value\":{\"literal\":\"invest\",\"type\":\"string\"}}},\"target\":\"tally_invest\",\"type\":\"goto\"},\"savings\":{\"set\":{\"goal\":{\"type\":\"string\",\"value\":{\"literal\":\"savings\",\"type\":\"string\"}}},\"target\":\"tally_savings\",\"type\":\"goto\"}},\"screen\":\"tally_goal\"},\"tally_invest\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"route\",\"type\":\"goto\"}},\"screen\":\"tally_invest\"},\"tally_recap_debt\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"tally_recap_debt\"},\"tally_recap_invest\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"tally_recap_invest\"},\"tally_recap_savings\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"tally_recap_savings\"},\"tally_savings\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"route\",\"type\":\"goto\"}},\"screen\":\"tally_savings\"},\"tally_welcome\":{\"kind\":\"screen\",\"on\":{\"start\":{\"target\":\"tally_goal\",\"type\":\"goto\"}},\"screen\":\"tally_welcome\"}},\"version\":1}",
    screens: {
      "tally_welcome": TallyWelcomeScreen.new,
      "tally_goal": TallyGoalScreen.new,
      "tally_debt": TallyDebtScreen.new,
      "tally_savings": TallySavingsScreen.new,
      "tally_invest": TallyInvestScreen.new,
      "tally_recap_debt": TallyRecapDebtScreen.new,
      "tally_recap_savings": TallyRecapSavingsScreen.new,
      "tally_recap_invest": TallyRecapInvestScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '375c3079a6439a36f90748d21d69950752b465a932d7a85d4e021d8a8318abd9',
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

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class TallyOnboardingFlowSurface
    extends RestageFlowGraph<TallyOnboardingResult> {
  const TallyOnboardingFlowSurface({
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
  }) : super(flow: tallyOnboardingFlowRef);
}
