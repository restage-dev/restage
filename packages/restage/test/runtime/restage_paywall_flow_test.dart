import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
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
// plus a skip -> end terminator. These tests drive and verify the runtime half:
// navigation follows the graph, custom events remain paywall-keyed, and
// reserved commerce events are inert.
// ---------------------------------------------------------------------------

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

Uint8List _contextScreenBlob({String marker = ''}) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      Text(text: data.context.label),
      Text(text: "$marker")
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the lowered 2-screen flow document: entry (pushes "plans" via
/// restageNav0, dismisses via skip) -> plans (a pushed paywall, on:{}).
FlowDocument _navFlowDocument({
  required Uint8List entryBytes,
  required Uint8List plansBytes,
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
      'plans': const ScreenFlowState(screen: 'plans', on: {}),
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

/// A flow-capable resolver returning a pre-resolved hosted flow payload with a
/// served version.
class _PublishedFlowResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _PublishedFlowResolver({this.publishedVersion});
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
  return _singleScreenResolvedFlowFromBlob(_screenBlob({text: 'noop'}));
}

ResolvedFlow _contextSingleScreenResolvedFlow({String marker = ''}) {
  return _singleScreenResolvedFlowFromBlob(_contextScreenBlob(marker: marker));
}

ResolvedFlow _singleScreenResolvedFlowFromBlob(Uint8List screen) {
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

  testWidgets('a flow-shaped paywall forwards context after controlled load',
      (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    var hostContext = <String, Object?>{'label': 'first'};
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: RestagePaywall(
                id: 'pro_upgrade',
                resolver: resolver,
                context: hostContext,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(resolver.responses, hasLength(1));

    hostContext['label'] = 'later';
    resolver.responses.single.complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(),
        paywallId: 'pro_upgrade',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('later'), findsNothing);

    updateHost(() => hostContext = <String, Object?>{'label': 'second'});
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a pending flow-shaped paywall retains its accepted context',
      (tester) async {
    final resolver = _ControlledFlowPayloadResolver();
    final hostContext = <String, Object?>{'label': 'accepted'};
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          context: hostContext,
        ),
      ),
    );
    await tester.pump();
    resolver.responses.single.complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(marker: 'Current content'),
        paywallId: 'pro_upgrade',
      ),
    );
    await tester.pumpAndSettle();

    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    expect(resolver.responses, hasLength(2));
    hostContext['label'] = 'later';
    resolver.responses[1].complete(
      FlowPaywallPayload(
        flow: _contextSingleScreenResolvedFlow(marker: 'Candidate content'),
        paywallId: 'pro_upgrade',
      ),
    );
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('Candidate content'), findsOneWidget);
    expect(find.text('accepted'), findsOneWidget);
    expect(find.text('later'), findsNothing);
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
    'the pushed screen, and ignores a reserved commerce event there',
    (tester) async {
      Restage.configure(apiKey: 'pk_test');

      final received = <RestageEvent>[];
      await _pumpFlowPaywall(tester, onEvent: received.add);

      expect(find.text('See plans'), findsOneWidget);
      expect(find.text('Buy'), findsNothing);

      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(find.text('Buy'), findsOneWidget);

      final beforeTap = received.length;
      await tester.tap(find.text('Buy'));
      await tester.pumpAndSettle();

      expect(received, hasLength(beforeTap));
      expect(find.text('Buy'), findsOneWidget);
    },
  );

  testWidgets('a flow-hosted paywall reports its published version',
      (tester) async {
    Restage.configure(apiKey: 'pk_test');

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _PublishedFlowResolver(publishedVersion: 7),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final viewed = received.whereType<PaywallViewed>().toList();
    expect(viewed, isNotEmpty,
        reason: 'a flow paywall must fire PaywallViewed');
    expect(viewed.first.publishedVersion, 7);
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
