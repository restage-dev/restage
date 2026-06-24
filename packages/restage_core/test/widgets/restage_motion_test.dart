import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

/// The runtime proof for the spring centerpiece: a spring entrance VISIBLY
/// overshoots its target (the difference from a curve tween — the whole point
/// of the cut), a critically-damped preset does not overshoot, and the
/// completion event fires exactly once and never after disposal.
void main() {
  // The current uniform scale of the single Transform.scale that RestageMotion
  // applies when `fromScale != 1.0`. Read storage[0] (the x-scale) directly —
  // getMaxScaleOnAxis() floors at 1.0 for scales below 1.0 (the untouched
  // z-axis column dominates), which would mask the from-state.
  double scaleOf(WidgetTester tester) =>
      tester.widget<Transform>(find.byType(Transform)).transform.storage[0];

  group('RestageMotion', () {
    testWidgets('a bouncy entrance overshoots the target scale',
        (tester) async {
      await tester.pumpWidget(
        const Center(
          child: RestageMotion(
            spring: RestageSpring.bouncy,
            fromScale: 0.5,
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );

      var maxScale = 0.0;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final s = scaleOf(tester);
        if (s > maxScale) maxScale = s;
      }
      // Overshoot: the rendered scale exceeds the rest value 1.0 at some frame.
      expect(maxScale, greaterThan(1.0));
      await tester.pumpAndSettle();
    });

    testWidgets('a smooth (critically damped) entrance does NOT overshoot',
        (tester) async {
      await tester.pumpWidget(
        const Center(
          child: RestageMotion(
            spring: RestageSpring.smooth,
            fromScale: 0.5,
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );

      var maxScale = 0.0;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final s = scaleOf(tester);
        if (s > maxScale) maxScale = s;
      }
      // No overshoot — approaches 1.0 from below (small epsilon for float math).
      expect(maxScale, lessThanOrEqualTo(1.01));
      await tester.pumpAndSettle();
    });

    testWidgets('onEnd fires exactly once when the entrance settles',
        (tester) async {
      var ends = 0;
      await tester.pumpWidget(
        Center(
          child: RestageMotion(
            spring: RestageSpring.smooth,
            fromOpacity: 0,
            onEnd: () => ends++,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(ends, 1);
    });

    testWidgets('disposing mid-entrance does not call onEnd', (tester) async {
      var ends = 0;
      await tester.pumpWidget(
        Center(
          child: RestageMotion(
            spring: RestageSpring.gentle, // 800ms — long enough to interrupt
            fromScale: 0.2,
            onEnd: () => ends++,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Replace the subtree mid-entrance — RestageMotion is disposed.
      await tester.pumpWidget(const Center(child: SizedBox()));
      await tester.pumpAndSettle();
      expect(ends, 0);
    });

    testWidgets(
        'a NaN/Infinity from-state renders finite (identity), not '
        'garbage', (tester) async {
      const key = Key('motion-child');
      await tester.pumpWidget(
        const Center(
          child: RestageMotion(
            fromScale: double.nan,
            fromOffset: Offset(double.infinity, double.nan),
            child: SizedBox(key: key, width: 20, height: 20),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // NaN/Infinity sanitize to identity (scale 1.0 / Offset.zero), so the
      // child's rendered geometry stays finite — no NaN reaches the render tree.
      expect(tester.getRect(find.byKey(key)).size.isFinite, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a finite-extreme fromScale stays finite through the spring '
        'overshoot (no interpolation overflow)', (tester) async {
      // double.maxFinite is finite (so the input guard passes) but the bouncy
      // spring's overshoot (t > 1) makes fromScale + (1-fromScale)*t overflow
      // to -Infinity — the render-boundary guard must catch the result.
      await tester.pumpWidget(
        const Center(
          child: RestageMotion(
            spring: RestageSpring.bouncy,
            fromScale: double.maxFinite,
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scaleOf(tester).isFinite, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('delay defers the start of the entrance', (tester) async {
      await tester.pumpWidget(
        const Center(
          child: RestageMotion(
            spring: RestageSpring.smooth,
            fromScale: 0.5,
            delay: Duration(milliseconds: 300),
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );
      // Before the delay elapses, the entrance has not started: scale is still
      // at the from value.
      await tester.pump(const Duration(milliseconds: 100));
      expect(scaleOf(tester), closeTo(0.5, 0.001));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });
}
