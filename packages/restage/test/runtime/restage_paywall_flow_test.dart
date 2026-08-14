import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart'
    show registerThrowingWidget, throwingResolvedFlow;
import '../support/hosted_artifact_delivery.dart';

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
          httpClient: _delivery.client((_) async => http.Response('', 200)),
        );

  final List<ReportTransactionRequest> reportTransactionCalls =
      <ReportTransactionRequest>[];
  final List<({String? paywallId, int? paywallPublishedVersion})>
      reportAttributionCalls = [];

  @override
  Future<ReportTransactionResponse?> reportTransaction(
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
    _assets['assets/paywalls/screens/$path'] = Uint8List.fromList(bytes);
  }

  void writeLegacyScreen(String path, Uint8List bytes) {
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

VariantResolver _legacyNavPaywallResolver() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restage.purchase'});
  final bundle = _FlowAssetBundle()
    ..writeFlow(
        'pro_upgrade', _navFlowDocument(entryBytes: entry, plansBytes: plans))
    ..writeLegacyScreen('paywall_pro_upgrade.rfw', entry)
    ..writeLegacyScreen('paywall_pro_upgrade_plans.rfw', plans);
  return AssetVariantResolver(bundle: bundle);
}

/// Same flow, but the plans screen's "Buy" control is rewired from a purchase to
/// a nav event — modelling a content-OTA (or customer content bug) that routes
/// the user PAST the charge. Delivery does NOT gate this (blob-OTA parity); the
/// runtime backstop is what keeps it safe (no charge, no entitlement).
VariantResolver _rewiredNavPaywallResolver() {
  final entry = _screenBlob({'See plans': 'restageNav0', 'No thanks': 'skip'});
  final plans = _screenBlob({'Buy': 'restageNav0'});
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
  _SeqFlowResolver(this._flow, {this.resolvedFromActiveArm = false});
  final ResolvedFlow _flow;
  final bool resolvedFromActiveArm;
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
      return FlowPaywallPayload(
        flow: _flow,
        paywallId: id,
        resolvedFromActiveArm: resolvedFromActiveArm,
      );
    }
    throw const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh resolve failed',
    );
  }
}

/// A flow-capable resolver returning a pre-resolved flow payload carrying an
/// experiment id + served version (mirroring what the hosted active arm sets),
/// so the flow-hosted lifecycle attributes the experiment on `PaywallViewed`.
class _AttributedFlowResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _AttributedFlowResolver({
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.publishedVersion,
  });
  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
  final int? publishedVersion;

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
  }) async =>
      FlowPaywallPayload(
        flow: _navResolvedFlow(),
        paywallId: id,
        paywallPublishedVersion: publishedVersion,
        experimentId: experimentId,
        variantId: variantId,
        experimentEpoch: experimentEpoch,
      );
}

/// A flow-capable resolver whose every payload response stays under explicit
/// test control.
final class _ControlledFlowPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  final List<Completer<ResolvedPaywallPayload>> responses = [];

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
  }) {
    final response = Completer<ResolvedPaywallPayload>();
    responses.add(response);
    return response.future;
  }
}

