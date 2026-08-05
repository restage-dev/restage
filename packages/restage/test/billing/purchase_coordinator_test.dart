import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:restage/restage.dart' hide InAppPurchaseGateway;
import 'package:restage/src/billing/in_app_purchase_gateway.dart';
import 'package:restage/src/billing/purchase_attribution.dart';
import 'package:restage/src/billing/purchase_platform_adapter.dart';
import 'package:restage/src/billing/purchase_token_digest.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CreatePurchaseIntentRequest,
        CreatePurchaseIntentResponse,
        EntitlementSummary,
        EntitlementSyncRequest,
        AcceptedStoreEvidence,
        AppleAcceptedStoreEvidence,
        AttributionDisposition,
        GoogleAcceptedStoreEvidence,
        IntentBoundOfferSignatureRequest,
        OfferSignatureResponse,
        OfferSignatureScheme,
        PurchaseIntentDisposition,
        ReportTransactionRequest,
        ReportTransactionResponse;
import 'package:shared_preferences/shared_preferences.dart';

const _anonymousToken = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const _productId = 'com.example.pro.monthly';
const _otherProductId = 'com.example.pro.yearly';
const _product = RestageProduct(
  id: _productId,
  slot: 'primary',
  entitlement: 'pro',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'restage.anonymous_app_user_token': _anonymousToken,
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    Restage.debugReset();
    debugDefaultTargetPlatformOverride = null;
  });

  test('intent is durably committed before store UI and stamped exactly',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    plugin.emitPurchasedOnBuy = true;
    final adapters = <PurchasePlatformAdapter>[];
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => adapters;
    final rpc = _IntentRpcClient(blockIntent: true);

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    final purchase = Restage.purchaseProduct(_productId);
    await _turn();

    expect(rpc.intentRequests, hasLength(1));
    expect(plugin.buyCalled, isFalse,
        reason: 'the intent response has not committed yet');
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    expect(rpc.intentRequests.single.store, 'appStore');
    expect(rpc.intentRequests.single.appAnonymousToken, _anonymousToken);
    expect(rpc.intentRequests.single.storeProductId, _productId);
    expect(rpc.intentRequests.single.basePlanId, isNull);
    expect(rpc.intentRequests.single.offerId, isNull);
    expect(
      intentId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    rpc.releaseIntent();
    final outcome = await purchase;
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(Restage.currentEntitlements, isEmpty,
        reason: 'an accepted empty authoritative set grants no access');
    expect(plugin.capturedParam?.applicationUserName, intentId);
    expect(plugin.completeCalls, 1,
        reason: 'the correlated accepted report authorizes finish');
  });

  test('Apple offer mint follows intent commit and uses the same immutable id',
      () async {
    final order = <String>[];
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: (param) {
        order.add('buy');
        return _purchasedForParam(param);
      },
    );
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final rpc = _IntentRpcClient(order: order);

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    final outcome = await Restage.purchaseProduct(
      _productId,
      offerId: 'winback',
    );

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(order, ['intent', 'mint', 'buy']);
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    expect(rpc.intentRequests.single.offerId, 'winback');
    expect(rpc.mintRequests.single.purchaseIntentId, intentId);
    final param = plugin.capturedParam as Sk2PurchaseParam;
    expect(param.applicationUserName, intentId);
    expect(param.promotionalOffer?.offerId, 'winback');
  });

  test('Google purchase stamps the exact intent as obfuscatedAccountId',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onBuy: _purchasedForParam,
    );
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final rpc = _IntentRpcClient();

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    final outcome = await Restage.purchaseProduct(
      _productId,
      basePlanId: 'monthly',
    );

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    expect(rpc.intentRequests.single.store, 'playStore');
    expect(rpc.intentRequests.single.basePlanId, 'monthly');
    final param = plugin.capturedParam as GooglePlayPurchaseParam;
    expect(param.applicationUserName, intentId);
    expect(param.offerToken, 'base-monthly');
  });

  test('Google sole base plan is frozen into intent before launch', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final googleProducts = _googleProducts(_productId);
    final order = <String>[];
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onQuery: (ids, _) {
        order.add('query');
        return ProductDetailsResponse(
          productDetails: googleProducts,
          notFoundIDs: const [],
        );
      },
      onBuy: (param) {
        order.add('buy');
        return _purchasedForParam(param);
      },
    );
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final rpc = _IntentRpcClient(order: order);

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    final outcome = await Restage.purchaseProduct(_productId);

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(order, ['query', 'intent', 'buy']);
    expect(plugin.productQueryCalls, 1);
    expect(rpc.intentRequests.single.basePlanId, 'monthly');
    final param = plugin.capturedParam as GooglePlayPurchaseParam;
    expect(param.productDetails, same(googleProducts.single));
    expect(param.offerToken, 'base-monthly');
  });

  test('authoritative active response grants through reconciliation', () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    plugin.emitPurchasedOnBuy = true;
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final rpc = _IntentRpcClient(
      reportEntitlements: [_activeEntitlement()],
    );

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    expect(await Restage.purchaseProduct(_productId),
        isA<PurchaseOutcomeSucceeded>());
    expect(
      Restage.currentEntitlements.map((entitlement) => entitlement.id),
      [_product.entitlement],
    );
  });

  test('reconfigure has one listener and invalidates a stale intent response',
      () async {
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final firstPlugin = _FakeInAppPurchase(product: _storeProduct());
    final firstRpc = _IntentRpcClient(blockIntent: true);
    Restage.configure(
      apiKey: 'rs_pk_first',
      baseUrl: 'https://first.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: firstPlugin),
    );
    Restage.debugRestageRpcClient = firstRpc;
    expect(firstPlugin.activeListeners, 1);

    final stalePurchase = Restage.purchaseProduct(_productId);
    await _turn();
    expect(firstRpc.intentRequests, hasLength(1));

    final secondPlugin = _FakeInAppPurchase(product: _storeProduct());
    Restage.configure(
      apiKey: 'rs_pk_second',
      baseUrl: 'https://second.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: secondPlugin),
    );
    Restage.debugRestageRpcClient = _IntentRpcClient();

    expect(firstPlugin.activeListeners, 0);
    expect(secondPlugin.activeListeners, 1);
    firstRpc.releaseIntent();
    final outcome = await stalePurchase;
    expect(
      (outcome as PurchaseOutcomeFailed).errorCode,
      RestageBillingErrorCodes.buyFailed,
    );
    expect(firstPlugin.buyCalled, isFalse);
  });

  test(
      'reconfigure during pre-intent product preparation never commits or buys',
      () async {
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final firstPlugin = _FakeInAppPurchase(
      product: _storeProduct(),
      blockProductQuery: true,
    );
    final firstRpc = _IntentRpcClient();
    Restage.configure(
      apiKey: 'rs_pk_first',
      baseUrl: 'https://first.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: firstPlugin),
    );
    Restage.debugRestageRpcClient = firstRpc;

    final stalePurchase = Restage.purchaseProduct(_productId);
    await firstPlugin.productQueryStarted;
    expect(firstRpc.intentRequests, isEmpty);

    Restage.configure(
      apiKey: 'rs_pk_second',
      baseUrl: 'https://second.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(
        plugin: _FakeInAppPurchase(product: _storeProduct()),
      ),
    );
    firstPlugin.releaseProductQuery();

    final outcome = await stalePurchase;
    expect(outcome, isA<PurchaseOutcomeFailed>());
    expect(firstRpc.intentRequests, isEmpty);
    expect(firstPlugin.buyCalls, 0);
  });

  test('concurrent same-product calls reserve one store launch', () async {
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      blockProductQuery: true,
      onBuy: _purchasedForParam,
    );
    final rpc = _IntentRpcClient();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    final winner = Restage.purchaseProduct(_productId);
    await plugin.productQueryStarted;
    final loser = await Restage.purchaseProduct(_productId);

    expect(loser, isA<PurchaseOutcomeFailed>());
    expect(plugin.buyCalls, 0);
    plugin.releaseProductQuery();

    expect(await winner, isA<PurchaseOutcomeSucceeded>());
    expect(plugin.buyCalls, 1);
    expect(plugin.capturedParam?.applicationUserName,
        rpc.intentRequests.first.purchaseIntentId);
  });

  test('StoreKit 2 cancellation without a hint resolves and clears attempt',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final firstPurchase = coordinator.purchase(_productId);
    await _flush();
    expect(plugin.buyCalls, 1);

    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: null,
      ),
    );
    final firstOutcome = await firstPurchase;
    expect(firstOutcome, isA<PurchaseOutcomeCancelled>());

    final secondPurchase = coordinator.purchase(_productId);
    await _flush();
    expect(plugin.buyCalls, 2,
        reason: 'the cancelled attempt must release the product');
    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: null,
      ),
    );

    expect(await secondPurchase, isA<PurchaseOutcomeCancelled>());
    coordinator.cancel();
  });

  test('unconfigured product fails before durable work or store UI', () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
      knownSubscriptionProductIds: const {'com.example.configured'},
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);

    expect(outcome, isA<PurchaseOutcomeFailed>());
    final failure = outcome as PurchaseOutcomeFailed;
    expect(failure.errorCode, RestageBillingErrorCodes.buyFailed);
    expect(failure.message, 'This product is not configured for purchase.');
    expect(rpc.intentRequests, isEmpty);
    expect(plugin.productQueryCalls, 0);
    expect(plugin.buyCalls, 0);
    coordinator.cancel();
  });

  test('StoreKit 2 pending without an intent hint resolves the attempt',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final purchase = coordinator.purchase(_productId);
    await _flush();
    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.pending,
        purchaseIntentId: null,
      ),
    );

    final outcome = await purchase;
    expect(outcome, isA<PurchaseOutcomePending>());
    expect((outcome as PurchaseOutcomePending).productId, _productId);

    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: null,
      ),
    );
    await _turn();
    coordinator.cancel();
  });

  test('Android bare cancellation resolves with the attempted product id',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final products = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: products.single,
      products: products,
    );
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      store: 'playStore',
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final purchase = coordinator.purchase(
      _productId,
      basePlanId: 'monthly',
    );
    await _flush();
    expect(plugin.buyCalls, 1);

    plugin.emit(_bareStatusUpdate(PurchaseStatus.canceled));
    final outcome = await purchase;

    expect(outcome, isA<PurchaseOutcomeCancelled>());
    expect((outcome as PurchaseOutcomeCancelled).productId, _productId);
    coordinator.cancel();
  });

  test('bare cancellation refuses to choose between multiple attempts',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      products: [
        _storeProduct(),
        _storeProduct(productId: _otherProductId),
      ],
    );
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
      knownSubscriptionProductIds: const {_productId, _otherProductId},
    );
    coordinator.start();

    var firstCompleted = false;
    var secondCompleted = false;
    final firstPurchase = coordinator.purchase(_productId);
    final secondPurchase = coordinator.purchase(_otherProductId);
    unawaited(firstPurchase.then((_) => firstCompleted = true));
    unawaited(secondPurchase.then((_) => secondCompleted = true));
    await _flush();
    expect(plugin.buyCalls, 2);

    plugin.emit(_bareStatusUpdate(PurchaseStatus.canceled));
    await _turn();

    expect(firstCompleted, isFalse);
    expect(secondCompleted, isFalse);
    coordinator.cancel();
    await Future.wait([firstPurchase, secondPurchase]);
  });

  test('cancellation with a foreign intent hint refuses the active attempt',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
    );
    coordinator.start();

    var completed = false;
    final purchase = coordinator.purchase(_productId);
    unawaited(purchase.then((_) => completed = true));
    await _flush();
    const foreignIntentId = '11111111-2222-4333-8444-555555555555';
    expect(rpc.intentRequests.single.purchaseIntentId, isNot(foreignIntentId));

    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: foreignIntentId,
      ),
    );
    await _turn();
    expect(completed, isFalse);

    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: null,
      ),
    );
    expect(await purchase, isA<PurchaseOutcomeCancelled>());
    coordinator.cancel();
  });

  test('bare cancellation with a foreign hint refuses the sole attempt',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    var completed = false;
    final purchase = coordinator.purchase(_productId);
    unawaited(purchase.then((_) => completed = true));
    await _flush();

    plugin.emit(
      _sk2StatusUpdate(
        '',
        status: PurchaseStatus.canceled,
        purchaseIntentId: '11111111-2222-4333-8444-555555555555',
      ),
    );
    await _turn();
    expect(completed, isFalse);

    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.canceled,
        purchaseIntentId: null,
      ),
    );
    expect(await purchase, isA<PurchaseOutcomeCancelled>());
    coordinator.cancel();
  });

  test('store error without an intent hint fails the active attempt', () async {
    const errorCode = 'store_declined';
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final purchase = coordinator.purchase(_productId);
    await _flush();
    plugin.emit(
      _sk2StatusUpdate(
        _productId,
        status: PurchaseStatus.error,
        purchaseIntentId: null,
        error: IAPError(
          source: 'store',
          code: errorCode,
          message: 'The purchase failed.',
        ),
      ),
    );
    final outcome = await purchase;

    expect(outcome, isA<PurchaseOutcomeFailed>());
    expect((outcome as PurchaseOutcomeFailed).errorCode, errorCode);
    coordinator.cancel();
  });

  test('StoreKit 1 success without an intent hint resolves the active attempt',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeKit1Product(),
      onBuy: (param) => _storeKit1Purchased(
        param.productDetails.id,
        purchaseIntentId: null,
        transactionId: 'storekit-1-transaction',
      ),
    );
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect((outcome as PurchaseOutcomeSucceeded).transactionId,
        'storekit-1-transaction');
    expect(rpc.reportRequests.single.purchaseIntentId, isNull);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('StoreKit 1 normalization reports the receipt and purchase intent',
      () async {
    const transactionId = 'storekit-1-transaction';
    const verificationData = 'storekit-1-receipt-secret';
    String? submittedIntentId;
    final plugin = _FakeInAppPurchase(
      product: _storeKit1Product(),
      onBuy: (param) {
        submittedIntentId = param.applicationUserName;
        return _storeKit1Purchased(
          param.productDetails.id,
          purchaseIntentId: submittedIntentId,
          transactionId: transactionId,
          verificationData: verificationData,
        );
      },
    );
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect((outcome as PurchaseOutcomeSucceeded).transactionId, transactionId);
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    final report = rpc.reportRequests.single;
    expect(submittedIntentId, intentId);
    expect(plugin.capturedParam?.applicationUserName, intentId);
    expect(report.storeTransactionId, transactionId);
    expect(report.storeVerificationData, verificationData);
    expect(report.purchaseIntentId, intentId);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('StoreKit 1 restored evidence carries its original transaction id',
      () async {
    final seen = <StoreTransactionEvidence>[];
    final plugin = _FakeInAppPurchase(product: _storeKit1Product());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      processor: (evidence, _) async => seen.add(evidence),
    );
    coordinator.start();

    plugin.emit(
      _storeKit1Restored(
        _productId,
        purchaseIntentId: null,
        transactionId: 'storekit-1-restored-transaction',
        originalTransactionId: 'storekit-1-original-transaction',
      ),
    );
    await _flush();

    expect(seen, hasLength(1));
    expect(seen.single.source, StoreTransactionSource.purchaseStream);
    expect(seen.single.store, 'appStore');
    expect(seen.single.transactionId, 'storekit-1-restored-transaction');
    expect(
      seen.single.originalTransactionId,
      'storekit-1-original-transaction',
    );
    coordinator.cancel();
  });

  test('StoreKit 1 empty transaction or receipt produces no report or finish',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeKit1Product());
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
    );
    coordinator.start();

    plugin.emit(
      _storeKit1Purchased(
        _productId,
        purchaseIntentId: null,
        transactionId: '',
      ),
    );
    plugin.emit(
      _storeKit1Purchased(
        _productId,
        purchaseIntentId: null,
        transactionId: 'storekit-1-empty-receipt',
        verificationData: '',
      ),
    );
    await _flush();

    expect(rpc.reportRequests, isEmpty);
    expect(plugin.completeCalls, 0);
    coordinator.cancel();
  });

  test('StoreKit 1 cancellation resolves the active attempt', () async {
    final plugin = _FakeInAppPurchase(product: _storeKit1Product());
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final purchase = coordinator.purchase(_productId);
    await _flush();
    plugin.emit(
      _storeKit1Cancelled(
        _productId,
        purchaseIntentId: null,
      ),
    );

    expect(await purchase, isA<PurchaseOutcomeCancelled>());
    coordinator.cancel();
  });

  test('successful evidence with a foreign intent hint refuses the attempt',
      () async {
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final rpc = _IntentRpcClient();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = rpc;

    var resolved = false;
    final purchase = Restage.purchaseProduct(_productId);
    unawaited(purchase.then((_) => resolved = true));
    await _turn();
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    expect(plugin.buyCalls, 1);

    plugin.emit(
      _sk2Purchased(
        _productId,
        purchaseIntentId: '11111111-2222-4333-8444-555555555555',
        transactionId: 'old-transaction',
      ),
    );
    await _turn();

    expect(
      rpc.reportRequests.map((request) => request.storeTransactionId),
      ['old-transaction'],
    );
    expect(resolved, isFalse);

    plugin.emit(
      _sk2Purchased(
        _productId,
        purchaseIntentId: intentId,
        transactionId: 'matching-transaction',
      ),
    );
    final outcome = await purchase;
    await _turn();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(
      rpc.reportRequests.map((request) => request.storeTransactionId),
      ['old-transaction', 'matching-transaction'],
    );
  });

  test('installed purchaseWithOffer creates and remints a fresh intent',
      () async {
    const callerToken = '11111111-2222-4333-8444-555555555555';
    const callerOffer = AppleSignedOffer(
      offerId: 'winback',
      keyIdentifier: 'CALLER_KEY',
      nonce: '22222222-3333-4444-8555-666666666666',
      timestampMs: 99,
      signatureBase64: 'caller-signature',
    );
    final order = <String>[];
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: (param) {
        order.add('buy');
        return _purchasedForParam(param);
      },
    );
    final gateway = InAppPurchaseGateway(plugin: plugin);
    final rpc = _IntentRpcClient(order: order);
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [_product],
      billingGateway: gateway,
    );
    Restage.debugRestageRpcClient = rpc;

    final outcome = await gateway.purchaseWithOffer(
      productId: _productId,
      offer: callerOffer,
      appAccountToken: callerToken,
    );

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(order, ['intent', 'mint', 'buy']);
    final intentId = rpc.intentRequests.single.purchaseIntentId;
    expect(intentId, isNot(callerToken));
    expect(rpc.intentRequests.single.offerId, callerOffer.offerId);
    expect(rpc.mintRequests.single.purchaseIntentId, intentId);
    final param = plugin.capturedParam as Sk2PurchaseParam;
    expect(param.applicationUserName, intentId);
    expect(param.promotionalOffer?.offerId, callerOffer.offerId);
    expect(param.promotionalOffer?.signature.keyID, 'KEY123');
    expect(param.promotionalOffer?.signature.signature, 'signature');
  });

  test('default recovery adapters are installed on Apple and Android',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);

    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      PurchaseCoordinator.debugPlatformAdapterFactory = null;
      logs.clear();
      final plugin = _FakeInAppPurchase(product: _storeProduct());
      final coordinator = PurchaseCoordinator(
        gateway: InAppPurchaseGateway(plugin: plugin),
        knownSubscriptionProductIds: const {_productId},
        anonymousTokenProvider: () async => _anonymousToken,
        rpcClientProvider: () => null,
        store: platform == TargetPlatform.iOS ? 'appStore' : 'playStore',
        epoch: 1,
        isCurrentEpoch: (_) => true,
      );
      addTearDown(coordinator.cancel);

      coordinator.start();
      await _flush();

      expect(
        logs,
        contains('[restage] native purchase recovery was unavailable'),
        reason: 'platform: $platform',
      );
      coordinator.cancel();
    }
  });

  test('failed recovery logs, skips inline retry, and does not block peers',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final failing = _FakeAdapter(
      evidence: const [],
      onResume: true,
      failure: StateError('recovery unavailable'),
    );
    var finishCount = 0;
    final succeeding = _FakeAdapter(
      evidence: [
        _evidence(
          store: 'appStore',
          source: StoreTransactionSource.storeKit2Unfinished,
          transactionId: 'apple-after-failed-recovery',
          verificationData: 'receipt-secret',
          finish: () async => finishCount += 1,
        ),
      ],
      onResume: true,
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [failing, succeeding],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(61),
    );
    addTearDown(coordinator.cancel);

    coordinator.start();
    await _flush();

    expect(failing.drainCount, 1);
    expect(succeeding.drainCount, 1);
    expect(rpc.requests, hasLength(1));
    expect(
      rpc.requests.single.storeTransactionId,
      'apple-after-failed-recovery',
    );
    expect(finishCount, 1);
    expect(
      logs,
      contains('[restage] native purchase recovery was unavailable'),
    );

    coordinator.onAppResumed();
    await _flush();

    expect(failing.drainCount, 2);
    expect(succeeding.drainCount, 2);
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);
  });

  test('WidgetsBinding resume lifecycle drains the installed coordinator',
      () async {
    final adapter = _FakeAdapter(evidence: const [], onResume: true);
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => [adapter];
    final plugin = _FakeInAppPurchase(product: _storeProduct());

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      analyticsEnabled: false,
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    Restage.debugRestageRpcClient = _IntentRpcClient();
    await _flush();
    expect(adapter.drainCount, 1);

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await _flush();

    expect(adapter.drainCount, 2);
  });

  test('StoreKit 2 unfinished transactions drain on app resume', () async {
    expect(StoreKit2UnfinishedPurchaseAdapter().drainOnResume, isTrue);

    var enumerationCount = 0;
    final finished = <int>[];
    final adapter = StoreKit2UnfinishedPurchaseAdapter(
      enumerate: () async {
        enumerationCount += 1;
        if (enumerationCount == 1) return const <SK2Transaction>[];
        return <SK2Transaction>[
          SK2Transaction(
            id: '42',
            originalId: '7',
            productId: _productId,
            purchaseDate: '0',
            appAccountToken: '11111111-2222-4333-8444-555555555555',
            receiptData: 'apple-jws-secret',
            jsonRepresentation: '{"transaction":"redacted"}',
          ),
        ];
      },
      finish: (id) async => finished.add(id),
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [adapter],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(60),
    );

    coordinator.start();
    await _flush();
    expect(enumerationCount, 1);
    expect(rpc.requests, isEmpty);
    expect(finished, isEmpty);

    coordinator.onAppResumed();
    await _flush();

    expect(enumerationCount, 2);
    expect(rpc.requests, hasLength(1));
    expect(rpc.requests.single.storeTransactionId, '42');
    expect(rpc.requests.single.purchaseIntentId,
        '11111111-2222-4333-8444-555555555555');
    expect(finished, [42]);
    coordinator.cancel();
  });

  test('Google owned purchases drain without configured-product filtering',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    var queryCount = 0;
    final adapter = GoogleOwnedPurchaseAdapter(
      plugin: plugin,
      query: () async {
        queryCount += 1;
        return QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            _googlePurchase(
              productId: _productId,
              orderId: 'GPA.known',
              token: 'known-token-secret',
            ),
            _googlePurchase(
              productId: 'com.example.unrelated',
              orderId: 'GPA.unrelated',
              token: 'unrelated-token-secret',
            ),
          ],
        );
      },
    );
    final seen = <StoreTransactionEvidence>[];
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [adapter],
      processor: (evidence, _) async => seen.add(evidence),
    );

    coordinator.start();
    await _turn();
    expect(queryCount, 1);
    expect(
      seen.map((e) => e.productId),
      [_productId, 'com.example.unrelated'],
    );
    expect(seen.first.evidenceKey, 'playStore/order/GPA.known');
    expect(seen.last.evidenceKey, 'playStore/order/GPA.unrelated');

    coordinator.onAppResumed();
    await _turn();
    expect(queryCount, 2);
    expect(
      seen.map((e) => e.productId),
      [
        _productId,
        'com.example.unrelated',
        _productId,
        'com.example.unrelated',
      ],
    );
    coordinator.cancel();
  });

  test('stale epoch blocks report follow-up, finish, identity, and outcome',
      () async {
    final reportGate = Completer<String>();
    final processorStarted = Completer<void>();
    var finishCount = 0;
    var identityCount = 0;
    var outcomeCount = 0;
    var processorCount = 0;
    var current = true;
    final evidence = _evidence(
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final adapter = _FakeAdapter(evidence: [evidence, evidence]);
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [adapter],
      isCurrentEpoch: (_) => current,
      processor: (item, context) async {
        processorCount += 1;
        if (!processorStarted.isCompleted) processorStarted.complete();
        final accepted = await context.report(() => reportGate.future);
        if (accepted == null) return;
        await context.finish(item);
        await context.repairIdentity(() async => identityCount += 1);
        context.emitOutcome(() => outcomeCount += 1);
      },
    );

    coordinator.start();
    await processorStarted.future;
    expect(adapter.drainCount, 1);
    current = false;
    coordinator.cancel();
    reportGate.complete('accepted');
    await _turn();

    expect(finishCount, 0);
    expect(identityCount, 0);
    expect(outcomeCount, 0);
    expect(processorCount, 1,
        reason: 'duplicate evidence is coalesced while processing is active');
  });

  test('secret evidence is neither persisted nor included in diagnostics',
      () async {
    const secret = 'raw-receipt-jws-purchase-token';
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(verificationData: secret),
          ],
        ),
      ],
      processor: (_, __) async => throw StateError(secret),
    );

    coordinator.start();
    await _turn();
    final prefs = await SharedPreferences.getInstance();

    expect(logs.whereType<String>().join('\n'), isNot(contains(secret)));
    expect(prefs.getKeys(), {'restage.anonymous_app_user_token'});
    expect(
        prefs.getString('restage.anonymous_app_user_token'), _anonymousToken);
    coordinator.cancel();
  });

  test('configured gateway without intent service retains direct purchasing',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: _purchasedForParam,
    );
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );

    final outcome = await Restage.purchaseProduct(_productId);

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(plugin.buyCalled, isTrue);
  });

  test('lazy bundled gateway without intent service stays uncoordinated', () {
    var adapterFactories = 0;
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) {
      adapterFactories += 1;
      return const [];
    };

    Restage.configure(
      apiKey: 'rs_pk_rendering',
      products: const [_product],
    );

    expect(Restage.billingGateway, isA<InAppPurchaseGateway>());
    expect(adapterFactories, 0);
  });

  test('durable recovery installs with an empty product registry', () async {
    var finishCount = 0;
    final adapter = _FakeAdapter(
      evidence: [
        _evidence(
          verificationData: 'receipt-secret',
          store: 'appStore',
          source: StoreTransactionSource.storeKit2Unfinished,
          transactionId: 'recovered-transaction',
          purchaseIntentId: null,
          finish: () async => finishCount += 1,
        ),
      ],
    );
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, productIds) {
      expect(productIds, isEmpty);
      return [adapter];
    };
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final rpc = _IntentRpcClient();

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://billing.example.com',
      products: const [],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );
    // Must follow configure: configure rebuilds the RPC client for the new
    // base URL, so a client installed beforehand is discarded.
    Restage.debugRestageRpcClient = rpc;
    await _flush();

    expect(adapter.drainCount, 1);
    expect(rpc.reportRequests, hasLength(1));
    expect(rpc.reportRequests.single.storeProductId, _productId);
    expect(finishCount, 1);
  });

  test('report failure replays with fresh ids and never finishes early',
      () async {
    var accepts = false;
    var nextId = 1;
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => accepts ? _acceptedResponse(request) : null,
    );
    final evidence = _evidence(
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true)
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(nextId++),
      maxReportAttempts: 2,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(
        rpc.requests.map((request) => request.reportId).toSet(), hasLength(2));
    expect(finishCount, 0);

    accepts = true;
    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(3));
    expect(
        rpc.requests.map((request) => request.reportId).toSet(), hasLength(3));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('report timeout consumes an attempt and the purchase still resolves',
      () async {
    final neverReported = Completer<ReportTransactionResponse?>();
    final rpc = _IntentRpcClient(
      onReport: (request, attempt) =>
          attempt == 0 ? neverReported.future : _acceptedResponse(request),
    );
    final products = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: products.single,
      products: products,
      onBuy: _purchasedForParam,
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: const [],
      rpcClient: rpc,
      maxReportAttempts: 2,
      reportAttemptTimeout: Duration.zero,
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(rpc.reportRequests, hasLength(2));
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('hung report releases the evidence barrier for a later drain', () async {
    final neverReported = Completer<ReportTransactionResponse?>();
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (_, __) => neverReported.future,
    );
    final evidence = _evidence(
      transactionId: 'GPA.report-timeout',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
      maxReportAttempts: 1,
      reportAttemptTimeout: Duration.zero,
    );

    coordinator.start();
    await _flush();
    expect(rpc.requests, hasLength(1));

    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(finishCount, 0);
    coordinator.cancel();
  });

  test('hung anonymous-token read releases the barrier for a later drain',
      () async {
    final neverRead = Completer<String?>();
    var tokenReads = 0;
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      // The server returns its own authoritative anonymous token, so an
      // acceptance still carries one even when this report could not read a
      // local token. The fixture would otherwise derive it from the request and
      // build an `associated` acceptance with no token, which the response type
      // rejects outright.
      onReport: (request, _) => _acceptedResponse(
        request,
        recoveredAppAnonymousToken: _anonymousToken,
      ),
    );
    final evidence = _evidence(
      transactionId: 'GPA.token-read-timeout',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
      anonymousTokenProvider: () {
        tokenReads += 1;
        return tokenReads == 1
            ? neverRead.future
            : Future<String?>.value(_anonymousToken);
      },
      maxReportAttempts: 1,
      retryDelayPolicy: (_) => Duration.zero,
      delay: (_) async {},
      externalAttemptTimeout: const Duration(milliseconds: 1),
    );

    coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(rpc.requests.single.appAnonymousToken, isNull);
    expect(finishCount, 1);

    coordinator.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(rpc.requests.last.appAnonymousToken, _anonymousToken);
    expect(finishCount, 2);
    coordinator.cancel();
  });

  test('report timeout is independent from the short external timeout',
      () async {
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _acceptedResponse(request);
      },
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              transactionId: 'GPA.slow-report',
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      maxReportAttempts: 1,
      externalAttemptTimeout: const Duration(milliseconds: 1),
      reportAttemptTimeout: const Duration(seconds: 1),
    );

    coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('default report budget accepts on the sixth attempt', () async {
    var nextId = 1;
    var finishCount = 0;
    final retryIndexes = <int>[];
    final delays = <Duration>[];
    final rpc = _ReportRpcClient(
      onReport: (request, attempt) =>
          attempt < 5 ? null : _acceptedResponse(request),
    );
    final plugin = _googleSubscriptionPlugin();
    final coordinator = PurchaseCoordinator(
      gateway: InAppPurchaseGateway(plugin: plugin),
      knownSubscriptionProductIds: const {_productId},
      anonymousTokenProvider: () async => _anonymousToken,
      rpcClientProvider: () => rpc,
      store: 'playStore',
      epoch: 1,
      isCurrentEpoch: (_) => true,
      platformAdapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      reportIdGenerator: () => _reportId(nextId++),
      retryDelayPolicy: (retryIndex) {
        retryIndexes.add(retryIndex);
        return Duration.zero;
      },
      delay: (delay) async => delays.add(delay),
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(6));
    expect(retryIndexes, [0, 1, 2, 3, 4]);
    expect(delays, List<Duration>.filled(5, Duration.zero));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('lost accepted response retries idempotently with a new report id',
      () async {
    var nextId = 10;
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, attempt) =>
          attempt == 0 ? null : _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(nextId++),
      maxReportAttempts: 2,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(rpc.requests.first.reportId, isNot(rpc.requests.last.reportId));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('rejected report never finishes across drains; accepted empty can',
      () async {
    var rejectedFinishCount = 0;
    final rejectedRpc = _ReportRpcClient(
      onReport: (request, _) {
        final accepted = _acceptedResponse(request);
        return ReportTransactionResponse(
          accepted: false,
          reportId: request.reportId,
          evidence: accepted.evidence,
          attributionDisposition: AttributionDisposition.notProvided,
        );
      },
    );
    final rejectedEvidence = _evidence(
      verificationData: 'purchase-token-secret',
      finish: () async => rejectedFinishCount += 1,
    );
    final rejectedAdapter = _FakeAdapter(
      evidence: [rejectedEvidence],
      onResume: true,
    );
    final rejected = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [rejectedAdapter],
      rpcClient: rejectedRpc,
      reportIdGenerator: () => _reportId(20),
      maxReportAttempts: 1,
    );
    rejected.start();
    await _flush();
    expect(rejectedFinishCount, 0);
    rejected.onAppResumed();
    await _flush();
    expect(rejectedRpc.requests, hasLength(2));
    expect(rejectedFinishCount, 0);
    rejected.cancel();

    var acceptedFinishCount = 0;
    final reconciled = <List<EntitlementSummary>>[];
    final acceptedRpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        entitlements: const [],
      ),
    );
    final accepted = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async => acceptedFinishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: acceptedRpc,
      reportIdGenerator: () => _reportId(21),
      maxReportAttempts: 1,
      entitlementReconciler: reconciled.add,
    );
    accepted.start();
    await _flush();
    expect(acceptedFinishCount, 1);
    expect(reconciled, hasLength(1));
    expect(reconciled.single, isEmpty);
    accepted.cancel();
  });

  test('intent-stamped exact acceptances finish across dispositions', () async {
    for (final disposition in <PurchaseIntentDisposition?>[
      null,
      PurchaseIntentDisposition.unmatched,
      PurchaseIntentDisposition.notProvided,
      PurchaseIntentDisposition.associated,
      PurchaseIntentDisposition.alreadyAssociated,
    ]) {
      var finishCount = 0;
      final rpc = _ReportRpcClient(
        onReport: (request, _) => _acceptedResponse(
          request,
          purchaseIntentDisposition: disposition,
        ),
      );
      final coordinator = _coordinator(
        plugin: _FakeInAppPurchase(product: _storeProduct()),
        adapters: [
          _FakeAdapter(
            evidence: [
              _evidence(
                verificationData: 'receipt-secret',
                store: 'appStore',
                source: StoreTransactionSource.storeKit2Unfinished,
                finish: () => Future<void>.microtask(() {
                  finishCount += 1;
                }),
              ),
            ],
          ),
        ],
        rpcClient: rpc,
        reportIdGenerator: () => _reportId(22),
        maxReportAttempts: 1,
      );

      coordinator.start();
      await _flush();

      expect(rpc.requests.single.purchaseIntentId, isNotNull);
      expect(finishCount, 1, reason: 'disposition: $disposition');
      coordinator.cancel();
    }
  });

  test('report correlation and exact accepted evidence authorize finish',
      () async {
    for (final mismatch in <String>['reportId', 'transactionId']) {
      var finishCount = 0;
      final rpc = _ReportRpcClient(
        onReport: (request, _) => _acceptedResponse(
          request,
          responseReportId: mismatch == 'reportId' ? _reportId(99) : null,
          submittedTransactionId:
              mismatch == 'transactionId' ? 'other-transaction' : null,
        ),
      );
      final coordinator = _coordinator(
        plugin: _FakeInAppPurchase(product: _storeProduct()),
        adapters: [
          _FakeAdapter(
            evidence: [
              _evidence(
                verificationData: 'receipt-secret',
                store: 'appStore',
                source: StoreTransactionSource.storeKit2Unfinished,
                finish: () async => finishCount += 1,
              ),
            ],
          ),
        ],
        rpcClient: rpc,
        reportIdGenerator: () => _reportId(25),
        maxReportAttempts: 1,
      );

      coordinator.start();
      await _flush();

      expect(rpc.requests, hasLength(1));
      expect(finishCount, 0, reason: 'mismatch: $mismatch');
      coordinator.cancel();
    }
  });

  test('out-of-app evidence finishes after exact durable acceptance', () async {
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        purchaseIntentDisposition: PurchaseIntentDisposition.notProvided,
      ),
    );
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'receipt-secret',
              store: 'appStore',
              source: StoreTransactionSource.storeKit2Unfinished,
              purchaseIntentId: null,
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(23),
      maxReportAttempts: 1,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests.single.purchaseIntentId, isNull);
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('unconfigured purchased product is reported and finished', () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
      knownSubscriptionProductIds: const {'com.example.configured'},
    );
    coordinator.start();

    plugin.emit(
      _sk2Purchased(
        _productId,
        purchaseIntentId: null,
        transactionId: 'unconfigured-transaction',
      ),
    );
    await _flush();

    expect(rpc.reportRequests, hasLength(1));
    expect(rpc.reportRequests.single.storeProductId, _productId);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('accepted purchase outcome carries prepared price and currency',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: _purchasedForParam,
    );
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    final succeeded = outcome as PurchaseOutcomeSucceeded;
    expect(succeeded.priceMicros, 9990000);
    expect(succeeded.currency, 'USD');
    coordinator.cancel();
  });

  test('concurrent Google duplicates coalesce but sequential replay reports',
      () async {
    var nextReportId = 30;
    final reportStarted = Completer<void>();
    final reportGate = Completer<void>();
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) async {
        if (!reportStarted.isCompleted) reportStarted.complete();
        await reportGate.future;
        return _acceptedResponse(request);
      },
    );
    final evidence = _evidence(
      verificationData: 'purchase-token-secret',
      transactionId: 'GPA.duplicate',
      finish: () async => finishCount += 1,
    );
    final plugin = _googleSubscriptionPlugin();
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence, evidence], onResume: true),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(nextReportId++),
    );

    coordinator.start();
    await reportStarted.future;
    plugin.emit(
      _googlePurchase(
        productId: _productId,
        orderId: 'GPA.duplicate',
        token: 'purchase-token-secret',
      ),
    );
    await _turn();
    expect(rpc.requests, hasLength(1));

    reportGate.complete();
    await _flush();
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);

    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(finishCount, 2);
    coordinator.cancel();
  });

  test('sequential Google reports can advance the canonical accepted order',
      () async {
    var nextReportId = 31;
    var finishCount = 0;
    final acceptedOrderIds = <String>[];
    final rpc = _ReportRpcClient(
      onReport: (request, attempt) {
        final acceptedOrderId =
            attempt == 0 ? 'GPA.family..0' : 'GPA.family..1';
        acceptedOrderIds.add(acceptedOrderId);
        return _acceptedResponse(
          request,
          acceptedTransactionId: acceptedOrderId,
        );
      },
    );
    final evidence = _evidence(
      verificationData: 'purchase-token-secret',
      transactionId: 'GPA.family',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence, evidence], onResume: true),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(nextReportId++),
    );

    coordinator.start();
    await _flush();
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);

    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(acceptedOrderIds, ['GPA.family..0', 'GPA.family..1']);
    expect(finishCount, 2,
        reason: 'each correlated acceptance authorizes its own observation');
    coordinator.cancel();
  });

  test('finish throw retries in-run and Google replay reports again', () async {
    var nextReportId = 40;
    var finishCount = 0;
    var reconcileCount = 0;
    var syncCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final evidence = _evidence(
      verificationData: 'purchase-token-secret',
      finish: () async {
        finishCount += 1;
        if (finishCount <= 2) throw StateError('finish unavailable');
      },
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true)
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(nextReportId++),
      maxFinishAttempts: 2,
      entitlementReconciler: (_) => reconcileCount += 1,
      entitlementSync: () async => syncCount += 1,
    );

    coordinator.start();
    await _flush();
    expect(finishCount, 2);
    expect(rpc.requests, hasLength(1));
    expect((reconcileCount, syncCount), (1, 1));

    coordinator.onAppResumed();
    await _flush();
    expect(finishCount, 3);
    expect(rpc.requests, hasLength(2));
    expect((reconcileCount, syncCount), (2, 2));
    coordinator.cancel();
  });

  test('authoritative token repair precedes reconcile and detached sync',
      () async {
    const recovered = '11111111-2222-4333-8444-555555555555';
    final order = <String>[];
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        purchaseIntentDisposition: PurchaseIntentDisposition.associated,
        recoveredAppAnonymousToken: recovered,
      ),
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async {
                finishCount += 1;
                order.add('finish');
              },
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(50),
      authoritativeTokenReplacer: (token) async {
        expect(token, recovered);
        order.add('repair');
      },
      entitlementReconciler: (_) => order.add('reconcile'),
      entitlementSync: () async => order.add('sync'),
    );

    coordinator.start();
    await _flush();

    expect(order, ['repair', 'reconcile', 'sync', 'finish']);
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('hung identity repair releases the barrier for a later drain', () async {
    const recovered = '11111111-2222-4333-8444-555555555555';
    final neverRepaired = Completer<void>();
    var repairStarts = 0;
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        purchaseIntentDisposition: PurchaseIntentDisposition.associated,
        recoveredAppAnonymousToken: recovered,
      ),
    );
    final evidence = _evidence(
      transactionId: 'GPA.identity-repair-timeout',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
      authoritativeTokenReplacer: (token) {
        expect(token, recovered);
        repairStarts += 1;
        return neverRepaired.future;
      },
      externalAttemptTimeout: const Duration(milliseconds: 1),
    );

    coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(repairStarts, 1);
    expect(finishCount, 1);

    coordinator.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await _flush();

    expect(rpc.requests, hasLength(2));
    expect(repairStarts, 2);
    expect(finishCount, 2);
    coordinator.cancel();
  });

  test('never-completing entitlement sync cannot block outcome or finish',
      () async {
    final syncGate = Completer<void>();
    var syncStarts = 0;
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onBuy: _purchasedForParam,
    );
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: const [],
      rpcClient: rpc,
      entitlementSync: () {
        syncStarts += 1;
        return syncGate.future;
      },
    );
    coordinator.start();

    final outcome = await coordinator.purchase(
      _productId,
      basePlanId: 'monthly',
    );
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(rpc.reportRequests, hasLength(1));
    expect(plugin.completeCalls, 1);

    plugin.emit(
      _googlePurchase(
        productId: _productId,
        orderId: 'GPA.transaction-1',
        token: 'server-secret',
        obfuscatedAccountId: rpc.intentRequests.single.purchaseIntentId,
      ),
    );
    await _flush();

    expect(rpc.reportRequests, hasLength(2),
        reason: 'the first in-flight entry was released without the sync');
    expect(plugin.completeCalls, 2);
    expect(syncStarts, 2);
    coordinator.cancel();
  });

  test('exhausted finish budget releases the operation for a later drain',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final finishGate = Completer<void>();
    var finishStarts = 0;
    final evidence = _evidence(
      store: 'appStore',
      transactionId: 'apple-timeout',
      verificationData: 'receipt-secret',
      finish: () {
        finishStarts += 1;
        return finishGate.future;
      },
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(52),
      maxFinishAttempts: 3,
      externalAttemptTimeout: Duration.zero,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(
      finishStarts,
      1,
      reason: 'one run re-observes one native finish across its retry budget',
    );
    expect(
      logs,
      contains(
        '[restage] appStore transaction-keyed evidence remains unfinished '
        'after the finish retry budget was exhausted',
      ),
    );
    expect(
      logs.whereType<String>().join('\n'),
      isNot(contains('apple-timeout')),
    );
    expect(
      logs.whereType<String>().join('\n'),
      isNot(contains('receipt-secret')),
    );

    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(1),
        reason: 'Apple exact acceptance remains reusable for native replay');
    expect(
      finishStarts,
      2,
      reason: 'a later drain starts fresh after the exhausted operation',
    );
    expect(
      logs.where(
        (message) =>
            message ==
            '[restage] appStore transaction-keyed evidence remains unfinished '
                'after the finish retry budget was exhausted',
      ),
      hasLength(1),
    );
    coordinator.cancel();
  });

  test('cached Apple acceptance requires the same purchase intent on replay',
      () async {
    for (final replayIntentId in <String?>[
      null,
      '22222222-3333-4444-8555-666666666666',
    ]) {
      var initialFinishCount = 0;
      var replayFinishCount = 0;
      final evidence = <StoreTransactionEvidence>[
        _evidence(
          store: 'appStore',
          transactionId: 'apple-intent-replay',
          verificationData: 'receipt-secret',
          finish: () async {
            initialFinishCount += 1;
            throw StateError('finish failed');
          },
        ),
      ];
      final rpc = _ReportRpcClient(
        onReport: (request, _) => _acceptedResponse(request),
      );
      final coordinator = _coordinator(
        plugin: _FakeInAppPurchase(product: _storeProduct()),
        adapters: [
          _FakeAdapter(evidence: evidence, onResume: true),
        ],
        rpcClient: rpc,
        reportIdGenerator: () => _reportId(53),
        maxFinishAttempts: 1,
      );

      coordinator.start();
      await _flush();
      expect(rpc.requests, hasLength(1));
      expect(initialFinishCount, 1);

      evidence[0] = _evidence(
        store: 'appStore',
        transactionId: 'apple-intent-replay',
        verificationData: 'receipt-secret',
        purchaseIntentId: replayIntentId,
        finish: () async => replayFinishCount += 1,
      );
      coordinator.onAppResumed();
      await _flush();

      expect(rpc.requests, hasLength(1));
      expect(replayFinishCount, 0, reason: 'replay hint: $replayIntentId');
      coordinator.cancel();
    }
  });

  test('local token write failure does not undo backend-authorized completion',
      () async {
    const recovered = '11111111-2222-4333-8444-555555555555';
    var finishCount = 0;
    var reconcileCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        purchaseIntentDisposition: PurchaseIntentDisposition.alreadyAssociated,
        recoveredAppAnonymousToken: recovered,
      ),
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(51),
      authoritativeTokenReplacer: (_) async =>
          throw StateError('preference write failed'),
      entitlementReconciler: (_) => reconcileCount += 1,
    );

    coordinator.start();
    await _flush();

    expect(reconcileCount, 1);
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('purchase attribution scope remains visible after an async gap',
      () async {
    const attribution = PurchaseAttributionSnapshot(
      paywallId: 'served-paywall',
      paywallPublishedVersion: 7,
      experimentId: 'experiment-a',
      experimentVariantId: 'arm-b',
      experimentEpoch: 3,
      offerId: 'winback',
    );

    expect(PurchaseAttributionScope.current, isNull);
    final observed = await PurchaseAttributionScope.run(
      attribution,
      () async {
        await _turn();
        return PurchaseAttributionScope.current;
      },
    );

    expect(observed, same(attribution));
    expect(PurchaseAttributionScope.current, isNull);
  });

  test('pending exact intent later emits one attributed global success',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: (param) => _sk2StatusUpdate(
        param.productDetails.id,
        status: PurchaseStatus.pending,
        purchaseIntentId: param.applicationUserName,
      ),
    );
    final rpc = _IntentRpcClient();
    final delayed = <PurchaseOutcomeSucceeded>[];
    final delayedAttribution = <PurchaseAttributionSnapshot>[];
    var reconcileCount = 0;
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
      entitlementReconciler: (_) => reconcileCount += 1,
      entitlementSync: () async {},
      delayedSuccessEmitter: (outcome, attribution) {
        delayed.add(outcome);
        delayedAttribution.add(attribution);
      },
    );
    coordinator.start();
    const attribution = PurchaseAttributionSnapshot(
      paywallId: 'served-paywall',
      paywallPublishedVersion: 7,
      experimentId: 'experiment-a',
      experimentVariantId: 'arm-b',
      experimentEpoch: 3,
      offerId: 'winback',
    );

    final purchase = PurchaseAttributionScope.run(
      attribution,
      () => coordinator.purchaseProduct(_productId, offerId: 'winback'),
    );
    final pending = await purchase;
    expect(pending, isA<PurchaseOutcomePending>());

    final intent = rpc.intentRequests.single;
    expect(intent.paywallId, 'served-paywall');
    expect(intent.paywallPublishedVersion, 7);
    expect(intent.offerId, 'winback');
    expect(intent.paywallVariantSlug, isNull);
    expect(intent.experimentId, 'experiment-a');
    expect(intent.experimentVariantId, 'arm-b');
    expect(intent.experimentEpoch, 3);
    final purchased = _sk2Purchased(
      _productId,
      purchaseIntentId: intent.purchaseIntentId,
      transactionId: 'delayed-transaction',
    );

    plugin.emit(purchased);
    await _flush();
    plugin.emit(purchased);
    await _flush();

    expect(delayed, hasLength(1));
    expect(delayed.single.transactionId, 'delayed-transaction');
    expect(delayedAttribution.single.paywallId, 'served-paywall');
    expect(delayedAttribution.single.offerId, 'winback');
    expect(reconcileCount, 1);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('restore uses the global listener and the common processor', () async {
    final restored = _sk2Restored(
      _productId,
      purchaseIntentId: null,
      transactionId: 'restored-transaction',
    );
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      restoreDetail: restored,
    );
    final rpc = _IntentRpcClient();
    var reconcileCount = 0;
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: const [],
      rpcClient: rpc,
      entitlementReconciler: (_) => reconcileCount += 1,
      entitlementSync: () async {},
    );
    coordinator.start();
    expect(plugin.activeListeners, 1);

    final outcome = await coordinator.restore();
    await _flush();

    expect(outcome, isA<RestoreOutcomeSucceeded>());
    expect(
      (outcome as RestoreOutcomeSucceeded).restoredProductIds,
      [_productId],
    );
    expect(plugin.activeListeners, 1);
    expect(rpc.reportRequests, hasLength(1));
    expect(
      plugin.completeCalls,
      0,
      reason: 'StoreKit 2 restored stream records are already non-pending',
    );
    expect(reconcileCount, 1);
    coordinator.cancel();
  });

  test('Google subscription gate rejects prepaid and accepts renewing plans',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final prepaidProducts = _googleProductsWithPricingPhases(
      _productId,
      const <PricingPhaseWrapper>[
        PricingPhaseWrapper(
          billingCycleCount: 1,
          billingPeriod: 'P1M',
          formattedPrice: r'$9.99',
          priceAmountMicros: 9990000,
          priceCurrencyCode: 'USD',
          recurrenceMode: RecurrenceMode.nonRecurring,
        ),
      ],
    );
    final prepaidPlugin = _FakeInAppPurchase(
      product: prepaidProducts.single,
      products: prepaidProducts,
    );
    final prepaidRpc = _IntentRpcClient();
    final prepaidCoordinator = _coordinator(
      plugin: prepaidPlugin,
      store: 'playStore',
      adapters: const [],
      rpcClient: prepaidRpc,
    );
    prepaidCoordinator.start();

    final prepaidOutcome = await prepaidCoordinator.purchase(_productId);

    expect(prepaidOutcome, isA<PurchaseOutcomeFailed>());
    final prepaidFailure = prepaidOutcome as PurchaseOutcomeFailed;
    expect(prepaidFailure.errorCode, RestageBillingErrorCodes.buyFailed);
    expect(
      prepaidFailure.message,
      'Only auto-renewing subscriptions are supported.',
    );
    expect(prepaidRpc.intentRequests, isEmpty);
    expect(prepaidPlugin.buyCalled, isFalse);
    prepaidCoordinator.cancel();

    final renewingProducts = _googleProductsWithPricingPhases(
      _productId,
      const <PricingPhaseWrapper>[
        PricingPhaseWrapper(
          billingCycleCount: 1,
          billingPeriod: 'P1W',
          formattedPrice: r'$0.00',
          priceAmountMicros: 0,
          priceCurrencyCode: 'USD',
          recurrenceMode: RecurrenceMode.nonRecurring,
        ),
        PricingPhaseWrapper(
          billingCycleCount: 0,
          billingPeriod: 'P1M',
          formattedPrice: r'$9.99',
          priceAmountMicros: 9990000,
          priceCurrencyCode: 'USD',
          recurrenceMode: RecurrenceMode.infiniteRecurring,
        ),
      ],
    );
    final renewingPlugin = _FakeInAppPurchase(
      product: renewingProducts.single,
      products: renewingProducts,
      onBuy: _purchasedForParam,
    );
    final renewingCoordinator = _coordinator(
      plugin: renewingPlugin,
      store: 'playStore',
      adapters: const [],
      rpcClient: _IntentRpcClient(),
    );
    renewingCoordinator.start();

    final renewingOutcome = await renewingCoordinator.purchase(_productId);

    expect(renewingOutcome, isA<PurchaseOutcomeSucceeded>());
    expect(renewingPlugin.buyCalled, isTrue);
    renewingCoordinator.cancel();
  });

  test('configured unsupported recovery logs the unrecovered transaction',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final products = _unsupportedGoogleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: products.single,
      products: products,
    );
    final rpc = _IntentRpcClient();
    var finishCount = 0;
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              transactionId: 'GPA.configured-unsupported',
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
    );

    coordinator.start();
    await _flush();

    expect(plugin.productQueryCalls, 1);
    expect(rpc.reportRequests, isEmpty);
    expect(finishCount, 0);
    expect(
      logs,
      contains(
        '[restage] configured product $_productId has an unsupported '
        'subscription shape in playStore; leaving its transaction untouched',
      ),
    );
    coordinator.cancel();
  });

  test('unconfigured unsupported recovery logs that it was left untouched',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final products = _unsupportedGoogleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: products.single,
      products: products,
    );
    final rpc = _IntentRpcClient();
    var finishCount = 0;
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              transactionId: 'GPA.unconfigured-unsupported',
              verificationData: 'purchase-token-secret',
              finish: () async => finishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      knownSubscriptionProductIds: const {},
    );

    coordinator.start();
    await _flush();

    expect(plugin.productQueryCalls, 1);
    expect(rpc.reportRequests, isEmpty);
    expect(finishCount, 0);
    expect(
      logs,
      contains('[restage] leaving unsupported product $_productId untouched'),
    );
    coordinator.cancel();
  });

  test('unsupported recovery is terminal and logged only once', () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final products = _unsupportedGoogleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: products.single,
      products: products,
    );
    final rpc = _IntentRpcClient();
    var finishCount = 0;
    final evidence = _evidence(
      transactionId: 'GPA.terminal-unsupported',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
    );

    coordinator.start();
    await _flush();
    coordinator.onAppResumed();
    await _flush();

    const diagnostic =
        '[restage] configured product $_productId has an unsupported '
        'subscription shape in playStore; leaving its transaction untouched';
    expect(plugin.productQueryCalls, 1);
    expect(logs.where((message) => message == diagnostic), hasLength(1));
    expect(rpc.reportRequests, isEmpty);
    expect(finishCount, 0);
    coordinator.cancel();
  });

  test('supported sibling rescues terminal evidence for the same product',
      () async {
    final unsupportedProducts = _unsupportedGoogleProducts(_productId);
    final supportedProducts = _googleProducts(_productId);
    final supportedQuery = Completer<ProductDetailsResponse>();
    final plugin = _FakeInAppPurchase(
      product: supportedProducts.single,
      onQuery: (ids, attempt) {
        if (attempt == 1) {
          return ProductDetailsResponse(
            productDetails: unsupportedProducts,
            notFoundIDs: const [],
          );
        }
        return supportedQuery.future;
      },
    );
    var unsupportedFinishCount = 0;
    var supportedFinishCount = 0;
    final unsupportedEvidence = _evidence(
      transactionId: 'GPA.sibling-unsupported',
      verificationData: 'unsupported-purchase-token-secret',
      finish: () async => unsupportedFinishCount += 1,
    );
    final supportedEvidence = _evidence(
      transactionId: 'GPA.sibling-supported',
      verificationData: 'supported-purchase-token-secret',
      finish: () async => supportedFinishCount += 1,
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [unsupportedEvidence, supportedEvidence],
          onResume: true,
        ),
      ],
      rpcClient: rpc,
    );

    coordinator.start();
    await _flush();

    expect(plugin.productQueryCalls, 2);
    expect(rpc.requests, isEmpty);
    expect(unsupportedFinishCount, 0);

    supportedQuery.complete(
      ProductDetailsResponse(
        productDetails: supportedProducts,
        notFoundIDs: const [],
      ),
    );
    await _flush();

    expect(
      rpc.requests.map((request) => request.storeTransactionId),
      ['GPA.sibling-supported'],
    );
    expect(supportedFinishCount, 1);

    coordinator.onAppResumed();
    await _flush();

    expect(plugin.productQueryCalls, 2);
    expect(
      rpc.requests.where(
        (request) => request.storeTransactionId == 'GPA.sibling-unsupported',
      ),
      hasLength(1),
    );
    expect(unsupportedFinishCount, 1);
    coordinator.cancel();
  });

  test('configured Google in-app product is rejected before durable work',
      () async {
    final inAppProduct = _googleInAppProduct(_productId);
    final plugin = _FakeInAppPurchase(product: inAppProduct);
    final rpc = _IntentRpcClient();
    var finishCount = 0;
    final evidence = _evidence(
      transactionId: 'GPA.in-app',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence]),
      ],
      rpcClient: rpc,
    );
    coordinator.start();
    await _flush();

    final outcome = await coordinator.purchase(_productId);
    await _flush();

    expect(outcome, isA<PurchaseOutcomeFailed>());
    expect(rpc.intentRequests, isEmpty);
    expect(plugin.buyCalls, 0);
    expect(rpc.reportRequests, isEmpty);
    expect(finishCount, 0);
    coordinator.cancel();
  });

  test('direct uninstalled gateway retains legacy Google in-app behavior',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final inAppProduct = _googleInAppProduct(_productId);
    final plugin = _FakeInAppPurchase(
      product: inAppProduct,
      onBuy: (_) => _googlePurchase(
        productId: _productId,
        orderId: 'GPA.legacy-in-app',
        token: 'legacy-token-secret',
      ),
    );
    final gateway = InAppPurchaseGateway(plugin: plugin);

    final outcome = await gateway.purchase(_productId);

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect(plugin.buyCalls, 1);
    expect(plugin.completeCalls, 1);
  });

  test('metadata not-found response leaves recovered evidence retryable',
      () async {
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onQuery: (ids, attempt) {
        if (attempt == 1) {
          return ProductDetailsResponse(
            productDetails: const [],
            notFoundIDs: const [_productId],
          );
        }
        return ProductDetailsResponse(
          productDetails: googleProducts,
          notFoundIDs: const [],
        );
      },
    );
    var finishCount = 0;
    final evidence = _evidence(
      transactionId: 'GPA.retryable-metadata',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
    );

    coordinator.start();
    await _flush();
    expect(rpc.requests, isEmpty);
    expect(finishCount, 0);

    coordinator.onAppResumed();
    await _flush();

    expect(plugin.productQueryCalls, 2);
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('metadata query timeout leaves recovered evidence retryable', () async {
    final neverQueried = Completer<ProductDetailsResponse>();
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onQuery: (ids, attempt) => attempt == 1
          ? neverQueried.future
          : ProductDetailsResponse(
              productDetails: googleProducts,
              notFoundIDs: const [],
            ),
    );
    var finishCount = 0;
    final evidence = _evidence(
      transactionId: 'GPA.retryable-metadata-timeout',
      verificationData: 'purchase-token-secret',
      finish: () async => finishCount += 1,
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
      externalAttemptTimeout: Duration.zero,
    );

    coordinator.start();
    await _flush();
    expect(rpc.requests, isEmpty);
    expect(finishCount, 0);

    coordinator.onAppResumed();
    await _flush();

    expect(plugin.productQueryCalls, 2);
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('unrecognized product subtype leaves recovered evidence retryable',
      () async {
    final unrecognizedProduct = ProductDetails(
      id: _productId,
      title: 'Pro',
      description: 'Pro subscription',
      price: r'$9.99',
      rawPrice: 9.99,
      currencyCode: 'USD',
    );
    final recognizedProduct = _storeProduct();
    final plugin = _FakeInAppPurchase(
      product: unrecognizedProduct,
      onQuery: (ids, attempt) => ProductDetailsResponse(
        productDetails: [
          attempt == 1 ? unrecognizedProduct : recognizedProduct,
        ],
        notFoundIDs: const [],
      ),
    );
    var finishCount = 0;
    final evidence = _evidence(
      store: 'appStore',
      source: StoreTransactionSource.storeKit2Unfinished,
      transactionId: 'apple-unrecognized-product',
      verificationData: 'receipt-secret',
      finish: () async => finishCount += 1,
    );
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: plugin,
      adapters: [
        _FakeAdapter(evidence: [evidence], onResume: true),
      ],
      rpcClient: rpc,
    );

    coordinator.start();
    await _flush();

    expect(plugin.productQueryCalls, 1);
    expect(rpc.requests, isEmpty);
    expect(finishCount, 0);

    coordinator.onAppResumed();
    await _flush();

    expect(plugin.productQueryCalls, 2);
    expect(rpc.requests, hasLength(1));
    expect(finishCount, 1);
    coordinator.cancel();
  });

  test('Google promotional purchase drains, reports, and finishes once',
      () async {
    const purchaseToken = 'promotional-purchase-token-secret';
    final plugin = _googleSubscriptionPlugin();
    final rpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(request),
    );
    final adapter = GoogleOwnedPurchaseAdapter(
      plugin: plugin,
      query: () async => QueryPurchaseDetailsResponse(
        pastPurchases: [
          _googlePurchase(
            productId: _productId,
            orderId: '',
            token: purchaseToken,
          ),
        ],
      ),
    );
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: [adapter],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(70),
      maxReportAttempts: 1,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(rpc.requests.single.storeTransactionId, isNull);
    expect(rpc.requests.single.storeVerificationData, purchaseToken);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('Google purchase stream preserves an absent order identity', () async {
    const purchaseToken = 'stream-promotional-purchase-token-secret';
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onBuy: (param) => _googlePurchase(
        productId: param.productDetails.id,
        orderId: '',
        token: purchaseToken,
        obfuscatedAccountId: param.applicationUserName,
      ),
    );
    final rpc = _IntentRpcClient();
    final coordinator = _coordinator(
      plugin: plugin,
      store: 'playStore',
      adapters: const [],
      rpcClient: rpc,
    );
    coordinator.start();

    final outcome = await coordinator.purchase(_productId);
    await _flush();

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    expect((outcome as PurchaseOutcomeSucceeded).transactionId, isNull);
    expect(rpc.reportRequests.single.storeTransactionId, isNull);
    expect(rpc.reportRequests.single.storeVerificationData, purchaseToken);
    expect(plugin.completeCalls, 1);
    coordinator.cancel();
  });

  test('Google order-bearing purchase requires its exact submitted-order echo',
      () async {
    const purchaseToken = 'order-bearing-purchase-token-secret';
    const submittedOrderId = 'GPA.exact-order';
    for (final echoedOrderId in <String>[
      submittedOrderId,
      'GPA.other-order',
    ]) {
      var finishCount = 0;
      final rpc = _ReportRpcClient(
        onReport: (request, _) => ReportTransactionResponse(
          accepted: true,
          reportId: request.reportId,
          evidence: GoogleAcceptedStoreEvidence(
            submittedOrderId: echoedOrderId,
            acceptedOrderId: echoedOrderId,
            orderLineageId: echoedOrderId.split('..').first,
            acceptedPurchaseTokenDigest:
                googlePurchaseTokenDigest(request.storeVerificationData),
          ),
          attributionDisposition: AttributionDisposition.notProvided,
        ),
      );
      final coordinator = _coordinator(
        plugin: _googleSubscriptionPlugin(),
        store: 'playStore',
        adapters: [
          _FakeAdapter(
            evidence: [
              _evidence(
                verificationData: purchaseToken,
                transactionId: submittedOrderId,
                finish: () => Future<void>.microtask(() {
                  finishCount += 1;
                }),
              ),
            ],
          ),
        ],
        rpcClient: rpc,
        reportIdGenerator: () => _reportId(71),
        maxReportAttempts: 1,
      );

      coordinator.start();
      await _flush();

      expect(rpc.requests, hasLength(1));
      expect(
        finishCount,
        echoedOrderId == submittedOrderId ? 1 : 0,
        reason: 'echoed order id: $echoedOrderId',
      );
      coordinator.cancel();
    }
  });

  test('Google acceptance with a different token digest does not finish',
      () async {
    const purchaseToken = 'submitted-purchase-token-secret';
    const orderId = 'GPA.digest-check';
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => ReportTransactionResponse(
        accepted: true,
        reportId: request.reportId,
        evidence: GoogleAcceptedStoreEvidence(
          submittedOrderId: orderId,
          acceptedOrderId: orderId,
          orderLineageId: orderId,
          acceptedPurchaseTokenDigest:
              googlePurchaseTokenDigest('other-purchase-token-secret'),
        ),
        attributionDisposition: AttributionDisposition.notProvided,
      ),
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: purchaseToken,
              transactionId: orderId,
              finish: () => Future<void>.microtask(() {
                finishCount += 1;
              }),
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(72),
      maxReportAttempts: 1,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(finishCount, 0);
    coordinator.cancel();
  });

  test('Google acceptance with an unexpected order triple does not finish',
      () async {
    const purchaseToken = 'orderless-purchase-token-secret';
    const unexpectedOrderId = 'GPA.unexpected-order';
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, _) => ReportTransactionResponse(
        accepted: true,
        reportId: request.reportId,
        evidence: GoogleAcceptedStoreEvidence(
          submittedOrderId: unexpectedOrderId,
          acceptedOrderId: unexpectedOrderId,
          orderLineageId: unexpectedOrderId,
          acceptedPurchaseTokenDigest:
              googlePurchaseTokenDigest(request.storeVerificationData),
        ),
        attributionDisposition: AttributionDisposition.notProvided,
      ),
    );
    final coordinator = _coordinator(
      plugin: _googleSubscriptionPlugin(),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: purchaseToken,
              transactionId: null,
              finish: () => Future<void>.microtask(() {
                finishCount += 1;
              }),
            ),
          ],
        ),
      ],
      rpcClient: rpc,
      reportIdGenerator: () => _reportId(73),
      maxReportAttempts: 1,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests.single.storeTransactionId, isNull);
    expect(finishCount, 0);
    coordinator.cancel();
  });

  test('Google purchase-token digest matches the SHA-256 contract', () {
    const vectors = <(String, String)>[
      (
        'abc',
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ),
      (
        '',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      ),
      (
        ' abc ',
        '3eaf1941003943dfaa935adecffcaaa217e290def6fb0181141ced6c9daabaad',
      ),
      (
        'ABC',
        'b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78',
      ),
      (
        'é',
        '4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c',
      ),
      (
        'mIxEd Case Token',
        '6b4a4ade53d2370e01519489246b242a66f9ad790b69420b5d836cd62981edc1',
      ),
    ];

    for (final (input, expected) in vectors) {
      final digest = googlePurchaseTokenDigest(input);

      expect(digest, expected, reason: 'input: <$input>');
      expect(digest, hasLength(64));
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });

  test('Google pending purchase is skipped while purchased evidence drains',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final adapter = GoogleOwnedPurchaseAdapter(
      plugin: plugin,
      query: () async => QueryPurchaseDetailsResponse(
        pastPurchases: [
          _googlePurchase(
            productId: _productId,
            orderId: '',
            token: 'pending-token-secret',
            purchaseState: PurchaseStateWrapper.pending,
          ),
          _googlePurchase(
            productId: _productId,
            orderId: 'GPA.purchased',
            token: 'purchased-token-secret',
          ),
        ],
      ),
    );

    final evidence = await adapter.drain();

    expect(evidence, hasLength(1));
    expect(evidence.single.transactionId, 'GPA.purchased');
    expect(evidence.single.state, StoreTransactionState.purchased);
  });
}

