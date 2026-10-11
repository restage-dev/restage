import 'dart:async';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:restage/restage.dart';

/// Builds a paywall `onEvent` handler using the app's RevenueCat configuration.
///
/// `revenuecat.purchase` requires a `packageIdentifier` from [offering].
/// `revenuecat.restore` restores purchases. Other events are ignored.
/// [onCustomerInfo] receives RevenueCat's result after either operation.
/// [onError] receives purchase, restore and identifier errors, including native
/// cancellation errors. Without it, the returned future propagates the error.
///
/// Successful purchases report a conversion for the originating exposure when
/// available. Reporting failure does not change the purchase result. RevenueCat
/// remains the entitlement source; restores never report a conversion.
Future<void> Function(RestageEvent) revenueCatEventHandler({
  required Offering offering,
  FutureOr<void> Function(CustomerInfo)? onCustomerInfo,
  FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
}) {
  return (event) async {
    if (event is! PaywallCustomEvent) return;
    final isPurchase = event.eventName == 'revenuecat.purchase';
    if (!isPurchase && event.eventName != 'revenuecat.restore') return;

    CustomerInfo customerInfo;
    Package? package;
    try {
      if (isPurchase) {
        final identifier = event.args['packageIdentifier'];
        if (identifier is! String || identifier.isEmpty) {
          throw ArgumentError.value(identifier, 'packageIdentifier',
              'must name a package in the supplied offering');
        }
        for (final candidate in offering.availablePackages) {
          if (candidate.identifier == identifier) {
            package = candidate;
            break;
          }
        }
        if (package == null) {
          throw ArgumentError.value(identifier, 'packageIdentifier',
              'is not in offering ${offering.identifier}');
        }
        final result =
            await Purchases.purchase(PurchaseParams.package(package));
        customerInfo = result.customerInfo;
      } else {
        customerInfo = await Purchases.restorePurchases();
      }
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      await onError(error, stackTrace);
      return;
    }

    final report = package == null
        ? null
        : Restage.measurement.reportPurchase(
            event,
            packageIdentifier: package.identifier,
            productIdentifier: package.storeProduct.identifier,
          );
    await onCustomerInfo?.call(customerInfo);
    await report;
  };
}
