import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes, {this.publishedVersion});
  final Uint8List bytes;
  final int? publishedVersion;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
        bytes: bytes,
        paywallId: id,
        paywallPublishedVersion: publishedVersion,
      );
}

/// A resolver that returns each of [_variants] on successive `resolve` calls
/// (the last repeats once exhausted) — used to model a re-resolve that returns
/// a newer-but-undecodable blob after a prior successful render.
class _SeqResolver implements VariantResolver {
  _SeqResolver(this._variants);
  final List<ResolvedVariant> _variants;
  int _i = 0;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final v = _variants[_i < _variants.length ? _i : _variants.length - 1];
    _i++;
    return v;
  }
}

/// Fake [BillingGateway] returning a fixed [PurchaseOutcome] / [RestoreOutcome].
class _FakeGateway implements BillingGateway {
  _FakeGateway({required this.onPurchase});

  final Future<PurchaseOutcome> Function(String productId) onPurchase;
  Future<RestoreOutcome> Function()? onRestore;
  final List<String> purchaseCalls = <String>[];

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) {
    purchaseCalls.add(productId);
    return onPurchase(productId);
  }

  @override
  Future<RestoreOutcome> restore() async =>
      onRestore?.call() ?? RestoreOutcome.noPurchases();
}

/// Records which report method the runtime routed a purchase to, without
/// touching the network. Injected via [Restage.debugRestageRpcClient].
class _SpyRestageRpcClient extends RestageRpcClient {
  _SpyRestageRpcClient()
      : super(
          baseUrl: 'https://attribution.test',
          apiKey: 'k',
          // Both report methods are overridden to record without touching the
          // network; the MockClient just avoids constructing a real HttpClient.
          httpClient: MockClient((_) async => http.Response('', 200)),
        );

  final List<ReportTransactionRequest> reportTransactionCalls =
      <ReportTransactionRequest>[];
  final List<
      ({
        String storeProductId,
        String storeTransactionId,
        String? paywallId,
        int? paywallPublishedVersion,
      })> reportAttributionCalls = [];

  @override
  Future<List<EntitlementSummary>?> reportTransaction(
    ReportTransactionRequest request,
  ) async {
    reportTransactionCalls.add(request);
    return null;
  }

  @override
  Future<void> reportAttribution({
    required String store,
    required String storeProductId,
    required String storeTransactionId,
    String? paywallId,
    int? paywallPublishedVersion,
  }) async {
    reportAttributionCalls.add((
      storeProductId: storeProductId,
      storeTransactionId: storeTransactionId,
      paywallId: paywallId,
      paywallPublishedVersion: paywallPublishedVersion,
    ));
  }
}

/// A minimal paywall whose single button fires `restage.purchase` for the
/// `primary` slot.
const _buyButtonSource = '''
  import restage.core;
  import restage.material;
  widget Paywall = ElevatedButton(
    onPressed: event 'restage.purchase' { slot: "primary" },
    child: Text(text: "Buy"),
  );
''';

