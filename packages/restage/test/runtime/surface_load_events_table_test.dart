import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../flow/flow_test_support.dart' as flows;
import '../surface_screen/surface_screen_test_support.dart';

/// Every mount kind reports the same load events for the same painted
/// outcome.
void main() {
  setUp(() {
    Restage.debugReset();
    Restage.registerWidgetLibrary(_layoutThrowLibrary, widgets: [
      RestageWidgetFactory(
          name: 'LayoutThrow', builder: (_, __) => const _LayoutThrow()),
      RestageWidgetFactory(
          name: 'PaintThrow', builder: (_, __) => const _PaintThrow()),
    ]);
  });
  tearDown(Restage.debugReset);

  final hosts = <_Host Function()>[
    _PaywallHost.new,
    _PlacementHost.new,
    _GeneratedHost.new,
    _ScreenHost.new,
    _FlowHost.new,
  ];

  // After its original was viewed, a rebound placement with nothing published
  // paints its error state, and its load fails.
  testWidgets('a placement rebound to nothing published reports what it paints',
      (tester) async {
    final host = _PlacementHost();
    Restage.configure(
      firstLaunchWait: const Duration(seconds: 1),
      freshWindow: const Duration(milliseconds: 100),
      resolver: host.globalResolver,
    );
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    await tester.pumpWidget(host.mount());
    await tester.pump(const Duration(milliseconds: 50));
    host.publishNothing();
    await _settle(tester);
    await tester.pumpWidget(host.mount(rebound: true));
    await _settle(tester);
    host.publishNothing();
    await _settle(tester);
    expect(find.text('Original'), findsNothing);
    expect([
      for (final event in events)
        if (event is SurfaceLoadStarted ||
            event is SurfaceLoadCompleted ||
            event is SurfaceLoadFailed)
          _describe(event),
    ], [
      'started',
      'completed original wait=false window=false',
      'started',
      'failed unavailable',
    ]);
  });

  for (final row in _Row.values) {
    group(row.label, () {
      for (final create in hosts) {
        final host = create();
        if (!host.supports(row)) continue;
        testWidgets(host.name, (tester) async {
          Restage.configure(
            firstLaunchWait: const Duration(seconds: 1),
            freshWindow: const Duration(milliseconds: 100),
            liveRefresh: row == _Row.deliveredAfterWait
                ? const {SurfaceRefreshTrigger.appResume}
                : const {},
            resolver: host.globalResolver,
          );
          final events = <RestageEvent>[];
          final subscription = Restage.events.listen(events.add);
          addTearDown(subscription.cancel);
          await row.drive(tester, host);
          if (row == _Row.renderFailure || row == _Row.paintFailure) {
            tester.takeException();
          }
          final loads = [
            for (final event in events)
              if (event is SurfaceLoadStarted ||
                  event is SurfaceLoadCompleted ||
                  event is SurfaceLoadFailed)
                event,
          ];
          expect(loads.map(_describe), row.expected);
          for (final event in loads) {
            if (event is SurfaceLoadFailed) {
              expect(event.detail, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
            }
            expect(event.surfaceType, host.surface);
            expect(event.analyticsProperties['restage_surface_type'],
                host.surface.wireName);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
      }
    });
  }
}

String _describe(RestageEvent event) => switch (event) {
      SurfaceLoadStarted() => 'started',
      SurfaceLoadCompleted(
        :final source,
        :final firstLaunchWaitPassed,
        :final freshWindowPassed,
      ) =>
        'completed ${source.wireName} '
            'wait=$firstLaunchWaitPassed window=$freshWindowPassed',
      SurfaceLoadFailed(:final reason) => 'failed ${reason.wireName}',
      _ => event.name,
    };

enum _Row {
  deliveredBeforeWait('delivered before the wait',
      ['started', 'completed delivered wait=false window=false']),
  nothingPublished('nothing published paints the original',
      ['started', 'completed original wait=false window=false']),
  deliveredAfterWait('delivered after the wait keeps one completion',
      ['started', 'completed original wait=true window=true']),
  saved('saved content within the fresh window',
      ['started', 'completed saved wait=false window=true']),
  nothingPaints('nothing can paint', ['started', 'failed unavailable']),
  renderFailure('delivered content that fails to render',
      ['started', 'failed render_error']),
  paintFailure('delivered content that fails while painting',
      ['started', 'failed render_error']),
  rebind('a rebind starts a new load', [
    'started',
    'completed delivered wait=false window=false',
    'started',
    'completed delivered wait=false window=false',
  ]),
  rebindAfterOriginal(
      'a rebind from the original reports what it then paints', [
    'started',
    'completed original wait=false window=false',
    'started',
    'completed delivered wait=false window=false',
  ]);

  const _Row(this.label, this.expected);

  final String label;
  final List<String> expected;

  Future<void> drive(WidgetTester tester, _Host host) async {
    switch (this) {
      case deliveredBeforeWait:
        await tester.pumpWidget(host.mount());
        await tester.pump(const Duration(milliseconds: 50));
        host.deliver();
        await _settle(tester);
      case nothingPublished:
        await tester.pumpWidget(host.mount());
        await tester.pump(const Duration(milliseconds: 50));
        host.publishNothing();
        await _settle(tester);
      case deliveredAfterWait:
        await tester.pumpWidget(host.mount());
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
        host.deliver();
        await _settle(tester);
      case saved:
        host.save();
        await tester.pumpWidget(host.mount());
        await tester.pump(const Duration(milliseconds: 100));
        await _settle(tester);
      case nothingPaints:
        await tester.pumpWidget(host.mount(original: false));
        await tester.pump(const Duration(milliseconds: 50));
        host.fail();
        await _settle(tester);
      case renderFailure:
        await tester.pumpWidget(host.mount(original: false));
        await tester.pump(const Duration(milliseconds: 50));
        host.deliverBroken();
        await _settle(tester);
      case paintFailure:
        await tester.pumpWidget(host.mount(original: false));
        await tester.pump(const Duration(milliseconds: 50));
        host.deliverBroken(widget: 'PaintThrow');
        await _settle(tester);
      case rebind || rebindAfterOriginal:
        await tester.pumpWidget(host.mount());
        await tester.pump(const Duration(milliseconds: 50));
        if (this == rebind) {
          host.deliver();
        } else {
          host.publishNothing();
        }
        await _settle(tester);
        await tester.pumpWidget(host.mount(rebound: true));
        await tester.pump(const Duration(milliseconds: 50));
        host.deliver();
        await _settle(tester);
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

abstract class _Host {
  String get name;
  Surface get surface;
  VariantResolver? get globalResolver => null;
  bool supports(_Row row) => true;
  Widget mount({bool original = true, bool rebound = false});
  void deliver();
  void publishNothing();
  void save();
  void fail();
  void deliverBroken({String widget = 'LayoutThrow'});
}

/// A raced resolver whose answers the test supplies, one per fetch.
mixin _Answers<T extends Object> on RacedSurfaceReporting<T>
    implements RacedSurfaceResolver<T> {
  final List<Completer<T?>> answers = [];
  T? local;

  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {}

  @override
  Future<T?> bestLocal(SurfaceStoreKey key) async => local;

  @override
  Future<T?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) {
    final answer = Completer<T?>();
    answers.add(answer);
    return answer.future;
  }

  void answer(T? value) => answers.last.complete(value);
  void refuse(Object error) => answers.last.completeError(error);
}

final class _PaywallResolver extends VariantResolver
    with
        RacedSurfaceReporting<ResolvedPaywallPayload>,
        _Answers<ResolvedPaywallPayload> {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      Future.error(StateError('raced resolvers are not resolved directly'));
}

ResolvedPaywallPayload _blob(String text, SurfaceResolutionSource source) =>
    labelSurfaceSource(
        BlobPaywallPayload(ResolvedVariant(
          bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
            import restage.core;
            widget Paywall = Text(text: "$text");
          '''))),
          surfaceVersion: text,
          paywallId: 'pro',
        )),
        source);

abstract class _PaywallLike extends _Host {
  _PaywallResolver resolver = _PaywallResolver();

  @override
  void deliver() =>
      resolver.answer(_blob('Fresh', SurfaceResolutionSource.fresh));

  @override
  void publishNothing() => resolver.answer(null);

  @override
  void save() =>
      resolver.local = _blob('Saved', SurfaceResolutionSource.holdLastGood);

  @override
  void fail() => resolver.refuse(const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable, message: 'offline'));

  @override
  void deliverBroken({String widget = 'LayoutThrow'}) =>
      resolver.answer(labelSurfaceSource(
          BlobPaywallPayload(ResolvedVariant(
            bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
            import acme.load_test;
            widget Paywall = $widget();
          '''))),
            surfaceVersion: 'broken',
            paywallId: 'pro',
          )),
          SurfaceResolutionSource.fresh));
}

final class _PaywallHost extends _PaywallLike {
  @override
  String get name => 'paywall';

  @override
  Surface get surface => Surface.paywall;

  // A paywall without a placement binding has nothing to rebind.
  @override
  bool supports(_Row row) =>
      row != _Row.rebind && row != _Row.rebindAfterOriginal;

  @override
  Widget mount({bool original = true, bool rebound = false}) => MaterialApp(
        home: RestagePaywall(
          id: 'pro',
          resolver: resolver,
          fallbackBuilder: original ? (_) => const Text('Original') : null,
        ),
      );
}

final class _PlacementHost extends _PaywallLike {
  @override
  String get name => 'placement';

  @override
  Surface get surface => Surface.message;

  @override
  VariantResolver get globalResolver => resolver;

  // A placement always has its fallback to paint.
  @override
  bool supports(_Row row) => row != _Row.nothingPaints;

  @override
  Widget mount({bool original = true, bool rebound = false}) => MaterialApp(
        home: RestagePlacement.forSurface(
          surfaceType: Surface.message,
          surfaceId: rebound ? 'welcome_again' : 'welcome_back',
          fallback: (_) => const Text('Original'),
        ),
      );
}

final class _GeneratedHost extends _PaywallLike {
  @override
  String get name => 'generated surface';

  @override
  Surface get surface => Surface.paywall;

  // A generated surface always has its compiled original to paint.
  @override
  bool supports(_Row row) => row != _Row.nothingPaints;

  @override
  Widget mount({bool original = true, bool rebound = false}) => MaterialApp(
        home: Scaffold(
          body: NativeOfferSurface(
            resolver: resolver,
            placement: rebound ? 'checkout' : null,
          ),
        ),
      );
}

final class _ScreenResolver
    with RacedSurfaceReporting<ResolvedSurfaceScreen>, _Answers
    implements SurfaceScreenResolver {
  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) => key.surfaceType == 'screen'
      ? Surface.general
      : Surface.fromWireName(key.surfaceType);

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) =>
      Future.error(StateError('raced resolvers are not resolved directly'));
}