PurchaseCoordinator _coordinator({
  required _FakeInAppPurchase plugin,
  required List<PurchasePlatformAdapter> adapters,
  Future<void> Function(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  )? processor,
  RestageRpcClient? rpcClient,
  String store = 'appStore',
  bool Function(int epoch)? isCurrentEpoch,
  String Function()? reportIdGenerator,
  Future<String?> Function()? anonymousTokenProvider,
  Future<void> Function(String token)? authoritativeTokenReplacer,
  void Function(List<EntitlementSummary> entitlements)? entitlementReconciler,
  Future<void> Function()? entitlementSync,
  void Function(
    PurchaseOutcomeSucceeded outcome,
    PurchaseAttributionSnapshot attribution,
  )? delayedSuccessEmitter,
  Duration Function(int retryIndex)? retryDelayPolicy,
  Future<void> Function(Duration delay)? delay,
  int maxReportAttempts = 3,
  int maxFinishAttempts = 3,
  Duration externalAttemptTimeout = const Duration(seconds: 15),
  Duration reportAttemptTimeout = const Duration(seconds: 75),
  Duration restoreTimeout = Duration.zero,
  Set<String> knownSubscriptionProductIds = const {_productId},
}) {
  return PurchaseCoordinator(
    gateway: InAppPurchaseGateway(
      plugin: plugin,
      restoreTimeout: restoreTimeout,
    ),
    knownSubscriptionProductIds: knownSubscriptionProductIds,
    anonymousTokenProvider:
        anonymousTokenProvider ?? () async => _anonymousToken,
    rpcClientProvider: () => rpcClient,
    store: store,
    epoch: 1,
    isCurrentEpoch: isCurrentEpoch ?? (_) => true,
    platformAdapters: adapters,
    evidenceProcessor: processor,
    reportIdGenerator: reportIdGenerator,
    authoritativeTokenReplacer: authoritativeTokenReplacer,
    entitlementReconciler: entitlementReconciler,
    entitlementSync: entitlementSync,
    delayedSuccessEmitter: delayedSuccessEmitter,
    retryDelayPolicy: retryDelayPolicy ?? (_) => Duration.zero,
    delay: delay ?? (_) async {},
    maxReportAttempts: maxReportAttempts,
    maxFinishAttempts: maxFinishAttempts,
    externalAttemptTimeout: externalAttemptTimeout,
    reportAttemptTimeout: reportAttemptTimeout,
  );
}

