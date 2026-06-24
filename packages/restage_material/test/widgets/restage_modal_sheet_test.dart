import 'package:flutter/cupertino.dart' show CupertinoSheetTransition;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_material/restage_material.dart';

/// Drives `open` so the sheet animates on a state flip, mirroring how a
/// paywall binds the sheet to a local state field.
class _Host extends StatefulWidget {
  const _Host({
    this.isDismissible = true,
    this.enableDrag = true,
    this.onSheetDismissed,
    this.enterDuration,
    this.exitDuration,
    this.enterCurve,
    this.exitCurve,
  });

  final bool isDismissible;
  final bool enableDrag;
  final VoidCallback? onSheetDismissed;
  final Duration? enterDuration;
  final Duration? exitDuration;
  final Curve? enterCurve;
  final Curve? exitCurve;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: ElevatedButton(
            onPressed: () => setState(() => _open = true),
            child: const Text('Open'),
          ),
        ),
        RestageModalSheet(
          open: _open,
          isDismissible: widget.isDismissible,
          enableDrag: widget.enableDrag,
          enterDuration: widget.enterDuration,
          exitDuration: widget.exitDuration,
          enterCurve: widget.enterCurve,
          exitCurve: widget.exitCurve,
          onSheetDismissed: () {
            setState(() => _open = false);
            widget.onSheetDismissed?.call();
          },
          child: const SizedBox(
            height: 300,
            width: double.infinity,
            child: Center(child: Text('Sheet body')),
          ),
        ),
      ],
    );
  }
}

/// Drives `open` imperatively (via [_ControlledHostState.setOpen]) so a
/// test can flip it across frames without relying on a built-in gesture.
/// On dismiss it flips `open` back to `false` (the normal binding) and
/// notifies [onSheetDismissed], so each open→dismiss cycle is observable.
class _ControlledHost extends StatefulWidget {
  const _ControlledHost({this.onSheetDismissed});

  final VoidCallback? onSheetDismissed;

  @override
  State<_ControlledHost> createState() => _ControlledHostState();
}

class _ControlledHostState extends State<_ControlledHost> {
  bool _open = false;

  void setOpen(bool value) => setState(() => _open = value);

  @override
  Widget build(BuildContext context) {
    return RestageModalSheet(
      open: _open,
      onSheetDismissed: () {
        setState(() => _open = false);
        widget.onSheetDismissed?.call();
      },
      child: const SizedBox(
        height: 300,
        width: double.infinity,
        child: Center(child: Text('Sheet body')),
      ),
    );
  }
}

/// Binds `open` to state and flips it false on dismiss (the normal binding),
/// while also exposing [setOpen] for a programmatic close — and supports the
/// enter curve + an owned underlay so a single host covers every close driver
/// across both platform render paths.
class _JitterHost extends StatefulWidget {
  const _JitterHost({this.enterCurve, this.withUnderlay = false});

  final Curve? enterCurve;
  final bool withUnderlay;

  @override
  State<_JitterHost> createState() => _JitterHostState();
}

class _JitterHostState extends State<_JitterHost> {
  bool _open = false;

  void setOpen(bool value) => setState(() => _open = value);

  @override
  Widget build(BuildContext context) {
    return RestageModalSheet(
      open: _open,
      showDragHandle: true,
      enterCurve: widget.enterCurve,
      underlay: widget.withUnderlay
          ? const ColoredBox(color: Color(0xFF202020))
          : null,
      onSheetDismissed: () => setState(() => _open = false),
      child: const SizedBox(
        height: 300,
        width: double.infinity,
        child: Center(child: Text('Sheet body')),
      ),
    );
  }
}