/// A root flow whose initial state enters a child before any screen exists.
///
/// Paywall payloads are re-hosted through the already-resolved root artifact,
/// so the child lookup deterministically fails its flow-id contract. This
/// exercises the early root [FlowStarted] emitted before child resolution has
/// installed renderable content.
ResolvedFlow _initialSubFlowThatFailsBeforeScreen() {
  final childHash = FlowContentHash.compute(Uint8List.fromList(const [1]));
  final document = FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'child',
    actions: const {},
    screenArtifacts: const {},
    states: {
      'child': SubFlowState(
        flow: 'child_flow',
        version: 1,
        schemaVersion: 1,
        minClient: _renderableMinClient,
        contentHash: childHash,
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: {}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: const {},
    contentHash: FlowContentHash.compute(
      Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    ),
    cacheHit: false,
  );
}

ResolvedFlow _singleScreenResolvedFlow(String text) {
  final screen = _screenBlob({text: 'noop'});
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'pro_upgrade',
      version: 1,
      schemaVersion: 1,
      minClient: _renderableMinClient,
      initial: 'entry',
      actions: const {},
      screenArtifacts: {
        'entry': ScreenArtifact(
          path: 'entry.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: _renderableMinClient,
          contentHash: FlowContentHash.compute(screen),
        ),
      },
      states: const {
        'entry': ScreenFlowState(screen: 'entry', on: {}),
      },
    ),
    screenBlobs: {'entry': screen},
    cacheHit: false,
  );
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
  VariantResolver? resolver,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: paywallId,
        resolver: resolver ?? _navPaywallResolver(),
        onEvent: onEvent,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'an initial root SubFlow does not commit paywall lifecycle before a '
      'child installs the first screen', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          loadingBuilder: (_) => const Text('Loading child'),
          errorBuilder: (_, __) => const Text('Child unavailable'),
        ),
      ),
    ));
    await tester.pump();

    expect(resolver.responses, hasLength(1));
    expect(events.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(events.whereType<PaywallViewed>(), isEmpty);

    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _initialSubFlowThatFailsBeforeScreen(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await tester.pumpAndSettle();

    final observed = (
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      unavailable: find.text('Child unavailable').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      observed,
      (completed: 0, viewed: 0, failed: 1, unavailable: 1),
    );
  });

  testWidgets(
      'a refresh root SubFlow that fails before its child screen preserves the '
      'old rendered controller and published identity', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Refresh failed visibly'),
        ),
      ),
    ));
    await tester.pump();
    expect(resolver.responses, hasLength(1));
    resolver.responses[0].complete(FlowPaywallPayload(
      flow: _singleScreenResolvedFlow('Old rendered paywall'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Old rendered paywall'), findsOneWidget);
    events.clear();

    final failedRefresh = Restage.reloadSurfaces();
    await tester.pump();
    expect(resolver.responses, hasLength(2));
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: _initialSubFlowThatFailsBeforeScreen(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await failedRefresh;
    await tester.pumpAndSettle();

    final currentOld = find.text('Old rendered paywall').evaluate().length;
    final currentError = find.text('Refresh failed visibly').evaluate().length;

    // A remount whose fresh resolution fails must re-host the cached OLD
    // payload. This probes both that the failed candidate did not evict the
    // rendered controller's cache and that version 1 remains the render owner.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('No cached old paywall'),
        ),
      ),
    ));
    await tester.pump();
    expect(resolver.responses, hasLength(3));
    resolver.responses[2].completeError(const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh remount failed',
    ));
    await tester.pumpAndSettle();

    final cachedViews = events.whereType<PaywallViewed>().toList();
    final cachedLoads = events.whereType<PaywallLoadCompleted>().toList();
    final observed = (
      currentOld: currentOld,
      currentError: currentError,
      cachedOld: find.text('Old rendered paywall').evaluate().length,
      remountError: find.text('No cached old paywall').evaluate().length,
      failures: events.whereType<PaywallLoadFailed>().length,
      cachedViews: cachedViews.length,
      cachedVersion:
          cachedViews.isEmpty ? null : cachedViews.last.publishedVersion,
      cacheHit: cachedLoads.isEmpty ? null : cachedLoads.last.cacheHit,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      observed,
      (
        currentOld: 1,
        currentError: 0,
        cachedOld: 1,
        remountError: 0,
        failures: 0,
        cachedViews: 1,
        cachedVersion: 1,
        cacheHit: true,
      ),
    );
  });

  testWidgets(
      'an initial flow screen that throws on first build stamps no identity, '
      'cache, or paywall lifecycle', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    registerThrowingWidget();
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Initial render unavailable'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: throwingResolvedFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await tester.pumpAndSettle();

    final firstObserved = (
      error: find.text('Initial render unavailable').evaluate().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      dismissed: events.whereType<PaywallDismissed>().length,
      escaped: tester.takeException(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final dismissedAfterUnmount = events.whereType<PaywallDismissed>().length;

    // A resolver failure on remount must surface its own delivery error. If the
    // throwing first render had been cached, the fallback would re-host it and
    // surface render_error instead.
    events.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Fresh delivery unavailable'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses[1].completeError(const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh remount failed',
    ));
    await tester.pumpAndSettle();
    final remountFailure = events.whereType<PaywallLoadFailed>().single;
    final remountObserved = (
      error: find.text('Fresh delivery unavailable').evaluate().length,
      code: remountFailure.errorCode,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      firstObserved,
      (
        error: 1,
        completed: 0,
        viewed: 0,
        failed: 1,
        dismissed: 0,
        escaped: null,
      ),
    );
    expect(dismissedAfterUnmount, 0);
    expect(
      remountObserved,
      (
        error: 1,
        code: RestageErrorCodes.deliveryUnavailable,
        completed: 0,
        viewed: 0,
      ),
    );
  });

  testWidgets(
      'a refresh flow screen that throws on first build preserves last-good '
      'render, identity, cache, and lifecycle', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    registerThrowingWidget();
    final resolver = _ControlledFlowPayloadResolver();
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('Refresh failed visibly'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _singleScreenResolvedFlow('Old rendered paywall'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
    ));
    await tester.pumpAndSettle();
    events.clear();

    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: throwingResolvedFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await refresh;
    await tester.pumpAndSettle();

    final currentObserved = (
      old: find.text('Old rendered paywall').evaluate().length,
      error: find.text('Refresh failed visibly').evaluate().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      dismissed: events.whereType<PaywallDismissed>().length,
      escaped: tester.takeException(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    events.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: events.add,
          errorBuilder: (_, __) => const Text('No cached old paywall'),
        ),
      ),
    ));
    await tester.pump();
    resolver.responses[2].completeError(const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'fresh remount failed',
    ));
    await tester.pumpAndSettle();
    final viewed = events.whereType<PaywallViewed>().single;
    final cachedObserved = (
      old: find.text('Old rendered paywall').evaluate().length,
      error: find.text('No cached old paywall').evaluate().length,
      version: viewed.publishedVersion,
      cacheHit: events.whereType<PaywallLoadCompleted>().single.cacheHit,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      currentObserved,
      (
        old: 1,
        error: 0,
        completed: 0,
        viewed: 0,
        failed: 0,
        dismissed: 0,
        escaped: null,
      ),
    );
    expect(
      cachedObserved,
      (old: 1, error: 0, version: 1, cacheHit: true),
    );
  });

  testWidgets(
      'a legacy flow-hosted paywall renders from the compatibility bundle path',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');

    await _pumpFlowPaywall(tester, resolver: _legacyNavPaywallResolver());

    expect(find.text('See plans'), findsOneWidget);
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);
  });

  testWidgets(
      'a canonical flow-hosted paywall renders its entry screen, navigates to '
      'the pushed screen, and a purchase there charges exactly once + grants + '
      'attributes', (tester) async {
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

  // The entitlement backstop — why the delivery-time money-path gate was dropped.
  // A hosted active flow-paywall content-OTA (or a customer content bug) can
  // rewire the Buy control PAST the charge; delivery does not gate that (blob-OTA
  // parity). It is safe because the runtime grants an entitlement ONLY on a real
  // purchase success: a rewired control fires a non-charge event, so no
  // PurchaseInitiated, no gateway call, no entitlement — the user gets nothing.
  testWidgets(
      'a rewired Buy control (purchase -> nav) fires NO charge and grants NO '
      'entitlement (route-past = nothing granted)', (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async => PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: 'tx_never',
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

    final received = <RestageEvent>[];
    await _pumpFlowPaywall(
      tester,
      onEvent: received.add,
      resolver: _rewiredNavPaywallResolver(),
    );

    // Navigate to the pushed "plans" screen, then tap the (rewired) "Buy".
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    // No charge was initiated, so nothing was granted.
    expect(gateway.purchaseCalls, isEmpty);
    final names = received.map((e) => e.name).toList();
    expect(names, isNot(contains('purchase_initiated')));
    expect(names, isNot(contains('purchase_succeeded')));
    expect(Restage.currentEntitlements, isEmpty);
  });

  testWidgets(
      'a hosted active flow paywall charges keyed on the SERVED version '
      '(MAR attribution over OTA)', (tester) async {
    final gateway = _FakeGateway(
      onPurchase: (productId) async => PurchaseOutcome.succeeded(
        productId: productId,
        transactionId: 'tx_active',
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _AttributedFlowResolver(
            publishedVersion: 9,
            experimentId: 'exp_x',
            variantId: 'variant_a',
            experimentEpoch: 3,
          ),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Navigate to the pushed "plans" screen, then buy there.
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, ['pro_monthly']);
    // The conversion attributes to the SERVED active version (9), not null.
    expect(spy.reportAttributionCalls, hasLength(1));
    expect(spy.reportAttributionCalls.single.paywallId, 'pro_upgrade');
    expect(spy.reportAttributionCalls.single.paywallPublishedVersion, 9);
  });

  testWidgets(
      'a flow-hosted paywall attributes the experiment on PaywallViewed '
      '(experiment-attribution parity with the blob path)', (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
    );

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _AttributedFlowResolver(
            experimentId: 'exp_arm_A',
            variantId: 'variant_a',
            experimentEpoch: 3,
            publishedVersion: 7,
          ),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final viewed = received.whereType<PaywallViewed>().toList();
    expect(viewed, isNotEmpty,
        reason: 'a flow paywall must fire PaywallViewed');
    expect(viewed.first.experimentId, 'exp_arm_A');
    expect(viewed.first.variantId, 'variant_a');
    expect(viewed.first.experimentEpoch, 3);
  });

  testWidgets(
      'a flow-hosted paywall emits one canonical root with served attribution',
      (tester) async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = _delivery.client((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );

    await _pumpFlowPaywall(
      tester,
      resolver: _AttributedFlowResolver(
        experimentId: 'exp_arm_A',
        variantId: 'variant_a',
        experimentEpoch: 3,
        publishedVersion: 7,
      ),
    );
    await Restage.debugFlushAnalytics();

    final events = _analyticsEvents(requests);
    final presentations =
        events.where((event) => event['name'] == 'surface_presented').toList();
    expect(presentations, hasLength(1));
    expect(presentations.single['surface'], 'paywall');
    expect(presentations.single['surfaceId'], 'pro_upgrade');
    expect(presentations.single['surfaceVersion'], '7');
    expect(presentations.single['surfaceSessionId'], isNotNull);
    expect(presentations.single['experimentId'], 'exp_arm_A');
    expect(presentations.single['variantId'], 'variant_a');
    expect(presentations.single['experimentEpoch'], 3);

    final viewed =
        events.singleWhere((event) => event['name'] == 'paywall_viewed');
    expect(viewed['surface'], 'paywall');
    expect(viewed['surfaceId'], 'pro_upgrade');
    expect(viewed['surfaceVersion'], '7');
    expect(
      viewed['surfaceSessionId'],
      presentations.single['surfaceSessionId'],
    );
    expect(viewed['experimentId'], 'exp_arm_A');
    expect(viewed['variantId'], 'variant_a');
    expect(viewed['experimentEpoch'], 3);
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
      surfaceType: Surface.paywall,
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
      httpClient: _delivery.client(
        (_) async => http.Response(
          jsonEncode({..._delivery.describeEnvelope(hostedFlowEnvelope)}),
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

  testWidgets(
      'a cacheLastRender ACTIVE-resolved flow is NOT re-hosted un-re-gated from '
      'the runtime cache — it defers to the resolver hold-last-good (fails '
      'closed here)', (tester) async {
    Restage.configure(apiKey: 'pk_test');
    // The active-resolved flow renders once, then the resolver fails.
    final resolver =
        _SeqFlowResolver(_navResolvedFlow(), resolvedFromActiveArm: true);

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

    // Mount 1: the fresh active flow resolves + renders + caches.
    final first = <RestageEvent>[];
    await tester.pumpWidget(paywall(first));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsOneWidget);

    // Remount: the fresh resolve fails. Unlike a bundled flow, an ACTIVE-resolved
    // flow must NOT be re-hosted from the runtime cache un-re-gated — the
    // resolver's own re-gated hold-last-good owns re-serving it. Here (a
    // stub resolver that just fails) it falls closed to the error path.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final second = <RestageEvent>[];
    await tester.pumpWidget(paywall(second));
    await tester.pumpAndSettle();
    expect(find.text('See plans'), findsNothing);
    expect(second.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(second.whereType<PaywallLoadFailed>(), isNotEmpty);
  });
}

List<Map<String, Object?>> _analyticsEvents(List<http.Request> requests) =>
    <Map<String, Object?>>[
      for (final request in requests)
        for (final event in (jsonDecode(request.body)
            as Map<String, Object?>)['events']! as List)
          (event! as Map).cast<String, Object?>(),
    ];