/// Pumps a [RestagePaywall] built from [source] and taps its Buy button,
/// settling after each step.
Future<void> _pumpAndBuy(
  WidgetTester tester, {
  String source = _buyButtonSource,
  String paywallId = 'pro_upgrade',
  int? publishedVersion,
  void Function(RestageEvent)? onEvent,
}) async {
  final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: paywallId,
        resolver: _StaticResolver(bytes, publishedVersion: publishedVersion),
        onEvent: onEvent,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Buy'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Restage.debugReset();
    // The receipt-bearing report path resolves the anonymous token via
    // SharedPreferences; seed it so every test runs without the platform
    // channel and stays deterministic.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'PurchaseInitiated -> BillingGateway.purchase -> PurchaseSucceeded + entitlement granted',
      (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async => PurchaseOutcome.succeeded(
          productId: productId,
          transactionId: 'tx_42',
          verificationData: 'fake-verification',
          priceMicros: 9990000,
          currency: 'USD',
        ),
      ),
    );

    // Source with a button that fires restage.purchase { slot: 'primary' }.
    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = ElevatedButton(
        onPressed: event 'restage.purchase' { slot: "primary" },
        child: Text(text: "Buy"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the button to fire restage.purchase.
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toList();
    expect(names, contains('purchase_initiated'));
    expect(names, contains('purchase_succeeded'));

    final initiated =
        received.firstWhere((e) => e is PurchaseInitiated) as PurchaseInitiated;
    expect(initiated.productId, 'pro_monthly');
    expect(initiated.paywallId, 'pro_upgrade');

    final succeeded =
        received.firstWhere((e) => e is PurchaseSucceeded) as PurchaseSucceeded;
    expect(succeeded.productId, 'pro_monthly');
    expect(succeeded.transactionId, 'tx_42');
    expect(succeeded.priceMicros, 9990000);
    expect(succeeded.currency, 'USD');

    expect(
      Restage.currentEntitlements.any(
        (e) => e.id == 'pro' && e.source == EntitlementSource.purchase,
      ),
      isTrue,
    );
  });

  testWidgets(
      'a state-conditional purchase fires the CURRENTLY-selected product — '
      'initial selection AND after toggling (per branch)', (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async => PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: 'tx',
        verificationData: 'fake-verification',
        priceMicros: 1,
        currency: 'USD',
      ),
    );
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_annual', slot: 'annual', entitlement: 'pro'),
        RestageProduct(id: 'pro_monthly', slot: 'monthly', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );

    // A stateful paywall whose purchase slot is a switch over the selection
    // state: the fired product must follow the CURRENT selection, not a value
    // frozen when the blob was built. This is the never-charge-the-wrong-price
    // invariant proven end-to-end through the real rfw runtime + the demux.
    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall { annualSelected: true } = Column(
        children: [
          ElevatedButton(
            onPressed: set state.annualSelected = false,
            child: Text(text: "Pick monthly"),
          ),
          ElevatedButton(
            onPressed: event "restage.purchase" { slot: switch state.annualSelected { true: "annual", false: "monthly" } },
            child: Text(text: "Buy"),
          ),
        ],
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'plan_paywall',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Initial selection is annual -> the purchase resolves to the annual SKU,
    // and the billing gateway (what actually charges) is called with it.
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(
      received.whereType<PurchaseInitiated>().last.productId,
      'pro_annual',
    );
    expect(gateway.purchaseCalls, ['pro_annual']);

    // Toggle the selection to monthly, then purchase again. The SAME button now
    // fires the monthly SKU — a frozen lowering would (wrongly) re-charge the
    // annual product.
    await tester.tap(find.text('Pick monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(
      received.whereType<PurchaseInitiated>().last.productId,
      'pro_monthly',
    );
    expect(gateway.purchaseCalls, ['pro_annual', 'pro_monthly']);
  });

  testWidgets(
      'a receipt-less (attribution-only) success still grants the entitlement '
      'and fires PurchaseSucceeded', (tester) async {
    // An external-provider gateway delegates the purchase and does not surface
    // the store receipt, so it returns a receipt-less success
    // (verificationData == null). The optimistic local grant + the
    // PurchaseSucceeded event must fire exactly as for a verified success —
    // the user paid and must receive access.
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async => PurchaseOutcome.succeeded(
          productId: productId,
          transactionId: 'GPA.1234-5678-9012-34567',
          verificationData: null,
          priceMicros: 9990000,
          currency: 'USD',
        ),
      ),
    );

    final received = <RestageEvent>[];
    await _pumpAndBuy(tester, onEvent: received.add);

    final succeeded =
        received.firstWhere((e) => e is PurchaseSucceeded) as PurchaseSucceeded;
    expect(succeeded.productId, 'pro_monthly');
    expect(succeeded.transactionId, 'GPA.1234-5678-9012-34567');

    expect(
      Restage.currentEntitlements.any(
        (e) => e.id == 'pro' && e.source == EntitlementSource.purchase,
      ),
      isTrue,
    );
  });

  testWidgets(
      'a receipt-less success routes to the attribution-only report, not the '
      'full-receipt reportTransaction', (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async => PurchaseOutcome.succeeded(
          productId: productId,
          transactionId: 'GPA.42',
          verificationData: null,
          priceMicros: 9990000,
          currency: 'USD',
        ),
      ),
    );
    final spy = _SpyRestageRpcClient();
    Restage.debugRestageRpcClient = spy;

    await _pumpAndBuy(tester, publishedVersion: 7);

    expect(spy.reportTransactionCalls, isEmpty);
    expect(spy.reportAttributionCalls, hasLength(1));
    final report = spy.reportAttributionCalls.single;
    expect(report.storeProductId, 'pro_monthly');
    expect(report.storeTransactionId, 'GPA.42');
    expect(report.paywallId, 'pro_upgrade');
    // The served published version attributes the conversion to MAR, on the
    // receipt-less (external-provider) path too.
    expect(report.paywallPublishedVersion, 7);
  });

  testWidgets(
      'a receipt-bearing success routes to the full-receipt reportTransaction, '
      'not the attribution-only report', (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async => PurchaseOutcome.succeeded(
          productId: productId,
          transactionId: 'tx_42',
          verificationData: 'receipt-blob',
          priceMicros: 9990000,
          currency: 'USD',
        ),
      ),
    );
    final spy = _SpyRestageRpcClient();
    Restage.debugRestageRpcClient = spy;

    await _pumpAndBuy(tester, publishedVersion: 7);

    expect(spy.reportAttributionCalls, isEmpty);
    expect(spy.reportTransactionCalls, hasLength(1));
    final request = spy.reportTransactionCalls.single;
    expect(request.storeVerificationData, 'receipt-blob');
    expect(request.storeProductId, 'pro_monthly');
    expect(request.storeTransactionId, 'tx_42');
    // The served published version is threaded onto the verified-purchase
    // report for MAR attribution.
    expect(request.paywallPublishedVersion, 7);
  });

  testWidgets(
      'a cache-fallback render reports the RENDERED blob version, not a newer '
      'undecodable fresh blob', (tester) async {
    // MAR invariant: the reported published version must match the blob the
    // user actually saw. Mount v5 (cached), then re-mount when the fresh
    // re-resolve returns v6 bytes that fail to decode -> the widget falls back
    // to the cached v5 -> a purchase must attribute to 5, never the failed 6.
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async => PurchaseOutcome.succeeded(
          productId: productId,
          transactionId: 'tx_99',
          verificationData: 'receipt-blob',
          priceMicros: 9990000,
          currency: 'USD',
        ),
      ),
    );
    final spy = _SpyRestageRpcClient();
    Restage.debugEntitlementClient = spy;

    final validBytes = Uint8List.fromList(
        encodeLibraryBlob(parseLibraryFile(_buyButtonSource)));
    final resolver = _SeqResolver([
      ResolvedVariant(
        bytes: validBytes,
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 5,
      ),
      ResolvedVariant(
        bytes: Uint8List.fromList([0, 1, 2, 3]), // undecodable .rfw
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 6,
      ),
    ]);

    Widget paywall() => MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'pro_upgrade',
              resolver: resolver,
              cacheLastRender: true,
            ),
          ),
        );

    // Mount 1: renders + caches the valid v5 blob (bytes + version).
    await tester.pumpWidget(paywall());
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);

    // Dispose mount 1, then re-mount: the fresh re-resolve returns the v6
    // bytes that fail to decode -> cache fallback renders the cached v5.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(paywall());
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget); // the cached v5 rendered

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    expect(spy.reportTransactionCalls, hasLength(1));
    expect(spy.reportTransactionCalls.single.paywallPublishedVersion, 5);
  });

  testWidgets('PurchaseOutcomeCancelled -> PurchaseCancelled, no entitlement',
      (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onPurchase: (productId) async =>
            PurchaseOutcome.cancelled(productId: productId),
      ),
    );

    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = ElevatedButton(
        onPressed: event 'restage.purchase' { slot: "primary" },
        child: Text(text: "Buy"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toList();
    expect(names, contains('purchase_initiated'));
    expect(names, contains('purchase_cancelled'));
    expect(Restage.currentEntitlements, isEmpty);
  });

  testWidgets(
      'purchase outcome arriving after unmount still grants entitlement',
      (tester) async {
    final completer = Completer<PurchaseOutcome>();
    final gw = _FakeGateway(onPurchase: (_) => completer.future);
    Restage.configure(
      apiKey: 'pk',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gw,
    );
    final globalReceived = <RestageEvent>[];
    final sub = Restage.events.listen(globalReceived.add);
    addTearDown(sub.cancel);

    final source = '''
      import restage.core;
      import restage.material;
      widget Paywall = ElevatedButton(
        onPressed: event "restage.purchase" { slot: "primary" },
        child: Text(text: "Buy"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    // User navigates away mid-purchase. The paywall is unmounted before the
    // platform store reports back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    // Now the gateway resolves with a successful purchase. The widget is
    // gone — but the global side effects (event + entitlement grant) must
    // still run, otherwise the user is charged but never receives access.
    completer.complete(PurchaseOutcome.succeeded(
      productId: 'pro_monthly',
      transactionId: 'tx_1',
      verificationData: 'fake-verification',
      priceMicros: 9990000,
      currency: 'USD',
    ));
    await tester.pumpAndSettle();

    final names = globalReceived.map((e) => e.name).toList();
    expect(names, contains('purchase_succeeded'));
    expect(names, contains('entitlement_granted'));
    expect(
      Restage.currentEntitlements.map((e) => e.id),
      contains('pro'),
    );
  });

  test(
      'restore re-grant fires EntitlementGranted even when entitlement '
      'was already active', () async {
    Restage.configure(
      apiKey: 'pk',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
    );

    // Pre-grant from a purchase.
    Restage.grantEntitlement(
      const RestageEntitlement(id: 'pro', source: EntitlementSource.purchase),
      productId: 'pro_monthly',
    );
    final globalReceived = <RestageEvent>[];
    final sub = Restage.events.listen(globalReceived.add);
    addTearDown(sub.cancel);

    // Simulate a restore that re-grants the same entitlement from a
    // different source.
    Restage.grantEntitlementForProduct(
      'pro_monthly',
      EntitlementSource.restore,
    );
    // Broadcast streams deliver via microtask — flush before asserting.
    await Future<void>.delayed(Duration.zero);

    // The re-grant must reach the host as the "Welcome back!" signal.
    final granted = globalReceived.whereType<EntitlementGranted>().toList();
    expect(granted.length, 1);
    expect(granted.single.source, EntitlementSource.restore);
    // The stored entitlement now reflects the restore-source metadata.
    expect(
      Restage.currentEntitlements.firstWhere((e) => e.id == 'pro').source,
      EntitlementSource.restore,
    );
  });

  testWidgets(
      'a double-tap on a blob paywall Buy invokes billing exactly once — the '
      'in-flight dedup guard is transparent to sequential purchases',
      (tester) async {
    final completer = Completer<PurchaseOutcome>();
    final gateway = _FakeGateway(onPurchase: (_) => completer.future);
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );
    final bytes = Uint8List.fromList(
        encodeLibraryBlob(parseLibraryFile(_buyButtonSource)));
    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Two taps before the first purchase resolves: the second is a no-op so the
    // user is never charged twice.
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(gateway.purchaseCalls, hasLength(1));
    // The guard is reserved before the initiation event fires, so the duplicate
    // tap fires no duplicate purchase_initiated either.
    expect(received.where((e) => e.name == 'purchase_initiated'), hasLength(1));

    completer.complete(PurchaseOutcome.succeeded(
      productId: 'pro_monthly',
      transactionId: 'tx',
      verificationData: null,
      priceMicros: 1,
      currency: 'USD',
    ));
    await tester.pumpAndSettle();
    expect(gateway.purchaseCalls, ['pro_monthly']);
  });
}
