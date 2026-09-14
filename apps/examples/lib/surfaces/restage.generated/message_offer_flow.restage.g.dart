part of '../message_offer_flow.dart';

const messageOfferRef = SurfaceFlowRef<
    MessageOfferResult>.generatedWithMeasurementPublicationDraftDigest(
  id: 'message_offer',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMessageOfferResult,
  measurementPublicationDraftDigest:
      '544d07461561a2944ecf7536186892561517a5cfd0795719ba4f78461156a61b',
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
