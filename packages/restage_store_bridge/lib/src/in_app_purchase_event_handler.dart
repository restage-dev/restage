import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:restage/restage.dart';

import 'in_app_purchase_controller.dart';

/// Builds a paywall handler for an app-scoped native store [controller].
///
/// `in_app_purchase.purchase` selects an exact product using `packageIdentifier`;
/// `in_app_purchase.restore` requests restoration. Other events are ignored.
/// The package map is copied when the handler is built. Use the same immutable
/// map for display data and dispatch. Unknown or malformed keys are errors.
/// Purchase, restore and selection errors reach [onError], or propagate.
///
/// Dispatch acceptance does not identify a transaction. This handler never
/// automatically reports conversions. Apps with trustworthy correlation may
/// call `Restage.measurement.reportPurchase` with the original event themselves.
Future<void> Function(RestageEvent) inAppPurchaseEventHandler({
  required Map<String, ProductDetails> packages,
  required InAppPurchaseController controller,
  FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
}) => _eventHandler(
  packages: packages,
  purchase: (product) async {
    if (!await controller.purchase(product)) {
      throw StateError('The store did not accept the purchase dispatch.');
    }
    return null;
  },
  restore: controller.restorePurchases,
  onError: onError,
);

/// Builds a paywall handler using the app's existing purchase service.
///
/// The app owns verification, delivery, stream processing and completion. A
/// non-null [purchase] result must be a new purchase correlated to this call,
/// verified and delivered by the app. Null means no confirmed new purchase.
/// The helper requires purchased status and the selected product's exact ID.
///
/// Confirmed results report the original event's exposure, with package/product
/// identifiers only. Reporting failure does not change purchase success. Each
/// event is reported at most once; the app owns transaction deduplication and
/// correlation across distinct events. Restore never reports a conversion.
/// [onPurchase] errors propagate separately from purchase/validation errors,
/// while the confirmed report is still observed.
///
/// Selection, event filtering, map snapshots and [onError] follow
/// [inAppPurchaseEventHandler]. Choose one store lifecycle owner per app.
Future<void> Function(RestageEvent) inAppPurchaseCustomEventHandler({
  required Map<String, ProductDetails> packages,
  required Future<PurchaseDetails?> Function(ProductDetails) purchase,
  required Future<void> Function() restore,
  FutureOr<void> Function(PurchaseDetails)? onPurchase,
  FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
}) => _eventHandler(
  packages: packages,
  purchase: purchase,
  restore: restore,
  onError: onError,
  onConfirmed: (event, identifier, product, result) async {
    final report = Restage.measurement.reportPurchase(
      event,
      packageIdentifier: identifier,
      productIdentifier: product.id,
    );
    try {
      await onPurchase?.call(result);
    } finally {
      await report;
    }
  },
);

Future<void> Function(RestageEvent) _eventHandler({
  required Map<String, ProductDetails> packages,
  required Future<PurchaseDetails?> Function(ProductDetails) purchase,
  required Future<void> Function() restore,
  FutureOr<void> Function(Object, StackTrace)? onError,
  Future<void> Function(
    PaywallCustomEvent,
    String,
    ProductDetails,
    PurchaseDetails,
  )?
  onConfirmed,
}) {
  final snapshot = Map<String, ProductDetails>.unmodifiable(packages);
  return (event) async {
    if (event is! PaywallCustomEvent) return;
    final isPurchase = event.eventName == 'in_app_purchase.purchase';
    if (!isPurchase && event.eventName != 'in_app_purchase.restore') return;

    late String identifier;
    late ProductDetails product;
    PurchaseDetails? result;
    try {
      if (!isPurchase) {
        await restore();
        return;
      }
      final key = event.args['packageIdentifier'];
      if (key is! String || key.isEmpty || !snapshot.containsKey(key)) {
        throw ArgumentError.value(
          key,
          'packageIdentifier',
          'must name a package in the supplied package map',
        );
      }
      identifier = key;
      product = snapshot[key]!;
      result = await purchase(product);
      if (result != null &&
          (result.status != PurchaseStatus.purchased ||
              result.productID != product.id)) {
        throw StateError(
          'The purchase result must confirm the selected product.',
        );
      }
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      await onError(error, stackTrace);
      return;
    }
    if (result != null) {
      await onConfirmed?.call(event, identifier, product, result);
    }
  };
}
