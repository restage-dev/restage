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
      '549eb154015433042a5f49e2f81bce08f8c7ecfad17b58fa4d8e566d16724413',
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
