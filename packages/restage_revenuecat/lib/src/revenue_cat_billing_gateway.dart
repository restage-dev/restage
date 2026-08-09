import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';
import 'package:restage/restage.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Internal indirection over the static `Purchases` API that
/// [RevenueCatBillingGateway] delegates to.
///
/// This is a test seam, not part of the public surface: it exists so the
/// gateway's result/error mapping can be unit-tested without live RevenueCat
/// calls. The default implementation forwards to RevenueCat.
@visibleForTesting
abstract interface class RevenueCatPurchases {
  /// Fetches store products for [productIdentifiers] (see `Purchases.getProducts`).
  Future<List<StoreProduct>> getProducts(List<String> productIdentifiers);

  /// Fetches the configured offerings (see `Purchases.getOfferings`).
  ///
  /// The gateway resolves a `productId` to its offer-bearing package through
  /// these offerings, so a purchase applies the package's configured
  /// offer / trial / base-plan.
  Future<Offerings> getOfferings();

  /// Runs a purchase (see `Purchases.purchase`).
  Future<PurchaseResult> purchase(PurchaseParams params);

  /// Restores prior purchases (see `Purchases.restorePurchases`).
  Future<CustomerInfo> restorePurchases();
}

/// Default [RevenueCatPurchases] backed by the static `Purchases` API.
class _PluginRevenueCatPurchases implements RevenueCatPurchases {
  const _PluginRevenueCatPurchases();

  @override
  Future<List<StoreProduct>> getProducts(List<String> productIdentifiers) =>
      Purchases.getProducts(productIdentifiers);

  @override
  Future<Offerings> getOfferings() => Purchases.getOfferings();

  @override
  Future<PurchaseResult> purchase(PurchaseParams params) =>
      Purchases.purchase(params);

  @override
  Future<CustomerInfo> restorePurchases() => Purchases.restorePurchases();
}

/// A [BillingGateway] that delegates purchases to the host app's existing
/// RevenueCat configuration.
///
/// Lets a Restage paywall trigger a purchase through RevenueCat while Restage
/// renders the surface and owns its own analytics. RevenueCat performs the
/// actual StoreKit / Google Play purchase and keeps its own receipt, so this
/// gateway returns a **receipt-less** ([PurchaseOutcomeSucceeded] with a `null`
/// `verificationData`) success: the transaction id is carried for attribution,
/// but there is no receipt on the wire and the success is never a verified one.
///
/// The host keeps all of its existing RevenueCat entitlement-gating code; this
/// gateway only routes the paywall's Buy / Restore taps into RevenueCat.
final class RevenueCatBillingGateway implements BillingGateway {
  /// Creates a gateway delegating to the host's RevenueCat configuration.
  ///
  /// [purchases] is a test seam; it defaults to the static RevenueCat
  /// `Purchases` API.
  RevenueCatBillingGateway({RevenueCatPurchases? purchases})
      : _purchases = purchases ?? const _PluginRevenueCatPurchases();

