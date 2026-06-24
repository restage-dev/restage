import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

/// RestageFadeIn is the discoverable, simple front-door for the single most
/// common entrance: a curve-based opacity fade (optionally with a rise) on
/// appear. Curve-based, not spring — opacity has no visible overshoot, so a
/// spring buys nothing here; for spring entrances, RestageMotion is the widget.
void main() {
  double opacityOf(WidgetTester tester) =>
      tester.widget<Opacity>(find.byType(Opacity)).opacity;

  testWidgets('fades opacity from fromOpacity up to 1.0', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          duration: Duration(milliseconds: 300),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    // Starts at fromOpacity (default 0).
    expect(opacityOf(tester), closeTo(0.0, 0.01));
    // Settles fully opaque.
    await tester.pumpAndSettle();
    expect(opacityOf(tester), closeTo(1.0, 0.001));
  });

  testWidgets('opacity is monotonic — no overshoot (curve, not spring)',
      (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          duration: Duration(milliseconds: 300),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    var last = -1.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final o = opacityOf(tester);
      expect(o, greaterThanOrEqualTo(last - 0.001)); // never decreases
      expect(o, lessThanOrEqualTo(1.0)); // never exceeds 1
      last = o;
    }
    await tester.pumpAndSettle();
  });

  testWidgets('onEnd fires exactly once on settle', (tester) async {
    var ends = 0;
    await tester.pumpWidget(
      Center(
        child: RestageFadeIn(
          duration: const Duration(milliseconds: 200),
          onEnd: () => ends++,
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(ends, 1);
  });

  testWidgets('a NaN/Infinity fromOffset renders finite (identity)',
      (tester) async {
    const key = Key('fade-child');
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          fromOffset: Offset(double.nan, double.infinity),
          child: SizedBox(key: key, width: 20, height: 20),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(find.byKey(key)).size.isFinite, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a finite-extreme fromOffset stays finite under an overshooting '
      'curve (no interpolation overflow)', (tester) async {
    // easeInBack anticipates below 0, so (1 - t) > 1 makes a maxFinite offset
    // overflow to Infinity — the render-boundary guard must catch the result.
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          curve: Curves.easeInBack,
          fromOffset: Offset(double.maxFinite, 0),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final transform =
          tester.widget<Transform>(find.byType(Transform)).transform;
      expect(transform.storage[12].isFinite, isTrue); // x translation
    }
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a negative duration from the wire is clamped — no crash',
      (tester) async {
    // A negative wire duration would otherwise assert in
    // AnimationController.forward (simulationDuration > Duration.zero).
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          duration: Duration(milliseconds: -500),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(opacityOf(tester), closeTo(1.0, 0.001));
  });

  testWidgets('delay defers the fade', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RestageFadeIn(
          delay: Duration(milliseconds: 300),
          duration: Duration(milliseconds: 200),
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(tester), closeTo(0.0, 0.01)); // not started
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
