import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/runtime/surface_unavailable_policy.dart'
    show
        SurfaceUnavailablePolicy,
        SurfaceUnavailableView,
        surfaceUnavailableBuilder,
        surfaceUnavailableUsesCompiledOriginal,
        surfaceUnavailableView;
import 'package:restage_shared/restage_shared.dart'
    show
        FlowHostBoundaryV1,
        ScreenArtifact,
        SurfaceContentKindV1,
        SurfaceHostContractV1,
        SurfaceHostingV1,
        SurfacePresentationV1,
        SurfaceScreenEventSchema,
        SurfaceScreenHostDataSchema;
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart' show RemoteWidget;

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../flow/flow_test_support.dart' as flows;
import '../surface_screen/surface_screen_test_support.dart';

/// Every host chooses between its original, its error builder and nothing
/// the same way when a load fails.
void main() {
  setUp(() {
    Restage.debugReset();
    _trip.value = false;
    Restage.registerWidgetLibrary(_library, widgets: [
      RestageWidgetFactory(name: 'Tripwire', builder: (_, __) => _Tripwire()),
    ]);
  });
  tearDown(Restage.debugReset);

  group('surfaceUnavailableView', () {
    Widget original(BuildContext _) => const Text('Original');
    Widget error(BuildContext _, Object __) => const Text('Error');

    test('shows the fallback until the load advanced', () {
      final policy = SurfaceUnavailablePolicy<Object>(
          fallbackBuilder: original, errorBuilder: error);
      expect(surfaceUnavailableView(policy, advanced: false),
          SurfaceUnavailableView.original);
      expect(surfaceUnavailableView(policy, advanced: true),
          SurfaceUnavailableView.error);
      expect(surfaceUnavailableBuilder(policy, advanced: true), same(error));
      expect(surfaceUnavailableUsesCompiledOriginal(policy), isFalse);
    });

    test('shows the fallback after progress without an error builder', () {
      final policy =
          SurfaceUnavailablePolicy<Object>(fallbackBuilder: original);
      for (final advanced in [false, true]) {
        expect(surfaceUnavailableView(policy, advanced: advanced),
            SurfaceUnavailableView.original);
        expect(
            surfaceUnavailableBuilder(policy, advanced: advanced), isNotNull);
      }
    });

    test('an error builder with nothing below it shows before progress', () {
      final policy = SurfaceUnavailablePolicy<Object>(errorBuilder: error);
      for (final advanced in [false, true]) {
        expect(surfaceUnavailableView(policy, advanced: advanced),
            SurfaceUnavailableView.error);
        expect(
            surfaceUnavailableBuilder(policy, advanced: advanced), same(error));
      }
      expect(surfaceUnavailableUsesCompiledOriginal(policy), isTrue);
    });

    test('an error builder above a compiled original waits for progress', () {
      final policy = SurfaceUnavailablePolicy<Object>(errorBuilder: error);
      expect(surfaceUnavailableView(policy, advanced: false, hasOriginal: true),
          SurfaceUnavailableView.nothing);
      expect(surfaceUnavailableView(policy, advanced: true, hasOriginal: true),
          SurfaceUnavailableView.error);
    });

    test('nothing at all shows nothing', () {
      final policy = SurfaceUnavailablePolicy<Object>();
      for (final advanced in [false, true]) {
        expect(surfaceUnavailableView(policy, advanced: advanced),
            SurfaceUnavailableView.nothing);
        expect(surfaceUnavailableBuilder(policy, advanced: advanced), isNull);
      }
    });
  });

  group('a generated paywall mount', () {
    Widget error(BuildContext _, RestagePaywallError __) => const Text('Error');
    Widget replacement(BuildContext _) => const Text('Replacement');

    Future<RestagePaywall> hostOf(WidgetTester tester,
        {WidgetBuilder? fallbackBuilder,
        Widget Function(BuildContext, RestagePaywallError)?
            errorBuilder}) async {
      await tester.pumpWidget(MaterialApp(
          home: NativeOfferSurface(
              resolver: _GatedPaywall(),
              fallbackBuilder: fallbackBuilder,
              errorBuilder: errorBuilder)));
      final host = tester.widget<RestagePaywall>(find.byType(RestagePaywall));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      return host;
    }

    testWidgets('falls back to its compiled original', (tester) async {
      final host = await hostOf(tester, errorBuilder: error);
      expect(host.errorBuilder, same(error));
      final original =
          host.fallbackBuilder!(tester.element(find.byType(SizedBox)));
      expect(original, isA<NativeOffer>());
    });

    testWidgets('passes a fallback builder through', (tester) async {
      final host = await hostOf(tester, fallbackBuilder: replacement);
      expect(host.fallbackBuilder, same(replacement));
      expect(host.errorBuilder, isNull);
    });
  });

  group('a generated screen mount', () {
    Widget error(BuildContext _, SurfaceScreenUnavailableError __) =>
        const Text('Error');
    Widget replacement(BuildContext _) => const Text('Replacement');

    Future<RestageScreen<Never>> hostOf(WidgetTester tester,
        {WidgetBuilder? fallbackBuilder,
        Widget Function(BuildContext, SurfaceScreenUnavailableError)?
            errorBuilder}) async {
      await tester.pumpWidget(MaterialApp(
          home: NativeNoticeSurface('Notice original', 3, null, null, null,
              null, null, fallbackBuilder, errorBuilder)));
      final host = tester
          .widget<RestageScreen<Never>>(find.byType(RestageScreen<Never>));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      return host;
    }

    testWidgets('falls back to its compiled original', (tester) async {
      final host = await hostOf(tester, errorBuilder: error);
      expect(host.errorBuilder, same(error));
      final original =
          host.fallbackBuilder!(tester.element(find.byType(SizedBox)));
      expect((original as NativeNotice).title, 'Notice original');
    });

    testWidgets('passes a fallback builder through', (tester) async {
      final host = await hostOf(tester, fallbackBuilder: replacement);
      expect(host.fallbackBuilder, same(replacement));
      expect(host.errorBuilder, isNull);
    });
  });

  for (final create in <_Case Function()>[
    _PaywallCase.new,
    _PlacementCase.new,
    _ScreenCase.new,
    _FlowCase.new,
    _OnboardingCase.new,
  ]) {
    group(create().name, () {
      void hostTest(String description,
              Future<void> Function(WidgetTester, _Case) body) =>
          testWidgets(description, (tester) => body(tester, create()));

      hostTest('a failure before progress shows the original',
          (tester, host) async {
        await _show(tester, host, _Policy.originalAndError);
        await _failNow(tester);
        expect(find.text('Original'), findsOneWidget);
        expect(find.text('Error'), findsNothing);
      });

      hostTest('a failure after the user interacts shows the error builder',
          (tester, host) async {
        await _show(tester, host, _Policy.originalAndError);
        await _drag(tester, find.byType(_Tripwire));
        await _failNow(tester);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Original'), findsNothing);
      });

      hostTest('a failure after a handler ran shows the error builder',
          (tester, host) async {
        await _show(tester, host, _Policy.originalAndError);
        await host.runHandler(tester);
        await _failNow(tester);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Original'), findsNothing);
      });

      hostTest(
          'a failure after progress shows the original without an error '
          'builder', (tester, host) async {
        await _show(tester, host, _Policy.originalOnly);
        await _drag(tester, find.byType(_Tripwire));
        await _failNow(tester);
        expect(find.text('Original'), findsOneWidget);
      });

      hostTest('changed builders apply to a failed load at once',
          (tester, host) async {
        Future<void> pump(_Policy policy) async {
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: host.mount(
                      policy: policy,
                      load: 0,
                      failAfter: Future<void>.value()))));
          await _settle(tester);
        }

        await pump(_Policy.originalOnly);
        expect(find.text('Original'), findsOneWidget);
        await pump(_Policy.none);
        expect(tester.takeException(), isNull);
        expect(find.text('Original'), findsNothing);
        await pump(_Policy.originalOnly);
        expect(tester.takeException(), isNull);
        expect(find.text('Original'), findsOneWidget);
      });

      for (final policy in _throwingBuilders) {
        hostTest(
            '${policy.name}: shows nothing, fails the load and is reported '
            'once', (tester, host) async {
          final events = <RestageEvent>[];
          final subscription = Restage.events.listen(events.add);
          addTearDown(subscription.cancel);
          final mounted = host.mount(
              policy: policy, load: 0, failAfter: Future<void>.value());
          Future<void> pump(Brightness brightness) async {
            await tester.pumpWidget(MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Scaffold(body: mounted)));
            await _settle(tester);
          }

          await pump(Brightness.light);
          // One report: a second would surface as a combined failure.
          expect(tester.takeException(), isA<StateError>());
          // Rebuilding the host does not build the broken widget again.
          await pump(Brightness.dark);
          await pump(Brightness.light);
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          expect(
              events
                  .where((e) =>
                      e is SurfaceLoadCompleted || e is SurfaceLoadFailed)
                  .map((e) => e is SurfaceLoadFailed ? e.reason : 'completed'),
              [SurfaceLoadFailureReason.renderError]);
        });
      }

      hostTest('a new load shows its fallback widget again after one threw',
          (tester, host) async {
        Future<void> pump(_Policy policy, int load) async {
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: host.mount(
                      policy: policy,
                      load: load,
                      failAfter: Future<void>.value()))));
          await _settle(tester);
          tester.takeException();
        }

        await pump(_Policy.throwing, 0);
        expect(find.text('Original'), findsNothing);
        await pump(_Policy.originalOnly, 1);
        expect(find.text('Original'), findsOneWidget);
      });

      hostTest('with only an error builder, a failure before progress shows it',
          (tester, host) async {
        await _show(tester, host, _Policy.errorOnly);
        await _failNow(tester);
        expect(find.text('Error'), findsOneWidget);
      });

      hostTest('with only an error builder, a failed fetch shows it',
          (tester, host) async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: host.mount(
                    policy: _Policy.errorOnly,
                    load: 0,
                    failAfter: Future<void>.value()))));
        await _settle(tester);
        expect(find.text('Error'), findsOneWidget);
      });

      hostTest('no fallback builder shows nothing', (tester, host) async {
        await _show(tester, host, _Policy.none);
        await _drag(tester, find.byType(_Tripwire));
        await _failNow(tester);
        expect(find.byType(_Tripwire), findsNothing);
        expect(find.text('Original'), findsNothing);
        expect(find.text('Error'), findsNothing);
      });

      hostTest('a rebind starts unadvanced, like a first mount',
          (tester, host) async {
        await _show(tester, host, _Policy.originalAndError);
        await _drag(tester, find.byType(_Tripwire));
        await _failNow(tester);
        expect(find.text('Error'), findsOneWidget);
        _trip.value = false;
        await _show(tester, host, _Policy.originalAndError, load: 1);
        await _failNow(tester);
        expect(find.text('Original'), findsOneWidget);
        expect(find.text('Error'), findsNothing);
      });

      hostTest(
          'a load that fails after the user touched its loading state shows '
          'the error builder', (tester, host) async {
        final events = <RestageEvent>[];
        final subscription = Restage.events.listen(events.add);
        addTearDown(subscription.cancel);
        final gate = Completer<void>();
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: host.mount(
                    policy: _Policy.originalAndError,
                    load: 0,
                    failAfter: gate.future))));
        await tester.pump();
        await _drag(tester, find.byKey(_loading));
        gate.complete();
        await _settle(tester);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Original'), findsNothing);
        // The error builder is a failed load, not the original.
        expect(events.whereType<SurfaceLoadFailed>(), hasLength(1));
        expect(events.whereType<SurfaceLoadCompleted>(), isEmpty);
      });
    });
  }

  testWidgets(
      'a flow the user went forward and back in is never swapped by a '
      'refresh', (tester) async {
    final resolver = _MutableFlowResolver(_flow('Fresh'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RestageFlowGraph<flows.FirstRunResult>(
      flow: flows.firstRunFlowRef,
      resolver: resolver,
      fallbackBuilder: _original,
      errorBuilder: _error,
    ))));
    await _settle(tester);
    await _fireEvent(tester, 'next');
    await tester.pump(const Duration(seconds: 1));
    await _fireEvent(tester, 'back');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Fresh'), findsOneWidget);
    // Back on the first screen, but the load advanced, so nothing swaps.
    resolver.flow = _flow('Second');
    await Restage.reloadSurfaces();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Second'), findsNothing);
    expect(find.text('Fresh'), findsOneWidget);
    await _failNow(tester);
    expect(find.text('Error'), findsOneWidget);
  });

  group('no fallback builder waits past the first-launch wait for late content',
      () {
    testWidgets('screen', (tester) async {
      final fixture = stringScreenFixture(text: 'Fresh');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageScreen<String>(
        screen: fixture.ref,
        resolver: _LateScreenResolver(const Duration(seconds: 5),
            fixture.hosted(hostedBlob: _blob('OnboardingScreen'))),
        // An error builder needs a failure, not a passed wait.
        errorBuilder: _error,
      ))));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Error'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Fresh'), findsOneWidget);
    });

    testWidgets('paywall', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestagePaywall(
        id: 'late',
        resolver: _LatePaywallResolver(const Duration(seconds: 5)),
        errorBuilder: _error,
      ))));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Error'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Fresh'), findsOneWidget);
    });
  });

  group('a flow with a compiled original', () {
    final offline = _GatedFlowResolver(Future<void>.value());
    final failures = <FlowUnavailableError>[];
    Future<void> mount(WidgetTester tester, FlowResolver resolver,
        {WidgetBuilder? fallbackBuilder,
        Widget Function(BuildContext, FlowUnavailableError)?
            errorBuilder}) async {
      failures.clear();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageFlowGraph<void>(
                  flow: nativeOfferFlowRef,
                  resolver: resolver,
                  onFlowUnavailable: failures.add,
                  fallbackBuilder: fallbackBuilder,
                  errorBuilder: errorBuilder))));
      await _settle(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
    }

    testWidgets('falls back to it by default', (tester) async {
      await mount(tester, offline);
      expect(find.text('Offer original'), findsOneWidget);
    });

    testWidgets('gives that rung to a fallback builder', (tester) async {
      await mount(tester, offline, fallbackBuilder: _original);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Offer original'), findsNothing);
      // The callback sees the fetch's own failure.
      expect(failures.map((e) => e.reason), ['missing_descriptor']);
    });

    testWidgets('gives that rung to a fallback builder after a raced outage',
        (tester) async {
      final resolver = _RacedOutage();
      await mount(tester, resolver, fallbackBuilder: _original);
      expect(find.text('Original'), findsOneWidget);
      expect(failures.map((e) => e.message), ['outage']);
    });

    testWidgets('gives that rung to a fallback builder over a resolver copy',
        (tester) async {
      // The asset resolver falls back to the compiled original itself.
      await mount(tester, AssetFlowResolver(bundle: _EmptyBundle()),
          fallbackBuilder: _original);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Offer original'), findsNothing);
    });

    testWidgets('restarts in it at most once per load', (tester) async {
      final compiled = nativeOfferFlowRef.compiled!;
      final broken = OnboardingFlowRef<void>(
        id: nativeOfferFlowRef.id,
        version: nativeOfferFlowRef.version,
        minClient: nativeOfferFlowRef.minClient,
        surface: Surface.onboarding,
        decodeResult: (_) {},
        compiled: CompiledFlow(documentJson: compiled.documentJson, screens: {
          for (final id in compiled.screens.keys) id: () => const _Throws(),
        }),
      );
      failures.clear();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageFlowGraph<void>(
                  flow: broken,
                  resolver: offline,
                  onFlowUnavailable: failures.add))));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }
      // The original failed, then its one restart failed: nothing is left.
      expect(failures, hasLength(2));
      expect(find.byType(_Throws), findsNothing);
    });

    for (final (name, builder) in [
      ('Original', _original),
      ('empty', _nothing)
    ]) {
      testWidgets(
          'at the first-launch wait, an $name fallback skips the original '
          'without a failure', (tester) async {
        await mount(tester, _GatedFlowResolver(Completer<void>().future),
            fallbackBuilder: builder);
        await tester.pump(const Duration(seconds: 4));
        await _settle(tester);
        expect(find.text('Offer original'), findsNothing);
        expect(failures, isEmpty);
      });
    }

    testWidgets('an empty fallback builder shows nothing in its place',
        (tester) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await mount(tester, offline, fallbackBuilder: _nothing);
      // It takes the compiled original's place, so the original never shows.
      expect(find.text('Offer original'), findsNothing);
      expect(find.text('Original'), findsNothing);
      // Unlike nothing at all, it is a shown fallback: the load completes.
      expect(events.whereType<SurfaceLoadCompleted>().map((e) => e.source),
          [SurfaceLoadSource.original]);
      expect(events.whereType<SurfaceLoadFailed>(), isEmpty);
    });

    testWidgets('restarts in it again when a refreshed version fails too',
        (tester) async {
      final resolver = _MutableFlowResolver(_deliveredOffer(text: 'Fresh A'));
      await mount(tester, resolver);
      expect(find.text('Fresh A'), findsOneWidget);
      await _failNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Offer original'), findsOneWidget);
      // Newer content replaces the original before the user made progress.
      _trip.value = false;
      resolver.flow = _deliveredOffer(text: 'Fresh B');
      await Restage.reloadSurfaces();
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Fresh B'), findsOneWidget);
      await _failNow(tester);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Offer original'), findsOneWidget);
      expect(failures, hasLength(2));
    });

    testWidgets(
        'restarts in it when delivered content fails, after reporting the '
        'failure', (tester) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await mount(tester, flows.StaticFlowResolver(_deliveredOffer()));
      expect(find.byType(_Tripwire), findsOneWidget);
      await _failNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Offer original'), findsOneWidget);
      expect(
          events
              .where((e) => e is SurfaceLoadCompleted || e is SurfaceLoadFailed)
              .map((e) => e is SurfaceLoadFailed
                  ? 'failed ${e.reason.wireName}'
                  : 'completed'),
          ['completed']);
    });

    testWidgets('a first-frame render failure reports render_error, once',
        (tester) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      _trip.value = true;
      await mount(tester, flows.StaticFlowResolver(_deliveredOffer()));
      tester.takeException();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Offer original'), findsOneWidget);
      expect(
          events
              .where((e) => e is SurfaceLoadCompleted || e is SurfaceLoadFailed)
              .map((e) => e is SurfaceLoadFailed
                  ? 'failed ${e.reason.wireName}'
                  : 'completed'),
          ['failed render_error']);
    });

    testWidgets('restarts in it before progress despite an error builder',
        (tester) async {
      await mount(tester, flows.StaticFlowResolver(_deliveredOffer()),
          errorBuilder: _error);
      await _failNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Offer original'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
    });

    testWidgets('shows the error builder instead after progress',
        (tester) async {
      await mount(tester, flows.StaticFlowResolver(_deliveredOffer()),
          errorBuilder: _error);
      await _drag(tester, find.byType(_Tripwire));
      await _failNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Offer original'), findsNothing);
    });
  });

  group('the fallback at the first-launch wait', () {
    final failures = <FlowUnavailableError>[];
    Future<void> pending(WidgetTester tester, _Policy policy) async {
      failures.clear();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageFlowGraph<flows.FirstRunResult>(
        flow: flows.firstRunFlowRef,
        resolver: _GatedFlowResolver(Completer<void>().future),
        onFlowUnavailable: failures.add,
        fallbackBuilder: _fallbackFor(policy),
        errorBuilder: _errorFor(policy),
      ))));
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
    }

    testWidgets('a raw flow shows its fallback builder', (tester) async {
      await pending(tester, _Policy.originalOnly);
      expect(find.text('Original'), findsOneWidget);
      expect(failures, isEmpty);
    });

    testWidgets('a raw flow without one keeps waiting', (tester) async {
      await pending(tester, _Policy.none);
      expect(find.text('Original'), findsNothing);
    });

    testWidgets('a raw flow with only an error builder keeps waiting',
        (tester) async {
      await pending(tester, _Policy.errorOnly);
      expect(find.text('Error'), findsNothing);
      expect(failures, isEmpty);
    });
  });

  testWidgets(
      'a hosted paywall flow that is invalid before it paints shows the '
      'original as a completed load', (tester) async {
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final flow = flows.resolvedFlow();
    // The first screen's blob is missing, which is not a render failure.
    final missingFirst = ResolvedFlow(
        document: flow.document,
        screenBlobs: {'profile': flow.screenBlobs['profile']!},
        cacheHit: false);
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
            id: 'pro_upgrade',
            resolver: _FlowPayloadResolver(missingFirst),
            fallbackBuilder: _original)));
    await _settle(tester);
    expect(find.text('Original'), findsOneWidget);
    expect(
        events
            .where((e) => e is SurfaceLoadCompleted || e is SurfaceLoadFailed)
            .map((e) => e.runtimeType),
        [SurfaceLoadCompleted]);
  });

  for (final surfaceType in [Surface.onboarding, Surface.paywall]) {
    testWidgets(
        'a ${surfaceType.wireName} flow placement shows its fallback when '
        'nothing can render', (tester) async {
      final document = flows.flowDocument();
      await tester.pumpWidget(MaterialApp(
          home: RestagePlacement.flow(
              id: 'journey_slot',
              surfaceType: surfaceType,
              contract: SurfaceHostContractV1(
                  hosting: const SurfaceHostingV1(
                      contentKind: SurfaceContentKindV1.flow,
                      presentation: SurfacePresentationV1.inline),
                  providedContext: const SurfaceScreenHostDataSchema.empty(),
                  handledEvents: SurfaceScreenEventSchema(events: const []),
                  flowBoundary:
                      FlowHostBoundaryV1.fromDocument(document, signals: {})),
              fallbackBuilder: _original,
              errorBuilder: (_, error) =>
                  Text('Error ${error.cause.runtimeType}'))));
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
      expect(find.text('Original'), findsOneWidget);
      // The mounted host's error builder wraps the host's own error.
      final context = tester.element(find.text('Original'));
      final shown = surfaceType == Surface.paywall
          ? tester
                  .widget<RestagePaywall>(find.byType(RestagePaywall))
                  .errorBuilder!(
              context, const RestagePaywallError(code: 'x', message: ''))
          : tester
                  .widget<RestageFlowGraph<Map<String, Object?>>>(
                      find.byType(RestageFlowGraph<Map<String, Object?>>))
                  .errorBuilder!(
              context,
              const FlowUnavailableError(
                  flowId: 'journey_slot',
                  flowVersion: 0,
                  reason: 'x',
                  message: ''));
      expect(
          (shown as Text).data,
          surfaceType == Surface.paywall
              ? 'Error RestagePaywallError'
              : 'Error FlowUnavailableError');
    });
  }

  group('a paywall whose shown content fails', () {
    List<String> views(List<RestageEvent> events) => [
          for (final event in events)
            if (event is PaywallViewed)
              'viewed'
            else if (event is PaywallDismissed)
              'dismissed',
        ];

    testWidgets('before progress ends the delivered view for the original',
        (tester) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await _show(tester, _PaywallCase(), _Policy.originalAndError);
      await _failNow(tester);
      expect(find.text('Original'), findsOneWidget);
      expect(views(events), ['viewed', 'dismissed', 'viewed']);
    });

    testWidgets('after progress keeps the view for the error builder',
        (tester) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await _show(tester, _PaywallCase(), _Policy.originalAndError);
      await _drag(tester, find.byType(_Tripwire));
      await _failNow(tester);
      expect(find.text('Error'), findsOneWidget);
      expect(views(events), ['viewed']);
    });
  });

  testWidgets(
      'onboarding given another surface type shows the original, never the '
      'error builder', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RestageOnboarding<Object?>(
      flow: const SurfaceFlowRef<Object?>(
          id: 'offer',
          version: 1,
          minClient: 1,
          surface: Surface.message,
          decodeResult: _decodeNothing),
      fallbackBuilder: _original,
      errorBuilder: _error,
    )));
    await tester.pump();
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
  });

  testWidgets(
      'onboarding given another surface type shows an error builder that has '
      'nothing below it', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RestageOnboarding<Object?>(
      flow: const SurfaceFlowRef<Object?>(
          id: 'offer',
          version: 1,
          minClient: 1,
          surface: Surface.message,
          decodeResult: _decodeNothing),
      errorBuilder: _error,
    )));
    await tester.pump();
    expect(find.text('Error'), findsOneWidget);
  });

  for (final policy in [_Policy.fallbackThrows, _Policy.errorThrows]) {
    testWidgets(
        'onboarding given another surface type with a ${policy.name} builder '
        'shows nothing and reports it once', (tester) async {
      Future<void> pump(Brightness brightness) async {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: RestageOnboarding<Object?>(
              flow: const SurfaceFlowRef<Object?>(
                  id: 'offer',
                  version: 1,
                  minClient: 1,
                  surface: Surface.message,
                  decodeResult: _decodeNothing),
              fallbackBuilder: _fallbackFor(policy),
              errorBuilder: _errorFor(policy),
            )));
        await tester.pump();
      }

      await pump(Brightness.light);
      expect(tester.takeException(), isA<StateError>());
      await pump(Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });
  }
}