  final RevenueCatPurchases _purchases;

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    // This adapter resolves the base plan / offer from RevenueCat's own package
    // configuration at its SDK runtime — it cannot honor a caller-pinned
    // [basePlanId]. On Android, where base-plan selection is meaningful, letting
    // RevenueCat pick a different option than the one the caller pinned would be
    // a silent wrong-charge, so fail closed rather than substitute. (To select a
    // base plan, configure it as a RevenueCat package, or use the bundled
    // gateway; honoring basePlanId via RevenueCat `subscriptionOptions` is a
    // tracked follow-up.) On Apple and other platforms basePlanId has no
    // meaning, so it is ignored and the purchase proceeds — keeping
    // cross-platform call sites that pass it unconditionally working.
    if (basePlanId != null && defaultTargetPlatform == TargetPlatform.android) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.basePlanSelectionRequired,
        message: 'The RevenueCat coexistence adapter cannot apply an explicit '
            'basePlanId; configure the base plan as a RevenueCat package or use '
            'the bundled billing gateway.',
      );
    }
    try {
      // Purchase the offer-bearing RevenueCat *package* (resolved from the
      // store product id), so RevenueCat applies the package's configured
      // offer / free-trial / intro / base-plan at its own SDK runtime. The
      // concrete offer is resolved by RevenueCat, not supplied by Restage.
      //
      // v1 limitation: resolution uses RevenueCat's current offering (then any
      // offering). A per-slot package choice that DIVERGES from current-offering
      // resolution is not honored at runtime here — that precision needs an
      // explicit per-slot selection carried through the purchase intent (a
      // public-contract change). Tracked as a follow-up.
      final package = await _resolvePackage(productId);
      if (package != null) {
        final result =
            await _purchases.purchase(PurchaseParams.package(package));
        return _succeeded(productId, package.storeProduct, result);
      }

      // The product is in no offering, so there is no RevenueCat-configured
      // offer to apply. Fall back to purchasing the raw store product (exactly
      // the no-offer purchase): degrade gracefully rather than turn a working
      // Buy into a failure.
      final products = await _purchases.getProducts(<String>[productId]);
      if (products.isEmpty) {
        return PurchaseOutcome.failed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.productNotFound,
          message: 'RevenueCat does not recognize productId: $productId',
        );
      }
      final product = products.first;
      assert(() {
        debugPrint(
          '[restage_revenuecat] productId "$productId" is not in any '
          'RevenueCat offering — purchasing the raw store product without an '
          'offer. Add it to a package in your current offering for the '
          'offer / trial / base-plan to apply.',
        );
        return true;
      }());
      final result =
          await _purchases.purchase(PurchaseParams.storeProduct(product));
      return _succeeded(productId, product, result);
    } on PlatformException catch (error) {
      return _mapPurchaseError(productId, error);
    } on Object catch (error) {
      // Any non-PlatformException failure must still leave as a failed
      // outcome — a purchase attempt never throws out of a Buy tap. On web,
      // for instance, the store lookup / purchase throws an
      // `UnsupportedPlatformException` or `UnsupportedError` (the platform has
      // no native store), neither of which is a `PlatformException`; without
      // this, such errors would escape the gateway.
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: error.toString(),
      );
    }
  }

  /// Resolves [productId] to the RevenueCat [Package] that wraps it.
  ///
  /// Searches the current offering first (RevenueCat's active/default unit, the
  /// intended one), then every other offering in a stable (key-sorted) order,
  /// matching on `package.storeProduct.identifier`. Returns `null` when no
  /// offering contains the product. If more than one package wraps the product,
  /// the first in this order is chosen deterministically (a debug diagnostic is
  /// emitted) rather than failing a Buy tap.
  Future<Package?> _resolvePackage(String productId) async {
    final offerings = await _purchases.getOfferings();
    final matches = <Package>[];
    for (final offering in _offeringsInResolutionOrder(offerings)) {
      for (final package in offering.availablePackages) {
        if (package.storeProduct.identifier == productId) {
          matches.add(package);
        }
      }
    }
    if (matches.isEmpty) return null;
    if (matches.length > 1) {
      assert(() {
        final first = matches.first;
        debugPrint(
          '[restage_revenuecat] productId "$productId" matches '
          '${matches.length} packages across RevenueCat offerings; purchasing '
          'the first in current-offering-first order (package '
          '"${first.identifier}" in offering '
          '"${first.presentedOfferingContext.offeringIdentifier}").',
        );
        return true;
      }());
    }
    return matches.first;
  }

  /// The offerings to search, current first (then the rest, key-sorted for
  /// determinism). The current offering, if present, also appears in `all`; it
  /// is included once, up front.
  List<Offering> _offeringsInResolutionOrder(Offerings offerings) {
    final current = offerings.current;
    final keys = offerings.all.keys.toList()..sort();
    final rest = keys
        .map((key) =>
            offerings.all[key]!) // key is from `all.keys`, always present
        .where((offering) => offering.identifier != current?.identifier);
    return <Offering>[if (current != null) current, ...rest];
  }

  /// Builds the receipt-less, attribution-only success outcome shared by the
  /// package-purchase and store-product-fallback paths. [product] is the store
  /// product actually purchased (the package's product, or the fallback
  /// product); its list price/currency are carried for attribution.
  PurchaseOutcome _succeeded(
    String productId,
    StoreProduct product,
    PurchaseResult result,
  ) =>
      PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: result.storeTransaction.transactionIdentifier,
        // RevenueCat owns the receipt — this is an attribution-only success.
        verificationData: null,
        priceMicros: (product.price * 1000000).round(),
        currency: product.currencyCode,
      );

  @override
  Future<RestoreOutcome> restore() async {
    try {
      final customerInfo = await _purchases.restorePurchases();
      // Active subscription SKUs are the products the user is currently
      // entitled to; the SDK maps each to its configured entitlement. Expired
      // purchases are intentionally excluded (they would over-grant).
      final restoredProductIds = customerInfo.activeSubscriptions;
      if (restoredProductIds.isEmpty) {
        return RestoreOutcome.noPurchases();
      }
      return RestoreOutcome.succeeded(
        restoredProductIds: List<String>.unmodifiable(restoredProductIds),
      );
    } on PlatformException catch (error) {
      return RestoreOutcome.failed(
        errorCode: _errorCode(error).name,
        message: error.message ?? 'RevenueCat restore failed.',
      );
    }
  }

  PurchaseOutcome _mapPurchaseError(String productId, PlatformException error) {
    final code = _errorCode(error);
    switch (code) {
      case PurchasesErrorCode.purchaseCancelledError:
        return PurchaseOutcome.cancelled(productId: productId);
      case PurchasesErrorCode.paymentPendingError:
        return PurchaseOutcome.pending(
          productId: productId,
          reason: PendingReason.paymentPending,
        );
      default:
        return PurchaseOutcome.failed(
          productId: productId,
          errorCode: code.name,
          message: error.message ?? 'RevenueCat purchase failed.',
          platformErrorCode: error.code,
        );
    }
  }

  /// Resolves [error] to a [PurchasesErrorCode].
  ///
  /// `PurchasesErrorHelper.getErrorCode` parses `PlatformException.code`
  /// numerically and indexes the enum, which can throw on a malformed code:
  /// non-numeric (`FormatException`), negative / out-of-range (`RangeError`),
  /// or non-finite like `Infinity`/`NaN` (`UnsupportedError`). RevenueCat
  /// itself only sends valid indices, but a lower native/plugin layer can set
  /// an arbitrary code — so any malformed code degrades to
  /// [PurchasesErrorCode.unknownError] rather than throwing out of a Buy /
  /// Restore tap.
  PurchasesErrorCode _errorCode(PlatformException error) {
    try {
      return PurchasesErrorHelper.getErrorCode(error);
    } on Object {
      return PurchasesErrorCode.unknownError;
    }
  }
}
