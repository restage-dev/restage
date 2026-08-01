import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:restage/restage.dart' hide InAppPurchaseGateway;
import 'package:restage/src/billing/in_app_purchase_gateway.dart';
import 'package:restage/src/billing/purchase_attribution.dart';
import 'package:restage/src/billing/purchase_platform_adapter.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CreatePurchaseIntentRequest,
        CreatePurchaseIntentResponse,
        EntitlementSummary,
        EntitlementSyncRequest,
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

  test('same-product evidence resolves only its exact purchase intent',
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

  test('StoreKit 2 unfinished transactions drain on configure', () async {
    final finished = <int>[];
    final adapter = StoreKit2UnfinishedPurchaseAdapter(
      enumerate: () async => <SK2Transaction>[
        SK2Transaction(
          id: '42',
          originalId: '7',
          productId: _productId,
          purchaseDate: '0',
          appAccountToken: '11111111-2222-4333-8444-555555555555',
          receiptData: 'apple-jws-secret',
          jsonRepresentation: '{"transaction":"redacted"}',
        ),
      ],
      finish: (id) async => finished.add(id),
    );
    final seen = <StoreTransactionEvidence>[];
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [adapter],
      processor: (evidence, _) async => seen.add(evidence),
    );

    coordinator.start();
    await _turn();

    expect(seen, hasLength(1));
    expect(seen.single.evidenceKey, 'appStore/transaction/42');
    expect(seen.single.originalTransactionId, '7');
    expect(
        seen.single.purchaseIntentId, '11111111-2222-4333-8444-555555555555');
    expect(finished, isEmpty,
        reason: 'enumeration alone never grants permission to finish');
    coordinator.onAppResumed();
    await _turn();
    expect(seen, hasLength(1), reason: 'Apple drain is configure-owned');
    coordinator.cancel();
  });

  test('Google owned purchases drain on configure and resume, filtered',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    var queryCount = 0;
    final adapter = GoogleOwnedPurchaseAdapter(
      plugin: plugin,
      knownSubscriptionProductIds: const {_productId},
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
    expect(seen.map((e) => e.productId), [_productId]);
    expect(seen.single.evidenceKey, 'playStore/order/GPA.known');

    coordinator.onAppResumed();
    await _turn();
    expect(queryCount, 2);
    expect(seen.map((e) => e.productId), [_productId, _productId]);
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

  test('bundled billing without intent service fails before store UI',
      () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) => const [];
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [_product],
      billingGateway: InAppPurchaseGateway(plugin: plugin),
    );

    final outcome = await Restage.purchaseProduct(_productId);

    expect(
      (outcome as PurchaseOutcomeFailed).errorCode,
      RestageBillingErrorCodes.buyFailed,
    );
    expect(plugin.buyCalled, isFalse);
  });

  test('rendering-only configure does not materialize bundled billing', () {
    var adapterFactories = 0;
    PurchaseCoordinator.debugPlatformAdapterFactory = (_, __) {
      adapterFactories += 1;
      return const [];
    };

    Restage.configure(
      apiKey: 'rs_pk_rendering',
      products: const [_product],
    );

    expect(adapterFactories, 0);
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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

  test('lost accepted response retries idempotently with a new report id',
      () async {
    var nextId = 10;
    var finishCount = 0;
    final rpc = _ReportRpcClient(
      onReport: (request, attempt) =>
          attempt == 0 ? null : _acceptedResponse(request),
    );
    final coordinator = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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

  test('nonaccepted response cannot finish; accepted zero-entitlement can',
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
    final rejected = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      store: 'playStore',
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'purchase-token-secret',
              finish: () async => rejectedFinishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: rejectedRpc,
      reportIdGenerator: () => _reportId(20),
      maxReportAttempts: 1,
    );
    rejected.start();
    await _flush();
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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

  test('intent-stamped evidence requires an explicit associated disposition',
      () async {
    for (final disposition in <PurchaseIntentDisposition?>[
      null,
      PurchaseIntentDisposition.unmatched,
      PurchaseIntentDisposition.notProvided,
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
                finish: () async => finishCount += 1,
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
      expect(finishCount, 0, reason: 'disposition: $disposition');
      coordinator.cancel();
    }

    var associatedFinishCount = 0;
    final associatedRpc = _ReportRpcClient(
      onReport: (request, _) => _acceptedResponse(
        request,
        purchaseIntentDisposition: PurchaseIntentDisposition.associated,
      ),
    );
    final associated = _coordinator(
      plugin: _FakeInAppPurchase(product: _storeProduct()),
      adapters: [
        _FakeAdapter(
          evidence: [
            _evidence(
              verificationData: 'receipt-secret',
              store: 'appStore',
              source: StoreTransactionSource.storeKit2Unfinished,
              finish: () async => associatedFinishCount += 1,
            ),
          ],
        ),
      ],
      rpcClient: associatedRpc,
      reportIdGenerator: () => _reportId(24),
      maxReportAttempts: 1,
    );

    associated.start();
    await _flush();

    expect(associatedFinishCount, 1);
    associated.cancel();
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

  test('out-of-app evidence finishes only with explicit notProvided', () async {
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
    final plugin = _FakeInAppPurchase(product: _storeProduct());
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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

  test('finish timeout stops same-run retries and leaves replay retryable',
      () async {
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
      finishAttemptTimeout: Duration.zero,
    );

    coordinator.start();
    await _flush();

    expect(rpc.requests, hasLength(1));
    expect(finishStarts, 1,
        reason: 'a timed-out non-cancelable finish is not overlapped');

    coordinator.onAppResumed();
    await _flush();

    expect(rpc.requests, hasLength(1),
        reason: 'Apple exact acceptance remains reusable for native replay');
    expect(finishStarts, 2,
        reason: 'a later native replay owns the next finish attempt');
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
      plugin: _FakeInAppPurchase(product: _storeProduct()),
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

  test('pending exact intent later emits one attributed global success',
      () async {
    final plugin = _FakeInAppPurchase(
      product: _storeProduct(),
      onBuy: (param) => _sk2Pending(
        param.productDetails.id,
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
      verifySubscriptionFromStore: true,
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

  test('metadata query failure leaves recovered evidence retryable', () async {
    final googleProducts = _googleProducts(_productId);
    final plugin = _FakeInAppPurchase(
      product: googleProducts.single,
      products: googleProducts,
      onQuery: (ids, attempt) {
        if (attempt == 1) throw StateError('metadata unavailable');
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
      verifySubscriptionFromStore: true,
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

  test('Google pending without an order is skipped until purchased', () async {
    final plugin = _FakeInAppPurchase(product: _storeProduct());
    final adapter = GoogleOwnedPurchaseAdapter(
      plugin: plugin,
      knownSubscriptionProductIds: const {_productId},
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
  Future<void> Function(String token)? authoritativeTokenReplacer,
  void Function(List<EntitlementSummary> entitlements)? entitlementReconciler,
  Future<void> Function()? entitlementSync,
  void Function(
    PurchaseOutcomeSucceeded outcome,
    PurchaseAttributionSnapshot attribution,
  )? delayedSuccessEmitter,
  int maxReportAttempts = 3,
  int maxFinishAttempts = 3,
  Duration finishAttemptTimeout = const Duration(seconds: 15),
  Duration restoreTimeout = Duration.zero,
  bool verifySubscriptionFromStore = false,
}) {
  return PurchaseCoordinator(
    gateway: InAppPurchaseGateway(
      plugin: plugin,
      restoreTimeout: restoreTimeout,
    ),
    knownSubscriptionProductIds: const {_productId},
    anonymousTokenProvider: () async => _anonymousToken,
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
    subscriptionVerifier:
        verifySubscriptionFromStore ? null : (_) async => true,
    delayedSuccessEmitter: delayedSuccessEmitter,
    retryDelayPolicy: (_) => Duration.zero,
    delay: (_) async {},
    maxReportAttempts: maxReportAttempts,
    maxFinishAttempts: maxFinishAttempts,
    finishAttemptTimeout: finishAttemptTimeout,
  );
}

final class _IntentRpcClient extends RestageRpcClient {
  _IntentRpcClient({
    this.blockIntent = false,
    this.order,
    this.reportEntitlements = const [],
  }) : super(
          baseUrl: 'https://billing.example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', 500)),
        );

  final bool blockIntent;
  final List<String>? order;
  final List<EntitlementSummary> reportEntitlements;
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
  ) async {
    reportRequests.add(request);
    return _acceptedResponse(request, entitlements: reportEntitlements);
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
  ) async {
    requests.add(request);
    return onReport(request, requests.length - 1);
  }
}

final class _FakeAdapter implements PurchasePlatformAdapter {
  _FakeAdapter({required this.evidence, this.onResume = false});

  final List<StoreTransactionEvidence> evidence;
  final bool onResume;
  int drainCount = 0;

  @override
  bool get drainOnConfigure => true;

  @override
  bool get drainOnResume => onResume;

  @override
  Future<List<StoreTransactionEvidence>> drain() async {
    drainCount += 1;
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
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls += 1;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final detail = restoreDetail;
    if (detail != null) scheduleMicrotask(() => emit(detail));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProductDetails _storeProduct() => AppStoreProduct2Details(
      id: _productId,
      title: 'Pro',
      description: 'Pro subscription',
      price: r'$9.99',
      rawPrice: 9.99,
      currencyCode: 'USD',
      currencySymbol: r'$',
      sk2Product: SK2Product(
        id: _productId,
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
  final wrapper = ProductDetailsWrapper(
    description: 'Pro subscription',
    name: 'Pro',
    productId: productId,
    productType: ProductType.subs,
    title: 'Pro',
    subscriptionOfferDetails: const <SubscriptionOfferDetailsWrapper>[
      SubscriptionOfferDetailsWrapper(
        basePlanId: 'monthly',
        offerTags: <String>[],
        offerIdToken: 'base-monthly',
        pricingPhases: <PricingPhaseWrapper>[
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

SK2PurchaseDetails _sk2Pending(
  String productId, {
  required String? purchaseIntentId,
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
      status: PurchaseStatus.pending,
      appAccountToken: purchaseIntentId,
    );

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
  String transactionId = 'GPA.safe',
  String? purchaseIntentId = '11111111-2222-4333-8444-555555555555',
  bool needsFinish = true,
}) {
  return StoreTransactionEvidence(
    evidenceKey: store == 'appStore'
        ? appleEvidenceKey(transactionId)
        : googleEvidenceKey(transactionId),
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
  final evidence = request.store == 'appStore'
      ? AppleAcceptedStoreEvidence(
          submittedTransactionId:
              submittedTransactionId ?? request.storeTransactionId,
          acceptedTransactionId: canonicalTransactionId,
          originalTransactionId: canonicalTransactionId,
        )
      : GoogleAcceptedStoreEvidence(
          submittedOrderId:
              submittedTransactionId ?? request.storeTransactionId,
          acceptedOrderId: canonicalTransactionId,
          orderLineageId: canonicalTransactionId.split('..').first,
        );
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