Object? _decodeNothing(Map<String, Object?> _) => null;

/// The builders a host is given.
enum _Policy {
  originalAndError,
  originalOnly,
  errorOnly,
  none,
  throwing,
  fallbackThrows,
  errorWidgetThrows,
  errorThrows,
}

/// The ways a builder can throw: the widget it returns, or the call itself.
const _throwingBuilders = [
  _Policy.throwing,
  _Policy.fallbackThrows,
  _Policy.errorWidgetThrows,
  _Policy.errorThrows,
];

Widget _original(BuildContext _) => const Text('Original');
Widget _error(BuildContext _, Object __) => const Text('Error');
Widget _nothing(BuildContext _) => const SizedBox.shrink();

WidgetBuilder? _fallbackFor(_Policy policy) => switch (policy) {
      _Policy.originalAndError || _Policy.originalOnly => _original,
      _Policy.errorOnly ||
      _Policy.none ||
      _Policy.errorWidgetThrows ||
      _Policy.errorThrows =>
        null,
      _Policy.throwing => (_) => const _Throws(),
      _Policy.fallbackThrows => (_) => throw StateError('fallback broke'),
    };

Widget Function(BuildContext, E)? _errorFor<E extends Object>(_Policy policy) =>
    switch (policy) {
      _Policy.originalAndError || _Policy.errorOnly => _error,
      _Policy.errorWidgetThrows => (_, __) => const _Throws(),
      _Policy.errorThrows => (_, __) => throw StateError('error broke'),
      _ => null,
    };

