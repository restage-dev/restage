import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

/// A flow resolver whose served flow is mutable between resolves.
class _MutableFlowResolver implements FlowResolver {
  _MutableFlowResolver(this.flow);
  ResolvedFlow flow;
  int calls = 0;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    calls++;
    return this.flow;
  }
}

/// An ACTIVE-arm resolver whose served flow is mutable between resolves. The
/// active arm is what populates `resolvedVersion` on the lifecycle events (an
/// active-served doc whose version differs from the contract is a content OTA).
class _MutableActiveFlowResolver
    implements FlowResolver, ActiveArmFlowResolver {
  _MutableActiveFlowResolver(this.flow);
  ResolvedFlow flow;

  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async =>
      this.flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

/// A single-tap-to-complete first-run flow at a chosen active [version]
/// (differs from the contract version 1, so it surfaces as `resolvedVersion`).
/// The welcome screen fires `next`, which transitions straight to `done`.
ResolvedFlow _versionedTappableFlow(int version) {
  final welcome = screenBlob('Welcome', 'next');
  final document = FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    legacyTerminalResultPassthrough: true,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 0,
        contentHash: FlowContentHash.compute(welcome),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: {'welcome': welcome},
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    cacheHit: false,
  );
}

/// A flow whose document is valid but whose entry-screen bytes don't match the
/// artifact hash, so the controller fails at load time (the reachable "fresh
/// payload that fails to render" case for a live refresh).
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

Widget _host(FlowResolver resolver) => Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    );

void main() {
  setUp(Restage.debugReset);

  testWidgets('a pristine onboarding swaps to freshly-served content on reload',
      (tester) async {
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    resolver.flow = resolvedFlow(welcomeText: 'Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets(
      'a failed onboarding refresh keeps the current render and stays silent',
      (tester) async {
    var unavailableCalls = 0;
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, __) => const Text('FALLBACK'),
        ),
        onFlowUnavailable: (_) => unavailableCalls++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // A re-resolve that fails at controller load.
    resolver.flow = _brokenFlow('Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget); // current render kept
    expect(find.text('FALLBACK'), findsNothing); // no fail-closed UI
    expect(unavailableCalls, 0); // no host callback
  });

  testWidgets('a successful onboarding refresh shows no loading flash',
      (tester) async {
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    resolver.flow = resolvedFlow(welcomeText: 'Second');
    // Drive the refresh but pump only a single frame: the current screen must
    // stay visible while the pending controller loads (no blank/loading flash).
    unawaited(Restage.reloadSurfaces());
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a mid-flow onboarding does not swap (dirty gate)',
      (tester) async {
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();

    // Advance to the second screen — the flow now holds user-contributed state.
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    resolver.flow = resolvedFlow(welcomeText: 'Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    // Still on the mid-flow screen; the reload was gated out.
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets(
      'a live swap does not re-enter the funnel (no second FlowStarted)',
      (tester) async {
    final started = <FlowStarted>[];
    final sub = Restage.events.listen((e) {
      if (e is FlowStarted) started.add(e);
    });
    addTearDown(sub.cancel);
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    expect(started, hasLength(1)); // the mounted session's single start

    resolver.flow = resolvedFlow(welcomeText: 'Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget); // swap applied

    // The promoting FlowStarted is consumed as the promotion trigger, never
    // re-emitted — a live swap is a content change WITHIN the session, not a
    // new funnel entry. So still exactly one FlowStarted.
    expect(started, hasLength(1));
  });

  testWidgets(
      'a pristine live swap completes on the NEW version — FlowCompleted '
      'carries the swapped-to resolvedVersion, not the stale one',
      (tester) async {
    final completed = <FlowCompleted>[];
    final sub = Restage.events.listen((e) {
      if (e is FlowCompleted) completed.add(e);
    });
    addTearDown(sub.cancel);
    final resolver = _MutableActiveFlowResolver(_versionedTappableFlow(2));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    // Pristine live swap to the v3 content (promotes the fresh controller).
    resolver.flow = _versionedTappableFlow(3);
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    // Drive the now-promoted flow to completion.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    // Completion attribution rides the PROMOTED (fresh) controller: the session
    // finishes on the version the user actually ended on, not the pre-swap one.
    expect(completed, hasLength(1));
    expect(completed.single.resolvedVersion, 3);
  });

  testWidgets('a moved hosted stamp re-resolves onboarding', (tester) async {
    final resolver = _MutableFlowResolver(resolvedFlow(welcomeText: 'First'));
    var stampCalls = 0;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/sdk/v1/surface-stamp') {
          stampCalls++;
          return http.Response('{"version":2}', 200);
        }
        return http.Response('{"entitlements":[]}', 200);
      }),
    );
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: firstRunFlowRef,
        unavailable: FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();

    resolver.flow = resolvedFlow(welcomeText: 'Second');
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(stampCalls, 1);
    expect(resolver.calls, 2);
    expect(find.text('Second'), findsOneWidget);
  });
}