final class _IntentRpcClient extends RestageRpcClient {
  _IntentRpcClient({
    this.blockIntent = false,
    this.order,
    this.reportEntitlements = const [],
    this.onReport,
  }) : super(
          baseUrl: 'https://billing.example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', 500)),
        );

  final bool blockIntent;
  final List<String>? order;
  final List<EntitlementSummary> reportEntitlements;
  final FutureOr<ReportTransactionResponse?> Function(
    ReportTransactionRequest request,
    int attempt,
  )? onReport;
  final Completer<void> _intentGate = Completer<void>();
  final List<CreatePurchaseIntentRequest> intentRequests = [];
  final List<IntentBoundOfferSignatureRequest> mintRequests = [];
  final List<ReportTransactionRequest> reportRequests = [];

  void releaseIntent() {
    if (!_intentGate.isCompleted) _intentGate.complete();
  }

  @override
  Future<CreatePurchaseIntentResponse?> createPurchaseIntent(
    CreatePurchaseIntentRequest request,
  ) async {
    intentRequests.add(request);
    order?.add('intent');
    if (blockIntent) await _intentGate.future;
    return CreatePurchaseIntentResponse(
      purchaseIntentId: request.purchaseIntentId,
      created: true,
    );
  }

  @override
  Future<OfferSignatureResponse?> mintIntentBoundOfferSignature(
    IntentBoundOfferSignatureRequest request,
  ) async {
    mintRequests.add(request);
    order?.add('mint');
    return const OfferSignatureResponse(
      scheme: OfferSignatureScheme.legacy,
      keyIdentifier: 'KEY123',
      nonce: '11111111-2222-4333-8444-555555555555',
      timestampMs: 1,
      signatureBase64: 'signature',
    );
  }

  @override
  Future<ReportTransactionResponse?> reportTransaction(
    ReportTransactionRequest request,
  ) {
    final attempt = reportRequests.length;
    reportRequests.add(request);
    final report = onReport;
    return Future<ReportTransactionResponse?>.microtask(
      () => report == null
          ? _acceptedResponse(request, entitlements: reportEntitlements)
          : report(request, attempt),
    );
  }

  @override
  Future<List<EntitlementSummary>?> syncEntitlements(
    EntitlementSyncRequest request,
  ) async =>
      reportEntitlements;
}