Future<void> _show(WidgetTester tester, _Case host, _Policy policy,
    {int load = 0}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: host.mount(policy: policy, load: load))));
  await _settle(tester);
  expect(find.byType(_Tripwire), findsOneWidget);
}

/// Makes the shown content throw on its next layout, then settles.
Future<void> _failNow(WidgetTester tester) async {
  _trip.value = true;
  await _settle(tester);
  tester.takeException();
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Drags across [target]: an interaction that fires no event.
Future<void> _drag(WidgetTester tester, Finder target) async {
  await tester.drag(target, const Offset(0, 30));
  await _settle(tester);
}

/// Fires [name] from the shown content without a pointer.
Future<void> _fireEvent(WidgetTester tester, String name) async {
  final remote = tester.widget<RemoteWidget>(find.byType(RemoteWidget).last);
  remote.onEvent!(name, const <String, Object?>{});
  await _settle(tester);
}

abstract class _Case {
  String get name;

  /// Mounts content with a tripwire; with [failAfter], a load that fails
  /// once it completes and shows [_loading] until then.
  Widget mount(
      {required _Policy policy, required int load, Future<void>? failAfter});
  Future<void> runHandler(WidgetTester tester);
}

const _loading = ValueKey('loading');

Widget _loadingBuilder(BuildContext _) => const SizedBox.expand(
    key: _loading, child: ColoredBox(color: Colors.white));

final class _PaywallResolver implements VariantResolver {
  _PaywallResolver([this.failAfter]);

  final Future<void>? failAfter;

  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    if (failAfter case final gate?) {
      await gate;
      throw const RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable, message: 'offline');
    }
    return ResolvedVariant(
      bytes: _blob('Paywall'),
      surfaceVersion: 'tripwire',
      paywallId: id,
    );
  }
}

