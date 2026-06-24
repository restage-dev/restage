import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A delivered baseline paywall is at or below the installed built-in catalog
/// version; using it keeps these fixtures renderable on this build (the
/// resolvers reject anything above the installed ceiling).
const int _renderableMinClient =
    RestageBuiltInCatalogCapabilities.currentVersion;

// ---------------------------------------------------------------------------
// Flow-hosting integration tests for RestagePaywall.
//
// A paywall whose handler called Navigator.push is lowered (at build time) to a
// 2-screen flow: an entry paywall screen that pushes a "plans" paywall screen,
// plus a non-purchase skip -> end terminator. These tests drive + verify the
// runtime half: the present path hosts the flow, and a purchase on ANY screen
// still charges (billing + entitlement + MAR attribution), never navigating the
// graph speculatively, and never charging twice on a double-tap.
// ---------------------------------------------------------------------------

/// Fake [BillingGateway] recording every purchase/restore call.
class _FakeGateway implements BillingGateway {
  _FakeGateway({required this.onPurchase, this.onRestore});

  final Future<PurchaseOutcome> Function(String productId) onPurchase;
  Future<RestoreOutcome> Function()? onRestore;
  final List<String> purchaseCalls = <String>[];
  int restoreCalls = 0;

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) {
    purchaseCalls.add(productId);
    return onPurchase(productId);
  }

  @override
  Future<RestoreOutcome> restore() async {
    restoreCalls++;
    return onRestore?.call() ?? RestoreOutcome.noPurchases();
  }
}

/// Records MAR attribution reporting without touching the network.
class _SpyRestageRpcClient extends RestageRpcClient {
  _SpyRestageRpcClient()
      : super(
          baseUrl: 'https://attribution.test',
          apiKey: 'k',
          httpClient: MockClient((_) async => http.Response('', 200)),
        );

  final List<ReportTransactionRequest> reportTransactionCalls =
      <ReportTransactionRequest>[];
  final List<({String? paywallId, int? paywallPublishedVersion})>
      reportAttributionCalls = [];

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
      paywallId: paywallId,
      paywallPublishedVersion: paywallPublishedVersion,
    ));
  }
}

/// A flow screen blob whose root is `OnboardingScreen` (what the flow view
/// renders), with one tappable label per (label -> event).
Uint8List _screenBlob(Map<String, String> labelToEvent) {
  // Each label is a tall, full-width, centered tap target, with the content
  // pushed below the flow chrome (a pushed flow screen shows a top-start back
  // chevron), so the labels are reliably hit-testable in the widget test.
  final buttons = labelToEvent.entries
      .map(
        (e) => 'SizedBox(height: 100.0, child: GestureDetector('
            "onTap: event '${e.value}' { slot: \"primary\" }, "
            'child: Center(child: Text(text: "${e.key}"))))',
      )
      .join(',\n');
  final source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      SizedBox(height: 96.0),
      $buttons
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the lowered 2-screen flow document: entry (pushes "plans" via
/// restageNav0, dismisses via skip) -> plans (a pushed paywall, on:{}).
FlowDocument _navFlowDocument({
  required Uint8List entryBytes,
  required Uint8List plansBytes,
  bool plansSkipsToEnd = false,
}) {
  return FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'entry',
    actions: const {},
    screenArtifacts: {
      'entry': ScreenArtifact(
        path: 'paywall_pro_upgrade.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: FlowContentHash.compute(entryBytes),
      ),
      'plans': ScreenArtifact(
        path: 'paywall_pro_upgrade_plans.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: FlowContentHash.compute(plansBytes),
      ),
    },
    states: {
      'entry': const ScreenFlowState(
        screen: 'entry',
        on: {
          'restageNav0': FlowTransition.goto('plans'),
          'skip': FlowTransition.goto('done'),
        },
      ),
      'plans': ScreenFlowState(
        screen: 'plans',
        on: plansSkipsToEnd
            ? const {'skip': FlowTransition.goto('done')}
            : const {},
      ),
      'done': const EndFlowState(result: {}),
    },
  );
}

/// An in-memory bundle serving the flow JSON + its screen blobs.
final class _FlowAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> _assets = {};

  void writeFlow(String id, FlowDocument document) {
    _assets['assets/paywalls/$id.flow.json'] = Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/onboarding/screens/$path'] = Uint8List.fromList(bytes);
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

/// Assembles the resolver for the lowered nav paywall.
VariantResolver _navPaywallResolver() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  final bundle = _FlowAssetBundle()
    ..writeFlow(
        'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
    ..writeScreen('paywall_pro_upgrade.rfw', entry)
    ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);
  return AssetVariantResolver(bundle: bundle);
}

/// A flow-capable resolver that resolves a flow payload once, then fails — to
/// drive the cache-fallback re-host path on a remount.
class _SeqFlowResolver implements VariantResolver, FlowCapableVariantResolver {
  _SeqFlowResolver(this._flow);
  final ResolvedFlow _flow;
  int _calls = 0;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (_calls++ == 0) {
      return FlowPaywallPayload(flow: _flow, paywallId: id);
    }
    throw const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh resolve failed',
    );
  }
}