void main() {
  group('RestageModalSheet — slide', () {
    testWidgets('open=false at mount: the sheet is not in the tree',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'a closed sheet renders nothing');
      expect(
        find.descendant(
          of: find.byType(RestageModalSheet),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
        reason: 'a closed sheet has no scrim of its own',
      );
    });

    testWidgets('open=true slides the sheet up monotonically to rest',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      final screenH = tester.getSize(find.byType(MaterialApp)).height;
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pump();

      // First frame after opening: sheet is just below the bottom edge.
      final firstTop = tester.getTopLeft(sheet).dy;
      expect(firstTop, greaterThan(screenH - 50),
          reason: 'the sheet starts near the bottom edge');

      final trace = <double>[firstTop];
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        trace.add(tester.getTopLeft(sheet).dy);
      }
      await tester.pumpAndSettle();
      trace.add(tester.getTopLeft(sheet).dy);

      for (var i = 1; i < trace.length; i++) {
        expect(trace[i], lessThanOrEqualTo(trace[i - 1]),
            reason: 'slide-in should move the sheet top upward');
      }
      expect(trace.last, lessThan(firstTop - 100),
          reason: 'settled sheet should be well above its closed position');
      expect(trace.last, closeTo(screenH - 300, 1.0),
          reason: 'a 300px sheet rests with its top 300px above the bottom');
    });

    testWidgets('open=false reverses the slide, then removes the sheet',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final openTop = tester.getTopLeft(sheet).dy;

      await tester.tapAt(const Offset(10, 10)); // scrim tap → close
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getTopLeft(sheet).dy, greaterThan(openTop),
          reason: 'reverse should move the sheet back down');
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'a fully-closed sheet is removed from the tree');
    });

    testWidgets('open=true at initial mount renders the sheet open',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RestageModalSheet(
            open: true,
            child: SizedBox(height: 300, child: Center(child: Text('Body'))),
          ),
        ),
      );
      // No animation to settle: a true-at-mount sheet shows instantly.
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'an open-at-mount sheet is present');
      expect(find.text('Body'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RestageModalSheet),
          matching: find.byType(ModalBarrier),
        ),
        findsOneWidget,
        reason: 'an open-at-mount sheet has its scrim',
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the sheet stays open after settling');
    });

    testWidgets(
        'rapid open true→false→true before settling: no exception, ends '
        'open, dismiss re-arms', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(MaterialApp(
        home: _ControlledHost(onSheetDismissed: () => dismissed++),
      ));
      final state = tester.state<_ControlledHostState>(
        find.byType(_ControlledHost),
      );

      // Flip open across frames faster than the slide can settle.
      state.setOpen(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      state.setOpen(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      state.setOpen(true);
      await tester.pumpAndSettle();

      // Controller ended in the open state: the sheet is up and resting.
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget, reason: 'ends open after the final flip');
      final screenH = tester.getSize(find.byType(MaterialApp)).height;
      expect(tester.getTopLeft(sheet).dy, closeTo(screenH - 300, 1.0),
          reason: 'a 300px sheet rests with its top 300px above the bottom');

      // Dismiss now: the guard must have re-armed on the last open, so the
      // handler fires exactly once for this open→dismiss cycle.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(dismissed, 1, reason: 'the dismiss guard re-arms on each open');

      // A second open→dismiss cycle fires again (proves per-cycle re-arm).
      state.setOpen(true);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(dismissed, 2,
          reason: 'each open→dismiss cycle fires exactly once');
    });
  });

  group('RestageModalSheet — curve-swap (eased programmatic / linear drag)',
      () {
    testWidgets('programmatic open is EASED (front-loaded), not linear',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pump(); // first frame: animation starts, value ~ 0
      final closedTop = tester.getTopLeft(sheet).dy;

      // Advance to the time-midpoint of the 250ms enter (controller value 0.5).
      await tester.pump(const Duration(milliseconds: 125));
      final midTop = tester.getTopLeft(sheet).dy;

      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;

      final progress = (closedTop - midTop) / (closedTop - restTop);
      // A decelerate (Easing.legacyDecelerate) curve is well past halfway at
      // the time-midpoint (~0.84); a raw-linear slide would sit at ~0.5.
      expect(progress, greaterThan(0.62),
          reason: 'an eased open should be past the linear midpoint at '
              'the time-midpoint; got progress=$progress');
    });

    testWidgets('a drag tracks the finger 1:1 (linear, not eased)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(sheet));
      // Engage the drag past the touch slop first.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
      final engagedTop = tester.getTopLeft(sheet).dy;

      // A further 60px in the fully-engaged drag (childHeight ~ 300) must move
      // the sheet ~60px 1:1; an eased curve would damp it well below that.
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      final moved = tester.getTopLeft(sheet).dy - engagedTop;
      expect(moved, closeTo(60, 12),
          reason: 'a drag must follow the finger 1:1; got $moved');
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('RestageModalSheet — tunable duration + curve', () {
    testWidgets('custom enterDuration lengthens the open animation',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: _Host(enterDuration: Duration(milliseconds: 600)),
      ));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pump();
      // At 250ms into a 600ms enter the sheet is still well short of rest
      // (a default 250ms enter would already be settled here).
      await tester.pump(const Duration(milliseconds: 250));
      final midTop = tester.getTopLeft(sheet).dy;

      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;
      expect(midTop, greaterThan(restTop + 20),
          reason: 'a 600ms enter is still animating at 250ms');
    });

    testWidgets('custom enterCurve overrides the eased default (linear here)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: _Host(enterCurve: Curves.linear),
      ));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pump();
      final closedTop = tester.getTopLeft(sheet).dy;
      await tester.pump(const Duration(milliseconds: 125)); // time-midpoint
      final midTop = tester.getTopLeft(sheet).dy;
      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;

      final progress = (closedTop - midTop) / (closedTop - restTop);
      // A linear enterCurve sits at ~0.5 at the time-midpoint, not the eased
      // default's ~0.84.
      expect(progress, closeTo(0.5, 0.12),
          reason: 'a linear enterCurve makes the open linear; got $progress');
    });

    testWidgets('custom exitDuration + exitCurve lengthen the close',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: _Host(
          exitDuration: Duration(milliseconds: 600),
          exitCurve: Curves.linear,
        ),
      ));
      final sheet = find.byType(BottomSheet);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final openTop = tester.getTopLeft(sheet).dy;

      // Close via a scrim tap (the host flips open=false → reverse over 600ms).
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester
          .pump(const Duration(milliseconds: 250)); // < 600, still closing
      final midTop = tester.getTopLeft(sheet).dy;
      expect(midTop, greaterThan(openTop + 20),
          reason: 'a 600ms close is still animating at 250ms');
      await tester.pumpAndSettle();
    });

    testWidgets('default enter timing matches the framework (250ms eased)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      final sheet = find.byType(BottomSheet);
      await tester.tap(find.text('Open'));
      await tester.pump();
      // After 250ms (the default enter) the sheet has reached rest.
      await tester.pump(const Duration(milliseconds: 250));
      final at250 = tester.getTopLeft(sheet).dy;
      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;
      expect(at250, closeTo(restTop, 1.0),
          reason: 'the default 250ms enter is settled by 250ms');
    });
  });

  group('RestageModalSheet — dismiss triggers', () {
    testWidgets('drag-down past threshold fires onSheetDismissed',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
          MaterialApp(home: _Host(onSheetDismissed: () => dismissed++)));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;

      final gesture = await tester.startGesture(tester.getCenter(sheet));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 45));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getTopLeft(sheet).dy, greaterThan(restTop),
          reason: 'sheet should follow the finger downward during the drag');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dismissed, equals(1),
          reason: 'a single dismiss must fire onSheetDismissed exactly once');
    });

    testWidgets('enableDrag=false: a downward drag does NOT dismiss',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Host(enableDrag: false, onSheetDismissed: () => dismissed++),
      ));
      final sheet = find.byType(BottomSheet);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final restTop = tester.getTopLeft(sheet).dy;

      final gesture = await tester.startGesture(tester.getCenter(sheet));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 45));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dismissed, 0, reason: 'enableDrag=false must not drag-dismiss');
      expect(tester.getTopLeft(sheet).dy, closeTo(restTop, 1.0),
          reason: 'the sheet should not have moved');
    });

    testWidgets('scrim-tap fires onSheetDismissed when isDismissible',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
          MaterialApp(home: _Host(onSheetDismissed: () => dismissed++)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(dismissed, 1);
    });

    testWidgets('scrim-tap does NOT dismiss when isDismissible=false',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Host(isDismissible: false, onSheetDismissed: () => dismissed++),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(dismissed, 0);
    });
  });

  group('RestageModalSheet — platform-adaptive (iOS-B) + underlay', () {
    // Reset inside the body (before the framework checks foundation vars).
    Future<void> withIos(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('iOS renders the sheet via CupertinoSheetTransition',
        (tester) async {
      await withIos(() async {
        await tester.pumpWidget(const MaterialApp(home: _Host()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoSheetTransition), findsOneWidget,
            reason: 'on iOS the sheet slides via the Cupertino transition');
        // The Material drag primitive is still underneath.
        expect(find.byType(BottomSheet), findsOneWidget);
      });
    });

    testWidgets('iOS with an underlay scales it down when the sheet opens',
        (tester) async {
      await withIos(() async {
        const underlayKey = Key('underlay');
        // (open=false unmounts the whole widget — measure the scaled underlay
        // at open=true against the full surface instead.)
        await tester.pumpWidget(
          const MaterialApp(
            home: RestageModalSheet(
              open: true,
              underlay: ColoredBox(
                key: underlayKey,
                color: Color(0xFF2E6BE6),
                child: SizedBox.expand(),
              ),
              child: SizedBox(height: 300),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final appRect = tester.getRect(find.byType(MaterialApp));
        final underlayRect = tester.getRect(find.byKey(underlayKey));

        expect(underlayRect.width, lessThan(appRect.width - 20),
            reason: 'the owned underlay shrinks (iOS scale-down) when open');
        expect(underlayRect.top, greaterThan(appRect.top + 10),
            reason: 'the underlay slides down slightly behind the sheet');
      });
    });

    testWidgets('iOS with a null underlay is a pure overlay + tap-dismisses',
        (tester) async {
      await withIos(() async {
        var dismissed = 0;
        await tester.pumpWidget(
            MaterialApp(home: _Host(onSheetDismissed: () => dismissed++)));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10)); // tap the scrim
        await tester.pump();
        expect(dismissed, 1, reason: 'iOS pure-overlay still tap-dismisses');
      });
    });

    testWidgets('iOS honors a dev enterCurve override (renders + opens)',
        (tester) async {
      await withIos(() async {
        await tester.pumpWidget(const MaterialApp(
          home: _Host(enterCurve: Curves.easeInOutCubic),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // The override branch composes route-free (no double-curve crash) and
        // still slides via the Cupertino transition.
        expect(find.byType(CupertinoSheetTransition), findsOneWidget);
        expect(find.text('Sheet body'), findsOneWidget);
      });
    });

    testWidgets('iOS drag-down still fires onSheetDismissed (Material drag)',
        (tester) async {
      await withIos(() async {
        var dismissed = 0;
        await tester.pumpWidget(
            MaterialApp(home: _Host(onSheetDismissed: () => dismissed++)));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(BottomSheet), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(dismissed, 1,
            reason: 'the Material drag fires through the Cupertino wrapper');
      });
    });
  });

  group('RestageModalSheet — underlay on Android (plain, no scale-down)', () {
    testWidgets(
        'underlay stays visible + interactive while the sheet is closed',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: RestageModalSheet(
          open: false,
          underlay: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('Surface'),
            ),
          ),
          child: const SizedBox(height: 300),
        ),
      ));
      await tester.pumpAndSettle();
      // The owned surface shows even with the sheet closed (the widget no
      // longer collapses to nothing when it owns an underlay).
      expect(find.text('Surface'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'the sheet is absent when closed');
      // …and it is fully interactive (no scrim intercepting).
      await tester.tap(find.text('Surface'));
      await tester.pump();
      expect(taps, 1,
          reason: 'the underlay is interactive while the sheet is closed');
    });

    testWidgets('Android renders the underlay plain (full size), no Cupertino',
        (tester) async {
      const underlayKey = Key('underlay');
      await tester.pumpWidget(
        const MaterialApp(
          home: RestageModalSheet(
            open: true,
            underlay: ColoredBox(
              key: underlayKey,
              color: Color(0xFF2E6BE6),
              child: SizedBox.expand(),
            ),
            child: SizedBox(height: 300),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Android default (test platform): the underlay is NOT scaled down.
      final appRect = tester.getRect(find.byType(MaterialApp));
      final underlayRect = tester.getRect(find.byKey(underlayKey));
      expect(underlayRect.width, closeTo(appRect.width, 1.0),
          reason: 'Android renders the underlay at full size');
      expect(find.byType(CupertinoSheetTransition), findsNothing,
          reason: 'Android uses the Material path');
    });
  });

  group('RestageModalSheet — presentation override', () {
    // Reset the override inside the body (before the framework checks the
    // foundation vars at test end), mirroring the iOS group's `withIos`.
    Future<void> runOn(
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

    Future<void> pumpOpen(
      WidgetTester tester, {
      required RestageSheetPresentation presentation,
      required TargetPlatform platform,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: RestageModalSheet(
            open: true,
            presentation: presentation,
            child: const SizedBox(height: 300, child: Text('body')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('material renders the Material path even on iOS',
        (tester) async {
      await runOn(TargetPlatform.iOS, () async {
        await pumpOpen(tester,
            presentation: RestageSheetPresentation.material,
            platform: TargetPlatform.iOS);
        expect(find.byType(CupertinoSheetTransition), findsNothing,
            reason: 'presentation: material pins the Material path on iOS');
        expect(find.byType(BottomSheet), findsOneWidget);
      });
    });

    testWidgets('cupertino renders the Cupertino path even on Android',
        (tester) async {
      await runOn(TargetPlatform.android, () async {
        await pumpOpen(tester,
            presentation: RestageSheetPresentation.cupertino,
            platform: TargetPlatform.android);
        expect(find.byType(CupertinoSheetTransition), findsOneWidget,
            reason:
                'presentation: cupertino pins the Cupertino path on Android');
      });
    });

    testWidgets('adaptive default follows the platform (iOS -> Cupertino)',
        (tester) async {
      await runOn(TargetPlatform.iOS, () async {
        await pumpOpen(tester,
            presentation: RestageSheetPresentation.adaptive,
            platform: TargetPlatform.iOS);
        expect(find.byType(CupertinoSheetTransition), findsOneWidget,
            reason: 'adaptive on iOS is unchanged (Cupertino card sheet)');
      });
    });

    testWidgets('adaptive default follows the platform (Android -> Material)',
        (tester) async {
      await runOn(TargetPlatform.android, () async {
        await pumpOpen(tester,
            presentation: RestageSheetPresentation.adaptive,
            platform: TargetPlatform.android);
        expect(find.byType(CupertinoSheetTransition), findsNothing,
            reason: 'adaptive on Android is unchanged (Material path)');
      });
    });
  });

  group('RestageModalSheet — full-surface scrim', () {
    testWidgets('open scrim covers the surface and blocks taps to content',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The "Open" button is centered behind the scrim; tapping its
      // location must NOT re-trigger it (the scrim intercepts), it must
      // dismiss the sheet instead (a tap on the scrim, not the button).
      final modalSheet = find.byType(RestageModalSheet);
      final scrim = find.descendant(
        of: modalSheet,
        matching: find.byType(ModalBarrier),
      );
      expect(scrim, findsOneWidget, reason: 'an open sheet has a scrim');
      expect(tester.getSize(scrim), tester.getSize(find.byType(MaterialApp)),
          reason: 'the scrim must cover the whole surface');
    });

    testWidgets('closed sheet does not intercept taps to content behind',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: ElevatedButton(
                onPressed: () => opened++,
                child: const Text('Behind'),
              ),
            ),
            const RestageModalSheet(
              open: false,
              child: SizedBox(height: 300),
            ),
          ],
        ),
      ));
      await tester.tap(find.text('Behind'));
      await tester.pump();
      expect(opened, 1, reason: 'a closed sheet must let taps through');
    });

    testWidgets(
        'self-closed scrim (open stays true, onSheetDismissed null) lets '
        'taps through', (tester) async {
      // The sheet drives itself shut on a drag while `open` stays true and
      // no dismiss handler flips it. The scrim is still mounted at alpha 0
      // but must not intercept taps to the surface beneath it.
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: ElevatedButton(
                onPressed: () => opened++,
                child: const Text('Behind'),
              ),
            ),
            const RestageModalSheet(
              open: true,
              child: SizedBox(
                height: 300,
                width: double.infinity,
                child: Center(child: Text('Sheet body')),
              ),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // Drag the sheet down past the dismiss threshold; with no handler the
      // controller settles to 0 while `open` remains true, so the sheet is
      // not unmounted — only the IgnorePointer keeps the scrim inert.
      final sheet = find.byType(BottomSheet);
      final gesture = await tester.startGesture(tester.getCenter(sheet));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // The scrim is still in the tree (open is still true), at alpha 0.
      final scrim = find.descendant(
        of: find.byType(RestageModalSheet),
        matching: find.byType(ModalBarrier),
      );
      expect(scrim, findsOneWidget,
          reason: 'open stays true so the scrim remains mounted');
      expect(tester.widget<ModalBarrier>(scrim).color!.a, 0.0,
          reason: 'a fully-closed scrim is transparent');

      // A tap on the underlying button must reach it, not the scrim.
      await tester.tap(find.text('Behind'));
      await tester.pump();
      expect(opened, 1,
          reason: 'a transparent self-closed scrim must let taps through');
    });
  });

  group('RestageModalSheet — styling passthrough', () {
    testWidgets('backgroundColor + elevation reach the sheet Material',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RestageModalSheet(
            open: true,
            backgroundColor: Color(0xFF112233),
            elevation: 12,
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, const Color(0xFF112233));
      expect(material.elevation, 12);
    });

    testWidgets('barrierColor tints the scrim', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RestageModalSheet(
            open: true,
            barrierColor: Color(0xFF445566),
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final barrier = tester.widget<ModalBarrier>(
        find.descendant(
          of: find.byType(RestageModalSheet),
          matching: find.byType(ModalBarrier),
        ),
      );
      expect(barrier.color, const Color(0xFF445566));
    });

    testWidgets('scrim alpha animates up as the sheet slides in',
        (tester) async {
      final scrim = find.descendant(
        of: find.byType(RestageModalSheet),
        matching: find.byType(ModalBarrier),
      );
      double scrimAlpha() => tester.widget<ModalBarrier>(scrim).color!.a;

      await tester.pumpWidget(const MaterialApp(home: _Host()));
      await tester.tap(find.text('Open'));
      await tester.pump(); // first frame: t ~ 0, alpha ~ 0
      await tester.pump(const Duration(milliseconds: 80)); // mid-animation
      final midAlpha = scrimAlpha();

      await tester.pumpAndSettle();
      final settledAlpha = scrimAlpha();

      expect(midAlpha, lessThan(settledAlpha),
          reason: 'the scrim alpha must ramp up over the slide-in');
      expect(settledAlpha, closeTo(Colors.black54.a, 0.001),
          reason: 'settled scrim is the opaque default (black54)');
    });

    testWidgets('anchorPoint wraps the sheet in a DisplayFeatureSubScreen',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RestageModalSheet(
            open: true,
            anchorPoint: Offset(100, 100),
            child: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sub = tester.widget<DisplayFeatureSubScreen>(
        find.byType(DisplayFeatureSubScreen),
      );
      expect(sub.anchorPoint, const Offset(100, 100));
    });
  });

  // A drag-release settle must continue the finger's slide smoothly: the
  // rendered sheet only ever moves in the settle's direction (DOWN for a
  // close, UP for a snap-back-open), with no one-frame snap. This closes the
  // class the earlier curve-swap tests missed by using pumpAndSettle (which
  // masks the per-frame discontinuity); here we pump frame-by-frame.
  group('RestageModalSheet — drag-settle is smooth + monotone (no jitter)', () {
    // Frame-by-frame (8ms) capture of the rendered BottomSheet top dy AND the
    // raw controller value, prefixed with the pre-action sample so the
    // action->frame-0 step is measured. Stops on unmount, a settled tail, or
    // the frame cap.
    Future<(List<double> values, List<double> dys)> capture(
      WidgetTester tester, {
      required double startValue,
      required double startDy,
    }) async {
      final values = <double>[startValue];
      final dys = <double>[startDy];
      var stable = 0;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        if (!tester.any(find.byType(BottomSheet))) break;
        final value = tester
            .widget<BottomSheet>(find.byType(BottomSheet))
            .animationController!
            .value;
        final dy = tester.getTopLeft(find.byType(BottomSheet)).dy;
        final moved = (dy - dys.last).abs();
        values.add(value);
        dys.add(dy);
        if (moved < 0.05) {
          if (++stable >= 4) break;
        } else {
          stable = 0;
        }
      }
      return (values, dys);
    }

    // Flutter-identity for a drag-release settle: the rendered slide is the
    // controller value mapped by an IDENTITY/linear curve. iOS keeps
    // `linearTransition: true` through the settle (== Flutter's route, which
    // holds `popGestureInProgress` true so it never swaps the curve mid-flight,
    // `cupertino/sheet.dart` linearTransition = popGestureInProgress); the
    // Material drag-close runs in the `Split`'s below-split identity region
    // (`Split.transform(v) == v` for `v < split`, == `_ModalBottomSheetState`).
    // So the rendered dy is AFFINE in the controller value across the settle.
    // The jitter bug — the iOS curve/driver swap, or the Material curve reset —
    // maps the same value through a non-identity curve, breaking affinity.
    void expectAffineInValue(
      List<double> values,
      List<double> dys, {
      required String reason,
      double tol = 2.0,
    }) {
      final n = values.length;
      expect(n, greaterThan(3),
          reason: 'too few frames for an affinity fit ($reason)');
      final meanV = values.reduce((a, b) => a + b) / n;
      final meanD = dys.reduce((a, b) => a + b) / n;
      var cov = 0.0;
      var varV = 0.0;
      for (var i = 0; i < n; i++) {
        cov += (values[i] - meanV) * (dys[i] - meanD);
        varV += (values[i] - meanV) * (values[i] - meanV);
      }
      final m = varV == 0 ? 0.0 : cov / varV;
      final c = meanD - m * meanV;
      var maxResidual = 0.0;
      for (var i = 0; i < n; i++) {
        final residual = (dys[i] - (m * values[i] + c)).abs();
        if (residual > maxResidual) maxResidual = residual;
      }
      expect(maxResidual, lessThan(tol),
          reason: 'rendered dy is NOT affine in the controller value '
              '(max residual ${maxResidual.toStringAsFixed(1)}px) — the '
              'linearTransition/Split-identity mapping is not in effect '
              '($reason); values=$values dys=$dys');
    }

    // `down` = the allowed travel direction. A move in the forbidden direction
    // beyond `eps` is the jitter; a single-frame move beyond `maxStep` in the
    // allowed direction is a snap discontinuity (e.g. the no-override iOS
    // down-snap). `maxStep` sits above the legitimate eased-close peak
    // (~63px/frame for the iOS fastEaseInToSlowEaseOut tail) and below the
    // curve-swap snaps (≥119px/frame).
    void expectSmoothMonotone(
      List<double> dys, {
      required bool down,
      required String reason,
      double eps = 1.5,
      double maxStep = 90,
    }) {
      expect(dys.length, greaterThan(2),
          reason: 'too few frames to judge ($reason); trace=$dys');
      for (var i = 1; i < dys.length; i++) {
        final delta = dys[i] - dys[i - 1]; // + => moved DOWN
        final wrongWay = down ? -delta : delta;
        final rightWay = down ? delta : -delta;
        expect(wrongWay, lessThan(eps),
            reason: 'frame $i moved the WRONG way '
                '${wrongWay.toStringAsFixed(1)}px ($reason) — the jitter; '
                'trace=$dys');
        expect(rightWay, lessThan(maxStep),
            reason: 'frame $i jumped ${rightWay.toStringAsFixed(1)}px in one '
                'step ($reason) — a snap discontinuity; trace=$dys');
      }
    }

    // Drags the sheet down until the controller is at/below `target`, bleeding
    // the pointer velocity so the release takes the value-based branch (a slow
    // fling-close below 0.5, or a snap-back-open above 0.5) — never a
    // high-velocity fling.
    Future<TestGesture> dragToValue(WidgetTester tester, double target) async {
      final sheet = find.byType(BottomSheet);
      double value() =>
          tester.widget<BottomSheet>(sheet).animationController!.value;
      final gesture = await tester.startGesture(tester.getCenter(sheet));
      await gesture.moveBy(const Offset(0, 40)); // past the touch slop
      await tester.pump();
      var guard = 0;
      while (value() > target && guard++ < 80) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump();
      }
      await gesture.moveBy(Offset.zero);
      await tester.pump(const Duration(milliseconds: 250)); // decay velocity
      return gesture;
    }

    // Reset the platform override inside the body (before the framework checks
    // foundation vars at test end), mirroring the iOS group's `withIos`.
    Future<void> runOn(
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

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      final isIos = platform == TargetPlatform.iOS;
      for (final enterCurve in <Curve?>[null, Curves.easeOutCubic]) {
        final label =
            '${isIos ? 'iOS' : 'Material'}${enterCurve == null ? '' : ' +curve'}';

        Future<void> pumpHost(WidgetTester tester) async {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: _JitterHost(enterCurve: enterCurve, withUnderlay: isIos),
            ),
          ));
        }

        _JitterHostState host(WidgetTester tester) =>
            tester.state<_JitterHostState>(find.byType(_JitterHost));

        double controllerValue(WidgetTester tester) => tester
            .widget<BottomSheet>(find.byType(BottomSheet))
            .animationController!
            .value;

        testWidgets('drag-release-to-close stays monotone DOWN ($label)',
            (tester) async {
          await runOn(platform, () async {
            await pumpHost(tester);
            host(tester).setOpen(true);
            await tester.pumpAndSettle();
            final gesture = await dragToValue(tester, 0.25); // below threshold
            final startValue = controllerValue(tester);
            final startDy = tester.getTopLeft(find.byType(BottomSheet)).dy;
            await gesture.up();
            final (values, dys) =
                await capture(tester, startValue: startValue, startDy: startDy);
            expectSmoothMonotone(dys, down: true, reason: '$label drag-close');
            // Flutter-identity: a drag-close settle renders linearly (iOS
            // linearTransition:true; Material Split below-split identity).
            expectAffineInValue(values, dys, reason: '$label drag-close');
          });
        });

        testWidgets('drag-release snap-back-open stays monotone UP ($label)',
            (tester) async {
          await runOn(platform, () async {
            await pumpHost(tester);
            host(tester).setOpen(true);
            await tester.pumpAndSettle();
            final gesture = await dragToValue(tester, 0.70); // above threshold
            final startValue = controllerValue(tester);
            final startDy = tester.getTopLeft(find.byType(BottomSheet)).dy;
            await gesture.up();
            final (values, dys) =
                await capture(tester, startValue: startValue, startDy: startDy);
            expectSmoothMonotone(dys,
                down: false, reason: '$label snap-back-open');
            // Flutter-identity: iOS holds linearTransition:true through the
            // snap-back settle (linear). (Material snap-back runs the Split's
            // eased above-split region — Flutter-identical by construction, no
            // affinity assertion.)
            if (isIos) {
              expectAffineInValue(values, dys,
                  reason: '$label snap-back-open (iOS linearTransition)');
            }
          });
        });

        testWidgets('programmatic close stays monotone DOWN ($label)',
            (tester) async {
          await runOn(platform, () async {
            await pumpHost(tester);
            host(tester).setOpen(true);
            await tester.pumpAndSettle();
            final startValue = controllerValue(tester);
            final startDy = tester.getTopLeft(find.byType(BottomSheet)).dy;
            host(tester).setOpen(false);
            // A programmatic close is EASED (the route's non-gesture curve), not
            // linear — so no affinity assertion here; smoothness is the bar.
            final (_, dys) =
                await capture(tester, startValue: startValue, startDy: startDy);
            expectSmoothMonotone(dys,
                down: true, reason: '$label programmatic close');
          });
        });

        testWidgets('scrim-tap close stays monotone DOWN ($label)',
            (tester) async {
          await runOn(platform, () async {
            await pumpHost(tester);
            host(tester).setOpen(true);
            await tester.pumpAndSettle();
            final startValue = controllerValue(tester);
            final startDy = tester.getTopLeft(find.byType(BottomSheet)).dy;
            await tester.tapAt(const Offset(400, 40)); // scrim, above the sheet
            await tester.pump();
            // A scrim-tap close is EASED (programmatic), not linear.
            final (_, dys) =
                await capture(tester, startValue: startValue, startDy: startDy);
            expectSmoothMonotone(dys,
                down: true, reason: '$label scrim-tap close');
          });
        });
      }
    }
  });
}
