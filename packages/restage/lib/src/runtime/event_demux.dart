import '../events/restage_event.dart';

const Set<String> _reservedCommerceEventNames = <String>{
  'purchase',
  'restore',
  'restage.purchase',
  'restage.restore',
  'restage.purchase.succeeded',
  'restage.purchase.pending',
  'restage.purchase.cancelled',
  'restage.purchase.failed',
  'restage.restore.succeeded',
  'restage.restore.noPurchases',
  'restage.restore.failed',
};

bool isReservedCommerceEventName(String name) =>
    _reservedCommerceEventNames.contains(name);

/// Translates an RFW-fired event into a [PaywallCustomEvent].
///
/// Reserved event names are dropped. Every other name remains available to the
/// host as a custom event.
RestageEvent? demuxRfwEvent({
  required String paywallId,
  required String name,
  required Map<String, Object?> args,
}) {
  if (isReservedCommerceEventName(name)) return null;
  return PaywallCustomEvent(paywallId: paywallId, eventName: name, args: args);
}