ResolvedFlow _navResolvedFlow() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  return ResolvedFlow(
    document: _navFlowDocument(entryBytes: entry, plansBytes: plans),
    screenBlobs: {'entry': entry, 'plans': plans},
    cacheHit: false,
  );
}

Future<void> _pumpFlowPaywall(
  WidgetTester tester, {
  String paywallId = 'pro_upgrade',
  void Function(RestageEvent)? onEvent,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: paywallId,
        resolver: _navPaywallResolver(),
        onEvent: onEvent,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'a flow-hosted paywall renders its entry screen, navigates to the pushed '
      'screen, and a purchase there charges exactly once + grants + attributes',
      (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async => PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: 'tx_flow',
        verificationData: null,
        priceMicros: 9990000,
        currency: 'USD',
      ),
    );
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );
    final spy = _SpyRestageRpcClient();
    Restage.debugRestageRpcClient = spy;

    final received = <RestageEvent>[];
    await _pumpFlowPaywall(tester, onEvent: received.add);

    // The entry screen rendered (hosted as a flow, not the missing blob).
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Buy'), findsNothing);

    // Navigate to the pushed "plans" screen via the synthetic nav event.
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);

    // Buy on the pushed screen: bills exactly once, no graph transition.
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, ['pro_monthly']);
    final names = received.map((e) => e.name).toList();
    expect(names, contains('purchase_initiated'));
    expect(names, contains('purchase_succeeded'));
    expect(
      Restage.currentEntitlements.any(
        (e) => e.id == 'pro' && e.source == EntitlementSource.purchase,
      ),
      isTrue,
    );
    // Attribution fired (receipt-less -> attribution-only); bundled flow has no
    // published version, so it attributes to null (the served version plumbs
    // through for the hosted path).
    expect(spy.reportAttributionCalls, hasLength(1));
    expect(spy.reportAttributionCalls.single.paywallId, 'pro_upgrade');
    expect(spy.reportAttributionCalls.single.paywallPublishedVersion, isNull);

    // The Buy tap did NOT navigate the graph (still on the pushed screen).
    expect(find.text('Buy'), findsOneWidget);
  });

  testWidgets(
      'a double-tap on a flow paywall Buy invokes billing exactly once '
      '(the shared in-flight dedup)', (tester) async {
    final completer = Completer<PurchaseOutcome>();
    final gateway = _FakeGateway(onPurchase: (_) => completer.future);
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );

    final received = <RestageEvent>[];
    await _pumpFlowPaywall(tester, onEvent: received.add);
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();

    // Two taps before the first purchase resolves: the second must be a no-op.
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(gateway.purchaseCalls, hasLength(1));
    // The guard is reserved BEFORE the initiation event fires, so the duplicate
    // tap also fires no duplicate purchase_initiated (no funnel double-count).
    expect(
      received.where((e) => e.name == 'purchase_initiated'),
      hasLength(1),
    );

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

  testWidgets(
      'tapping skip on the entry screen completes the flow as a paywall '
      'dismiss keyed on paywallId (not an onboarding completion)',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];
    await _pumpFlowPaywall(tester, onEvent: received.add);

    await tester.tap(find.text('No thanks')); // the skip affordance
    await tester.pumpAndSettle();

    final dismissed = received.whereType<PaywallDismissed>().toList();
    expect(dismissed, hasLength(1));
    expect(dismissed.single.paywallId, 'pro_upgrade');
    expect(dismissed.single.reason, DismissReason.userClose);
  });

  testWidgets(
      'a flow-hosted paywall surfaces PAYWALL lifecycle (not onboarding) — no '
      'flowId-bearing event leaks to analytics', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];
    final sub = Restage.events.listen(received.add);
    addTearDown(sub.cancel);

    await _pumpFlowPaywall(tester);
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toSet();
    // Paywall-shaped lifecycle fires, keyed on paywallId.
    expect(names, contains('paywall_load_started'));
    expect(names, contains('paywall_load_completed'));
    expect(names, contains('paywall_viewed'));
    for (final e in received) {
      expect(e.paywallId, anyOf(isNull, 'pro_upgrade'));
    }
    // The vanilla onboarding flow lifecycle is suppressed — none of these leak.
    expect(names, isNot(contains('onboarding_started')));
    expect(names, isNot(contains('flow_started')));
    expect(names, isNot(contains('onboarding_step_viewed')));
  });

  testWidgets(
      'restore on a flow paywall screen runs billing.restore + grants the '
      'restored entitlement (keyed paywall)', (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async =>
          PurchaseOutcome.cancelled(productId: productId),
      onRestore: () async =>
          RestoreOutcome.succeeded(restoredProductIds: const ['pro_monthly']),
    );
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );

    final received = <RestageEvent>[];
    // The plans screen fires restage.restore from its single button.
    final entry =
        _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
    final plans = _screenBlob({'Restore': 'restage.restore'});
    final bundle = _FlowAssetBundle()
      ..writeFlow(
          'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: AssetVariantResolver(bundle: bundle),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(gateway.restoreCalls, 1);
    final restored = received.whereType<RestoreSucceeded>().toList();
    expect(restored, hasLength(1));
    expect(restored.single.paywallId, 'pro_upgrade');
    expect(
      Restage.currentEntitlements.any(
        (e) => e.id == 'pro' && e.source == EntitlementSource.restore,
      ),
      isTrue,
    );
  });

  testWidgets(
      'FAIL-CLOSED: a hosted flow payload under a paywall surface is rejected '
      'by the hosted resolver and does NOT render — it falls through to the '
      'bundled/error path', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    // The hosted fetch returns a FLOW payload under a paywall surface. The
    // hosted resolver rejects a non-blob hosted payload, and with no bundled
    // asset there is nothing to fall back to -> the paywall fails closed to its
    // error builder. The hosted flow's screens are NEVER hosted/rendered.
    final entry =
        _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
    final plans = _screenBlob({'Buy': 'restage.purchase'});
    final hostedFlowEnvelope = SurfaceDocumentCodec.encode(SurfaceDocument(
      surfaceType: SurfaceType.paywall,
      surfaceSlug: 'pro_upgrade',
      version: 9,
      minClient: _renderableMinClient,
      payload: FlowSurfacePayload(
        flowDocument: _navFlowDocument(entryBytes: entry, plansBytes: plans),
        // screenBlobs are keyed by screen id (matching the document artifacts).
        screenBlobs: {'entry': entry, 'plans': plans},
      ),
      publishedAt: DateTime.utc(2026),
    ));
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test_x',
      environment: RestageEnvironment.production,
      baseUrl: 'https://surfaces.example.com',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'envelope': base64Encode(hostedFlowEnvelope)}),
          200,
        ),
      ),
      // An empty bundle: no bundled fallback for this id.
      assetFallback: AssetVariantResolver(bundle: _FlowAssetBundle()),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          errorBuilder: (_, __) => const Text('FAILED_CLOSED'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The error builder rendered; the hosted flow's screens did NOT.
    expect(find.text('FAILED_CLOSED'), findsOneWidget);
    expect(find.text('See plans'), findsNothing);
    expect(find.text('Buy'), findsNothing);
  });

  testWidgets(
      'a stale purchase tap after the flow has completed does NOT bill — the '
      'interceptor mirrors the controller busy/complete gate', (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async => PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: 'tx',
        verificationData: null,
        priceMicros: 1,
        currency: 'USD',
      ),
    );
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: gateway,
    );

    // A pushed "plans" screen that can both Buy and Leave (skip -> end).
    final entry = _screenBlob({'See plans': 'restageNav0'});
    final plans = _screenBlob({'Buy': 'restage.purchase', 'Leave': 'skip'});
    final bundle = _FlowAssetBundle()
      ..writeFlow(
        'pro_upgrade',
        _navFlowDocument(
          entryBytes: entry,
          plansBytes: plans,
          plansSkipsToEnd: true,
        ),
      )
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: AssetVariantResolver(bundle: bundle),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();

    // Leave the flow (skip -> end) — it is now complete. A stale Buy tap on the
    // still-mounted last screen must NOT charge.
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, isEmpty);
  });

  testWidgets(
      'a restageNav look-alike custom event (restageNavFoo) surfaces as a '
      'PaywallCustomEvent, not a navigation event', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final received = <RestageEvent>[];

    // The entry screen also exposes a look-alike "restageNavFoo" event.
    final entry = _screenBlob({
      'See plans': 'restageNav0',
      'Help': 'restageNavFoo',
      'No thanks': 'skip',
    });
    final plans = _screenBlob({'Buy': 'restage.purchase'});
    final bundle = _FlowAssetBundle()
      ..writeFlow(
          'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
      ..writeScreen('paywall_pro_upgrade.rfw', entry)
      ..writeScreen('paywall_pro_upgrade_plans.rfw', plans);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: AssetVariantResolver(bundle: bundle),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    // It did NOT navigate (still on the entry screen) and surfaced as a custom
    // event, not a swallowed/forwarded navigation.
    expect(find.text('See plans'), findsOneWidget);
    final custom = received.whereType<PaywallCustomEvent>().toList();
    expect(custom.map((e) => e.eventName), contains('restageNavFoo'));
  });

  testWidgets(
      'a cacheLastRender flow re-hosted from the last-good cache reports '
      'PaywallLoadCompleted.cacheHit == true (consistent with the blob path)',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final resolver = _SeqFlowResolver(_navResolvedFlow());

    Widget paywall(List<RestageEvent> received) => MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'pro_upgrade',
              resolver: resolver,
              cacheLastRender: true,
              onEvent: received.add,
            ),
          ),
        );

    // Mount 1: the fresh flow resolves + renders + caches (cacheHit false).
    final first = <RestageEvent>[];
    await tester.pumpWidget(paywall(first));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsOneWidget);
    expect(first.whereType<PaywallLoadCompleted>().single.cacheHit, isFalse);

    // Remount: the fresh resolve fails -> fall back to the cached flow. The
    // re-host must report a cache HIT (matching the blob fallback).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final second = <RestageEvent>[];
    await tester.pumpWidget(paywall(second));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsOneWidget);
    expect(second.whereType<PaywallLoadCompleted>().single.cacheHit, isTrue);
  });
}
