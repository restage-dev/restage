part of '../message_offer_flow.dart';

const messageOfferRef = SurfaceFlowRef<
    MessageOfferResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'message_offer',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMessageOfferResult,
  compiled: CompiledFlow(
    documentJson:
        "{\"flow\":\"message_offer\",\"initial\":\"message_notice\",\"minClient\":1,\"outbound\":{},\"schemaVersion\":1,\"screenArtifacts\":{\"message_notice\":{\"contentHash\":\"sha256:562850c510f4a7b96da6be807d931e848052bbdeaa33b5b7f76c2871f9546a45\",\"minClient\":1,\"path\":\"message_notice.rfw\",\"schemaVersion\":1,\"version\":1},\"paywall_upgrade_offer\":{\"contentHash\":\"sha256:f381b3d9a17e881db13ba9b8871d1e8274ee83a00ecc4c96d3f750f409a6dfbc\",\"minClient\":1,\"path\":\"paywall_upgrade_offer.rfw\",\"schemaVersion\":1,\"version\":1}},\"states\":{\"done\":{\"kind\":\"end\",\"result\":{}},\"message_notice\":{\"kind\":\"screen\",\"on\":{\"open_offer\":{\"target\":\"paywall_upgrade_offer\",\"type\":\"goto\"}},\"screen\":\"message_notice\"},\"paywall_upgrade_offer\":{\"kind\":\"screen\",\"on\":{\"continue\":{\"target\":\"done\",\"type\":\"goto\"}},\"screen\":\"paywall_upgrade_offer\"}},\"version\":1}",
    screens: {
      "message_notice": MessageNotice.new,
      "paywall_upgrade_offer": UpgradeOffer.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      '549eb154015433042a5f49e2f81bce08f8c7ecfad17b58fa4d8e566d16724413',
  vocabulary: SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
      material: {
        'FilledButton': buildFilledButton,
      },
    ),
  ),
);

MessageOfferResult _decodeMessageOfferResult(Map<String, Object?> result) {
  if (result.isNotEmpty) {
    throw const FormatException('Unexpected flow result keys.');
  }
  return const MessageOfferResult();
}

final class MessageOfferResult {
  const MessageOfferResult();
}

/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class MessageOfferSurface extends RestageFlowGraph<MessageOfferResult> {
  const MessageOfferSurface({
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
  }) : super(flow: messageOfferRef);
}