final class _ReportRpcClient extends RestageRpcClient {
  _ReportRpcClient({required this.onReport})
      : super(
          baseUrl: 'https://billing.example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', 500)),
        );

  final FutureOr<ReportTransactionResponse?> Function(
    ReportTransactionRequest request,
    int attempt,
  ) onReport;
  final List<ReportTransactionRequest> requests = [];

  @override
  Future<ReportTransactionResponse?> reportTransaction(
    ReportTransactionRequest request,
  ) {
    final attempt = requests.length;
    requests.add(request);
    return Future<ReportTransactionResponse?>.microtask(
      () => onReport(request, attempt),
    );
  }
}

final class _FakeAdapter implements PurchasePlatformAdapter {
  _FakeAdapter({
    required this.evidence,
    this.onResume = false,
    this.failure,
  });

  final List<StoreTransactionEvidence> evidence;
  final bool onResume;
  final Object? failure;
  int drainCount = 0;

  @override
  bool get drainOnConfigure => true;

  @override
  bool get drainOnResume => onResume;

  @override
  Future<List<StoreTransactionEvidence>> drain() async {
    drainCount += 1;
    if (failure != null) throw failure!;
    return evidence;
  }
}

final class _FakeInAppPurchase implements InAppPurchase {
  _FakeInAppPurchase({
    required this.product,
    this.products,
    this.onBuy,
    this.onQuery,
    this.blockProductQuery = false,
    this.restoreDetail,
  }) {
    _controller = StreamController<List<PurchaseDetails>>.broadcast(
      onListen: () => activeListeners += 1,
      onCancel: () => activeListeners -= 1,
    );
  }

