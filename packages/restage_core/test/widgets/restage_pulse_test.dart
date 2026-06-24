import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

/// RestagePulse is the one genuinely-looping motion (the implicit Animated*
/// suite cannot loop): a subtle, repeating breathing scale for drawing
/// attention to a CTA.
void main() {
  double scaleOf(WidgetTester tester) =>
      tester.widget<Transform>(find.byType(Transform)).transform.storage[0];

  testWidgets('pulses (oscillates) within [minScale, maxScale]',
      (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RestagePulse(
          minScale: 0.9,
          maxScale: 1.1,
          period: Duration(milliseconds: 400),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );

    var minObs = double.infinity;
    var maxObs = 0.0;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = scaleOf(tester);
      minObs = math.min(minObs, s);
      maxObs = math.max(maxObs, s);
    }
    expect(minObs, greaterThanOrEqualTo(0.9 - 0.01));
    expect(maxObs, lessThanOrEqualTo(1.1 + 0.01));
    // It actually moves a meaningful amount (a real pulse, not a static frame).
    expect(maxObs - minObs, greaterThan(0.05));

    // Dispose the looping animation cleanly before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a non-positive period from the wire is clamped — no crash, '
      'no divide-by-zero NaN loop', (tester) async {
    // A wire period of 0 (or negative) would otherwise assert in
    // AnimationController.repeat (_periodInSeconds > 0) and, in release, drive
    // a divide-by-zero NaN scale forever.
    await tester.pumpWidget(
      const Center(
        child: RestagePulse(
          period: Duration.zero,
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scaleOf(tester).isFinite, isTrue);
    }
    expect(tester.takeException(), isNull);
    // Regression for the compound finding: the throwing late-final initializer
    // (when the controller asserted) left the field unassigned, so dispose
    // re-ran the initializer and created a SECOND ticker. With the clamp the
    // initializer never throws, so disposing is clean.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('NaN scale bounds from the wire render finite (identity)',
      (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RestagePulse(
          minScale: double.nan,
          maxScale: double.infinity,
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scaleOf(tester).isFinite, isTrue);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('default scale range is subtle (restrained taste)',
      (tester) async {
    await tester.pumpWidget(
      const Center(child: RestagePulse(child: SizedBox(width: 20, height: 20))),
    );
    var maxObs = 0.0;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      maxObs = math.max(maxObs, scaleOf(tester));
    }
    // The default never grows beyond ~3% — not a garish bounce.
    expect(maxObs, lessThan(1.05));
    await tester.pumpWidget(const SizedBox());
  });
}
