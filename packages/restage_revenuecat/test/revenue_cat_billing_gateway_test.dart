// The test fake implements the [RevenueCatPurchases] seam — its documented
// test purpose. The seam is @visibleForTesting and lives in src/, so it's
// imported directly here rather than through the public barrel.
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride, debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_revenuecat/src/revenue_cat_billing_gateway.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Hand-written fake of the RevenueCat surface — no live RevenueCat calls.
class _FakeRevenueCatPurchases implements RevenueCatPurchases {
  _FakeRevenueCatPurchases({
    this.onGetProducts,
    this.onGetOfferings,
    this.onPurchase,
    this.onRestore,
  });

  Future<List<StoreProduct>> Function(List<String> ids)? onGetProducts;
  Future<Offerings> Function()? onGetOfferings;
  Future<PurchaseResult> Function(PurchaseParams params)? onPurchase;
  Future<CustomerInfo> Function()? onRestore;

  final List<String> calls = <String>[];

  /// The params of the most recent [purchase] call — lets a test assert whether
  /// the offer-bearing package (`params.package`) or the raw store product
  /// (`params.product`) was purchased.
  PurchaseParams? lastPurchaseParams;

  @override
  Future<List<StoreProduct>> getProducts(List<String> productIdentifiers) {
    calls.add('getProducts:${productIdentifiers.join(",")}');
    return onGetProducts!(productIdentifiers);
  }

  @override
  Future<Offerings> getOfferings() {
    calls.add('getOfferings');
    // Default: no offerings configured. Drives the graceful store-product
    // fallback for tests that don't exercise offer resolution.
    return onGetOfferings?.call() ??
        Future<Offerings>.value(const Offerings(<String, Offering>{}));
  }

  @override
  Future<PurchaseResult> purchase(PurchaseParams params) {
    lastPurchaseParams = params;
    calls.add(
      'purchase:product=${params.product?.identifier},'
      'package=${params.package?.identifier}',
    );
    return onPurchase!(params);
  }

  @override
  Future<CustomerInfo> restorePurchases() {
    calls.add('restorePurchases');
    return onRestore!();
  }
}

StoreProduct _product({
  String identifier = 'pro_monthly',
  double price = 9.99,
  String currencyCode = 'USD',
}) =>
    StoreProduct(identifier, 'desc', 'title', price, r'$9.99', currencyCode);

Package _package({
  String identifier = r'$rc_monthly',
  PackageType packageType = PackageType.monthly,
  StoreProduct? storeProduct,
  String offeringIdentifier = 'default',
}) =>
    Package(
      identifier,
      packageType,
      storeProduct ?? _product(),
      PresentedOfferingContext(offeringIdentifier, null, null),
    );

Offering _offering({
  String identifier = 'default',
  List<Package>? packages,
}) =>
    Offering(
      identifier,
      'desc',
      const <String, Object>{},
      packages ?? <Package>[_package(offeringIdentifier: identifier)],
    );

/// Builds an [Offerings] with [current] (also placed in `all`) plus [others].
Offerings _offerings({
  Offering? current,
  List<Offering> others = const <Offering>[],
}) {
  final all = <String, Offering>{};
  if (current != null) all[current.identifier] = current;
  for (final offering in others) {
    all[offering.identifier] = offering;
  }
  return Offerings(all, current: current);
}

/// Convenience: a single current offering whose one package wraps [productId].
Offerings _offeringsWith(String productId, {String offeringId = 'default'}) =>
    _offerings(
      current: _offering(
        identifier: offeringId,
        packages: <Package>[
          _package(
            storeProduct: _product(identifier: productId),
            offeringIdentifier: offeringId,
          ),
        ],
      ),
    );

PurchaseResult _purchaseResult({
  String transactionId = 'GPA.1234',
  String productId = 'pro_monthly',
}) =>
    PurchaseResult(
      _customerInfo(const <String>[]),
      StoreTransaction(transactionId, productId, '2026-01-01T00:00:00Z'),
    );

CustomerInfo _customerInfo(List<String> activeSubscriptions) => CustomerInfo(
      const EntitlementInfos(
          <String, EntitlementInfo>{}, <String, EntitlementInfo>{}),
      const <String, String?>{},
      activeSubscriptions,
      activeSubscriptions,
      const <StoreTransaction>[],
      '2026-01-01T00:00:00Z',
      'anon',
      const <String, String?>{},
      '2026-01-01T00:00:00Z',
    );

