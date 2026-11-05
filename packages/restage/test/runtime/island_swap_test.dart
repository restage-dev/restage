import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:restage/restage.dart';
import 'package:restage/src/delivery/render_deadline.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart';

Uint8List _blob(String text) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import restage.material;
      import app.islands;
      widget Paywall = Column(children: [
        ElevatedButton(onPressed: event 'tap' { }, child: Text(text: "$text")),
        Keep(),
      ]);
    ''')));

Uint8List _screen(String text) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import app.islands;
      widget OnboardingScreen = Column(children: [
        GestureDetector(onTap: event "next" { }, child: Text(text: "$text")),
        Keep(),
      ]);
    ''')));

final class _FlowResolver implements FlowResolver {
  _FlowResolver(this.flow);
  ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

/// Serves nothing local and fresh content only when [fresh] completes.
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

Widget _keep(BuildContext context, DataSource source) =>
    RestageIslandScope.build('Keep', 'missing', context, source);

// The app's islands, installed as a generated mount installs them.
const _islands = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.islands'),
  widgets: [RestageWidgetFactory(name: 'Keep', builder: _keep)],
  islands: true,
);

var _starts = 0;

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    _starts++;
  }

  @override
  Widget build(BuildContext context) => Text('count $count');
}

// The app's own global key, held by the island.
final _held = GlobalKey();

Widget _scope(Object owner, Widget child, {bool held = true}) =>
    RestageIslandScope(
      owner: owner,
      builders: {
        'Keep': (context, source) => held
            ? KeyedSubtree(key: _held, child: const _Counter())
            : const _Counter(),
      },
      child: child,
    );

/// Pumps until [text] is built offstage, then checks nothing shows it yet.
Future<void> _expectOffstage(WidgetTester tester, String text) async {
  var built = false;
  for (var frame = 0; frame < 60 && !built; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    built = find.text(text, skipOffstage: false).evaluate().isNotEmpty;
  }
  expect(built, isTrue);
  expect(find.text(text), findsNothing);
}

void main() {
  setUp(() {
    Restage.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _starts = 0;
    const SurfaceVocabulary(libraries: [_islands]).addToInstalled();
  });

  Future<_Resolver> mount(
      WidgetTester tester, List<PaywallViewed> viewed) async {
    final resolver = _Resolver(_blob('A'), 1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _scope(
          resolver,
          RestagePaywall(
            id: 'p',
            resolver: resolver,
            onEvent: (event) {
              if (event is PaywallViewed) viewed.add(event);
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;
    resolver
      ..bytes = _blob('B')
      ..version = 2;
    return resolver;
  }

  testWidgets(
      'a staged refresh waits offstage, then keeps an island holding a '
      'global key and counts once', (tester) async {
    final viewed = <PaywallViewed>[];
    await mount(tester, viewed);
    expect(viewed, hasLength(1));

    await Restage.reloadSurfaces();
    // Built and laid out offstage: nothing shown or counted yet.
    await _expectOffstage(tester, 'B');
    expect(viewed, hasLength(1));

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(_Counter), findsOneWidget);
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    expect(_starts, 1);
    expect(viewed, hasLength(2));
    expect(viewed.last.publishedVersion, 2);
  });

  testWidgets(
      'a promoted refresh rejected at its first paint shows the last '
      'version again', (tester) async {
    await mount(tester, []);

    await Restage.reloadSurfaces();
    await _expectOffstage(tester, 'B');
    // Promoted after that frame; the user acts before its first paint.
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B', skipOffstage: false), findsNothing);
    expect(find.byType(_Counter), findsOneWidget);
  });

  testWidgets(
      'a library named like islands but not installed as them '
      'paints above the shown version', (tester) async {
    Restage.debugReset();
    Restage.registerWidgetLibrary(
      WidgetLibrary.custom('app.islands'),
      widgets: [RestageWidgetFactory(name: 'Keep', builder: _keep)],
    );
    await mount(tester, []);

    await Restage.reloadSurfaces();
    var built = false;
    for (var frame = 0; frame < 60 && !built; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      built = find.text('B', skipOffstage: false).evaluate().isNotEmpty;
    }
    // Its first frame already paints it.
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a refresh that may not replace what is shown stays offstage',
      (tester) async {
    final viewed = <PaywallViewed>[];
    await mount(tester, viewed);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    expect(viewed, hasLength(1));
  });

  testWidgets('a flow refresh waits offstage and keeps the island',
      (tester) async {
    final viewed = <OnboardingStepViewed>[];
    final sub = Restage.events.listen((event) {
      if (event is OnboardingStepViewed) viewed.add(event);
    });
    addTearDown(sub.cancel);
    final resolver = _FlowResolver(resolvedFlow(
      screenBlobs: {'welcome': _screen('A'), 'profile': _screen('P')},
    ));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: _scope(
        resolver,
        RestageOnboarding<FirstRunResult>(
          flow: firstRunFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;
    final before = viewed.length;

    resolver.flow = resolvedFlow(
      screenBlobs: {'welcome': _screen('B'), 'profile': _screen('P')},
    );
    await Restage.reloadSurfaces();
    await _expectOffstage(tester, 'B');
    expect(viewed, hasLength(before));

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    expect(_starts, 1);
  });

  testWidgets('a compiled fallback hands its keyed island to late content',
      (tester) async {
    final resolver = _LateResolver();
    late BuildContext owner;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          owner = context;
          return _scope(
            context,
            held: false,
            RestagePaywall(
              id: 'p',
              resolver: resolver,
              liveRefresh: const {SurfaceRefreshTrigger.appResume},
              fallbackBuilder: (_) =>
                  RestageIslandScope.keyed(owner, 'Keep', const _Counter()),
            ),
          );
        }),
      ),
    ));
    // Past the first-launch wait, so the compiled fallback shows.
    await tester.pump(RenderDeadline.defaultFirstLaunchWait);
    await tester.pump();
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;

    resolver.late.complete(BlobPaywallPayload(ResolvedVariant(
      bytes: _blob('B'),
      surfaceVersion: '2',
      paywallId: 'p',
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('B'), findsOneWidget);
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    expect(_starts, 1);
  });

  testWidgets('a looped island keeps its state from the fallback by position',
      (tester) async {
    _starts = 0;
    final resolver = _LateResolver();
    late BuildContext owner;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          owner = context;
          return _scope(
            context,
            held: false,
            RestagePaywall(
              id: 'p',
              resolver: resolver,
              liveRefresh: const {SurfaceRefreshTrigger.appResume},
              fallbackBuilder: (_) => Column(children: [
                for (final (position, _) in ['a', 'b', 'c'].indexed)
                  RestageIslandScope.keyed(owner, 'Keep', const _Counter(),
                      items: [position]),
              ]),
            ),
          );
        }),
      ),
    ));
    // Past the first-launch wait, so the compiled fallback shows.
    await tester.pump(RenderDeadline.defaultFirstLaunchWait);
    await tester.pump();
    tester.stateList<_CounterState>(find.byType(_Counter)).elementAt(1).count =
        7;

    resolver.late.complete(BlobPaywallPayload(ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
        import restage.core;
        import app.islands;
        widget Paywall = Column(children: [
          Text(text: "B"),
          ...for position in [0, 1, 2]: Keep(restageItems: [position]),
        ]);
      '''))),
      surfaceVersion: '2',
      paywallId: 'p',
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('B'), findsOneWidget);
    expect([
      for (final state
          in tester.stateList<_CounterState>(find.byType(_Counter)))
        state.count,
    ], [
      0,
      7,
      0
    ]);
    expect(_starts, 3);
  });
}
