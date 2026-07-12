import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:rfw/formats.dart';

import '../flow/flow_test_support.dart';

Uint8List _blob(String text) {
  final source = '''
    import restage.core;
    widget Paywall = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A blob whose single button fires a custom event when tapped.
Uint8List _tappableBlob(String text, String event) {
  final source = '''
    import restage.core;
    import restage.material;
    widget Paywall = ElevatedButton(
      onPressed: event '$event' { },
      child: Text(text: "$text"),
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A resolver whose served content is mutable between resolves and can be told
/// to throw on the next resolve (to exercise the silent-failure refresh path).
class _MutableResolver implements VariantResolver {
  _MutableResolver(this.bytes, {this.version, this.experimentId});

  Uint8List bytes;
  int? version;
  String? experimentId;
  bool throwNext = false;
  int calls = 0;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    calls++;
    if (throwNext) {
      throwNext = false;
      throw const RestagePaywallError(
        code: RestageErrorCodes.unknown,
        message: 'boom',
      );
    }
    return ResolvedVariant(
      bytes: bytes,
      paywallId: id,
      experimentId: experimentId,
      paywallPublishedVersion: version,
    );
  }
}

Future<void> _pump(WidgetTester tester, RestagePaywall paywall) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: paywall)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('reloadSurfaces swaps a clean paywall in place', (tester) async {
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('A'), findsOneWidget);

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets(
      'a blob live swap fires exactly one fresh PaywallViewed carrying the '
      'new published version', (tester) async {
    final viewed = <PaywallViewed>[];
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallViewed) viewed.add(e);
        },
      ),
    );
    expect(viewed.length, 1);
    expect(viewed.single.publishedVersion, 1);

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(find.text('B'), findsOneWidget);
    // Exactly one NEW impression, carrying the RENDERED version.
    expect(viewed.length, 2);
    expect(viewed.last.publishedVersion, 2);
  });

  testWidgets(
      'the fresh impression and load-completed fire together, once per '
      'applied swap', (tester) async {
    final events = <RestageEvent>[];
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(id: 'p', resolver: resolver, onEvent: events.add),
    );
    events.clear();

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    final completed = events.whereType<PaywallLoadCompleted>().toList();
    final viewed = events.whereType<PaywallViewed>().toList();
    expect(completed.length, 1); // the pair fires exactly once
    expect(viewed.length, 1);
    expect(viewed.single.publishedVersion, 2); // version == what rendered
  });

  testWidgets(
      'two sub-frame applies coalesce into one impression for the settled '
      'content (no frame pumped between the reloads)', (tester) async {
    final viewed = <PaywallViewed>[];
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallViewed) viewed.add(e);
        },
      ),
    );
    expect(viewed.length, 1);

    // Two applies with NO frame pumped between them: the first apply's impression
    // callback has not run yet when the second apply lands.
    resolver
      ..bytes = _blob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    resolver
      ..bytes = _blob('C')
      ..version = 3;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    // The intermediate B was never framed; exactly one fresh impression fires,
    // describing the SETTLED content C and its version, not one per apply.
    expect(find.text('C'), findsOneWidget);
    expect(viewed.length, 2); // initial + one coalesced settled impression
    expect(viewed.last.publishedVersion, 3);
  });

  testWidgets('a no-op (unchanged) refresh fires no fresh impression',
      (tester) async {
    final viewed = <PaywallViewed>[];
    final resolver = _MutableResolver(_blob('A'), version: 7);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallViewed) viewed.add(e);
        },
      ),
    );
    expect(viewed.length, 1);

    await Restage.reloadSurfaces(); // same version served
    await tester.pumpAndSettle();
    expect(viewed.length, 1); // no second impression
  });

  testWidgets('a deferred (experiment-arm) refresh fires no fresh impression',
      (tester) async {
    final viewed = <PaywallViewed>[];
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallViewed) viewed.add(e);
        },
      ),
    );
    expect(viewed.length, 1);

    resolver
      ..bytes = _blob('B')
      ..version = 2
      ..experimentId = 'exp1'; // enrolling arm → deferred, not applied
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget); // held
    expect(viewed.length, 1); // no impression for a deferred swap
  });

  testWidgets('unchanged content is not re-applied (no duplicate lifecycle)',
      (tester) async {
    final completed = <String>[];
    final resolver = _MutableResolver(_blob('A'), version: 7);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallLoadCompleted) completed.add('c');
        },
      ),
    );
    expect(completed.length, 1);

    // Same version served again — the surface skips the swap.
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(completed.length, 1); // no second completion
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a tapped (dirty) paywall does not live-swap', (tester) async {
    final tapped = <String>[];
    final resolver = _MutableResolver(_tappableBlob('A', 'poke'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallCustomEvent) tapped.add(e.name);
        },
      ),
    );
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(tapped, isNotEmpty); // interaction registered

    resolver
      ..bytes = _tappableBlob('B', 'poke')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget); // gate blocked the swap
    expect(find.text('B'), findsNothing);
  });

  testWidgets('a purchase in flight blocks the swap', (tester) async {
    final gate = Completer<PurchaseOutcome>();
    Restage.configure(
      apiKey: 'pk',
      products: const [
        RestageProduct(id: 'pro', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _CompleterGateway(gate),
    );
    final resolver = _MutableResolver(_buyBlob('A'), version: 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    await tester.tap(find.text('A'));
    await tester.pump(); // purchase now in flight (future unresolved)

    resolver
      ..bytes = _buyBlob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pump();
    expect(find.text('A'), findsOneWidget); // blocked while billing in flight

    gate.complete(PurchaseOutcome.cancelled(productId: 'pro'));
    await tester.pumpAndSettle();
  });

  testWidgets('an experiment-assigned render never live-swaps', (tester) async {
    final resolver =
        _MutableResolver(_blob('A'), version: 1, experimentId: 'exp1');
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('A'), findsOneWidget);

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget); // experiment lockout
    expect(find.text('B'), findsNothing);
  });

  testWidgets('a failed refresh keeps the current render and stays silent',
      (tester) async {
    final failures = <String>[];
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        onEvent: (e) {
          if (e is PaywallLoadFailed) failures.add(e.message);
        },
      ),
    );
    resolver.throwNext = true;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget); // held last good
    expect(failures, isEmpty); // never surfaced as an error
  });

  testWidgets(
      'a flow-shaped paywall re-hosts on reload without a spurious dismiss',
      (tester) async {
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    final events = <RestageEvent>[];
    await _pump(
      tester,
      RestagePaywall(id: 'p', resolver: resolver, onEvent: events.add),
    );
    expect(find.text('FlowA'), findsOneWidget);

    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowB')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowB'), findsOneWidget); // re-hosted in place
    // The clean re-host must not surface as the user dismissing the paywall.
    expect(events.whereType<PaywallDismissed>(), isEmpty);
  });

  testWidgets(
      'a failed flow refresh keeps the current flow render and stays silent',
      (tester) async {
    final events = <RestageEvent>[];
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        cacheLastRender: true,
        resolver: resolver,
        onEvent: events.add,
      ),
    );
    expect(find.text('FlowA'), findsOneWidget);
    events.clear();

    // A fresh flow that resolves fine but fails at controller load (its entry
    // screen's bytes don't match the artifact hash).
    resolver
      ..flow = _brokenFlow('FlowB')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    // Current render is untouched; the failure never surfaced.
    expect(find.text('FlowA'), findsOneWidget);
    expect(events.whereType<PaywallLoadFailed>(), isEmpty);
    expect(events.whereType<PaywallLoadStarted>(), isEmpty);
    expect(events.whereType<PaywallDismissed>(), isEmpty);
  });

  testWidgets(
      'after a failed flow refresh the rendered identity is unchanged '
      '(a re-serve of the original version is skipped as unchanged)',
      (tester) async {
    final events = <RestageEvent>[];
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(
      tester,
      RestagePaywall(id: 'p', resolver: resolver, onEvent: events.add),
    );
    resolver
      ..flow = _brokenFlow('FlowB')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    // Serve the ORIGINAL version again; if the failed refresh had corrupted the
    // rendered version to 2, this would attempt a re-host — it must be skipped.
    events.clear();
    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowC')
      ..version = 1;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowA'), findsOneWidget); // unchanged version => skipped
    expect(find.text('FlowC'), findsNothing);
  });

  testWidgets(
      'a successful flow refresh promotes without a duplicate '
      'load-completed or a dismiss', (tester) async {
    final events = <RestageEvent>[];
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(
      tester,
      RestagePaywall(id: 'p', resolver: resolver, onEvent: events.add),
    );
    expect(find.text('FlowA'), findsOneWidget);
    events.clear();

    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowB')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowB'), findsOneWidget);
    // A flow-shaped paywall does not re-announce its lifecycle on a live swap:
    // the promoted controller's suppressed flow lifecycle keeps the impression
    // (PaywallViewed) + load-completed one-shot for the mounted session, and it
    // never fires a dismiss. (Version-per-event rides the blob path; a flow
    // live-swap re-enters no funnel — see the onboarding FlowCompleted contract.)
    expect(events.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(events.whereType<PaywallViewed>(), isEmpty);
    expect(events.whereType<PaywallDismissed>(), isEmpty);
  });

  testWidgets('repeated flow refreshes each promote cleanly (no stale render)',
      (tester) async {
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('FlowA'), findsOneWidget);

    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowB')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowB'), findsOneWidget);
    expect(find.text('FlowA'), findsNothing);

    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowC')
      ..version = 3;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowC'), findsOneWidget);
    expect(find.text('FlowB'), findsNothing);
  });

  testWidgets(
      'a second reload while a flow refresh is in flight is a no-op '
      '(the registry guard holds through the resolve; the held refresh wins)',
      (tester) async {
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('FlowA'), findsOneWidget);

    // Park the first refresh inside its resolve: the per-handle guard stays
    // held for the whole `refresh()` future, which spans the resolve.
    final hold = Completer<void>();
    resolver
      ..hold = hold
      ..flow = resolvedFlow(welcomeText: 'FlowB')
      ..version = 2;
    final first =
        Restage.reloadSurfaces(); // parks on `hold`; _refreshing = true

    // A second reload arrives while the first is in flight — the guard drops it,
    // so FlowC is never even resolved.
    resolver
      ..hold = null
      ..flow = resolvedFlow(welcomeText: 'FlowC')
      ..version = 3;
    await Restage.reloadSurfaces(); // no-op under the guard
    await tester.pump();
    expect(find.text('FlowA'), findsOneWidget); // nothing swapped yet

    // Release the first: it promotes FlowB. FlowC never applied.
    hold.complete();
    await first;
    await tester.pumpAndSettle();
    expect(find.text('FlowB'), findsOneWidget); // the held refresh won
    expect(
        find.text('FlowC'), findsNothing); // the dropped reload never applied
  });

  testWidgets(
      'a flow->blob refresh renders the blob and tears down the old flow',
      (tester) async {
    final events = <RestageEvent>[];
    final resolver = _ShapeResolver.flow(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(
      tester,
      RestagePaywall(id: 'p', resolver: resolver, onEvent: events.add),
    );
    expect(find.text('FlowA'), findsOneWidget);
    events.clear();

    resolver.serveBlob(_blob('BlobB'), 2);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    // The blob is what renders — the stale flow must not keep showing.
    expect(find.text('BlobB'), findsOneWidget);
    expect(find.text('FlowA'), findsNothing);
  });

  testWidgets('a blob->flow refresh renders the flow and leaves no stale blob',
      (tester) async {
    final resolver = _ShapeResolver.blob(_blob('BlobA'), 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('BlobA'), findsOneWidget);

    resolver.serveFlow(resolvedFlow(welcomeText: 'FlowB'), 2);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowB'), findsOneWidget);
    expect(find.text('BlobA'), findsNothing);
  });

  testWidgets('a blob refresh into a new experiment arm is deferred',
      (tester) async {
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('A'), findsOneWidget);

    // The fresh resolution now carries an experiment arm — the surface must not
    // enroll a live view into an experiment; defer to remount.
    resolver
      ..bytes = _blob('B')
      ..version = 2
      ..experimentId = 'exp1';
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('a flow refresh into a new experiment arm is deferred',
      (tester) async {
    final resolver = _FlowResolver(resolvedFlow(welcomeText: 'FlowA'), 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));
    expect(find.text('FlowA'), findsOneWidget);

    resolver
      ..flow = resolvedFlow(welcomeText: 'FlowB')
      ..version = 2
      ..experimentId = 'exp1';
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('FlowA'), findsOneWidget);
    expect(find.text('FlowB'), findsNothing);
  });

  testWidgets('widget liveRefresh override wins over the global set',
      (tester) async {
    // Global opts every surface into appResume; the widget opts out with {}.
    Restage.configure(
      apiKey: 'pk',
      liveRefresh: const {SurfaceRefreshTrigger.appResume},
    );
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(
      tester,
      RestagePaywall(
        id: 'p',
        resolver: resolver,
        liveRefresh: const <SurfaceRefreshTrigger>{},
      ),
    );

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    // The resume sweep must skip this surface (empty effective triggers).
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);

    // But an explicit reload still applies (never gated by triggers).
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('matching hosted stamp skips a paywall content re-fetch',
      (tester) async {
    final resolver = _MutableResolver(_blob('A'), version: 7);
    var stampCalls = 0;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      resolver: resolver,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/sdk/v1/surface-stamp') {
          stampCalls++;
          return http.Response('{"version":7}', 200);
        }
        return http.Response('{"entitlements":[]}', 200);
      }),
    );
    await _pump(tester, const RestagePaywall(id: 'p'));
    expect(resolver.calls, 1);

    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(stampCalls, 1);
    expect(resolver.calls, 1);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('moved hosted stamp re-fetches paywall content', (tester) async {
    final resolver = _MutableResolver(_blob('A'), version: 7);
    var stampVersion = 7;
    var stampCalls = 0;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      resolver: resolver,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/sdk/v1/surface-stamp') {
          stampCalls++;
          return http.Response('{"version":$stampVersion}', 200);
        }
        return http.Response('{"entitlements":[]}', 200);
      }),
    );
    await _pump(tester, const RestagePaywall(id: 'p'));

    stampVersion = 8;
    resolver
      ..bytes = _blob('B')
      ..version = 8;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(stampCalls, 1);
    expect(resolver.calls, 2);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('app resume refreshes an opted-in paywall', (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      liveRefresh: const {SurfaceRefreshTrigger.appResume},
    );
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('app resume leaves an opted-out paywall unchanged',
      (tester) async {
    Restage.configure(apiKey: 'rs_pk_test');
    final resolver = _MutableResolver(_blob('A'), version: 1);
    await _pump(tester, RestagePaywall(id: 'p', resolver: resolver));

    resolver
      ..bytes = _blob('B')
      ..version = 2;
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });
}