final class _PaywallCase extends _Case {
  final _resolver = _PaywallResolver();

  @override
  String get name => 'paywall';

  @override
  Widget mount(
          {required _Policy policy,
          required int load,
          Future<void>? failAfter}) =>
      RestagePaywall(
        id: 'native_offer',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: nativeOfferPlacementDefinition,
          name: load == 0 ? null : 'checkout',
        ),
        resolver: failAfter == null ? _resolver : _PaywallResolver(failAfter),
        loadingBuilder: _loadingBuilder,
        fallbackBuilder: _fallbackFor(policy),
        errorBuilder: _errorFor(policy),
      );

  // An authored event from the content reaches the host's onEvent.
  @override
  Future<void> runHandler(WidgetTester tester) => _fireEvent(tester, 'tapped');
}

final class _PlacementCase extends _Case {
  @override
  String get name => 'placement';

  @override
  Widget mount(
      {required _Policy policy, required int load, Future<void>? failAfter}) {
    // A placement reads the configured resolver.
    Restage.configure(
        resolver: failAfter == null
            ? _PaywallResolver()
            : _PaywallResolver(failAfter));
    return RestagePlacement.forSurface(
      surfaceType: Surface.message,
      // A new placement is a new load.
      surfaceId: load == 0 ? 'welcome_back' : 'welcome_again',
      loadingBuilder: _loadingBuilder,
      fallbackBuilder: _fallbackFor(policy),
      // The error a placement shows wraps the mounted host's own.
      errorBuilder: policy == _Policy.originalAndError ||
              policy == _Policy.errorOnly
          ? (_, error) =>
              Text(error.cause is RestagePaywallError ? 'Error' : 'Wrong cause')
          : _errorFor(policy),
    );
  }