  final ProductDetails product;
  final List<ProductDetails>? products;
  final FutureOr<PurchaseDetails?> Function(PurchaseParam param)? onBuy;
  final FutureOr<ProductDetailsResponse> Function(Set<String> ids, int attempt)?
      onQuery;
  final bool blockProductQuery;
  final PurchaseDetails? restoreDetail;
  late final StreamController<List<PurchaseDetails>> _controller;
  final Completer<void> _productQueryStarted = Completer<void>();
  final Completer<void> _productQueryGate = Completer<void>();

  bool buyCalled = false;
  bool emitPurchasedOnBuy = false;
  int buyCalls = 0;
  int productQueryCalls = 0;
  int activeListeners = 0;
  int completeCalls = 0;
  PurchaseParam? capturedParam;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    productQueryCalls += 1;
    if (!_productQueryStarted.isCompleted) _productQueryStarted.complete();
    if (blockProductQuery) await _productQueryGate.future;
    final query = onQuery;
    if (query != null) return query(ids, productQueryCalls);
    final all = products ?? <ProductDetails>[product];
    final found = all.where((item) => ids.contains(item.id)).toList();
    return ProductDetailsResponse(
      productDetails: found,
      notFoundIDs: found.isEmpty ? ids.toList() : const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalled = true;
    buyCalls += 1;
    capturedParam = purchaseParam;
    final detail = emitPurchasedOnBuy
        ? _purchasedForParam(purchaseParam)
        : await onBuy?.call(purchaseParam);
    if (detail != null) {
      scheduleMicrotask(() => emit(detail));
    }
    return true;
  }