final class _ScreenHost extends _Host {
  final fixture = stringScreenFixture(text: 'Screen');
  _ScreenResolver resolver = _ScreenResolver();

  @override
  String get name => 'screen';

  @override
  Surface get surface => fixture.ref.surface;

  @override
  Widget mount({bool original = true, bool rebound = false}) {
    // A new resolver is a new declaration for a screen.
    if (rebound) resolver = _ScreenResolver();
    return MaterialApp(
      home: RestageScreen<String>(
        screen: fixture.ref,
        resolver: resolver,
        unavailable: original
            ? SurfaceScreenUnavailablePolicy.fallback(
                builder: (_, __) => const Text('Original'))
            : const SurfaceScreenUnavailablePolicy.hide(),
      ),
    );
  }

  @override
  void deliver() => resolver.answer(
      labelSurfaceSource(fixture.hosted(), SurfaceResolutionSource.fresh));

  @override
  void publishNothing() => resolver.answer(null);

  @override
  void save() => resolver.local = labelSurfaceSource(
      fixture.bundled(), SurfaceResolutionSource.holdLastGood);

  @override
  void fail() => resolver.refuse(const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.missing, message: 'offline'));

  @override
  void deliverBroken({String widget = 'LayoutThrow'}) => resolver
      .answer(labelSurfaceSource(fixture.hosted(hostedBlob: rfwSourceBlob('''
import acme.load_test;

widget OnboardingScreen = $widget();
''')), SurfaceResolutionSource.fresh));
}