  @override
  Future<void> runHandler(WidgetTester tester) => _fireEvent(tester, 'tapped');
}

final class _ScreenCase extends _Case {
  final _fixture = stringScreenFixture(text: 'Fresh');
  final _resolvers = <int, SurfaceScreenResolver>{};
  final handled = <String>[];

  @override
  String get name => 'screen';

  @override
  Widget mount(
          {required _Policy policy,
          required int load,
          Future<void>? failAfter}) =>
      RestageScreen<String>(
        screen: _fixture.ref,
        // A new resolver is a new declaration, so a new load.
        resolver: failAfter != null
            ? _GatedScreenResolver(failAfter)
            : _resolvers[load] ??= FixedScreenResolver(
                _fixture.hosted(hostedBlob: _blob('OnboardingScreen'))),
        loadingBuilder: _loadingBuilder,
        onEvent: handled.add,
        fallbackBuilder: _fallbackFor(policy),
        errorBuilder: _errorFor(policy),
      );

  @override
  Future<void> runHandler(WidgetTester tester) async {
    await _fireEvent(tester, 'tap');
    expect(handled, ['tap']);
  }
}

final class _GatedScreenResolver implements SurfaceScreenResolver {
  _GatedScreenResolver(this.gate);

  final Future<void> gate;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    await gate;
    throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing, message: 'offline');
  }
}

