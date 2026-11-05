import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;

import 'flow_test_support.dart';

Uint8List _screen(String event) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import app.islands;
      widget OnboardingScreen = Column(children: [
        GestureDetector(onTap: event "$event" { }, child: Text(text: data.context._hTitle)),
        Keep(),
      ]);
    ''')));

class _Step extends StatelessWidget {
  const _Step(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(title);
}

final _owner = Object();

Uint8List _blob(String body) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(body)));

var _heldStarts = 0;
var _heldMoves = 0;

Widget _heldMount(BuildContext context, Widget child, Widget original) =>
    _Held(original: original as _Step, child: child);

// A step mount that holds State, as a generated one for a stateful step does.
class _Held extends StatefulWidget {
  const _Held({required this.original, required this.child});
  final _Step original;
  final Widget child;
  @override
  State<_Held> createState() => _HeldState();
}

class _HeldState extends State<_Held> {
  @override
  void initState() {
    super.initState();
    _heldStarts++;
  }

  @override
  void activate() {
    super.activate();
    _heldMoves++;
  }

  @override
  Widget build(BuildContext context) => RestageStepValues(
        values: {'_hTitle': widget.original.title},
        built: widget.original,
        child: widget.child,
      );
}

final class _Mutable implements FlowResolver {
  _Mutable(this.flow);
  ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

Widget _keep(BuildContext context, DataSource source) =>
    RestageIslandScope.build('Keep', 'missing', context, source);

const _islands = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.islands'),
  widgets: [RestageWidgetFactory(name: 'Keep', builder: _keep)],
  islands: true,
);

Widget _mount(BuildContext context, Widget child, Widget original) =>
    RestageIslandScope(
      owner: RestageIslandScope.hostOf(context) ?? _owner,
      builders: {'Keep': (context, source) => const Text('island')},
      child: RestageStepValues(
        values: {'_hTitle': (original as _Step).title},
        child: child,
      ),
    );

/// Serves [flow] as the active version, which may be newer than the app's.
final class _ActiveResolver implements FlowResolver, ActiveArmFlowResolver {
  _ActiveResolver(this.flow);
  final ResolvedFlow flow;

  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> ref) async =>
      flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> ref) async => flow;
}

void main() {
  // Nothing is registered up front: the flow installs the step's islands.
  setUp(Restage.debugReset);

  for (final (name, mounts, bound, served, outcome) in [
    (
      'a step mount supplies its values and islands',
      {'welcome': _mount},
      true,
      1,
      'shown'
    ),
    (
      'a served version newer than the compiled one keeps its step mounts',
      {'welcome': _mount},
      true,
      2,
      'shown'
    ),
    (
      'delivered content that needs a mount fails without it',
      <String, RestageStepMount>{},
      true,
      1,
      'fails'
    ),
    (
      'a step mount without a bound step builder makes the flow unavailable',
      {'welcome': _mount},
      false,
      1,
      'unavailable'
    ),
  ]) {
    testWidgets(name, (tester) async {
      final base = resolvedFlow(
        screenBlobs: {'welcome': _screen('next'), 'profile': _screen('finish')},
      );
      final json = FlowDocumentCodec.encodeCanonicalJson(base.document);
      final delivered = ResolvedFlow(
        document: FlowDocumentCodec.decodeJson(jsonEncode(
          {...jsonDecode(utf8.decode(json)) as Map, 'version': served},
        )),
        screenBlobs: base.screenBlobs,
        cacheHit: false,
      );
      var builds = 0;
      final unavailable = <FlowUnavailableError>[];
      final ref = OnboardingFlowRef<FirstRunResult>(
        id: firstRunFlowRef.id,
        version: firstRunFlowRef.version,
        minClient: firstRunFlowRef.minClient,
        surface: firstRunFlowRef.surface,
        decodeResult: firstRunFlowRef.decodeResult,
        vocabulary: SurfaceVocabulary(
          stepMounts: mounts,
          libraries: [if (mounts.isNotEmpty) _islands],
        ),
        compiled: CompiledFlow(
          documentJson: utf8.decode(json),
          screens: {
            if (bound)
              'welcome': () {
                builds++;
                return const _Step('Hello');
              },
            'profile': () => const _Step('Profile'),
          },
        ),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageOnboarding<FirstRunResult>(
          flow: ref,
          resolver: _ActiveResolver(delivered),
          unavailable: const FlowUnavailablePolicy.hide(),
          onFlowUnavailable: unavailable.add,
        ),
      ));
      await tester.pumpAndSettle();
      final shown = outcome == 'shown';
      expect(tester.takeException(), outcome == 'fails' ? isNotNull : isNull);
      expect(find.text('Hello'), shown ? findsOneWidget : findsNothing);
      expect(find.text('island'), shown ? findsOneWidget : findsNothing);
      expect(builds > 0, shown);
      expect(unavailable, hasLength(shown ? 0 : 1));
      if (outcome == 'unavailable') {
        expect(unavailable.single.reason, 'missing_screen_builder');
        // A reference with no generated widget says how to bind the step.
        expect(
          unavailable.single.message,
          "Step `'welcome'` can't render. Try binding its screen builder "
          'with `withScreenBuilders`.',
        );
      }
    });
  }

  testWidgets(
      'two hosts or bare views showing one step each keep their own island',
      (tester) async {
    final delivered = resolvedFlow(
      screenBlobs: {'welcome': _screen('next'), 'profile': _screen('finish')},
    );
    final ref = OnboardingFlowRef<FirstRunResult>(
      id: firstRunFlowRef.id,
      version: firstRunFlowRef.version,
      minClient: firstRunFlowRef.minClient,
      surface: firstRunFlowRef.surface,
      decodeResult: firstRunFlowRef.decodeResult,
      vocabulary: const SurfaceVocabulary(
        stepMounts: {'welcome': _mount},
        libraries: [_islands],
      ),
      compiled: CompiledFlow(
        documentJson: utf8.decode(
          FlowDocumentCodec.encodeCanonicalJson(delivered.document),
        ),
        screens: {
          'welcome': () => const _Step('Hello'),
          'profile': () => const _Step('Profile'),
        },
      ),
    );
    RestageFlowController<FirstRunResult> controller() =>
        RestageFlowController<FirstRunResult>(
          flow: ref,
          resolver: StaticFlowResolver(delivered),
          actions: null,
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        )..load();
    // One controller shown by two views, as across a route transition.
    final shared = controller();
    for (final host in ['onboarding', 'view', 'shared view']) {
      Widget host_() => Expanded(
            child: host != 'onboarding'
                ? RestageFlowView<FirstRunResult>(
                    controller: host == 'view' ? controller() : shared,
                  )
                : RestageOnboarding<FirstRunResult>(
                    flow: ref,
                    resolver: StaticFlowResolver(delivered),
                    unavailable: const FlowUnavailablePolicy.hide(),
                  ),
          );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(key: ValueKey(host), children: [host_(), host_()]),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: host);
      expect(find.text('island'), findsNWidgets(2), reason: host);
    }
  });

  testWidgets('a step version whose body throws is rejected offstage',
      (tester) async {
    _heldStarts = 0;
    _heldMoves = 0;
    registerThrowingWidget();
    final shown = resolvedFlow(screenBlobs: {
      'welcome': _blob('''
        import restage.core;
        widget OnboardingScreen = GestureDetector(
          onTap: event "next" { }, child: Text(text: data.context._hTitle));
      '''),
    });
    final ref = OnboardingFlowRef<FirstRunResult>(
      id: firstRunFlowRef.id,
      version: firstRunFlowRef.version,
      minClient: firstRunFlowRef.minClient,
      surface: firstRunFlowRef.surface,
      decodeResult: firstRunFlowRef.decodeResult,
      vocabulary: const SurfaceVocabulary(stepMounts: {'welcome': _heldMount}),
      compiled: CompiledFlow(
        documentJson: utf8.decode(
          FlowDocumentCodec.encodeCanonicalJson(shown.document),
        ),
        screens: {
          'welcome': () => const _Step('Hello'),
          'profile': () => const _Step('Profile'),
        },
      ),
    );
    final resolver = _Mutable(shown);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: ref,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    final state = tester.state(find.byType(_Held));

    resolver.flow = resolvedFlow(screenBlobs: {
      'welcome': _blob('''
        import restage.core;
        import acme.throwing;
        widget OnboardingScreen = Column(children: [
          Text(text: data.context._hTitle), Text(text: "New"), ThrowingWidget(),
        ]);
      '''),
    });
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNotNull);
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('New', skipOffstage: false), findsNothing);
    expect(tester.state(find.byType(_Held)), same(state));
    expect(_heldStarts, 1);
    // Rejected before it was shown: the step never moved to it.
    expect(_heldMoves, 0);
  });

  testWidgets('a step visited twice keeps an island per visit', (tester) async {
    final delivered = resolvedFlow(
      screenBlobs: {
        'welcome': _screen('next'),
        'profile': screenBlob('Profile', 'back'),
      },
      states: {
        'welcome': const ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('profile')},
        ),
        'profile': const ScreenFlowState(
          screen: 'profile',
          on: {
            'back': FlowTransition.goto('welcome'),
            'finish': FlowTransition.goto('done'),
          },
        ),
        'done': const EndFlowState(result: {'completed': true}),
      },
    );
    final ref = OnboardingFlowRef<FirstRunResult>(
      id: firstRunFlowRef.id,
      version: firstRunFlowRef.version,
      minClient: firstRunFlowRef.minClient,
      surface: firstRunFlowRef.surface,
      decodeResult: firstRunFlowRef.decodeResult,
      vocabulary: const SurfaceVocabulary(
        stepMounts: {'welcome': _mount},
        libraries: [_islands],
      ),
      compiled: CompiledFlow(
        documentJson: utf8.decode(
          FlowDocumentCodec.encodeCanonicalJson(delivered.document),
        ),
        screens: {
          'welcome': () => const _Step('Hello'),
          'profile': () => const _Step('Profile'),
        },
      ),
    );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: ref,
        resolver: StaticFlowResolver(delivered),
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('island', skipOffstage: false), findsNWidgets(2));
  });

  for (final host in [
    'RestageOnboarding',
    'RestageFlowGraph',
    'RestageFlowController',
  ]) {
    testWidgets('an unbound step under $host says how to bind it',
        (tester) async {
      final delivered = resolvedFlow(
        screenBlobs: {'welcome': _screen('next'), 'profile': _screen('finish')},
      );
      final ref = OnboardingFlowRef<FirstRunResult>(
        id: firstRunFlowRef.id,
        version: firstRunFlowRef.version,
        minClient: firstRunFlowRef.minClient,
        surface: firstRunFlowRef.surface,
        decodeResult: firstRunFlowRef.decodeResult,
        vocabulary: const SurfaceVocabulary(
          stepMounts: {'welcome': _mount},
          libraries: [_islands],
        ),
        compiled: CompiledFlow(
          documentJson: utf8.decode(
            FlowDocumentCodec.encodeCanonicalJson(delivered.document),
          ),
          screens: const {},
        ),
        surfaceWidget: 'FirstRunSurface',
      );
      final unavailable = <FlowUnavailableError>[];
      const policy = FlowUnavailablePolicy.hide();
      final resolver = StaticFlowResolver(delivered);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: switch (host) {
          'RestageOnboarding' => RestageOnboarding<FirstRunResult>(
              flow: ref,
              resolver: resolver,
              unavailable: policy,
              onFlowUnavailable: unavailable.add,
            ),
          'RestageFlowGraph' => RestageFlowGraph<FirstRunResult>(
              flow: ref,
              resolver: resolver,
              unavailable: policy,
              onFlowUnavailable: unavailable.add,
            ),
          _ => RestageFlowView<FirstRunResult>(
              controller: RestageFlowController<FirstRunResult>(
                flow: ref,
                resolver: resolver,
                actions: null,
                onEvent: (_) {},
                onComplete: (_) {},
                onUnavailable: unavailable.add,
              )..load(),
            ),
        },
      ));
      await tester.pumpAndSettle();
      // An app that drives the controller itself binds the builder.
      expect(
        unavailable.single.message,
        host == 'RestageFlowController'
            ? "Step `'welcome'` can't render. Try binding its screen "
                'builder with `withScreenBuilders`.'
            : "Step `'welcome'` can't render. Try replacing `$host(...)` "
                'with `FirstRunSurface(...)`.',
      );
    });
  }
}
