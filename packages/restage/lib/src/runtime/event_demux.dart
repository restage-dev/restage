import 'package:restage_shared/restage_shared.dart'
    show kReservedCommerceEventNames;

import '../events/restage_event.dart';

bool isReservedCommerceEventName(String name) =>
    kReservedCommerceEventNames.contains(name);

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
