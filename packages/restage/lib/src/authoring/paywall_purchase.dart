import 'package:flutter/widgets.dart';

import '../events/restage_event.dart';
import 'event_dispatcher.dart';
import 'paywall_event.dart';

/// Returns a callback that initiates a purchase of the configured product.
///
/// Provide either [slot] (preferred — references a slot configured via
/// `Restage.configure(products:)`) or [productId] (escape hatch for one-off
/// SKU references). Exactly one of the two must be non-null.
///
/// Pass [offerId] to apply a promotional offer to the purchase: the SDK fetches
/// a signature for the offer and transports it to the store, falling back to a
/// typed "offer unavailable" outcome (never a silent full-price charge) when no
/// signature is available.
///
/// Codegen replaces this expression in `.rfwtxt` with
/// `event 'restage.purchase' { slot: '...' }` (or `productId: '...'`, plus
/// `offerId: '...'`). The SDK runtime intercepts this event name and dispatches
/// to the billing layer.
///
/// In a non-codegen runtime context, the returned callback fires the same
/// `restage.purchase` event through the [RestagePaywallEventDispatcher]
/// captured at construction time. See [paywallEvent] for the no-dispatcher
/// reporting behavior.
VoidCallback paywallPurchase(
    {String? slot, String? productId, String? offerId}) {
  assert(
    (slot != null) ^ (productId != null),
    'Provide exactly one of slot: or productId:',
  );
  final args = <String, Object?>{
    if (slot != null) 'slot': slot,
    if (productId != null) 'productId': productId,
    if (offerId != null) 'offerId': offerId,
  };
  // Delegate to paywallEvent so the dispatcher is captured at build time
  // (same semantics) and so the no-dispatcher reporting path is shared.
  return paywallEvent(RestageEventNames.purchase, args: args);
}
