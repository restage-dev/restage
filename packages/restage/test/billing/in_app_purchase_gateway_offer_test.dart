import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:restage/src/billing/billing_gateway.dart';
import 'package:restage/src/billing/in_app_purchase_gateway.dart';
import 'package:restage/src/billing/signed_native_offer.dart';
import 'package:restage_shared/restage_shared.dart' show OfferSignatureScheme;

void main() {
  final product = ProductDetails(
    id: 'com.example.app.pro_monthly',
    title: 'Pro',
    description: 'Pro plan',
    price: r'$9.99',
    rawPrice: 9.99,
    currencyCode: 'USD',
  );

  const offer = AppleSignedOffer(
    offerId: 'winback_3mo',
    keyIdentifier: 'KEY123',
    nonce: 'a3f1c2d4-0000-4000-8000-000000000001',
    timestampMs: 1718312345678,
    signatureBase64: 'MEUCIQ...base64der...==',
  );

  group('buildApplePromotionalOfferParam', () {
    test('maps the signed offer field-for-field onto the StoreKit param', () {
      final param = buildApplePromotionalOfferParam(
        product: product,
        appAccountToken: 'token-uuid',
        offer: offer,
      );

      expect(param.productDetails, same(product));
      expect(param.applicationUserName, 'token-uuid');

      final promo = param.promotionalOffer;
      expect(promo, isNotNull);
      expect(promo!.offerId, 'winback_3mo');
      expect(promo.signature.keyID, 'KEY123');
      expect(promo.signature.nonce, 'a3f1c2d4-0000-4000-8000-000000000001');
      expect(promo.signature.timestamp, 1718312345678);
      expect(promo.signature.signature, 'MEUCIQ...base64der...==');
    });
  });

  group('buildGooglePlayOfferParam (offerId -> offerToken resolution)', () {
    const productId = 'com.example.app.pro_sub';

    test('resolves the eligible token for a matching discount offer id', () {
      final products = _googleSubProducts(productId, const [
        // A plain base plan (offerId == null) must never be treated as an offer.
        (basePlanId: 'monthly', offerId: null, token: 'tok-base-monthly'),
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-winback'),
      ]);

      final param = buildGooglePlayOfferParam(
        productId: productId,
        products: products,
        appAccountToken: 'token-uuid',
        offer: const GoogleOffer(offerId: 'winback_3mo'),
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-winback');
      expect(param.applicationUserName, 'token-uuid');
      expect(
        (param.productDetails as GooglePlayProductDetails).offerToken,
        'tok-winback',
        reason: 'the chosen product entry is the matched offer',
      );
    });

    test(
        'returns null (ambiguous) when the offer id recurs across base plans '
        'and no basePlanId is given', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: 'winback_3mo', token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-annual'),
      ]);

      expect(
        buildGooglePlayOfferParam(
          productId: productId,
          products: products,
          appAccountToken: 'token-uuid',
          offer: const GoogleOffer(offerId: 'winback_3mo'),
        ),
        isNull,
        reason: 'never guess which base plan to charge',
      );
    });

    test('disambiguates with basePlanId when the offer id recurs', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: 'winback_3mo', token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-annual'),
      ]);

      final param = buildGooglePlayOfferParam(
        productId: productId,
        products: products,
        appAccountToken: 'token-uuid',
        offer: const GoogleOffer(offerId: 'winback_3mo', basePlanId: 'annual'),
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-annual');
    });

    test('returns null when the offer id is absent from the product', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'annual', offerId: 'something_else', token: 'tok-other'),
      ]);

      expect(
        buildGooglePlayOfferParam(
          productId: productId,
          products: products,
          appAccountToken: 'token-uuid',
          offer: const GoogleOffer(offerId: 'winback_3mo'),
        ),
        isNull,
      );
    });

    test('never matches a plain base plan via its base-plan id', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'annual', offerId: null, token: 'tok-base-annual'),
      ]);

      // Passing the base-plan id as an offer id must NOT select the base plan
      // (that would charge an un-discounted plan the user didn't choose).
      expect(
        buildGooglePlayOfferParam(
          productId: productId,
          products: products,
          appAccountToken: 'token-uuid',
          offer: const GoogleOffer(offerId: 'annual'),
        ),
        isNull,
      );
    });

    test('skips non-Google ProductDetails entries', () {
      final products = <ProductDetails>[product];

      expect(
        buildGooglePlayOfferParam(
          productId: productId,
          products: products,
          appAccountToken: 'token-uuid',
          offer: const GoogleOffer(offerId: 'winback_3mo'),
        ),
        isNull,
      );
    });

    test('matches only entries for the requested product id', () {
      // Two products whose offers share an offer id. The resolver must not
      // cross products: it resolves the requested product's token and ignores
      // the other, rather than treating the collision as ambiguous.
      final products = <ProductDetails>[
        ..._googleSubProducts(productId, const [
          (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-wanted'),
        ]),
        ..._googleSubProducts('com.example.app.other_sub', const [
          (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-other'),
        ]),
      ];

      final param = buildGooglePlayOfferParam(
        productId: productId,
        products: products,
        appAccountToken: 'token-uuid',
        offer: const GoogleOffer(offerId: 'winback_3mo'),
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-wanted');
    });
  });

  group('buildGooglePlayBasePlanParam (base-plan selection, no discount)', () {
    const productId = 'com.example.app.pro_sub';

    test('resolves the only base plan when none is specified', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base-monthly'),
      ]);

      final param = buildGooglePlayBasePlanParam(
        productId: productId,
        products: products,
        basePlanId: null,
        applicationUserName: 'token-uuid',
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-base-monthly');
      expect(param.applicationUserName, 'token-uuid');
    });

    test('picks the standard base-plan entry, never an attached offer', () {
      // A single base plan that also carries a discounted offer. A plain
      // purchase must buy the standard base-plan entry (offerId == null), never
      // the discount the user didn't choose.
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base'),
        (basePlanId: 'monthly', offerId: 'intro_1mo', token: 'tok-intro'),
      ]);

      final param = buildGooglePlayBasePlanParam(
        productId: productId,
        products: products,
        basePlanId: null,
        applicationUserName: 'token-uuid',
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-base',
          reason: 'a plain purchase takes the base plan, not the offer');
    });

    test('returns null (ambiguous) when multiple base plans and none chosen',
        () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: null, token: 'tok-annual'),
      ]);

      expect(
        buildGooglePlayBasePlanParam(
          productId: productId,
          products: products,
          basePlanId: null,
          applicationUserName: 'token-uuid',
        ),
        isNull,
        reason: 'never guess which base plan to charge',
      );
    });

    test('resolves the chosen base plan when one is specified', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: null, token: 'tok-annual'),
      ]);

      final param = buildGooglePlayBasePlanParam(
        productId: productId,
        products: products,
        basePlanId: 'annual',
        applicationUserName: 'token-uuid',
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-annual');
    });

    test('returns null when the chosen base plan is absent', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
      ]);

      expect(
        buildGooglePlayBasePlanParam(
          productId: productId,
          products: products,
          basePlanId: 'annual',
          applicationUserName: 'token-uuid',
        ),
        isNull,
      );
    });

    test('never selects an offer entry via the base-plan id', () {
      // The 'annual' base plan exists only as a discounted offer entry here (no
      // standard base entry). Selecting it by base-plan id must NOT pick the
      // discounted offer — that would charge a discount the user didn't choose.
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'annual', offerId: 'promo', token: 'tok-promo'),
      ]);

      expect(
        buildGooglePlayBasePlanParam(
          productId: productId,
          products: products,
          basePlanId: 'annual',
          applicationUserName: 'token-uuid',
        ),
        isNull,
      );
    });

    test('returns null for a non-Google ProductDetails list', () {
      expect(
        buildGooglePlayBasePlanParam(
          productId: productId,
          products: <ProductDetails>[product],
          basePlanId: null,
          applicationUserName: 'token-uuid',
        ),
        isNull,
      );
    });

    test('matches only entries for the requested product id', () {
      final products = <ProductDetails>[
        ..._googleSubProducts(productId, const [
          (basePlanId: 'monthly', offerId: null, token: 'tok-wanted'),
        ]),
        ..._googleSubProducts('com.example.app.other_sub', const [
          (basePlanId: 'monthly', offerId: null, token: 'tok-other'),
        ]),
      ];

      final param = buildGooglePlayBasePlanParam(
        productId: productId,
        products: products,
        basePlanId: null,
        applicationUserName: 'token-uuid',
      );

      expect(param, isNotNull);
      expect(param!.offerToken, 'tok-wanted',
          reason: 'the other product\'s base plan must not create ambiguity');
    });

    test('carries a null application user name through unchanged', () {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base'),
      ]);

      final param = buildGooglePlayBasePlanParam(
        productId: productId,
        products: products,
        basePlanId: null,
        applicationUserName: null,
      );

      expect(param, isNotNull);
      expect(param!.applicationUserName, isNull);
    });
  });

  group('InAppPurchaseGateway.purchaseWithOffer', () {
    // The offer transport is Apple-only; pin an Apple platform so these tests
    // are deterministic regardless of the test host. The non-Apple case
    // overrides this within the test.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('threads the offer + token through buyNonConsumable and succeeds',
        () async {
      final plugin = _FakeInAppPurchase(
        product: product,
        onBuy: (_) => _purchased(product.id),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchaseWithOffer(
        productId: product.id,
        offer: offer,
        appAccountToken: 'token-uuid',
      );

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final captured = plugin.capturedParam;
      expect(captured, isA<Sk2PurchaseParam>());
      captured as Sk2PurchaseParam;
      expect(captured.applicationUserName, 'token-uuid');
      expect(captured.promotionalOffer?.offerId, 'winback_3mo');
      expect(captured.promotionalOffer?.signature.signature,
          'MEUCIQ...base64der...==');
    });

    test(
        'fails closed (offerUnavailable) for a non-legacy signing scheme, '
        'without calling the store', () async {
      final plugin = _FakeInAppPurchase(product: product);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      // A scheme the bundled gateway cannot transport today (only legacy
      // rides StoreKit 2). The orchestration also gates on this, but the
      // gateway is the defense-in-depth backstop.
      const unsupported = AppleSignedOffer(
        offerId: 'winback_3mo',
        keyIdentifier: 'KEY123',
        nonce: 'n',
        timestampMs: 1,
        signatureBase64: 'sig',
        scheme: OfferSignatureScheme.jws,
      );

      final outcome = await gateway.purchaseWithOffer(
        productId: product.id,
        offer: unsupported,
        appAccountToken: 'token-uuid',
      );

      expect(outcome, isA<PurchaseOutcomeFailed>());
      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(plugin.buyCalled, isFalse,
          reason: 'never reach the store for an offer it cannot transport');
    });

    test('fails closed on a non-Apple platform without calling the store',
        () async {
      final plugin = _FakeInAppPurchase(product: product);
      final gateway = InAppPurchaseGateway(plugin: plugin);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final outcome = await gateway.purchaseWithOffer(
        productId: product.id,
        offer: offer,
        appAccountToken: 'token-uuid',
      );

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(plugin.buyCalled, isFalse,
          reason: 'an Apple offer cannot ride a non-Apple store');
    });

    test('maps an SK2-unavailable platform error to offerUnavailable',
        () async {
      final plugin = _FakeInAppPurchase(
        product: product,
        onBuy: (_) => throw PlatformException(code: 'storekit2_not_enabled'),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchaseWithOffer(
        productId: product.id,
        offer: offer,
        appAccountToken: 'token-uuid',
      );

      expect(outcome, isA<PurchaseOutcomeFailed>());
      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
    });
  });

  group('InAppPurchaseGateway.purchaseWithOffer (Google)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    const googleProductId = 'com.example.app.pro_sub';
    const googleOffer = GoogleOffer(offerId: 'winback_3mo');

    test('resolves the offer token and transports it via buyNonConsumable',
        () async {
      final products = _googleSubProducts(googleProductId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base'),
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-winback'),
      ]);
      final plugin = _FakeInAppPurchase(
        product: products.first,
        products: products,
        onBuy: (_) => _purchased(googleProductId),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchaseWithOffer(
        productId: googleProductId,
        offer: googleOffer,
        appAccountToken: 'token-uuid',
      );

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final captured = plugin.capturedParam;
      expect(captured, isA<GooglePlayPurchaseParam>());
      captured as GooglePlayPurchaseParam;
      expect(captured.offerToken, 'tok-winback');
      expect(captured.applicationUserName, 'token-uuid');
    });

    test('fails closed (offerUnavailable) on an ambiguous offer, never buying',
        () async {
      final products = _googleSubProducts(googleProductId, const [
        (basePlanId: 'monthly', offerId: 'winback_3mo', token: 'tok-m'),
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-a'),
      ]);
      final plugin =
          _FakeInAppPurchase(product: products.first, products: products);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchaseWithOffer(
        productId: googleProductId,
        offer: googleOffer,
        appAccountToken: 'token-uuid',
      );

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(plugin.buyCalled, isFalse,
          reason: 'never buy when the offer cannot be resolved');
    });

    test('fails closed when the requested offer is absent, never buying',
        () async {
      final products = _googleSubProducts(googleProductId, const [
        (basePlanId: 'annual', offerId: 'something_else', token: 'tok-o'),
      ]);
      final plugin =
          _FakeInAppPurchase(product: products.first, products: products);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchaseWithOffer(
        productId: googleProductId,
        offer: googleOffer,
        appAccountToken: 'token-uuid',
      );

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(plugin.buyCalled, isFalse);
    });

    test('a Google offer on an Apple platform fails closed without buying',
        () async {
      final products = _googleSubProducts(googleProductId, const [
        (basePlanId: 'annual', offerId: 'winback_3mo', token: 'tok-w'),
      ]);
      final plugin =
          _FakeInAppPurchase(product: products.first, products: products);
      final gateway = InAppPurchaseGateway(plugin: plugin);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final outcome = await gateway.purchaseWithOffer(
        productId: googleProductId,
        offer: googleOffer,
        appAccountToken: 'token-uuid',
      );

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.offerUnavailable);
      expect(plugin.buyCalled, isFalse,
          reason: 'a Google offer cannot ride an Apple store');
    });
  });

  group('InAppPurchaseGateway.purchase (refactor regression guard)', () {
    test('a plain purchase carries no promotional offer and succeeds',
        () async {
      final plugin = _FakeInAppPurchase(
        product: product,
        onBuy: (_) => _purchased(product.id),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(product.id);

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final captured = plugin.capturedParam;
      // The plain path must NOT build an offer-bearing param.
      expect(captured, isNot(isA<Sk2PurchaseParam>()));
    });

    test('returns unavailable when the store is unavailable', () async {
      final plugin = _FakeInAppPurchase(product: product, available: false);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(product.id);

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.unavailable);
    });
  });

  group('InAppPurchaseGateway.purchase (Google base-plan selection)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    const productId = 'com.example.app.pro_sub';

    test(
        'fails closed on a multi-base-plan sub with no basePlanId, never buying',
        () async {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: null, token: 'tok-annual'),
      ]);
      final plugin =
          _FakeInAppPurchase(product: products.first, products: products);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(productId);

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.basePlanSelectionRequired);
      expect(plugin.buyCalled, isFalse,
          reason: 'never silently buy products.first on an ambiguous sub');
    });

    test('buys the chosen base plan at its standard price', () async {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
        (basePlanId: 'annual', offerId: null, token: 'tok-annual'),
      ]);
      final plugin = _FakeInAppPurchase(
        product: products.first,
        products: products,
        onBuy: (_) => _purchased(productId),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(productId, basePlanId: 'annual');

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      final captured = plugin.capturedParam;
      expect(captured, isA<GooglePlayPurchaseParam>());
      expect((captured! as GooglePlayPurchaseParam).offerToken, 'tok-annual');
    });

    test('a single base plan with offers buys the base plan, not the offer',
        () async {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base'),
        (basePlanId: 'monthly', offerId: 'intro_1mo', token: 'tok-intro'),
      ]);
      final plugin = _FakeInAppPurchase(
        product: products.first,
        products: products,
        onBuy: (_) => _purchased(productId),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(productId);

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect((plugin.capturedParam! as GooglePlayPurchaseParam).offerToken,
          'tok-base',
          reason: 'a plain purchase never silently applies a discount');
    });

    test('a single base plan with no offers buys it (no behavior change)',
        () async {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-base'),
      ]);
      final plugin = _FakeInAppPurchase(
        product: products.first,
        products: products,
        onBuy: (_) => _purchased(productId),
      );
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(productId);

      expect(outcome, isA<PurchaseOutcomeSucceeded>());
      expect((plugin.capturedParam! as GooglePlayPurchaseParam).offerToken,
          'tok-base');
    });

    test('fails closed when the requested basePlanId is absent, never buying',
        () async {
      final products = _googleSubProducts(productId, const [
        (basePlanId: 'monthly', offerId: null, token: 'tok-monthly'),
      ]);
      final plugin =
          _FakeInAppPurchase(product: products.first, products: products);
      final gateway = InAppPurchaseGateway(plugin: plugin);

      final outcome = await gateway.purchase(productId, basePlanId: 'annual');

      expect((outcome as PurchaseOutcomeFailed).errorCode,
          RestageBillingErrorCodes.basePlanSelectionRequired);
      expect(plugin.buyCalled, isFalse);
    });
  });
}