PlatformException _rcError(PurchasesErrorCode code,
        {String message = 'boom'}) =>
    PlatformException(code: code.index.toString(), message: message);

/// Captures `debugPrint` output for the duration of a test.
List<String> _captureDebugPrint() {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  addTearDown(() => debugPrint = original);
  return logs;
}

void main() {
  group('RevenueCatBillingGateway.purchase — explicit basePlanId', () {
    test('fails closed on Android, never delegating to RevenueCat', () async {
      // The adapter resolves base plans through RevenueCat's own package config,
      // so it cannot honor a caller-pinned basePlanId. Letting RevenueCat pick a
      // different option would be a silent wrong-charge — fail closed instead.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fake = _FakeRevenueCatPurchases();
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('pro_sub', basePlanId: 'annual');

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.basePlanSelectionRequired);
      expect(fake.calls, isEmpty,
          reason: 'never let RevenueCat substitute a base plan the caller '
              'explicitly pinned');
    });

    test('ignores basePlanId on Apple (no base-plan concept) and proceeds',
        () async {
      // basePlanId is meaningless on Apple, so a cross-platform call site that
      // passes it unconditionally must still purchase normally on iOS.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fake = _FakeRevenueCatPurchases(
        onGetOfferings: () async => _offeringsWith('pro_sub'),
        onPurchase: (_) async => _purchaseResult(productId: 'pro_sub'),
      );
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('pro_sub', basePlanId: 'annual');

      expect(outcome, isA<PurchaseOutcomeSucceeded>(),
          reason: 'basePlanId is irrelevant on Apple; the purchase proceeds');
    });
  });

  group('RevenueCatBillingGateway.purchase — package resolution', () {
    test(
        'resolves a product in the current offering and purchases the '
        'offer-bearing package', () async {
      final fake = _FakeRevenueCatPurchases(
        onGetOfferings: () async => _offerings(
          current: _offering(
            packages: <Package>[
              _package(
                identifier: r'$rc_monthly',
                storeProduct: _product(identifier: 'pro_monthly', price: 9.99),
              ),
            ],
          ),
        ),
        onPurchase: (_) async => _purchaseResult(transactionId: 'GPA.42'),
      );
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final succeeded = outcome as PurchaseOutcomeSucceeded;
      expect(succeeded.productId, 'pro_monthly');
      expect(succeeded.transactionId, 'GPA.42');
      // (Full success-field mapping is covered by the outcome-mapping group;
      // this test focuses on the package-routing decision.)
      // The PACKAGE was purchased (so RevenueCat applies the package's
      // configured offer / trial / base-plan), not the raw store product.
      expect(fake.lastPurchaseParams?.package, isNotNull);
      expect(fake.lastPurchaseParams?.package?.identifier, r'$rc_monthly');
      expect(
        fake.lastPurchaseParams?.package?.storeProduct.identifier,
        'pro_monthly',
      );
      expect(fake.lastPurchaseParams?.product, isNull);
      // No raw store lookup was needed — the package carried the product.
      expect(fake.calls.any((c) => c.startsWith('getProducts')), isFalse);
    });

    test('resolves a product found only in a non-current offering', () async {
      final fake = _FakeRevenueCatPurchases(
        onGetOfferings: () async => _offerings(
          current: _offering(
            packages: <Package>[
              _package(
                identifier: r'$rc_monthly',
                storeProduct: _product(identifier: 'pro_monthly'),
              ),
            ],
          ),
          others: <Offering>[
            _offering(
              identifier: 'promo',
              packages: <Package>[
                _package(
                  identifier: r'$rc_annual',
                  packageType: PackageType.annual,
                  storeProduct: _product(identifier: 'pro_annual'),
                  offeringIdentifier: 'promo',
                ),
              ],
            ),
          ],
        ),
        onPurchase: (_) async => _purchaseResult(
            transactionId: 'GPA.annual', productId: 'pro_annual'),
      );
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('pro_annual');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect(fake.lastPurchaseParams?.package?.identifier, r'$rc_annual');
      expect(
        fake.lastPurchaseParams?.package?.storeProduct.identifier,
        'pro_annual',
      );
    });

    test(
        'a product not in any offering falls back to a raw store-product '
        'purchase and emits a debug diagnostic', () async {
      final logs = _captureDebugPrint();
      final fake = _FakeRevenueCatPurchases(
        onGetOfferings: () async => _offeringsWith('pro_monthly'),
        onGetProducts: (_) async => <StoreProduct>[
          _product(identifier: 'legacy_sku', price: 4.99, currencyCode: 'EUR')
        ],
        onPurchase: (_) async => _purchaseResult(
            transactionId: 'GPA.legacy', productId: 'legacy_sku'),
      );
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('legacy_sku');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final succeeded = outcome as PurchaseOutcomeSucceeded;
      expect(succeeded.productId, 'legacy_sku');
      expect(succeeded.priceMicros, 4990000);
      expect(succeeded.currency, 'EUR');
      // The raw store product was purchased (no RC offer to apply).
      expect(fake.lastPurchaseParams?.product, isNotNull);
      expect(fake.lastPurchaseParams?.product?.identifier, 'legacy_sku');
      expect(fake.lastPurchaseParams?.package, isNull);
      // The dev gets a diagnostic so "my trial isn't applying" is self-explained.
      expect(
        logs.any((l) => l.contains('legacy_sku') && l.contains('offering')),
        isTrue,
      );
    });

    test(
        'an ambiguous product (in multiple packages) purchases the first in '
        'current-offering-first order and logs the ambiguity', () async {
      final logs = _captureDebugPrint();
      final fake = _FakeRevenueCatPurchases(
        onGetOfferings: () async => _offerings(
          current: _offering(
            packages: <Package>[
              _package(
                identifier: r'$rc_monthly',
                storeProduct: _product(identifier: 'pro_monthly'),
              ),
              _package(
                identifier: 'custom_duplicate',
                packageType: PackageType.custom,
                storeProduct: _product(identifier: 'pro_monthly'),
              ),
            ],
          ),
        ),
        onPurchase: (_) async => _purchaseResult(transactionId: 'GPA.first'),
      );
      final gateway = RevenueCatBillingGateway(purchases: fake);

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      // Deterministic: the first package in current-first order.
      expect(fake.lastPurchaseParams?.package?.identifier, r'$rc_monthly');
      expect(
        logs.any((l) => l.contains('pro_monthly') && l.contains('matches')),
        isTrue,
      );
    });

    test('an unknown product (no offering, no store) maps to product_not_found',
        () async {
      // No offerings configured (fake default) → fallback → getProducts empty.
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetProducts: (_) async => <StoreProduct>[],
        ),
      );

      final outcome = await gateway.purchase('mystery_sku');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      final failed = outcome as PurchaseOutcomeFailed;
      expect(failed.productId, 'mystery_sku');
      expect(failed.errorCode, RestageBillingErrorCodes.productNotFound);
    });

    test('a getOfferings failure maps to a failed outcome, not thrown',
        () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => throw _rcError(
              PurchasesErrorCode.networkError,
              message: 'offline'),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      final failed = outcome as PurchaseOutcomeFailed;
      expect(failed.errorCode, PurchasesErrorCode.networkError.name);
      expect(failed.message, 'offline');
    });

    test(
        'an unsupported-platform store lookup (e.g. web) maps to a failed '
        'outcome, not thrown', () async {
      // On the web the store-product lookup throws an UnsupportedError (the
      // platform has no native store). That is not a PlatformException, so the
      // gateway must still leave a failed outcome rather than let it escape out
      // of a Buy tap.
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          // No offerings (fake default) → store-product fallback path.
          onGetProducts: (_) async =>
              throw UnsupportedError('getProducts not implemented on web'),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.buyFailed);
    });

    test(
        'an unsupported-platform purchase (e.g. web) maps to a failed outcome, '
        'not thrown', () async {
      // On the web the purchase call throws an UnsupportedPlatformException —
      // an Exception, but not a PlatformException — so the gateway must still
      // map it to a failed outcome instead of throwing out of a Buy tap.
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async => throw UnsupportedPlatformException(),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.buyFailed);
    });
  });

  group('RevenueCatBillingGateway.purchase — outcome mapping', () {
    test('maps a successful purchase to a receipt-less succeeded outcome',
        () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async => _purchaseResult(transactionId: 'GPA.42'),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final succeeded = outcome as PurchaseOutcomeSucceeded;
      expect(succeeded.productId, 'pro_monthly');
      expect(succeeded.transactionId, 'GPA.42');
      // Receipt-less: RevenueCat keeps the receipt, so the success is
      // attribution-only and must never read as verified.
      expect(succeeded.verificationData, isNull);
      expect(succeeded.priceMicros, 9990000);
      expect(succeeded.currency, 'USD');
    });

    test('a success with an empty transaction id still succeeds', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async => _purchaseResult(transactionId: ''),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect((outcome as PurchaseOutcomeSucceeded).transactionId, '');
    });

    test('a user-cancelled purchase maps to cancelled', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async =>
              throw _rcError(PurchasesErrorCode.purchaseCancelledError),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeCancelled>());
      expect((outcome as PurchaseOutcomeCancelled).productId, 'pro_monthly');
    });

    test('a pending payment maps to pending(paymentPending)', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async =>
              throw _rcError(PurchasesErrorCode.paymentPendingError),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomePending>());
      final pending = outcome as PurchaseOutcomePending;
      expect(pending.productId, 'pro_monthly');
      expect(pending.reason, PendingReason.paymentPending);
    });

    test('any other RevenueCat error maps to failed, carrying the RC code',
        () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async => throw _rcError(
            PurchasesErrorCode.storeProblemError,
            message: 'store is down',
          ),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      final failed = outcome as PurchaseOutcomeFailed;
      expect(failed.productId, 'pro_monthly');
      expect(failed.errorCode, PurchasesErrorCode.storeProblemError.name);
      expect(failed.message, 'store is down');
      expect(
        failed.platformErrorCode,
        PurchasesErrorCode.storeProblemError.index.toString(),
      );
    });

    test('a non-numeric platform error code is handled, not thrown', () async {
      // PurchasesErrorHelper.getErrorCode does num.parse(e.code); a
      // non-numeric code must degrade to unknown, not throw out of the gateway.
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onGetOfferings: () async => _offeringsWith('pro_monthly'),
          onPurchase: (_) async => throw PlatformException(
            code: 'NOT_A_NUMBER',
            message: 'weird native error',
          ),
        ),
      );

      final outcome = await gateway.purchase('pro_monthly');

      expect(outcome, isA<PurchaseOutcomeFailed>());
      final failed = outcome as PurchaseOutcomeFailed;
      expect(failed.errorCode, PurchasesErrorCode.unknownError.name);
      expect(failed.platformErrorCode, 'NOT_A_NUMBER');
    });

    test(
        'an out-of-range / non-finite platform error code is handled, not '
        'thrown', () async {
      // getErrorCode parses e.code numerically then indexes the enum. A
      // negative code (e.g. "-1") indexes out of range (RangeError) and
      // "Infinity"/"NaN" throw on .round() (UnsupportedError) — neither is a
      // FormatException, so the guard must degrade rather than let an
      // exception escape on a Buy tap.
      for (final code in <String>['-1', 'Infinity', 'NaN']) {
        final gateway = RevenueCatBillingGateway(
          purchases: _FakeRevenueCatPurchases(
            onGetOfferings: () async => _offeringsWith('pro_monthly'),
            onPurchase: (_) async =>
                throw PlatformException(code: code, message: 'weird'),
          ),
        );

        final outcome = await gateway.purchase('pro_monthly');

        expect(outcome, isA<PurchaseOutcomeFailed>(), reason: 'code=$code');
        expect(
          (outcome as PurchaseOutcomeFailed).errorCode,
          PurchasesErrorCode.unknownError.name,
          reason: 'code=$code',
        );
      }
    });
  });

  group('RevenueCatBillingGateway.restore', () {
    test('active subscriptions map to a succeeded restore', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onRestore: () async =>
              _customerInfo(<String>['pro_monthly', 'pro_annual']),
        ),
      );

      final outcome = await gateway.restore();

      expect(outcome, isA<RestoreOutcomeSucceeded>());
      expect(
        (outcome as RestoreOutcomeSucceeded).restoredProductIds,
        <String>['pro_monthly', 'pro_annual'],
      );
    });

    test('no active subscriptions maps to noPurchases', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onRestore: () async => _customerInfo(const <String>[]),
        ),
      );

      final outcome = await gateway.restore();

      expect(outcome, isA<RestoreOutcomeNoPurchases>());
    });

    test('a restore error maps to failed, carrying the RC code', () async {
      final gateway = RevenueCatBillingGateway(
        purchases: _FakeRevenueCatPurchases(
          onRestore: () async => throw _rcError(
            PurchasesErrorCode.networkError,
            message: 'offline',
          ),
        ),
      );

      final outcome = await gateway.restore();

      expect(outcome, isA<RestoreOutcomeFailed>());
      final failed = outcome as RestoreOutcomeFailed;
      expect(failed.errorCode, PurchasesErrorCode.networkError.name);
      expect(failed.message, 'offline');
    });
  });
}
