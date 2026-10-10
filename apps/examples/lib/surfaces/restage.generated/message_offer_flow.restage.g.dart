part of '../message_offer_flow.dart';

// ignore_for_file: type=lint

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
        '{"flow":"message_offer","initial":"message_notice","minClient":1,"outbound":{},"schemaVersion":1,"screenArtifacts":{"message_notice":{"contentHash":"sha256:56a82e85dab2ada657cd706fe790cadc4b2ee3f8e08030b5f6ef5829d7bff107","minClient":1,"path":"measurement/cd846771222eec7f/message_notice.rfw","schemaVersion":1,"version":1},"paywall_upgrade_offer":{"contentHash":"sha256:34f841a2fc7bad46ae2683187e878dc75eb7103ea6488aff0d37573009411074","minClient":1,"path":"paywall_upgrade_offer.rfw","schemaVersion":1,"version":1}},"states":{"done":{"kind":"end","result":{}},"message_notice":{"kind":"screen","on":{"open_offer":{"target":"paywall_upgrade_offer","type":"goto"}},"screen":"message_notice"},"paywall_upgrade_offer":{"kind":"screen","on":{"continue":{"target":"done","type":"goto"}},"screen":"paywall_upgrade_offer"}},"version":1}',
    screens: {
      'message_notice': MessageNotice.new,
      'paywall_upgrade_offer': UpgradeOffer.new,
    },
    children: {},
  ),
  measurementPublicationDraftDigest:
      'a0eec6e07248181a5913343fb44e05fded25d15ac8eb5fd208232d8e02d8b80f',
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
