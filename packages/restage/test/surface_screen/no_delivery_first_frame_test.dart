import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../support/debug_print_capture.dart';

/// Swaps the wrapper around [child] like a transition that changes with
/// Reduce Motion, so the child's subtree mounts again.
final class _Wrapper extends StatelessWidget {
  const _Wrapper({required this.fade, required this.child});

  final bool fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => fade
      ? FadeTransition(opacity: kAlwaysCompleteAnimation, child: child)
      : SlideTransition(
          position: const AlwaysStoppedAnimation(Offset.zero), child: child);
}

/// An app whose page transition changes type with Reduce Motion, as an
/// onboarding flow's page turn can.
final class _ReduceMotionApp extends StatelessWidget {
  const _ReduceMotionApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: _Wrapper(
              fade: MediaQuery.disableAnimationsOf(context),
              child: const NativeNoticeSurface('Notice original'),
            ),
          ),
        ),
      );
}

Widget _app({bool fade = false, Widget? mount}) => MaterialApp(
      home: Scaffold(
        body: _Wrapper(
          fade: fade,
          child: mount ?? const NativeNoticeSurface('Notice original'),
        ),
      ),
    );

void main() {
  setUp(Restage.debugReset);

  final setups = <String, void Function()>{
    'Restage not configured': () {},
    'no key': Restage.configure,
    'delivery turned off': () => Restage.configure(apiKey: ''),
  };

  for (final MapEntry(key: label, value: setup) in setups.entries) {
    testWidgets('the compiled original shows on the first frame: $label',
        (tester) async {
      setup();
      final logs = await captureRestageLogs(() async {
        await tester.pumpWidget(_app());
        expect(find.text('Notice original'), findsOneWidget);
        await tester.pump();
      });

      expect(logs.where((line) => line.contains('resolve failed')), isEmpty);
    });

    testWidgets(
        'turning on Reduce Motion, which remounts the page, never blanks the '
        'original: $label', (tester) async {
      setup();
      await tester.pumpWidget(const _ReduceMotionApp());
      expect(find.text('Notice original'), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Notice original'), findsOneWidget,
            reason: 'frame $frame after the change');
      }
      expect(tester.widget(find.byType(_Wrapper)),
          isA<_Wrapper>().having((wrapper) => wrapper.fade, 'fade', isTrue));
    });

    testWidgets('a mount that mounts again shows its original at once: $label',
        (tester) async {
      setup();
      await tester.pumpWidget(_app());
      await tester.pumpWidget(_app(fade: true));

      expect(find.text('Notice original'), findsOneWidget);
    });
  }

  testWidgets('a MediaQuery change neither resolves again nor blanks',
      (tester) async {
    final resolver = _CountingResolver();
    Widget app(bool reduce) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
                body: NativeNoticeSurface(
                    'Notice original', 2, null, null, resolver)),
          ),
        );
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(find.text('Notice original'), findsOneWidget);

    await tester.pumpWidget(app(true));

    expect(find.text('Notice original'), findsOneWidget);
    expect(resolver.calls, 1);
  });

  testWidgets('an unconfigured paywall logs only the configuration hint',
      (tester) async {
    final logs = await captureRestageLogs(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NativeOfferSurface())));
      await tester.pump();
    });

    expect(find.text('Offer original'), findsOneWidget);
    expect(logs, [
      "[restage] `NativeOfferSurface` can't receive published designs because "
          "Restage isn't configured. Try calling `Restage.configure` in "
          '`main()`.',
    ]);
  });

  testWidgets('onUnavailable still reports the missing screen after the frame',
      (tester) async {
    final reasons = <SurfaceScreenUnavailableReason>[];
    await tester.pumpWidget(_app(
        mount: NativeNoticeSurface('Notice original', 2, null, null, null,
            (error) => reasons.add(error.reason))));

    expect(find.text('Notice original'), findsOneWidget);
    await tester.pump();
    expect(reasons, [SurfaceScreenUnavailableReason.missing]);
  });

  testWidgets('a custom resolver still resolves before the original shows',
      (tester) async {
    final resolver = _PendingResolver();
    await tester.pumpWidget(_app(
        mount:
            NativeNoticeSurface('Notice original', 2, null, null, resolver)));

    expect(resolver.calls, 1);
    expect(find.text('Notice original'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

final class _PendingResolver implements SurfaceScreenResolver {
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) {
    calls += 1;
    return Completer<ResolvedSurfaceScreen>().future;
  }
}

final class _CountingResolver implements SurfaceScreenResolver {
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    calls += 1;
    throw const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.missing,
      message: 'Nothing to deliver.',
    );
  }
}