/// Builds the per-offer `GooglePlayProductDetails` list a subscription query
/// returns on Android: one entry per base-plan/offer, each carrying its own
/// `offerToken` (offerIdToken). A null [offers] `offerId` models a plain base
/// plan (Play sets `offerId` only for a discounted offer).
List<ProductDetails> _googleSubProducts(
  String productId,
  List<({String basePlanId, String? offerId, String token})> offers,
) {
  final wrapper = ProductDetailsWrapper(
    description: 'desc',
    name: 'name',
    productId: productId,
    productType: ProductType.subs,
    title: 'title',
    subscriptionOfferDetails: <SubscriptionOfferDetailsWrapper>[
      for (final o in offers)
        SubscriptionOfferDetailsWrapper(
          basePlanId: o.basePlanId,
          offerId: o.offerId,
          offerTags: const <String>[],
          offerIdToken: o.token,
          pricingPhases: const <PricingPhaseWrapper>[
            PricingPhaseWrapper(
              billingCycleCount: 0,
              billingPeriod: 'P1M',
              formattedPrice: r'$9.99',
              priceAmountMicros: 9990000,
              priceCurrencyCode: 'USD',
              recurrenceMode: RecurrenceMode.infiniteRecurring,
            ),
          ],
        ),
    ],
  );
  return GooglePlayProductDetails.fromProductDetails(wrapper);
}

