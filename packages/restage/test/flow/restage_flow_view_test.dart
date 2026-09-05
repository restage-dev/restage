import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show ByteData, MethodCall, StandardMethodCodec, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_controller.dart'
    show createHostMeasurementFlowController;
import 'package:rfw/rfw.dart' show DynamicContent, RemoteWidget;

import 'flow_test_support.dart';

/// The product of every [FadeTransition]/[Opacity] opacity on the path from
/// [leaf] up to the enclosing [RestageFlowView] — i.e. how visibly that leaf
/// actually paints. A screen revealed by a back must settle at ~1.0; a screen
/// stuck in an exiting (faded-out) transition settles at ~0.0 even though
/// `findsOneWidget` still finds it onstage (the black-screen latch bug — present
/// in the tree ≠ visible, the same class as a non-tappable control).
double _effectiveOpacity(WidgetTester tester, Finder leaf) {
  var opacity = 1.0;
  tester.element(leaf).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FadeTransition) {
      opacity *= widget.opacity.value;
    } else if (widget is Opacity) {
      opacity *= widget.opacity;
    }
    // Stop at the view boundary so only the screen's own transition stack
    // counts (not any opacity the test harness wraps the view in).
    return widget is! RestageFlowView;
  });
  return opacity;
}

/// Unmounts the view (pumps an empty root) so a subsequent *failing* assertion
/// is reported cleanly rather than swallowed by a still-mounted
/// [RuntimeErrorBoundary]'s process-wide `FlutterError.onError` override — which
/// defers the failure via `scheduleMicrotask`, trips the binding's
/// `_pendingExceptionDetails` assert, and surfaces only as a 10-minute timeout
/// (a known test-DX hazard tracked against the error boundary). Capture every
/// opacity/position WHILE mounted, then call this once before the expectations.
Future<void> unmountView(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Asserts [leaf] settles fully visible (effective opacity ~1.0), unmounting
/// the view first so a regression fails cleanly and fast (see [unmountView]).
Future<void> expectFullyVisible(WidgetTester tester, Finder leaf) async {
  final opacity = _effectiveOpacity(tester, leaf);
  await unmountView(tester);
  expect(
    opacity,
    greaterThan(0.99),
    reason: 'the revealed screen must be fully visible, not faded out '
        '(effective opacity was $opacity)',
  );
}

Object? _readContextLabel(DynamicContent data) {
  void noop(Object _) {}
  final value = data.subscribe(const <Object>['context'], noop);
  data.unsubscribe(const <Object>['context'], noop);
  return value is Map<Object?, Object?> ? value['label'] : value;
}

void main() {
  RestageFlowController<FirstRunResult> loadedController() {
    return RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(resolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
  }

  // A controller over the linear One -> Two -> Three flow, for the back-nav
  // (cover/reveal) cases.
  RestageFlowController<FirstRunResult> threeScreenController() {
    return RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(threeScreenResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
  }

  // A controller over the welcome -> profile flow whose screens carry an
  // `AppBar`, for the route-history cases.
  RestageFlowController<FirstRunResult> appBarController() {
    return RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(appBarResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
  }

  // Mounts the view inside a real route, so it has a host route to register
  // its back history on.
  Widget routedFlow(
    RestageFlowController<FirstRunResult> controller, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: RestageFlowView(controller: controller),
    );
  }

  ModalRoute<dynamic> hostRoute(WidgetTester tester) => ModalRoute.of(
        tester.element(find.byType(RestageFlowView<FirstRunResult>)),
      )!;

  /// Delivers one predictive-back platform message to the binding.
  Future<void> backGesture(WidgetTester tester, MethodCall call) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(call),
      (ByteData? _) {},
    );
  }

  /// Runs [body] with the platform pinned, resetting inside the test body so
  /// the binding's foundation-vars-unset invariant never trips.
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  RestageFlowController<FirstRunResult> controllerFor(ResolvedFlow flow) =>
      RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: StaticFlowResolver(flow),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );

  PageRoute<dynamic> routeOf(WidgetTester tester, Finder finder) =>
      ModalRoute.of(tester.element(finder))! as PageRoute<dynamic>;

  PageRoute<dynamic> hostPageRoute(WidgetTester tester) =>
      routeOf(tester, find.byType(RestageFlowView<FirstRunResult>));

  Future<void> withIosPlatform(Future<void> Function() body) async {
    // Reset inside the test body, before the framework checks that foundation
    // debug vars are back at their defaults.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpWideFlowAtProfile(
    WidgetTester tester,
    RestageFlowController<FirstRunResult> controller,
  ) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 800,
        height: 600,
        child: RestageFlowView(controller: controller),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(controller.canBack, isTrue);
  }

  testWidgets('renders the controller current screen and routes its event',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets(
      'publishes context to controlled landings and every stacked screen',
      (tester) async {
    final resolver = ControlledFlowResolver();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: resolver,
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    var hostContext = <String, Object?>{'label': 'first'};
    late StateSetter updateHost;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: RestageFlowView<FirstRunResult>(
              controller: controller,
              context: hostContext,
            ),
          );
        },
      ),
    );
    unawaited(controller.load());
    await tester.pump();
    expect(find.byType(RemoteWidget), findsNothing);

    hostContext['label'] = 'later';
    resolver.response.complete(contextResolvedFlow());
    await tester.pumpAndSettle();
    final firstData =
        tester.widget<RemoteWidget>(find.byType(RemoteWidget)).data;
    final initialLabel = _readContextLabel(firstData);
    final laterVisibleInitially = find.text('later').evaluate().length;

    updateHost(() => hostContext = <String, Object?>{'label': 'second'});
    await tester.pump();
    controller.handleEvent('next', const <String, Object?>{});
    await tester.pumpAndSettle();
    final data = tester
        .widgetList<RemoteWidget>(
          find.byType(RemoteWidget, skipOffstage: false),
        )
        .map((widget) => widget.data)
        .toList();
    final labelsAfterPush = data.map(_readContextLabel).toList();

    final notifications = <int>[0, 0];
    final callbacks = <void Function(Object)>[];
    for (var index = 0; index < data.length; index += 1) {
      void onContext(Object _) => notifications[index] += 1;
      callbacks.add(onContext);
      data[index].subscribe(const <Object>['context'], onContext);
    }

    updateHost(() => hostContext = <String, Object?>{'label': 'third'});
    await tester.pump();
    final changedNotifications = List<int>.of(notifications);
    final changedLabels = data.map(_readContextLabel).toList();

    updateHost(() => hostContext = <String, Object?>{'label': 'third'});
    await tester.pump();
    final equalNotifications = List<int>.of(notifications);
    for (var index = 0; index < data.length; index += 1) {
      data[index].unsubscribe(const <Object>['context'], callbacks[index]);
    }
    await unmountView(tester);

    expect(initialLabel, 'first');
    expect(laterVisibleInitially, 0);
    expect(data, hasLength(2));
    expect(labelsAfterPush, everyElement('second'));
    expect(changedNotifications, <int>[1, 1]);
    expect(changedLabels, everyElement('third'));
    expect(equalNotifications, <int>[1, 1]);
  });

  testWidgets(
      'routes an RFW event through measurement before its interceptor and transition',
      (tester) async {
    final order = <String>[];
    final controller = createHostMeasurementFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(resolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
      onRootResolved: (_) async {},
      sanitizeAndRecordEvent: (rawValue) {
        order.add('measurement');
        return rawValue;
      },
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.currentScreenId == 'profile') {
        order.add('transition');
      }
    });

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView<FirstRunResult>(
        controller: controller,
        onScreenEvent: (name, arguments) {
          expect(name, 'next');
          expect(arguments, isEmpty);
          order.add('interceptor');
          return false;
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    expect(order, ['measurement', 'interceptor', 'transition']);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('a controller swap commits both controllers', (tester) async {
    final first = loadedController();
    final second = loadedController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: first),
    ));
    unawaited(first.load());
    await tester.pumpAndSettle();

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: second),
    ));
    unawaited(second.load());
    await tester.pumpAndSettle();

    final observed = (
      firstCommitted: first.hasRenderedContent,
      secondCommitted: second.hasRenderedContent,
    );
    await unmountView(tester);

    expect(
      observed,
      (
        firstCommitted: true,
        secondCommitted: true,
      ),
    );
  });

  testWidgets('forward navigation keeps the prior screen mounted offstage',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    // Profile is the current (onstage) screen.
    expect(find.text('Profile'), findsOneWidget);
    // Welcome is no longer onstage...
    expect(find.text('Welcome', skipOffstage: true), findsNothing);
    // ...but its widget instance is still mounted (kept offstage).
    expect(find.text('Welcome', skipOffstage: false), findsOneWidget);
  });

  testWidgets("a prior screen's element/state is preserved on forward nav",
      (tester) async {
    Restage.debugReset();
    registerStatefulProbe();
    addTearDown(Restage.debugReset);
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(probeResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(find.text('probe'), findsOneWidget);
    expect(StatefulProbe.initCount, 1);

    // Tap the probe screen (fires `next`) -> profile.
    await tester.tap(find.text('probe'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    // The probe screen stayed mounted offstage; its State was never recreated.
    expect(find.text('probe', skipOffstage: false), findsOneWidget);
    expect(find.text('probe', skipOffstage: true), findsNothing);
    expect(StatefulProbe.initCount, 1);
  });

  testWidgets(
      'forward navigation animates with both screens visible mid-flight',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pump(); // the controller advances
    await tester.pump(); // the screen's route is pushed
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60)); // mid-flight

    final animating = tester.hasRunningAnimations;
    // Both the incoming and outgoing screens are on-screen (not an instant cut).
    final incomingMidFlight = find.text('Profile').evaluate().length;
    final outgoingMidFlight =
        find.text('Welcome', skipOffstage: true).evaluate().length;

    await tester.pumpAndSettle();
    // Settled: only the incoming screen remains on-screen.
    final incomingSettled = find.text('Profile').evaluate().length;
    final outgoingSettled =
        find.text('Welcome', skipOffstage: true).evaluate().length;
    await unmountView(tester);

    expect(animating, isTrue);
    expect(incomingMidFlight, 1);
    expect(outgoingMidFlight, 1);
    expect(incomingSettled, 1);
    expect(outgoingSettled, 0);
  });

  testWidgets('back navigates to the prior screen with a reverse transition',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    // welcome -> profile.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(controller.canBack, isTrue);

    // Back to welcome: the reverse transition plays with both screens visible.
    controller.back();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.text('Welcome', skipOffstage: true), findsOneWidget);
    expect(find.text('Profile', skipOffstage: true), findsOneWidget);

    await tester.pumpAndSettle();
    // Settled on welcome; the popped profile screen is gone (no duplicate-key
    // assertion, no lingering profile).
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Profile', skipOffstage: false), findsNothing);
  });

  testWidgets('back restores the mounted prior screen with its state preserved',
      (tester) async {
    Restage.debugReset();
    registerStatefulProbe();
    addTearDown(Restage.debugReset);
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(probeResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
    expect(StatefulProbe.initCount, 1);

    // probe -> profile.
    await tester.tap(find.text('probe'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(controller.canBack, isTrue);

    // Back to the probe screen: it is restored from its still-mounted instance,
    // so its State was never recreated (initState did not run again).
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
    expect(StatefulProbe.initCount, 1);
  });

  testWidgets(
      'a multi-step back reveals the target, not an intermediate screen',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // One -> Two -> Three (three screens mounted).
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Two back()s before a rebuild settles: the view observes a two-step pop
    // (Three -> One). The revealed target is One; Two is an intermediate that
    // must stay offstage during the reverse transition.
    controller.back();
    controller.back();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.text('One', skipOffstage: true), findsOneWidget);
    expect(find.text('Three', skipOffstage: true), findsOneWidget);
    expect(find.text('Two', skipOffstage: true), findsNothing);

    await tester.pumpAndSettle();
    // Settled on One; the intermediate Two and the popped Three are gone.
    expect(tester.takeException(), isNull);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two', skipOffstage: false), findsNothing);
    expect(find.text('Three', skipOffstage: false), findsNothing);
    expect(controller.currentScreenId, 'one');
  });

  testWidgets('back reveals the prior screen fully visible, not faded out',
      (tester) async {
    // The Android shared-axis path: a screen covered by a push, then revealed
    // by a back, must settle at full opacity. (The persistent transition
    // element latched the revealed screen into its exit transition, fading it
    // to opacity 0 — onstage but invisible. findsOneWidget could not see that.)
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // One -> Two -> Three (Two is covered by Three's push).
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Back to Two: restored from its still-mounted instance, it must be fully
    // visible at rest — not stuck in a faded-out exit transition.
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    await expectFullyVisible(tester, find.text('Two'));
  });

  testWidgets('sequential backs each reveal their target fully visible',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Three -> Two (settle), then Two -> One (settle): each reveal lands fully
    // visible (the second reveal must not inherit a stale latch from the first).
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    final twoOpacity = _effectiveOpacity(tester, find.text('Two'));
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    final oneOpacity = _effectiveOpacity(tester, find.text('One'));

    await unmountView(tester);
    expect(twoOpacity, greaterThan(0.99),
        reason: 'Two (first reveal) must be fully visible (was $twoOpacity)');
    expect(oneOpacity, greaterThan(0.99),
        reason: 'One (second reveal) must be fully visible (was $oneOpacity)');
  });

  testWidgets('a queued multi-step back reveals the deep target fully visible',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Two back()s before a rebuild settles (e.g. a queued system-back): a
    // two-step pop Three -> One via the `_popTargetIndex` retarget path. The
    // revealed deep target must settle fully visible; the intermediate Two stays
    // offstage and gone.
    controller.back();
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two', skipOffstage: false), findsNothing);
    await expectFullyVisible(tester, find.text('One'));
  });

  testWidgets('a forward push after a back re-shows the screen fully visible',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Back to Two (revealed), then forward again Two -> Three (a fresh Three;
    // the popped one was removed), then back to Two once more. Each landing is
    // fully visible — covering then re-revealing a screen never strands it.
    controller.back();
    await tester.pumpAndSettle();
    final twoAfterBack = _effectiveOpacity(tester, find.text('Two'));
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);
    final threeReshown = _effectiveOpacity(tester, find.text('Three'));
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    final twoAfterSecondBack = _effectiveOpacity(tester, find.text('Two'));

    await unmountView(tester);
    expect(twoAfterBack, greaterThan(0.99),
        reason: 'Two after the first back (was $twoAfterBack)');
    expect(threeReshown, greaterThan(0.99),
        reason: 'Three re-pushed after the back (was $threeReshown)');
    expect(twoAfterSecondBack, greaterThan(0.99),
        reason: 'Two after the second back (was $twoAfterSecondBack)');
  });

  testWidgets('a back during an in-flight forward settles fully visible',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // One -> Two: start the forward transition, then back() before it settles.
    await tester.tap(find.text('One'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80)); // mid-flight
    expect(tester.hasRunningAnimations, isTrue);
    controller.back();
    await tester.pumpAndSettle();

    // Lands back on One, fully visible — an interrupted forward then a back does
    // not strand the revealed screen faded out.
    expect(controller.currentScreenId, 'one');
    expect(find.text('One'), findsOneWidget);
    await expectFullyVisible(tester, find.text('One'));
  });

  testWidgets('state survives a multi-step back without a remount',
      (tester) async {
    Restage.debugReset();
    registerStatefulProbe();
    addTearDown(Restage.debugReset);
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(probeThreeScreenResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
    expect(StatefulProbe.initCount, 1);

    // probe -> Two -> Three.
    await tester.tap(find.text('probe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // A two-step back to the probe: its preserved Element is MOVED back (the
    // GlobalKey content survives the fresh transition wrapper) — initState never
    // runs again — AND it lands fully visible.
    controller.back();
    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
    expect(StatefulProbe.initCount, 1);
    await expectFullyVisible(tester, find.text('probe'));
  });

  testWidgets('back on the Cupertino path reveals the screen at rest, visible',
      (tester) async {
    // Force the iOS Cupertino push (the default test platform is android). The
    // override is reset in `finally` — before the binding's post-test
    // foundation-vars-unset invariant runs — so it never leaks to the next test.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = loadedController();
    addTearDown(controller.dispose);
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFlowView(controller: controller),
      ));
      unawaited(controller.load());
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      final restingTopLeft = tester.getTopLeft(find.text('Welcome'));

      // welcome -> profile -> back to welcome.
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      controller.back();
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);

      // The Cupertino reveal returns the screen to its resting position (not
      // parked at a residual slide offset) and fully visible.
      final revealedTopLeft = tester.getTopLeft(find.text('Welcome'));
      final opacity = _effectiveOpacity(tester, find.text('Welcome'));
      await unmountView(tester);
      expect(revealedTopLeft, restingTopLeft,
          reason: 'iOS reveal must return the screen to its resting position');
      expect(opacity, greaterThan(0.99),
          reason: 'iOS revealed screen must be fully visible (was $opacity)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the first screen appears without an enter animation',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    // Pump only until the first screen mounts — catching it at first paint, so
    // an enter animation (if any) would still be running. A 320ms enter
    // transition would not finish within these short pumps.
    for (var i = 0; i < 12 && find.text('Welcome').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    final found = find.text('Welcome').evaluate().length;
    // The first screen is shown at rest — it does not slide or fade in.
    final firstPaint = tester.getTopLeft(find.text('Welcome'));
    final firstOpacity = _effectiveOpacity(tester, find.text('Welcome'));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('Welcome'));
    await unmountView(tester);
    expect(found, 1);
    expect(firstPaint, settled);
    expect(firstOpacity, greaterThan(0.99));
  });

  testWidgets('an app bar in the screen implies back once the flow has history',
      (tester) async {
    final controller = appBarController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // First screen: nothing behind it, so the app bar shows no back control.
    expect(find.text('Welcome bar'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(controller.canBack, isFalse);

    // welcome -> profile: the route now carries a local-history entry, so the
    // app bar implies back.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile bar'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(controller.canBack, isTrue);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'welcome');
    expect(find.byType(BackButton), findsNothing);
    expect(controller.canBack, isFalse);
  });

  testWidgets('Navigator.maybePop pops one flow screen per call',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(threeScreenResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller, navigatorKey: navigatorKey));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'three');

    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'two');

    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'one');
    expect(controller.canBack, isFalse);
  });

  testWidgets('a Cupertino navigation bar implies back from the same history',
      (tester) async {
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(cupertinoBarResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(CupertinoApp(
      home: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsNothing);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'welcome');
    expect(find.byType(CupertinoNavigationBarBackButton), findsNothing);
  });

  testWidgets('a flow-driven back pops exactly one screen', (tester) async {
    // The third screen fires the reserved `back` event, which no state handles,
    // so the controller pops its own history. The view drops the matching
    // route entry without that removal popping the controller a second time.
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(backEventThreeScreenResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'three');

    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'two');
    expect(controller.canBack, isTrue);
  });

  testWidgets('completing the flow drops the whole back history',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(threeScreenResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller, navigatorKey: navigatorKey));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    // `finish` on the third screen ends the flow: two entries go at once.
    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(controller.isComplete, isTrue);
    expect(controller.canBack, isFalse);
    expect(await navigatorKey.currentState!.maybePop(), isFalse);
  });

  testWidgets('an exhausted popHost system back dismisses the flow route',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = appBarController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('Host'))),
    ));
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => RestageFlowView(controller: controller),
    )));
    await tester.pumpAndSettle();
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // With history, system back pops one screen and the flow route stays.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'welcome');
    expect(find.text('Host'), findsNothing);

    // Exhausted, the default policy hands the gesture to the host route.
    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Host'), findsOneWidget);
  });

  testWidgets('the surface scope takes system back while the flow has history',
      (tester) async {
    // The surface's scope blocks the enclosing route's pop while in-flow back
    // is available and hands the gesture to the flow's own navigator. Once
    // exhausted the policy decides; `block()` traps the first screen.
    final controller = loadedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        systemBack: const SystemBackPolicy.block(),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    PopScope<Object?> surfaceScope() =>
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first);

    expect(controller.canBack, isFalse);
    expect(surfaceScope().canPop, isFalse);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);
    expect(surfaceScope().canPop, isFalse);

    // The blocked pop is forwarded to the flow's navigator, which pops one
    // screen rather than trapping the gesture.
    surfaceScope().onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'welcome');
  });

  testWidgets('a controller swap leaves no back history behind',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final first = appBarController();
    addTearDown(first.dispose);
    final second = appBarController();
    addTearDown(second.dispose);

    await tester.pumpWidget(routedFlow(first, navigatorKey: navigatorKey));
    unawaited(first.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(first.canBack, isTrue);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.pumpWidget(routedFlow(second, navigatorKey: navigatorKey));
    unawaited(second.load());
    await tester.pumpAndSettle();
    expect(second.canBack, isFalse);
    expect(find.byType(BackButton), findsNothing);
    expect(await navigatorKey.currentState!.maybePop(), isFalse);
    expect(first.currentScreenId, 'profile');
  });

  testWidgets('unmounting the view leaves no back history behind',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = appBarController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller, navigatorKey: navigatorKey));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('Host'))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);
    expect(await navigatorKey.currentState!.maybePop(), isFalse);
    expect(controller.currentScreenId, 'profile');
  });

  testWidgets('a flow mounted outside any route still navigates',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: RestageFlowView(controller: controller),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(
          tester.element(find.byType(RestageFlowView<FirstRunResult>))),
      isNull,
    );

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    controller.back();
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued multi-step back pops each screen exactly once',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller, navigatorKey: navigatorKey));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    // Two backs before the view rebuilds: both route entries go, and neither
    // removal pops the controller a second time.
    controller.back();
    controller.back();
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'one');
    expect(find.text('One'), findsOneWidget);
    expect(controller.canBack, isFalse);
    expect(await navigatorKey.currentState!.maybePop(), isFalse);
  });

  testWidgets('a skip control in the app bar drives the flow', (tester) async {
    // The reserved `skip` signal is the API for a developer-drawn control, and
    // the app bar's actions slot is where Material puts one.
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        barSkipResolvedFlow(
          welcome: appBarSkipScreenBlob(),
          profile: appBarScreenBlob('Profile', 'finish'),
        ),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(routedFlow(controller));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    final skip = find.descendant(
      of: find.byType(AppBar),
      matching: find.widgetWithText(TextButton, 'Skip'),
    );
    final canSkipBefore = controller.canSkip;
    final skipsInBar = skip.evaluate().length;

    // Guarded so a missing control fails on the expectations below rather than
    // throwing from `tap` while the view is still mounted.
    if (skipsInBar == 1) {
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }
    final screenAfterSkip = controller.currentScreenId;
    final profileVisible = find.text('Profile').evaluate().length;
    await unmountView(tester);

    expect(canSkipBefore, isTrue);
    expect(skipsInBar, 1,
        reason: 'the skip control renders inside the app bar');
    // `profile` is reachable only through the authored skip transition.
    expect(screenAfterSkip, 'profile');
    expect(profileVisible, 1);
  });

  testWidgets('a skip control in the Cupertino navigation bar drives the flow',
      (tester) async {
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        barSkipResolvedFlow(
          welcome: cupertinoBarSkipScreenBlob(),
          profile: cupertinoBarScreenBlob('Profile', 'finish'),
        ),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(CupertinoApp(
      home: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    final skip = find.descendant(
      of: find.byType(CupertinoNavigationBar),
      matching: find.widgetWithText(CupertinoButton, 'Skip'),
    );
    final canSkipBefore = controller.canSkip;
    final skipsInBar = skip.evaluate().length;

    // Guarded so a missing control fails on the expectations below rather than
    // throwing from `tap` while the view is still mounted.
    if (skipsInBar == 1) {
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }
    final screenAfterSkip = controller.currentScreenId;
    await unmountView(tester);

    expect(canSkipBefore, isTrue);
    expect(skipsInBar, 1);
    expect(screenAfterSkip, 'profile');
  });

  testWidgets('a back tap while the flow is busy leaves the route agreed',
      (tester) async {
    // `back()` is inert while a host action is in flight. The route must not
    // drop its entry for a pop that never happens, or the next gesture would
    // dismiss the whole flow.
    final navigatorKey = GlobalKey<NavigatorState>();
    final actions = HoldActionRegistry();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(appBarActionResolvedFlow()),
      actions: actions,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('Host'))),
    ));
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => RestageFlowView(controller: controller),
    )));
    await tester.pumpAndSettle();
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    final hadHistoryOnProfile = controller.canBack;

    // Hold the flow busy on the second screen.
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    final busyDuringAction = controller.isBusy;
    final canPopWhileBusy = tester
        .widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first)
        .canPop;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final screenAfterBusyTap = controller.currentScreenId;
    final historyAfterBusyTap = controller.canBack;
    final hostVisibleAfterBusyTap = find.text('Host').evaluate().isNotEmpty;

    // Settled: the same tap now pops one screen.
    actions.release();
    await tester.pumpAndSettle();
    final busyAfterRelease = controller.isBusy;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final screenAfterSettledTap = controller.currentScreenId;
    final hostVisibleAtEnd = find.text('Host').evaluate().isNotEmpty;
    await unmountView(tester);

    expect(hadHistoryOnProfile, isTrue);
    expect(busyDuringAction, isTrue);
    expect(canPopWhileBusy, isFalse);
    expect(screenAfterBusyTap, 'profile');
    expect(historyAfterBusyTap, isTrue);
    expect(hostVisibleAfterBusyTap, isFalse);
    expect(busyAfterRelease, isFalse);
    expect(screenAfterSettledTap, 'welcome');
    expect(hostVisibleAtEnd, isFalse);
  });

  testWidgets('advancing re-arms the platform back handler', (tester) async {
    // A route dispatches its navigation notification when a pop scope changes,
    // never when its local history does, so the surface announces the change
    // itself — otherwise Android system back leaves the app mid-flow.
    final handled = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handled.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final controller = appBarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(routedFlow(controller));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    handled.clear();

    controller.handleEvent('next', const <String, Object?>{});
    await tester.pumpAndSettle();
    final afterAdvance = List<bool>.of(handled);

    handled.clear();
    controller.back();
    await tester.pumpAndSettle();
    final afterBack = List<bool>.of(handled);
    await unmountView(tester);

    expect(afterAdvance, isNotEmpty,
        reason: 'advancing must re-arm the platform back handler');
    expect(afterAdvance.last, isTrue);
    expect(afterBack, isNotEmpty,
        reason: 'draining the history must hand the question back');
    expect(afterBack.last, isFalse);
  });

  testWidgets('a staged layer never contests the route pop or its history',
      (tester) async {
    // A swap mounts the candidate beside the live layer. A pop scope on the
    // candidate would be consulted first and starve the visible flow's pop,
    // and would run the candidate's exhausted policy.
    final navigatorKey = GlobalKey<NavigatorState>();
    final stagedKey = GlobalKey();
    var liveSkips = 0;
    var stagedSkips = 0;
    final live = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => liveSkips += 1,
      onUnavailable: (_) {},
    );
    addTearDown(live.dispose);
    final staged = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => stagedSkips += 1,
      onUnavailable: (_) {},
    );
    addTearDown(staged.dispose);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: Stack(
        children: [
          RestageFlowView(
            controller: live,
            systemBack: const SystemBackPolicy.complete(),
          ),
          // The candidate is mounted but inert, as a swap stages it.
          IgnorePointer(
            key: stagedKey,
            child: RestageFlowView.staging<FirstRunResult>(
              controller: staged,
              systemBack: const SystemBackPolicy.complete(),
            ),
          ),
        ],
      ),
    ));
    unawaited(live.load());
    unawaited(staged.load());
    await tester.pumpAndSettle();
    live.handleEvent('next', const <String, Object?>{});
    await tester.pumpAndSettle();

    final liveScreen = live.currentScreenId;
    final stagedScreen = staged.currentScreenId;
    // Every scope the candidate contributes allows the pop, so its
    // first-screen `complete()` never wins the disposition.
    final canPops = tester
        .widgetList<PopScope<Object?>>(find.descendant(
          of: find.byKey(stagedKey),
          matching: find.byType(PopScope<Object?>),
        ))
        .map((scope) => scope.canPop)
        .toList();
    final popped = await navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    final liveAfterPop = live.currentScreenId;
    final stagedAfterPop = staged.currentScreenId;
    // The live layer alone held the flow's history; the candidate held none.
    final historyAfterPop = live.canBack;
    await unmountView(tester);

    expect(liveScreen, 'profile');
    expect(stagedScreen, 'welcome');
    expect(canPops, everyElement(isTrue));
    expect(popped, isTrue);
    expect(liveAfterPop, 'welcome');
    expect(stagedAfterPop, 'welcome');
    expect(historyAfterPop, isFalse);
    expect(liveSkips, 0);
    expect(stagedSkips, 0);
  });

  testWidgets('a re-mount with history keeps system back working',
      (tester) async {
    // A re-mounted view holds only the screen the controller currently
    // exposes, so it has no earlier route to pop. System back still moves the
    // flow: the surface navigates the controller instead.
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = appBarController();
    addTearDown(controller.dispose);

    Widget host({required bool showFlow}) => MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: showFlow
                ? RestageFlowView(controller: controller)
                : const SizedBox.shrink(),
          ),
        );

    await tester.pumpWidget(host(showFlow: true));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    await tester.pumpWidget(host(showFlow: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(showFlow: true));
    await tester.pumpAndSettle();
    final restored = find.text('Profile').evaluate().length;

    final popped = await navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    final afterBack = controller.currentScreenId;
    final welcomeShown = find.text('Welcome').evaluate().length;
    await unmountView(tester);

    expect(restored, 1);
    expect(popped, isTrue);
    expect(afterBack, 'welcome');
    expect(welcomeShown, 1);
  });

  testWidgets('iOS leading-edge drag pops in-flow history', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await withIosPlatform(() async {
      await pumpWideFlowAtProfile(tester, controller);
      await tester.dragFrom(const Offset(1, 300), const Offset(520, 0));
      await tester.pumpAndSettle();

      final returnedToWelcome = find.text('Welcome').evaluate().length == 1;
      final canBackAfterDrag = controller.canBack;
      await unmountView(tester);

      expect(returnedToWelcome, isTrue);
      expect(canBackAfterDrag, isFalse);
    });
  });

  Future<void> pumpWideFlowAtProfileThemed(
    WidgetTester tester,
    RestageFlowController<FirstRunResult> controller,
    TargetPlatform platform,
  ) async {
    await tester.pumpWidget(Theme(
      data: ThemeData(platform: platform),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: RestageFlowView(controller: controller),
        ),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
  }

  testWidgets('the theme platform picks the page, not the host platform',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    // Host says Android; the theme says iOS. A host that simulates a device
    // (a preview frame) sets the theme, so the iOS edge drag must pop.
    await withPlatform(TargetPlatform.android, () async {
      await pumpWideFlowAtProfileThemed(tester, controller, TargetPlatform.iOS);
      await tester.dragFrom(const Offset(1, 300), const Offset(520, 0));
      await tester.pumpAndSettle();

      final returnedToWelcome = find.text('Welcome').evaluate().length == 1;
      await unmountView(tester);
      expect(returnedToWelcome, isTrue);
    });
  });

  testWidgets('an Android theme on an iOS host offers no edge drag',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await withIosPlatform(() async {
      await pumpWideFlowAtProfileThemed(
        tester,
        controller,
        TargetPlatform.android,
      );
      await tester.dragFrom(const Offset(1, 300), const Offset(520, 0));
      await tester.pumpAndSettle();

      final stillOnProfile = find.text('Profile').evaluate().length == 1;
      await unmountView(tester);
      expect(stillOnProfile, isTrue);
    });
  });

  testWidgets('iOS leading-edge drag previews back without early mutation',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await withIosPlatform(() async {
      await pumpWideFlowAtProfile(tester, controller);
      final gesture = await tester.startGesture(const Offset(1, 300));
      // The first move only starts the drag, so the preview needs a second.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await tester.pump();

      final currentDuringDrag = controller.currentScreenId;
      final welcomeVisibleDuringDrag =
          find.text('Welcome', skipOffstage: true).evaluate().length == 1;
      final profileVisibleDuringDrag =
          find.text('Profile', skipOffstage: true).evaluate().length == 1;

      await gesture.moveBy(const Offset(-240, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final currentAfterCancel = controller.currentScreenId;
      await unmountView(tester);

      expect(currentDuringDrag, 'profile');
      expect(welcomeVisibleDuringDrag, isTrue);
      expect(profileVisibleDuringDrag, isTrue);
      expect(currentAfterCancel, 'profile');
    });
  });

  testWidgets('an iOS leading-edge drag inside a route pops one entry',
      (tester) async {
    // The commit path goes through the controller, so the matching route entry
    // is dropped under the removal guard rather than popping a second screen.
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await withIosPlatform(() async {
      await tester.pumpWidget(
        routedFlow(controller, navigatorKey: navigatorKey),
      );
      unawaited(controller.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(1, 300), const Offset(520, 0));
      await tester.pumpAndSettle();

      expect(controller.currentScreenId, 'two');
      expect(controller.canBack, isTrue);
    });
  });

  testWidgets('the host route back gesture waits for the flow history to drain',
      (tester) async {
    // A route that will handle a pop internally turns its own back gesture off,
    // so the route's edge swipe is inert while the flow holds history and
    // dismisses the flow route once in-flow back is exhausted.
    final navigatorKey = GlobalKey<NavigatorState>();
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navigatorKey,
      home: const Center(child: Text('Host')),
    ));
    unawaited(navigatorKey.currentState!.push(CupertinoPageRoute<void>(
      builder: (_) => RestageFlowView(controller: controller),
    )));
    await tester.pumpAndSettle();
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final route = hostRoute(tester);
    expect(route.popGestureEnabled, isTrue);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);
    expect(route.popGestureEnabled, isFalse);

    controller.back();
    await tester.pumpAndSettle();
    expect(controller.canBack, isFalse);
    expect(route.popGestureEnabled, isTrue);
  });

  testWidgets('SystemBackPolicy.complete skips the flow when back is exhausted',
      (tester) async {
    var completed = false;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => completed = true,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        systemBack: const SystemBackPolicy.complete(),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(controller.canBack, isFalse);
    expect(controller.canSkip, isTrue);
    final popScope =
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first);
    // .complete() consumes exhausted system-back rather than passing it on.
    expect(popScope.canPop, isFalse);

    popScope.onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets(
      'SystemBackPolicy.complete with no skip destination warns and no-ops',
      (tester) async {
    // .complete() dismisses via the reserved skip signal; with no skip
    // destination wired there is nothing to dismiss to, so exhausted back is a
    // no-op and the surface warns (rather than silently trapping the user).
    var completed = false;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(resolvedFlow()), // default flow: no skip
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => completed = true,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        systemBack: const SystemBackPolicy.complete(),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // First screen: no in-flow history, no skip destination.
    expect(controller.canBack, isFalse);
    expect(controller.canSkip, isFalse);
    final popScope =
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first);
    // .complete() consumes system-back (does not propagate to the host).
    expect(popScope.canPop, isFalse);

    // The warning fires synchronously when the exhausted gesture finds no skip
    // destination. Capture it, restoring debugPrint before the test body ends
    // (the framework asserts foundation debug vars are left at their defaults).
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    try {
      popScope.onPopInvokedWithResult!(false, null);
    } finally {
      debugPrint = originalDebugPrint;
    }
    await tester.pump();

    // No-op (the flow did not complete) and a .complete()-specific warning fired.
    expect(completed, isFalse);
    expect(
      logs.any((l) => l != null && l.contains('SystemBackPolicy.complete()')),
      isTrue,
    );
  });

  testWidgets('the block system-back policy traps back at the first screen',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        systemBack: const SystemBackPolicy.block(),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    final popScope =
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first);
    // block never lets system-back leave the flow, even when exhausted.
    expect(controller.canBack, isFalse);
    expect(popScope.canPop, isFalse);
  });

  testWidgets('the onExhausted policy runs its callback when back is exhausted',
      (tester) async {
    var exhausted = 0;
    final controller = loadedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        systemBack: SystemBackPolicy.onExhausted((_) => exhausted += 1),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    final popScope =
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).first);
    expect(popScope.canPop, isFalse);
    popScope.onPopInvokedWithResult!(false, null);
    expect(exhausted, 1);
  });

  testWidgets('a returned-to (back) screen accepts events; the prior is inert',
      (tester) async {
    final controller = threeScreenController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // One -> Two -> Three.
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);

    // Back to Two: it becomes current again (entry id restored).
    controller.back();
    await tester.pumpAndSettle();
    expect(controller.currentScreenId, 'two');
    // One stays mounted offstage (inert: its RFW events are entry-gated, since
    // its entry id is no longer the controller's current entry).
    expect(find.text('One', skipOffstage: false), findsOneWidget);
    expect(find.text('One', skipOffstage: true), findsNothing);

    // The returned-to screen's RFW events are accepted and drive the flow.
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets(
      'a back-restored screen is preserved intact, not re-decoded '
      '(a poison-on-build flag never re-fires)', (tester) async {
    // The #3 (poisoned-screen-on-restore) assurance. Back restores a screen from
    // its still-mounted element WITHOUT re-running its build (the keystone:
    // state preserved, not re-decoded), so a screen that rendered fine can never
    // spontaneously throw on restore — the poison flag set below has no effect.
    // The fail-closed posture for a screen that genuinely throws *while it is the
    // current screen* is the entry-gated RuntimeErrorBoundary, exercised by
    // 'a screen render failure fails the controller closed': on a render throw,
    // the boundary calls controller.reportRenderFailure (gated to the current
    // entry), failing the flow closed rather than silently swallowing it. Back
    // sets currentScreenEntryId to the restored screen first, so that gate would
    // attribute any throw on the restored screen to it — but with the element
    // preserved, no such throw occurs, which is the desired outcome.
    Restage.debugReset();
    registerConditionalThrowProbe();
    addTearDown(Restage.debugReset);
    addTearDown(() => ConditionalThrowProbe.shouldThrow = false);
    FlowUnavailableError? unavailable;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(conditionalThrowResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (error) => unavailable = error,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('cond'), findsOneWidget);

    // Forward cond -> profile (cond renders fine, then is kept mounted offstage).
    await tester.tap(find.text('cond'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    // Arm the poison flag, then back to cond. The keystone restores the preserved
    // element without re-running build, so the flag never fires: cond comes back
    // intact and the flow does NOT fail closed.
    ConditionalThrowProbe.shouldThrow = true;
    controller.back();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.currentScreenId, 'welcome');
    expect(find.text('cond'), findsOneWidget);
    expect(unavailable, isNull);
    expect(controller.isUnavailable, isFalse);
  });

  testWidgets('a custom transition builder overrides the default',
      (tester) async {
    var transitionCalls = 0;
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        transition: (context, animation, secondary, child, isForward) {
          transitionCalls += 1;
          return child; // instant cut
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(transitionCalls, greaterThan(0));
  });

  testWidgets('a screen render failure fails the controller closed',
      (tester) async {
    Restage.debugReset();
    registerThrowingWidget();
    addTearDown(Restage.debugReset);
    FlowUnavailableError? unavailable;
    var notified = 0;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(throwingResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (error) => unavailable = error,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        onRuntimeError: (_, __) => notified += 1,
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // The boundary swallowed the throw; the controller failed closed.
    expect(tester.takeException(), isNull);
    expect(unavailable?.reason, 'render_failed');
    expect(controller.currentScreenEntryId, isNull);
    expect(controller.hasRenderedContent, isFalse);
    // onRuntimeError fired as a notification (not the safety mechanism).
    expect(notified, 1);
  });

  testWidgets('one back gesture is live at a time, and it is the flow screen',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      final controller = controllerFor(threeScreenResolvedFlow());
      addTearDown(controller.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          }),
        ),
        home: const Scaffold(body: Center(child: Text('Host'))),
      ));
      unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => RestageFlowView(controller: controller),
      )));
      await tester.pumpAndSettle();
      unawaited(controller.load());
      await tester.pumpAndSettle();

      // First screen: in-flow back is exhausted, so the enclosing route owns the
      // gesture and the flow's own screen route does not.
      final atFirst = (
        host: hostPageRoute(tester).popGestureEnabled,
        screen: routeOf(tester, find.text('One')).popGestureEnabled,
      );

      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();

      // With history the pair swaps: the screen route owns the gesture and the
      // enclosing route stands down. The two are never live together.
      final withHistory = (
        host: hostPageRoute(tester).popGestureEnabled,
        screen: routeOf(tester, find.text('Two')).popGestureEnabled,
      );

      final restingTopLeft = tester.getTopLeft(find.text('Two'));
      await backGesture(
        tester,
        const MethodCall('startBackGesture', <String, dynamic>{
          'touchOffset': <double>[5.0, 300.0],
          'progress': 0.0,
          'swipeEdge': 0,
        }),
      );
      await tester.pump();
      await backGesture(
        tester,
        const MethodCall('updateBackGestureProgress', <String, dynamic>{
          'x': 100.0,
          'y': 300.0,
          'progress': 0.4,
          'swipeEdge': 0,
        }),
      );
      await tester.pump();
      // The drag previews the pop: the screen being left moves, the one behind
      // it is revealed, and the controller has not advanced yet.
      final draggedTopLeft = tester.getTopLeft(find.text('Two'));
      final revealed = find.text('One', skipOffstage: true).evaluate().length;
      final screenDuringDrag = controller.currentScreenId;

      await backGesture(tester, const MethodCall('commitBackGesture'));
      await tester.pumpAndSettle();
      final screenAfterCommit = controller.currentScreenId;
      await unmountView(tester);

      expect(atFirst, (host: true, screen: false));
      expect(withHistory, (host: false, screen: true));
      expect(draggedTopLeft.dx, greaterThan(restingTopLeft.dx));
      expect(revealed, 1);
      expect(screenDuringDrag, 'two');
      expect(screenAfterCommit, 'one');
    });
  });

  testWidgets('a cancelled predictive back restores the screen',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      final controller = controllerFor(threeScreenResolvedFlow());
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          }),
        ),
        home: RestageFlowView(controller: controller),
      ));
      unawaited(controller.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();

      final restingTopLeft = tester.getTopLeft(find.text('Two'));
      await backGesture(
        tester,
        const MethodCall('startBackGesture', <String, dynamic>{
          'touchOffset': <double>[5.0, 300.0],
          'progress': 0.0,
          'swipeEdge': 0,
        }),
      );
      await tester.pump();
      await backGesture(
        tester,
        const MethodCall('updateBackGestureProgress', <String, dynamic>{
          'x': 60.0,
          'y': 300.0,
          'progress': 0.2,
          'swipeEdge': 0,
        }),
      );
      await tester.pump();
      await backGesture(tester, const MethodCall('cancelBackGesture'));
      await tester.pumpAndSettle();

      final settledTopLeft = tester.getTopLeft(find.text('Two'));
      final screenAfterCancel = controller.currentScreenId;
      await unmountView(tester);

      expect(screenAfterCancel, 'two');
      expect(settledTopLeft, restingTopLeft);
    });
  });

  testWidgets('a hero flies between two flow screens', (tester) async {
    Restage.debugReset();
    registerHeroProbe();
    addTearDown(Restage.debugReset);
    final controller = controllerFor(heroResolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final start = tester.getRect(find.byKey(heroBoxKey));

    await tester.tap(find.text('go'));
    await tester.pump();
    // Sample the flight: the box exists once and travels between the two
    // resting positions.
    var flyingBoxes = 0;
    var inFlight = start;
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 60));
      final rect = tester.getRect(find.byKey(heroBoxKey));
      if (rect.left > inFlight.left) {
        inFlight = rect;
        flyingBoxes = find.byKey(heroBoxKey).evaluate().length;
      }
    }

    await tester.pumpAndSettle();
    final end = tester.getRect(find.byKey(heroBoxKey));
    await unmountView(tester);

    expect(flyingBoxes, 1, reason: 'the pair flies as one box');
    expect(inFlight.left, greaterThan(start.left));
    expect(inFlight.left, lessThan(end.left));
    expect(inFlight.top, greaterThan(start.top));
    expect(inFlight.top, lessThan(end.top));
  });

  testWidgets('unbounded constraints fail with a message naming the view',
      (tester) async {
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);
    final errors = <Object>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [RestageFlowView(controller: controller)],
      ),
    ));
    unawaited(controller.load());
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await unmountView(tester);
    FlutterError.onError = previousOnError;
    tester.takeException();

    final message = errors.whereType<FlutterError>().map((e) => '$e').join();
    expect(message, contains('RestageFlowView'));
    expect(message, contains('unbounded'));
  });

  testWidgets('the first screen implies dismissal only when the host can pop',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final rootController = controllerFor(appBarResolvedFlow());
    addTearDown(rootController.dispose);

    // The flow is the whole app: nothing to dismiss to, so no back control.
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: RestageFlowView(controller: rootController),
    ));
    unawaited(rootController.load());
    await tester.pumpAndSettle();
    final atRoot = find.byType(BackButton).evaluate().length;

    final pushedController = controllerFor(appBarResolvedFlow());
    addTearDown(pushedController.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('Host'))),
    ));
    await tester.pumpAndSettle();
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => RestageFlowView(controller: pushedController),
    )));
    await tester.pumpAndSettle();
    unawaited(pushedController.load());
    await tester.pumpAndSettle();
    // Pushed onto a host route: the first screen's bar dismisses the flow.
    final whenPushed = find.byType(BackButton).evaluate().length;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final backAtHost = find.text('Host').evaluate().length;
    await unmountView(tester);

    expect(atRoot, 0);
    expect(whenPushed, 1);
    expect(backAtHost, 1);
  });

  testWidgets('a sub-flow barrier shows no back control', (tester) async {
    final child = appBarChildScreenFlow();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: SubFlowResolver(
        root: screenThenSubFlowRoot(child: child),
        child: child,
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(find.text('Welcome bar'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    final onChild = find.text('Child bar').evaluate().length;
    final backControls = find.byType(BackButton).evaluate().length;
    final canBack = controller.canBack;
    // The parent screen is behind a barrier, so it is not on the stack at all.
    final parentMounted =
        find.text('Welcome', skipOffstage: false).evaluate().length;
    await unmountView(tester);

    expect(onChild, 1);
    expect(canBack, isFalse);
    expect(backControls, 0);
    expect(parentMounted, 0);
  });

  testWidgets('the iOS screen swipe is live with history and off at a barrier',
      (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      final child = appBarChildScreenFlow();
      final controller = RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: SubFlowResolver(
          root: screenThenSubFlowRoot(child: child),
          child: child,
        ),
        actions: null,
        onEvent: (_) {},
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(controller.dispose);
      final linear = controllerFor(resolvedFlow());
      addTearDown(linear.dispose);

      await tester.pumpWidget(MaterialApp(
        home: RestageFlowView(controller: linear),
      ));
      unawaited(linear.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      final withHistory =
          routeOf(tester, find.text('Profile')).popGestureEnabled;

      await tester.pumpWidget(MaterialApp(
        home: RestageFlowView(controller: controller),
      ));
      unawaited(controller.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      final atBarrier = routeOf(tester, find.text('Child')).popGestureEnabled;
      await unmountView(tester);

      expect(withHistory, isTrue);
      expect(atBarrier, isFalse);
    });
  });

  testWidgets('a supplied transition drives the screen motion', (tester) async {
    final seen = <({double animation, double secondary, bool isForward})>[];
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: RestageFlowView(
        controller: controller,
        transition: (context, animation, secondary, child, isForward) {
          seen.add((
            animation: animation.value,
            secondary: secondary.value,
            isForward: isForward,
          ));
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final resting = tester.getTopLeft(find.text('Welcome'));

    await tester.tap(find.text('Welcome'));
    // The controller advances, the route is pushed, and the entering screen
    // spends its measuring frame offstage before it paints.
    for (var i = 0; i < 4 && find.text('Profile').evaluate().isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The supplied builder owns the motion: the entering screen slides up.
    final entering = tester.getTopLeft(find.text('Profile'));
    final animating = tester.hasRunningAnimations;

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('Profile'));
    final sawPartialEnter =
        seen.any((call) => call.animation > 0 && call.animation < 1);
    final sawPush = seen.any((call) => call.isForward);
    await unmountView(tester);

    expect(animating, isTrue);
    expect(entering.dy, greaterThan(settled.dy));
    expect(settled, resting);
    expect(sawPartialEnter, isTrue);
    expect(sawPush, isTrue);
  });

  testWidgets('a supplied transition runs in reverse on back', (tester) async {
    final directions = <bool>[];
    final controller = controllerFor(resolvedFlow());
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: RestageFlowView(
        controller: controller,
        transition: (context, animation, secondary, child, isForward) {
          directions.add(isForward);
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();

    directions.clear();
    controller.back();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final sawReverse = directions.contains(false);
    await tester.pumpAndSettle();
    final settledOn = controller.currentScreenId;
    await unmountView(tester);

    expect(sawReverse, isTrue);
    expect(settledOn, 'welcome');
  });
}
