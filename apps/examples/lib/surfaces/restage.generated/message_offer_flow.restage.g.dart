part of '../message_offer_flow.dart';

const messageOfferRef = SurfaceFlowRef<MessageOfferResult>(
  id: 'message_offer',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  deliveryMode: FlowDeliveryMode.typed,
  decodeResult: _decodeMessageOfferResult,
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