final class _GatedFlowResolver implements FlowResolver {
  _GatedFlowResolver(this.gate);

  final Future<void> gate;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    await gate;
    throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_descriptor',
        message: 'offline');
  }
}

/// A raced, active-arm resolver whose fetch fails with an outage.
final class _RacedOutage
    with RacedSurfaceReporting<ResolvedFlow>
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        RacedSurfaceResolver<ResolvedFlow> {
  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  bool get activeArmEnabled => true;

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {}

  @override
  Future<ResolvedFlow?> bestLocal(SurfaceStoreKey key) async => null;

  @override
  Future<ResolvedFlow?> fresh(SurfaceStoreKey key,
          {required bool sendAssignmentKey, Future<void>? keyDeadline}) =>
      Future.error(const FlowUnavailableError(
          flowId: 'native_offer_flow',
          flowVersion: 1,
          reason: 'delivery_unavailable',
          message: 'outage'));

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));
}

final class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError('original broke');
}

/// Answers every fetch with [flow] as a navigation paywall.
final class _FlowPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _FlowPayloadResolver(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(String id,
          {String? placementId, Locale? locale}) async =>
      FlowPaywallPayload(flow: flow, paywallId: id);
}

/// Holds no assets.
final class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('No asset $key.'));
}

final class _FlowCase extends _Case {
  final _resolvers = <int, FlowResolver>{};