  Future<void> get productQueryStarted => _productQueryStarted.future;

  void releaseProductQuery() {
    if (!_productQueryGate.isCompleted) _productQueryGate.complete();
  }

  void emit(PurchaseDetails purchase) {
    _controller.add(<PurchaseDetails>[purchase]);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) {
    return Future<void>.microtask(() {
      completeCalls += 1;
    });
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final detail = restoreDetail;
    if (detail != null) scheduleMicrotask(() => emit(detail));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProductDetails _storeProduct({String productId = _productId}) =>
    AppStoreProduct2Details(
      id: productId,
      title: 'Pro',
      description: 'Pro subscription',
      price: r'$9.99',
      rawPrice: 9.99,
      currencyCode: 'USD',
      currencySymbol: r'$',
      sk2Product: SK2Product(
        id: productId,
        displayName: 'Pro',
        displayPrice: r'$9.99',
        description: 'Pro subscription',
        price: 9.99,
        type: SK2ProductType.autoRenewable,
        priceLocale: SK2PriceLocale(
          currencyCode: 'USD',
          currencySymbol: r'$',
        ),
      ),
    );

ProductDetails _storeKit1Product({String productId = _productId}) =>
    AppStoreProductDetails(
      id: productId,
      title: 'Pro',
      description: 'Pro subscription',
      price: r'$9.99',
      rawPrice: 9.99,
      currencyCode: 'USD',
      currencySymbol: r'$',
      skProduct: SKProductWrapper(
        productIdentifier: productId,
        localizedTitle: 'Pro',
        localizedDescription: 'Pro subscription',
        priceLocale: SKPriceLocaleWrapper(
          currencyCode: 'USD',
          currencySymbol: r'$',
          countryCode: 'US',
        ),
        price: '9.99',
        subscriptionPeriod: SKProductSubscriptionPeriodWrapper(
          numberOfUnits: 1,
          unit: SKSubscriptionPeriodUnit.month,
        ),
      ),
    );

PurchaseDetails _bareStatusUpdate(PurchaseStatus status) => PurchaseDetails(
      purchaseID: '',
      productID: '',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'store',
      ),
      transactionDate: null,
      status: status,
    );

ProductDetails _googleInAppProduct(String productId) {
  const offer = OneTimePurchaseOfferDetailsWrapper(
    formattedPrice: r'$1.99',
    priceAmountMicros: 1990000,
    priceCurrencyCode: 'USD',
  );
  return GooglePlayProductDetails.fromProductDetails(
    ProductDetailsWrapper(
      description: 'One-time unlock',
      name: 'Unlock',
      oneTimePurchaseOfferDetails: offer,
      oneTimePurchaseOfferDetailsList: const [offer],
      productId: productId,
      productType: ProductType.inapp,
      title: 'Unlock',
    ),
  ).single;
}

List<ProductDetails> _googleProducts(String productId) {
  return _googleProductsWithPricingPhases(
    productId,
    const <PricingPhaseWrapper>[
      PricingPhaseWrapper(
        billingCycleCount: 0,
        billingPeriod: 'P1M',
        formattedPrice: r'$9.99',
        priceAmountMicros: 9990000,
        priceCurrencyCode: 'USD',
        recurrenceMode: RecurrenceMode.infiniteRecurring,
      ),
    ],
  );
}

_FakeInAppPurchase _googleSubscriptionPlugin() {
  final products = _googleProducts(_productId);
  return _FakeInAppPurchase(
    product: products.single,
    products: products,
  );
}

List<ProductDetails> _unsupportedGoogleProducts(String productId) {
  return _googleProductsWithPricingPhases(
    productId,
    const <PricingPhaseWrapper>[
      PricingPhaseWrapper(
        billingCycleCount: 1,
        billingPeriod: 'P1M',
        formattedPrice: r'$9.99',
        priceAmountMicros: 9990000,
        priceCurrencyCode: 'USD',
        recurrenceMode: RecurrenceMode.nonRecurring,
      ),
    ],
  );
}

List<ProductDetails> _googleProductsWithPricingPhases(
  String productId,
  List<PricingPhaseWrapper> pricingPhases,
) {
  final wrapper = ProductDetailsWrapper(
    description: 'Pro subscription',
    name: 'Pro',
    productId: productId,
    productType: ProductType.subs,
    title: 'Pro',
    subscriptionOfferDetails: <SubscriptionOfferDetailsWrapper>[
      SubscriptionOfferDetailsWrapper(
        basePlanId: 'monthly',
        offerTags: const <String>[],
        offerIdToken: 'base-monthly',
        pricingPhases: pricingPhases,
      ),
    ],
  );
  return GooglePlayProductDetails.fromProductDetails(wrapper);
}

GooglePlayPurchaseDetails _googlePurchase({
  required String productId,
  required String orderId,
  required String token,
  String? obfuscatedAccountId = '11111111-2222-4333-8444-555555555555',
  PurchaseStateWrapper purchaseState = PurchaseStateWrapper.purchased,
}) {
  final wrapper = PurchaseWrapper(
    orderId: orderId,
    packageName: 'com.example',
    purchaseTime: 1,
    purchaseToken: token,
    signature: 'signature',
    products: <String>[productId],
    isAutoRenewing: true,
    originalJson: '{"redacted":true}',
    isAcknowledged: false,
    purchaseState: purchaseState,
    obfuscatedAccountId: obfuscatedAccountId,
  );
  return GooglePlayPurchaseDetails.fromPurchase(wrapper).single;
}

PurchaseDetails _purchasedForParam(PurchaseParam param) {
  final intentId = param.applicationUserName;
  if (param is GooglePlayPurchaseParam) {
    return _googlePurchase(
      productId: param.productDetails.id,
      orderId: 'GPA.transaction-1',
      token: 'server-secret',
      obfuscatedAccountId: intentId,
    );
  }
  return _sk2Purchased(
    param.productDetails.id,
    purchaseIntentId: intentId,
    transactionId: 'transaction-1',
  );
}

AppStorePurchaseDetails _storeKit1Purchased(
  String productId, {
  required String? purchaseIntentId,
  required String transactionId,
  String verificationData = 'storekit-1-receipt-secret',
}) {
  return AppStorePurchaseDetails.fromSKTransaction(
    SKPaymentTransactionWrapper(
      payment: _storeKit1Payment(productId, purchaseIntentId),
      transactionState: SKPaymentTransactionStateWrapper.purchased,
      originalTransaction: null,
      transactionTimeStamp: 0,
      transactionIdentifier: transactionId,
    ),
    verificationData,
  );
}

AppStorePurchaseDetails _storeKit1Restored(
  String productId, {
  required String? purchaseIntentId,
  required String transactionId,
  required String originalTransactionId,
}) {
  final payment = _storeKit1Payment(productId, purchaseIntentId);
  return AppStorePurchaseDetails.fromSKTransaction(
    SKPaymentTransactionWrapper(
      payment: payment,
      transactionState: SKPaymentTransactionStateWrapper.restored,
      originalTransaction: SKPaymentTransactionWrapper(
        payment: payment,
        transactionState: SKPaymentTransactionStateWrapper.purchased,
        transactionTimeStamp: 0,
        transactionIdentifier: originalTransactionId,
      ),
      transactionTimeStamp: 1,
      transactionIdentifier: transactionId,
    ),
    'storekit-1-receipt-secret',
  );
}

AppStorePurchaseDetails _storeKit1Cancelled(
  String productId, {
  required String? purchaseIntentId,
}) {
  return AppStorePurchaseDetails.fromSKTransaction(
    SKPaymentTransactionWrapper(
      payment: _storeKit1Payment(productId, purchaseIntentId),
      transactionState: SKPaymentTransactionStateWrapper.failed,
      error: const SKError(
        code: 2,
        domain: 'SKErrorDomain',
        userInfo: <String, Object?>{},
      ),
    ),
    '',
  );
}

SKPaymentWrapper _storeKit1Payment(
  String productId,
  String? purchaseIntentId,
) {
  return SKPaymentWrapper(
    productIdentifier: productId,
    applicationUsername: purchaseIntentId,
    quantity: 1,
    simulatesAskToBuyInSandbox: false,
    paymentDiscount: null,
  );
}

SK2PurchaseDetails _sk2Purchased(
  String productId, {
  required String? purchaseIntentId,
  required String transactionId,
}) =>
    SK2PurchaseDetails(
      purchaseID: transactionId,
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local-secret',
        serverVerificationData: 'server-secret',
        source: 'store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
      appAccountToken: purchaseIntentId,
    );

SK2PurchaseDetails _sk2StatusUpdate(
  String productId, {
  required PurchaseStatus status,
  required String? purchaseIntentId,
  IAPError? error,
}) =>
    SK2PurchaseDetails(
      purchaseID: null,
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'store',
      ),
      transactionDate: '0',
      status: status,
      appAccountToken: purchaseIntentId,
    )..error = error;