Uint8List _buyBlob(String text) {
  final source = '''
    import restage.core;
    import restage.material;
    widget Paywall = ElevatedButton(
      onPressed: event 'restage.purchase' { slot: "primary" },
      child: Text(text: "$text"),
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A flow whose document is valid but whose entry-screen bytes don't match the
/// artifact content hash, so the controller fails at load time (after the
/// resolver already returned it) — the reachable "fresh payload that fails to
/// render" case for a live refresh.
ResolvedFlow _brokenFlow(String welcomeText) {
  final good = resolvedFlow(welcomeText: welcomeText);
  return ResolvedFlow(
    document: good.document,
    screenBlobs: {
      for (final entry in good.screenBlobs.entries)
        entry.key: entry.key == good.document.initial
            ? Uint8List.fromList(const [9, 9, 9, 9])
            : entry.value,
    },
    cacheHit: false,
  );
}

/// A flow-capable resolver serving a mutable flow-shaped paywall payload. When
/// [hold] is set, [resolvePayload] parks on it — letting a test keep one refresh
/// in flight while it fires a second. The served flow/version are captured at
/// call time so a mutation for a later call can't leak into a parked one.
class _FlowResolver implements VariantResolver, FlowCapableVariantResolver {
  _FlowResolver(this.flow, this.version);
  ResolvedFlow flow;
  int version;
  String? experimentId;
  Completer<void>? hold;

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
    final gate = hold;
    final servedFlow = flow;
    final servedVersion = version;
    final servedExperiment = experimentId;
    if (gate != null) await gate.future;
    return FlowPaywallPayload(
      flow: servedFlow,
      paywallId: id,
      paywallPublishedVersion: servedVersion,
      experimentId: servedExperiment,
    );
  }
}

/// A flow-capable resolver that can serve EITHER a blob or a flow payload,
/// switchable between resolves — for delivery-mode-change refresh tests.
class _ShapeResolver implements VariantResolver, FlowCapableVariantResolver {
  _ShapeResolver.blob(Uint8List bytes, this.version) : _bytes = bytes;
  _ShapeResolver.flow(ResolvedFlow flow, this.version) : _flow = flow;

  Uint8List? _bytes;
  ResolvedFlow? _flow;
  int version;
  String? experimentId;

  void serveBlob(Uint8List bytes, int v) {
    _bytes = bytes;
    _flow = null;
    version = v;
  }

  void serveFlow(ResolvedFlow flow, int v) {
    _flow = flow;
    _bytes = null;
    version = v;
  }

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
    final flow = _flow;
    if (flow != null) {
      return FlowPaywallPayload(
        flow: flow,
        paywallId: id,
        paywallPublishedVersion: version,
        experimentId: experimentId,
      );
    }
    return BlobPaywallPayload(
      ResolvedVariant(
        bytes: _bytes!,
        paywallId: id,
        paywallPublishedVersion: version,
        experimentId: experimentId,
      ),
    );
  }
}

class _CompleterGateway implements BillingGateway {
  _CompleterGateway(this._gate);
  final Completer<PurchaseOutcome> _gate;

  @override
  Future<PurchaseOutcome> purchase(String productId, {String? basePlanId}) =>
      _gate.future;

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}