  @override
  String get name => 'flow';

  FlowResolver resolver(int load, Future<void>? failAfter) => failAfter != null
      ? _GatedFlowResolver(failAfter)
      : _resolvers[load] ??=
          flows.StaticFlowResolver(flows.resolvedFlow(screenBlobs: {
          'welcome': _blob('OnboardingScreen', event: 'next'),
          'profile': _blob('OnboardingScreen', event: 'finish'),
        }));

  @override
  Widget mount(
          {required _Policy policy,
          required int load,
          Future<void>? failAfter}) =>
      RestageFlowGraph<flows.FirstRunResult>(
        flow: flows.firstRunFlowRef,
        resolver: resolver(load, failAfter),
        loadingBuilder: _loadingBuilder,
        fallbackBuilder: _fallbackFor(policy),
        errorBuilder: _errorFor(policy),
      );

  // Entering the second screen advances the load.
  @override
  Future<void> runHandler(WidgetTester tester) async {
    await _fireEvent(tester, 'next');
    // The page transition settles on the second screen.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(_Tripwire), findsOneWidget);
  }
}

final class _OnboardingCase extends _FlowCase {
  @override
  String get name => 'onboarding';

  @override
  Widget mount(
          {required _Policy policy,
          required int load,
          Future<void>? failAfter}) =>
      RestageOnboarding<flows.FirstRunResult>(
        flow: flows.firstRunFlowRef,
        resolver: resolver(load, failAfter),
        loadingBuilder: _loadingBuilder,
        fallbackBuilder: _fallbackFor(policy),
        errorBuilder: _errorFor(policy),
      );
}

