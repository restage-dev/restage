import 'package:flutter/foundation.dart';

import '../events/restage_event.dart';
import 'restage.dart';

/// Translate an RFW-fired event (name + args, either editor- or
/// codegen-authored) into the appropriate [RestageEvent] subclass.
///
/// SDK-owned events become typed conversion events; everything else flows
/// through as [PaywallCustomEvent] for the host to interpret.
///
/// - `restage.purchase` -> resolve product by `slot` or `productId`, emit
///   [PurchaseInitiated] with `priceMicros` and `currency` left null — the
///   platform store lookup populates them on the subsequent
///   [PurchaseSucceeded].
/// - `restage.restore`  -> emit [RestoreInitiated].
/// - everything else    -> wrap as [PaywallCustomEvent].
RestageEvent demuxRfwEvent({
  required String paywallId,
  required String name,
  required Map<String, Object?> args,
}) {
  switch (name) {
    case RestageEventNames.purchase:
      final slot = args['slot'] as String?;
      final productId = args['productId'] as String?;
      final offerId = args['offerId'] as String?;
      final resolvedProductId = productId ??
          (slot == null ? null : Restage.findProductBySlot(slot)?.id);
      if (resolvedProductId == null) {
        debugPrint(
          '[restage] purchase event could not resolve product '
          '(slot=$slot, productId=$productId). Call Restage.configure(products:'
          ' [...]) with a matching slot or productId, or pass an explicit '
          'productId on paywallPurchase().',
        );
      }
      return PurchaseInitiated(
        paywallId: paywallId,
        productId: resolvedProductId ?? '',
        offerId: offerId,
      );
    case RestageEventNames.restore:
      return RestoreInitiated(paywallId: paywallId);
    default:
      return PaywallCustomEvent(
        paywallId: paywallId,
        eventName: name,
        args: args,
      );
  }
}
