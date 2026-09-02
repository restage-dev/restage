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
      'c59035255e46ef021e813c4088498a066d5eff76b2d0fc7b0d70cd75157dfd3d',
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
