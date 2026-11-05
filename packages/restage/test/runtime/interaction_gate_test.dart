import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/render_deadline.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart';

// A long list headed by [mark], as the root widget [root].
Uint8List _list(String root, String mark) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      widget $root = ListView(children: [
        Text(text: "$mark"),
        ${[
      for (var i = 0; i < 30; i++)
        'SizedBox(height: 100.0, child: Text(text: "row $i")),'
    ].join()}
      ]);
    ''')));

Widget _appList(String mark) => ListView(children: [
      Text(mark),
      for (var i = 0; i < 30; i++) SizedBox(height: 100, child: Text('row $i')),
    ]);

final class _Resolver implements VariantResolver {
  _Resolver(this.bytes, this.version);
  Uint8List bytes;
  int version;

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      ResolvedVariant(
        bytes: bytes,
        surfaceVersion: '$version',
        paywallId: id,
        paywallPublishedVersion: version,
      );
}

/// Serves nothing local and fresh content only when [late] completes.
final class _LateResolver extends VariantResolver
    with RacedSurfaceReporting<ResolvedPaywallPayload>
    implements RacedSurfaceResolver<ResolvedPaywallPayload> {
  final late = Completer<ResolvedPaywallPayload?>();

  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {}

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      Future.error(StateError('raced'));

  @override
  Future<ResolvedPaywallPayload?> bestLocal(SurfaceStoreKey key) async => null;

  @override
  Future<ResolvedPaywallPayload?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) =>
      late.future;
}

final class _FlowResolver implements FlowResolver {
  _FlowResolver(this.flow);
  ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

ResolvedFlow _flow(String mark) =>
    resolvedFlow(screenBlobs: {'welcome': _list('OnboardingScreen', mark)});

// A flow whose first screen fails to load, so the fallback shows.
ResolvedFlow _broken() {
  final good = _flow('broken');
  return ResolvedFlow(
    document: good.document,
    screenBlobs: {
      ...good.screenBlobs,
      'welcome': Uint8List.fromList(const [9, 9, 9, 9]),
    },
    cacheHit: false,
  );
}

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

Future<void> _drag(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -140),
      touchSlopY: 0);
  await tester.pumpAndSettle();
  expect(_offset(tester), 140);
}

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final dragged in [true, false]) {
    final outcome = dragged ? 'is held' : 'lands';
    final when = dragged ? 'after a drag' : 'untouched';

    testWidgets('interaction gate: a paywall swap $when $outcome',
        (tester) async {
      final resolver = _Resolver(_list('Paywall', 'v1'), 1);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RestagePaywall(id: 'p', resolver: resolver)),
      ));
      await tester.pumpAndSettle();
      if (dragged) await _drag(tester);
      resolver
        ..bytes = _list('Paywall', 'v2')
        ..version = 2;
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('v2', skipOffstage: false),
          dragged ? findsNothing : findsOneWidget);
      if (dragged) expect(_offset(tester), 140);
    });

    testWidgets('interaction gate: a flow swap $when $outcome', (tester) async {
      final resolver = _FlowResolver(_flow('v1'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestageOnboarding<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: resolver,
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (dragged) await _drag(tester);
      resolver.flow = _flow('v2');
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('v2', skipOffstage: false),
          dragged ? findsNothing : findsOneWidget);
      if (dragged) expect(_offset(tester), 140);
    });

    testWidgets('interaction gate: a late paywall design $when $outcome',
        (tester) async {
      final resolver = _LateResolver();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'p',
            resolver: resolver,
            liveRefresh: const {SurfaceRefreshTrigger.appResume},
            fallbackBuilder: (_) => _appList('fallback'),
          ),
        ),
      ));
      // Past the first-launch wait, so the compiled fallback shows.
      await tester.pump(RenderDeadline.defaultFirstLaunchWait);
      await tester.pump();
      expect(find.text('fallback'), findsOneWidget);
      if (dragged) await _drag(tester);
      resolver.late.complete(BlobPaywallPayload(ResolvedVariant(
        bytes: _list('Paywall', 'design'),
        surfaceVersion: '2',
        paywallId: 'p',
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('design', skipOffstage: false),
          dragged ? findsNothing : findsOneWidget);
      if (dragged) expect(_offset(tester), 140);
    });

    testWidgets('interaction gate: a flow fallback flip $when $outcome',
        (tester) async {
      final resolver = _FlowResolver(_broken());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestageOnboarding<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: resolver,
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, __) => _appList('fallback'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('fallback'), findsOneWidget);
      if (dragged) await _drag(tester);
      resolver.flow = _flow('design');
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('design', skipOffstage: false),
          dragged ? findsNothing : findsOneWidget);
      if (dragged) expect(_offset(tester), 140);
    });
  }

  testWidgets('interaction gate: a paywall swap after a tap is not held',
      (tester) async {
    final resolver = _Resolver(_list('Paywall', 'v1'), 1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RestagePaywall(id: 'p', resolver: resolver)),
    ));
    await tester.pumpAndSettle();
    // A tap builds no state a swap would lose.
    await tester.tap(find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    resolver
      ..bytes = _list('Paywall', 'v2')
      ..version = 2;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('v2', skipOffstage: false), findsOneWidget);
  });
}