SK2PurchaseDetails _sk2Restored(
  String productId, {
  required String? purchaseIntentId,
  required String transactionId,
}) =>
    SK2PurchaseDetails(
      purchaseID: transactionId,
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local-secret',
        serverVerificationData: 'server-secret',
        source: 'store',
      ),
      transactionDate: '0',
      status: PurchaseStatus.restored,
      appAccountToken: purchaseIntentId,
    );

StoreTransactionEvidence _evidence({
  required String verificationData,
  Future<void> Function()? finish,
  StoreTransactionState state = StoreTransactionState.purchased,
  StoreTransactionSource source = StoreTransactionSource.googleOwnedPurchases,
  String store = 'playStore',
  String? transactionId = 'GPA.safe',
  String? purchaseIntentId = '11111111-2222-4333-8444-555555555555',
  bool needsFinish = true,
}) {
  if (store == 'appStore' && transactionId == null) {
    throw ArgumentError('App Store evidence requires a transaction ID.');
  }
  return StoreTransactionEvidence(
    evidenceKey: store == 'appStore'
        ? appleEvidenceKey(transactionId!)
        : transactionId != null
            ? googleEvidenceKey(transactionId)
            : googleTokenDigestEvidenceKey(
                googlePurchaseTokenDigest(verificationData),
              ),
    store: store,
    source: source,
    state: state,
    productId: _productId,
    transactionId: transactionId,
    verificationData: verificationData,
    purchaseIntentId: purchaseIntentId,
    originalTransactionId: null,
    needsFinish: needsFinish,
    finish: finish ?? () async {},
  );
}