const _library = WidgetLibrary.custom('acme.unavailable_policy');

Uint8List _blob(String root,
        {String event = 'tapped', String text = 'Fresh'}) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import acme.unavailable_policy;
      widget $root = GestureDetector(
        onTap: event "$event" { },
        child: Column(children: [Text(text: "$text"), Tripwire()]),
      );
    ''')));

ResolvedFlow _flow(String text) => flows.resolvedFlow(screenBlobs: {
      'welcome': _blob('OnboardingScreen', event: 'next', text: text),
      'profile': _blob('OnboardingScreen', event: 'back', text: 'Profile'),
    });

/// Delivered content for the compiled offer flow, with a tripwire on its
/// screen.
ResolvedFlow _deliveredOffer({String text = 'Fresh'}) {
  final document = nativeOfferFlowRef.compiled!.document;
  final blob = _blob('OnboardingScreen', text: text);
  return ResolvedFlow(
    document: document.copyWith(screenArtifacts: {
      for (final entry in document.screenArtifacts.entries)
        entry.key: ScreenArtifact(
            path: entry.value.path,
            version: entry.value.version,
            schemaVersion: entry.value.schemaVersion,
            minClient: entry.value.minClient,
            contentHash: FlowContentHash.compute(blob)),
    }),
    screenBlobs: {
      for (final id in document.screenArtifacts.keys) id: blob,
    },
    cacheHit: false,
  );
}

final class _MutableFlowResolver implements FlowResolver {
  _MutableFlowResolver(this.flow);

  ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

/// Answers once [delay] has passed.
final class _LateScreenResolver implements SurfaceScreenResolver {
  _LateScreenResolver(this.delay, this.screen);

  final Duration delay;
  final ResolvedSurfaceScreen screen;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> _) async {
    await Future<void>.delayed(delay);
    return screen;
  }
}

/// Never answers.
final class _GatedPaywall implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      Completer<ResolvedVariant>().future;
}

final class _LatePaywallResolver implements VariantResolver {
  _LatePaywallResolver(this.delay);

  final Duration delay;

  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    await Future<void>.delayed(delay);
    return ResolvedVariant(
        bytes: _blob('Paywall'), surfaceVersion: 'late', paywallId: id);
  }
}

/// While set, every shown tripwire throws on its next layout.
final _trip = ValueNotifier<bool>(false);

final class _Tripwire extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTripwire();
}

final class _RenderTripwire extends RenderBox {
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _trip.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _trip.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    if (_trip.value) throw StateError('tripped');
    size = constraints.constrain(const Size(40, 40));
  }
}