PurchaseDetails _purchased(String productId) => PurchaseDetails(
      purchaseID: 'txn-1',
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server-receipt',
        source: 'app_store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = false;

/// Minimal [InAppPurchase] fake that drives the gateway's purchase flow:
/// reports availability, returns [product] from a query, captures the param
/// passed to `buyNonConsumable`, and (via [onBuy]) either yields a purchase
/// detail to push on the stream or throws.
class _FakeInAppPurchase implements InAppPurchase {
  _FakeInAppPurchase({
    required this.product,
    this.products,
    this.available = true,
    this.onBuy,
  });

  final ProductDetails product;

  /// The full product list a query returns; defaults to `[product]`. A
  /// subscription query on Android returns one entry per base-plan/offer, so the
  /// offer path needs the whole list (not just `.first`).
  final List<ProductDetails>? products;
  final bool available;
  final FutureOr<PurchaseDetails?> Function(PurchaseParam param)? onBuy;

  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  PurchaseParam? capturedParam;
  bool buyCalled = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    final all = products ?? <ProductDetails>[product];
    final found = all.where((p) => ids.contains(p.id)).toList(growable: false);
    return ProductDetailsResponse(
      productDetails: found,
      notFoundIDs: found.isEmpty ? ids.toList() : <String>[],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalled = true;
    capturedParam = purchaseParam;
    final detail = await onBuy?.call(purchaseParam);
    if (detail != null) {
      scheduleMicrotask(() => _controller.add(<PurchaseDetails>[detail]));
    }
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