const _defaultPurchaseIntentDisposition = Object();
const _defaultRecoveredAppAnonymousToken = Object();

ReportTransactionResponse _acceptedResponse(
  ReportTransactionRequest request, {
  List<EntitlementSummary> entitlements = const [],
  String? acceptedTransactionId,
  String? submittedTransactionId,
  String? responseReportId,
  Object? purchaseIntentDisposition = _defaultPurchaseIntentDisposition,
  Object? recoveredAppAnonymousToken = _defaultRecoveredAppAnonymousToken,
}) {
  final canonicalTransactionId =
      acceptedTransactionId ?? request.storeTransactionId;
  late final AcceptedStoreEvidence evidence;
  if (request.store == 'appStore') {
    final submittedId = submittedTransactionId ?? request.storeTransactionId;
    if (submittedId == null || canonicalTransactionId == null) {
      throw StateError('App Store acceptance requires transaction identity.');
    }
    evidence = AppleAcceptedStoreEvidence(
      submittedTransactionId: submittedId,
      acceptedTransactionId: canonicalTransactionId,
      originalTransactionId: canonicalTransactionId,
    );
  } else {
    evidence = GoogleAcceptedStoreEvidence(
      submittedOrderId: submittedTransactionId ?? request.storeTransactionId,
      acceptedOrderId: canonicalTransactionId,
      orderLineageId: canonicalTransactionId?.split('..').first,
      acceptedPurchaseTokenDigest:
          googlePurchaseTokenDigest(request.storeVerificationData),
    );
  }
  final effectiveDisposition = identical(
    purchaseIntentDisposition,
    _defaultPurchaseIntentDisposition,
  )
      ? request.purchaseIntentId == null
          ? PurchaseIntentDisposition.notProvided
          : PurchaseIntentDisposition.associated
      : purchaseIntentDisposition as PurchaseIntentDisposition?;
  final effectiveRecoveredToken = identical(
    recoveredAppAnonymousToken,
    _defaultRecoveredAppAnonymousToken,
  )
      ? effectiveDisposition == PurchaseIntentDisposition.associated ||
              effectiveDisposition ==
                  PurchaseIntentDisposition.alreadyAssociated
          ? request.appAnonymousToken
          : null
      : recoveredAppAnonymousToken as String?;
  return ReportTransactionResponse(
    accepted: true,
    reportId: responseReportId ?? request.reportId,
    evidence: evidence,
    attributionDisposition: AttributionDisposition.notProvided,
    entitlements: entitlements,
    purchaseIntentDisposition: effectiveDisposition,
    recoveredAppAnonymousToken: effectiveRecoveredToken,
  );
}

EntitlementSummary _activeEntitlement() => EntitlementSummary.fromJson(
      const <String, dynamic>{
        'entitlementId': 'pro',
        'status': 'active',
        'productId': _productId,
        'source': 'storeNotification',
      },
    );

String _reportId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Future<void> _flush([int turns = 8]) async {
  for (var index = 0; index < turns; index += 1) {
    await _turn();
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);