final class _FlowResolver
    with RacedSurfaceReporting<ResolvedFlow>, _Answers
    implements FlowResolver, ActiveArmFlowResolver {
  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));
}

final class _FlowHost extends _Host {
  _FlowResolver resolver = _FlowResolver();

  @override
  String get name => 'flow';

  @override
  Surface get surface => Surface.onboarding;

  ResolvedFlow _content(SurfaceResolutionSource source) =>
      labelSurfaceSource(nativeOfferFlowRef.compiled!.resolve(), source);

  @override
  Widget mount({bool original = true, bool rebound = false}) {
    if (rebound) resolver = _FlowResolver();
    return MaterialApp(
      home: original
          ? RestageOnboarding(
              flow: nativeOfferFlowRef,
              resolver: resolver,
              unavailable: FlowUnavailablePolicy.fallback(
                  builder: (_, __) => const Text('Original')),
            )
          : RestageOnboarding(
              flow: flows.firstRunFlowRef,
              resolver: resolver,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
    );
  }

  @override
  void deliver() => resolver.answer(_content(SurfaceResolutionSource.fresh));

  @override
  void publishNothing() => resolver.answer(null);

  @override
  void save() =>
      resolver.local = _content(SurfaceResolutionSource.holdLastGood);

  @override
  void fail() => resolver.refuse(const FlowUnavailableError(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'delivery_unavailable',
      message: 'offline'));

  @override
  void deliverBroken({String widget = 'LayoutThrow'}) {
    if (widget == 'LayoutThrow') {
      flows.registerThrowingWidget();
      resolver.answer(labelSurfaceSource(
          flows.throwingResolvedFlow(), SurfaceResolutionSource.fresh));
      return;
    }
    final blob = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import acme.load_test;
      widget OnboardingScreen = $widget();
    ''')));
    resolver.answer(labelSurfaceSource(
        flows.resolvedFlow(screenBlobs: {'welcome': blob}),
        SurfaceResolutionSource.fresh));
  }
}

const _layoutThrowLibrary = WidgetLibrary.custom('acme.load_test');

/// Builds, then throws while laying out its first frame.
final class _LayoutThrow extends LeafRenderObjectWidget {
  const _LayoutThrow();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLayoutThrow();
}

final class _RenderLayoutThrow extends RenderBox {
  @override
  void performLayout() => throw StateError('layout failed');
}

/// Lays out, then throws while painting its first frame.
final class _PaintThrow extends LeafRenderObjectWidget {
  const _PaintThrow();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPaintThrow();
}

final class _RenderPaintThrow extends RenderBox {
  @override
  void performLayout() => size = constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) =>
      throw StateError('paint failed');
}
