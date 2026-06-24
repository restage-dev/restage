import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

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

/// Whether [leaf] has an enclosing `IgnorePointer(ignoring: true)` up to the
/// [RestageFlowView] — i.e. taps on it are currently swallowed. Used to assert
/// the built-in chrome goes inert while the controller is busy.
bool _chromeIgnoring(WidgetTester tester, Finder leaf) {
  var ignoring = false;
  tester.element(leaf).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is IgnorePointer && widget.ignoring) {
      ignoring = true;
      return false;
    }
    return widget is! RestageFlowView;
  });
  return ignoring;
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
    await tester.pump(); // controller advances + the transition kicks off
    await tester.pump(const Duration(milliseconds: 120)); // mid-flight

    expect(tester.hasRunningAnimations, isTrue);
    // Both the incoming and outgoing screens are on-screen (not an instant cut).
    expect(find.text('Profile', skipOffstage: true), findsOneWidget);
    expect(find.text('Welcome', skipOffstage: true), findsOneWidget);

    await tester.pumpAndSettle();
    // Settled: only the incoming screen remains on-screen.
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Welcome', skipOffstage: true), findsNothing);
  });

  testWidgets('taps during a forward transition are ignored', (tester) async {
    var completed = false;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(resolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => completed = true,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // welcome -> profile: the transition starts.
    await tester.tap(find.text('Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight
    expect(tester.hasRunningAnimations, isTrue);

    // A tap landing on the still-animating (possibly transparent / off-screen)
    // incoming screen must be ignored — not fire its event.
    await tester.tap(find.text('Profile'), warnIfMissed: false);
    await tester.pump();
    expect(completed, isFalse);

    await tester.pumpAndSettle();
    expect(completed, isFalse);

    // Once settled the screen is interactive again: finish -> done -> complete.
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
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

  testWidgets(
      'the iOS back chrome uses a bundled Material icon, not a CupertinoIcons '
      'font glyph', (tester) async {
    // The CupertinoIcons font ships only when the consuming app depends on
    // `cupertino_icons`; a Cupertino glyph would render as a missing-glyph box
    // on iOS in apps that do not. The chrome back affordance must use a Material
    // icon (bundled via `uses-material-design`).
    final controller = loadedController();
    addTearDown(controller.dispose);
    // Reset the platform override inside the body (a tearDown runs after the
    // framework's foundation-vars invariant check, which would then fail).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFlowView(controller: controller),
      ));
      unawaited(controller.load());
      await tester.pumpAndSettle();

      // welcome -> profile, so the back affordance is shown (canBack is true).
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      expect(controller.canBack, isTrue);

      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.back), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Theme rung: chromeTheme restyles the default back affordance',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeTheme: const FlowChromeTheme(
          backIcon: Icons.close,
          color: Color(0xFFFF0000),
          size: 40,
        ),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // welcome -> profile, so the back affordance is shown (canBack is true).
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    // The actual rendered Icon carries the themed icon/color/size — not just
    // "an icon is present".
    final icon = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(icon.icon, Icons.close);
    expect(icon.color, const Color(0xFFFF0000));
    expect(icon.size, 40);
    // The default arrow is gone (the theme replaced it).
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets(
      'persistentChrome:true (default) keeps the chrome at full opacity '
      'during a screen transition', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeTheme: const FlowChromeTheme(backIcon: Icons.close),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // Start the forward transition to profile (canBack becomes true). The
    // persistent chrome must NOT fade with the incoming screen.
    await tester.tap(find.text('Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160)); // mid-transition
    expect(tester.hasRunningAnimations, isTrue);

    final midOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(
      midOpacity,
      greaterThan(0.99),
      reason: 'persistent chrome frames the flow outside the transition, so it '
          'does not fade with the animating screen (was $midOpacity)',
    );
  });

  testWidgets(
      'persistentChrome:false rides the screen (fades with it during a '
      'transition)', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        persistentChrome: false,
        chromeTheme: const FlowChromeTheme(backIcon: Icons.close),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160)); // mid-transition
    expect(tester.hasRunningAnimations, isTrue);

    final midOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    // After settling, the per-screen chrome is fully visible at rest.
    final restOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));
    expect(
      midOpacity,
      lessThan(0.99),
      reason: 'per-screen chrome lives inside the animated slot, so it fades '
          'with the incoming screen mid-transition (was $midOpacity)',
    );
    expect(restOpacity, greaterThan(0.99),
        reason: 'per-screen chrome settles fully visible at rest');
  });

  testWidgets(
      'Slots rung: backBuilder supplies the back widget; the SDK positions it '
      'at the start edge and wires the pop', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        backBuilder: (context, onAction) => GestureDetector(
          onTap: onAction,
          child: const Text('CUSTOMBACK', textDirection: TextDirection.ltr),
        ),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);

    // The custom widget is shown at the top-start corner (real positioning),
    // and the default arrow is replaced.
    expect(find.text('CUSTOMBACK'), findsOneWidget);
    final topLeft = tester.getTopLeft(find.text('CUSTOMBACK'));
    expect(topLeft.dx, lessThan(120), reason: 'back slot at the start edge');
    expect(topLeft.dy, lessThan(120), reason: 'back slot near the top');
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    // Tapping the slot pops to welcome.
    await tester.tap(find.text('CUSTOMBACK'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(controller.canBack, isFalse);
  });

  testWidgets(
      'Slots rung: skipBuilder supplies the skip widget at the end edge and '
      'wires skip', (tester) async {
    FirstRunResult? completed;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (result) => completed = result,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        enableSkip: true,
        skipBuilder: (context, onAction) => GestureDetector(
          onTap: onAction,
          child: const Text('CUSTOMSKIP', textDirection: TextDirection.ltr),
        ),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(controller.canSkip, isTrue);

    expect(find.text('CUSTOMSKIP'), findsOneWidget);
    final topRight = tester.getTopRight(find.text('CUSTOMSKIP'));
    expect(topRight.dx, greaterThan(680), reason: 'skip slot at the end edge');
    expect(tester.getTopLeft(find.text('CUSTOMSKIP')).dy, lessThan(120));

    await tester.tap(find.text('CUSTOMSKIP'));
    await tester.pumpAndSettle();
    expect(completed, isNotNull, reason: 'skip routed to the end state');
  });

  testWidgets(
      'LOW: the built-in chrome goes inert without dimming while the controller is '
      'busy', (tester) async {
    final hold = HoldActionRegistry();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(actionFromProfileResolvedFlow()),
      actions: hold,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeTheme: const FlowChromeTheme(backIcon: Icons.close),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // welcome -> profile (canBack true); at rest the chrome is interactive.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    final canBackAtRest = controller.canBack;
    final busyAtRest = controller.isBusy;
    final ignoringAtRest = _chromeIgnoring(tester, find.byIcon(Icons.close));
    final restOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));

    // Fire the action; it holds in flight (isBusy true) until released.
    controller.handleEvent('request', const <String, Object?>{});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final busyDuringAction = controller.isBusy;

    // The auto-shown chrome is now inert (taps swallowed) without visual
    // opacity churn.
    final ignoringDuringAction =
        _chromeIgnoring(tester, find.byIcon(Icons.close));
    final busyOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));

    hold.release();
    await tester.pumpAndSettle();
    await unmountView(tester);

    expect(canBackAtRest, isTrue);
    expect(busyAtRest, isFalse);
    expect(ignoringAtRest, isFalse);
    expect(restOpacity, greaterThan(0.99));
    expect(busyDuringAction, isTrue);
    expect(ignoringDuringAction, isTrue);
    expect(
      busyOpacity,
      greaterThan(0.99),
      reason: 'host-action busy state should gate taps without dimming chrome',
    );
  });

  testWidgets(
      'short host actions keep built-in chrome inert without a visual '
      'flash-dim', (tester) async {
    final hold = HoldActionRegistry();
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(actionFromProfileResolvedFlow()),
      actions: hold,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeTheme: const FlowChromeTheme(backIcon: Icons.close),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    final restOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));

    controller.handleEvent('request', const <String, Object?>{});
    await tester.pump(const Duration(milliseconds: 16));
    final busy = controller.isBusy;
    final ignoring = _chromeIgnoring(tester, find.byIcon(Icons.close));
    final earlyOpacity = _effectiveOpacity(tester, find.byIcon(Icons.close));

    hold.release(result: true);
    await tester.pumpAndSettle();
    await unmountView(tester);

    expect(restOpacity, greaterThan(0.99));
    expect(busy, isTrue);
    expect(ignoring, isTrue);
    expect(
      earlyOpacity,
      greaterThan(0.99),
      reason: 'brief host actions should not produce a one-frame chrome flash',
    );
  });

  testWidgets(
      'Layout rung: chromeBuilder composes per-screen chrome from the '
      'FlowChromeState and suppresses the built-in chrome', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);
    late FlowChromeState seen;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeBuilder: (context, state, screen) {
          seen = state;
          return Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              screen,
              if (state.canBack)
                Positioned(
                  top: 0,
                  left: 0,
                  child: GestureDetector(
                    onTap: state.onBack,
                    child: Text(
                      'LAYOUTBACK:${state.screenId}',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // First screen: the screen renders, no custom back yet, and the built-in
    // chrome is suppressed (chromeBuilder owns the chrome).
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.textContaining('LAYOUTBACK'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    // welcome -> profile: the custom chrome appears, with the correct state.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('LAYOUTBACK:profile'), findsOneWidget);
    expect(seen.canBack, isTrue);
    expect(seen.screenId, 'profile');
    expect(seen.isForward, isTrue);
    expect(seen.isComplete, isFalse);

    // The custom back is wired to the pop.
    await tester.tap(find.text('LAYOUTBACK:profile'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.textContaining('LAYOUTBACK'), findsNothing);
  });

  testWidgets(
      'Layout rung: persistentChromeBuilder frames the flow and stays put '
      'during a transition', (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        persistentChromeBuilder: (context, state, flowBody) => Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            flowBody,
            Positioned(
              top: 0,
              left: 0,
              child: Text(
                'FRAME:${state.canBack}',
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(
        find.text('FRAME:false'), findsOneWidget); // canBack false on welcome
    expect(find.byIcon(Icons.arrow_back), findsNothing); // built-in suppressed

    // Forward: the frame stays at full opacity while the screen animates.
    await tester.tap(find.text('Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final frameOpacity =
        _effectiveOpacity(tester, find.textContaining('FRAME:'));
    await tester.pumpAndSettle();
    expect(
      frameOpacity,
      greaterThan(0.99),
      reason: 'the persistent frame does not fade with the animating screen',
    );
    expect(find.text('FRAME:true'), findsOneWidget); // canBack true on profile
  });

  testWidgets('MED-3: the built-in chrome collapses once the flow completes',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(
        controller: controller,
        chromeTheme: const FlowChromeTheme(backIcon: Icons.close),
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // welcome -> profile: the back chevron is shown.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);

    // profile -> finish -> done: the flow completes and the chrome collapses
    // (canBack/canSkip are false once complete; the surface rebuilds on the
    // completion notification).
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(controller.isComplete, isTrue);
    expect(find.byIcon(Icons.close), findsNothing);
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
    expect(find.text('Welcome'), findsOneWidget);
    // The first screen is shown at rest — no enter animation runs.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a Semantics-reachable back affordance shows when canBack + pops',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // No back affordance on the first screen.
    expect(find.bySemanticsLabel('Back'), findsNothing);

    // Forward -> profile: the default back affordance appears.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    // Tapping it pops back to welcome.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
  });

  testWidgets(
      'the auto-shown back chrome is a pure pop, ignoring an authored on[back]',
      (tester) async {
    // The SDK's auto-shown back chevron is a pure history pop; it must NOT take
    // an authored on['back'] transition (that hook is reserved for an
    // author-PLACED in-screen control). Here profile authors on['back']: ->done,
    // so a non-pure chrome back would complete the flow instead of popping.
    var completed = false;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(authoredBackResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) => completed = true,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    // welcome -> profile (profile authors on['back']: ->done).
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(controller.canBack, isTrue);

    // Tap the auto-shown back chevron: it pops to welcome (history pop), not
    // the authored on['back'] -> done transition (which would complete).
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(controller.currentScreenId, 'welcome');
    expect(completed, isFalse);
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
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
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

  testWidgets('the skip affordance shows only when enabled and wired',
      (tester) async {
    // enableSkip false -> no skip even though the screen is wired.
    final off = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(off.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: off),
    ));
    unawaited(off.load());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Skip'), findsNothing);

    // enableSkip true + a wired screen -> the skip affordance shows.
    final on = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(skipResolvedFlow()),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(on.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: on, enableSkip: true),
    ));
    unawaited(on.load());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Skip'), findsOneWidget);
  });

  testWidgets('enabled skip on an unwired screen shows no dead button',
      (tester) async {
    // enableSkip true but the default first-run flow has no skip destination.
    final controller = loadedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller, enableSkip: true),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(controller.canSkip, isFalse);
    expect(find.bySemanticsLabel('Skip'), findsNothing);
  });

  testWidgets('system back pops in-flow first, then applies the policy',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageFlowView(controller: controller),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();

    PopScope<Object?> popScope() =>
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));

    // On the first screen (no in-flow history), the default popHost policy lets
    // system-back propagate to the host.
    expect(controller.canBack, isFalse);
    expect(popScope().canPop, isTrue);

    // Forward -> profile: system-back is now consumed (canPop false) and pops.
    await tester.tap(find.text('Welcome'));
    await tester.pumpAndSettle();
    expect(controller.canBack, isTrue);
    expect(popScope().canPop, isFalse);
    popScope().onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    expect(controller.canBack, isFalse);
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

  testWidgets('iOS leading-edge drag previews back without early mutation',
      (tester) async {
    final controller = loadedController();
    addTearDown(controller.dispose);

    await withIosPlatform(() async {
      await pumpWideFlowAtProfile(tester, controller);
      final gesture = await tester.startGesture(const Offset(1, 300));
      await gesture.moveBy(const Offset(240, 0));
      await tester.pump();

      final currentDuringDrag = controller.currentScreenId;
      final welcomeVisibleDuringDrag =
          find.text('Welcome', skipOffstage: true).evaluate().length == 1;
      final profileVisibleDuringDrag =
          find.text('Profile', skipOffstage: true).evaluate().length == 1;

      await gesture.moveBy(const Offset(-240, 0));
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
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
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
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
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

  testWidgets('the default transition is platform-adaptive', (tester) async {
    Widget probe() => Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => defaultFlowTransitionBuilder(
              context,
              const AlwaysStoppedAnimation<double>(0.5),
              const AlwaysStoppedAnimation<double>(0),
              const SizedBox.shrink(),
              true,
            ),
          ),
        );

    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(probe());
      expect(find.byType(CupertinoPageTransition), findsOneWidget);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(probe());
      expect(find.byType(CupertinoPageTransition), findsNothing);
      expect(find.byType(SharedAxisTransition), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
    // onRuntimeError fired as a notification (not the safety mechanism).
    expect(notified, 1);
  });
}
