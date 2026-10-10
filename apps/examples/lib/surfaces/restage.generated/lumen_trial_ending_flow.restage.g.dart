part of '../lumen_trial_ending_flow.dart';

// ignore_for_file: type=lint

const lumenTrialOfferRef = SurfaceFlowRef<
    LumenTrialOfferResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'lumen_trial_offer',
  version: 1,
  minClient: 9,
  surface: Surface.message,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeLumenTrialOfferResult,
  compiled: CompiledFlow(
    documentJson:
        '{"flow":"lumen_trial_offer","initial":"lumen_trial_ending","minClient":9,"outbound":{},"schemaVersion":1,"screenArtifacts":{"lumen_trial_ending":{"contentHash":"sha256:65db54b015813542bfc70247dbfabe5bafb284e41a1cfde03c326604d6291d2b","minClient":9,"path":"measurement/82345ebf39848dea/lumen_trial_ending.rfw","schemaVersion":1,"version":1},"paywall_lumen_welcome_offer":{"contentHash":"sha256:efee39056ad3742910c00a091dc4a111bda214218a6ec00501b73bd39284c2e4","minClient":9,"path":"measurement/82345ebf39848dea/paywall_lumen_welcome_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"lumen_trial_ending":{"kind":"screen","on":{"later":{"target":"done","type":"goto"},"open_offer":{"target":"paywall_lumen_welcome_offer","type":"goto"}},"screen":"lumen_trial_ending"},"paywall_lumen_welcome_offer":{"kind":"screen","on":{"close":{"target":"done","type":"goto"},"continue":{"target":"done","type":"goto"}},"screen":"paywall_lumen_welcome_offer"}},"version":1}',
    screens: {
      'lumen_trial_ending': LumenTrialEndingScreen.new,
      'paywall_lumen_welcome_offer': LumenWelcomeOfferPaywall.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '0ac394124470458ca56b2d05813c9f602ac139caf14926ca80662c00b37375aa',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
        0xf0027: IconData(0xf0027, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

LumenTrialOfferResult _decodeLumenTrialOfferResult(
    Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const LumenTrialOfferResult();
}

final class LumenTrialOfferResult {
  const LumenTrialOfferResult();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class LumenTrialOfferSurface
    extends RestageFlowGraph<LumenTrialOfferResult> {
  const LumenTrialOfferSurface({
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
  }) : super(flow: lumenTrialOfferRef);
}
