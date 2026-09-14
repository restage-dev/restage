part of '../reel_cancel.dart';

const reelCancelFlowRef = SurfaceFlowRef<
    ReelCancelResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'reel_cancel',
  version: 1,
  minClient: 6,
  surface: Surface.onboarding,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeReelCancelFlowResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"actions\":{\"redeemOffer\":{\"actionName\":\"redeemOffer\",\"argsSchema\":{\"fields\":{},\"kind\":\"object\"},\"argsSchemaHash\":\"sha256:590f015bf5e877b53e3501b7e12ad48a11158d4c5b696f9a82593c4f3272411a\",\"contractVersion\":1,\"idempotent\":false,\"minClient\":6,\"resultSchema\":{\"fields\":{\"redeemed\":{\"required\":true,\"schema\":{\"kind\":\"bool\"}}},\"kind\":\"object\"},\"resultSchemaHash\":\"sha256:cdba58b8037dcf2c43d7add16c74558a786b6b1dede9d095ac4c00399ddaaaae\"}},\"flow\":\"reel_cancel\",\"flowState\":{\"retained\":{\"classification\":\"exportable\",\"type\":\"bool\"}},\"initial\":\"reel_reason\",\"minClient\":6,\"outbound\":{\"customEvents\":{\"cancel\":{\"fields\":{}}},\"terminalResult\":{\"fields\":{\"retained\":{\"ref\":{\"state\":\"retained\"},\"type\":\"bool\"}}}},\"schemaVersion\":1,\"screenArtifacts\":{\"reel_frequency\":{\"contentHash\":\"sha256:c2c8f7d37d037b3a3ec915a6e116fe3d07f760c2b0d049191a70af5563ccd8e3\",\"minClient\":6,\"path\":\"reel_frequency.rfw\",\"schemaVersion\":1,\"version\":1},\"reel_kept\":{\"contentHash\":\"sha256:775b7c05ea79f9081bc931073e240dbd0bc90593d5fa4dca792e1ef2d26de63c\",\"minClient\":6,\"path\":\"reel_kept.rfw\",\"schemaVersion\":1,\"version\":1},\"reel_offer\":{\"contentHash\":\"sha256:77658624e9a8ce58cea03ee2deffb0864f2225cbb38a52e55e8a1ce7f78cb07d\",\"minClient\":1,\"path\":\"reel_offer.rfw\",\"schemaVersion\":1,\"version\":1},\"reel_reason\":{\"contentHash\":\"sha256:1fa340731b837ac7beedc1ae0e175b7abdb33fb01e65b920ebba8952b51dcff0\",\"minClient\":6,\"path\":\"reel_reason.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{\"retained\":true}},\"reel_frequency\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"reel_offer\",\"type\":\"goto\"}},\"screen\":\"reel_frequency\"},\"reel_kept\":{\"kind\":\"screen\",\"on\":{\"finish\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"reel_kept\"},\"reel_offer\":{\"kind\":\"screen\",\"on\":{\"keep\":{\"action\":\"redeemOffer\",\"resultPredicate\":{\"field\":\"redeemed\",\"kind\":\"objectBoolFieldEquals\",\"value\":true},\"target\":\"reel_kept\",\"type\":\"action\"}},\"screen\":\"reel_offer\"},\"reel_reason\":{\"kind\":\"screen\",\"on\":{\"next\":{\"target\":\"reel_frequency\",\"type\":\"goto\"}},\"screen\":\"reel_reason\"}},\"version\":1}",
    screens: {
      "reel_reason": ReelReasonScreen.new,
      "reel_frequency": ReelFrequencyScreen.new,
      "reel_offer": ReelOfferScreen.new,
      "reel_kept": ReelKeptScreen.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '9fb03fb86a47155310129aaf92e996ec7c92d01c1cd237cd7ecf878e142108e6',
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
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'FilledButton': buildFilledButton,
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
        'TextButton': buildTextButton,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63b: IconData(0xf63b,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

ReelCancelResult _decodeReelCancelFlowResult(Map<String, Object?> result) {
  if (result.length != 1 || !result.containsKey('retained')) {
    throw const FormatException('Unexpected flow result keys.');
  }
  final retained = result['retained'];
  if (retained is! bool) {
    throw const FormatException('Expected result field retained to be bool.');
  }
  return ReelCancelResult(retained: retained);
}

@Deprecated('Use reelCancelFlowRef')
abstract final class ReelCancelFlowDescriptor {
  const ReelCancelFlowDescriptor._();

  static const SurfaceFlowRef<ReelCancelResult> ref = reelCancelFlowRef;
}

final class ReelCancelResult {
  const ReelCancelResult({required this.retained});
  final bool retained;
}

final class ReelCancelActions implements FlowActionRegistry {
  ReelCancelActions({
    required FlowActionHandler<void, OfferDecision> redeemOffer,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'redeemOffer': FlowActionBinding<void, OfferDecision>(
            descriptor: redeemOfferDescriptor,
            actionName: redeemOfferDescriptor.actionName,
            contractVersion: redeemOfferDescriptor.contractVersion,
            argsSchema: redeemOfferDescriptor.argsSchema,
            resultSchema: redeemOfferDescriptor.resultSchema,
            minClient: redeemOfferDescriptor.minClient,
            idempotent: redeemOfferDescriptor.idempotent,
            handler: redeemOffer,
            decodeArgs: (_) {},
            encodeResult: (value) => {'redeemed': value.redeemed},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, OfferDecision> redeemOfferDescriptor =
      FlowActionDescriptor<void, OfferDecision>(
    actionName: 'redeemOffer',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.object({
      'redeemed': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      )
    }),
    minClient: 6,
    idempotent: false,
  );
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class ReelCancelFlowSurface extends RestageFlowGraph<ReelCancelResult> {
  const ReelCancelFlowSurface({
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
  }) : super(flow: reelCancelFlowRef);
}
