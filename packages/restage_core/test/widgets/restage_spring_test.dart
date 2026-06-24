import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/widgets/restage_spring.dart';

/// The spring substrate is the heart of the motion cut: a named [RestageSpring]
/// preset (plus optional duration/bounce escape-hatch overrides) becomes a
/// Flutter [SpringDescription] via the Apple duration+bounce model at mass = 1.
/// These tests pin the math AND the fail-safe clamps — no wire value, however
/// malformed, may produce a non-settling (zero/negative-damping) spring.
void main() {
  double criticalDamping(double mass, double stiffness) =>
      2 * math.sqrt(mass * stiffness);

  group('springDescriptionFor', () {
    test('smooth (bounce 0) is critically damped — no overshoot', () {
      final s = springDescriptionFor(RestageSpring.smooth);
      // duration 500ms -> stiffness (2π/0.5)^2 ≈ 157.9
      expect(s.stiffness, closeTo(157.9, 1.0));
      // ratio 1.0 => damping == critical
      expect(s.damping, closeTo(criticalDamping(s.mass, s.stiffness), 0.01));
    });

    test('bouncy (bounce .3) is underdamped — damping below critical', () {
      final s = springDescriptionFor(RestageSpring.bouncy);
      expect(s.damping, lessThan(criticalDamping(s.mass, s.stiffness)));
      // ratio = 1 - .3 = .7
      expect(
          s.damping, closeTo(0.7 * criticalDamping(s.mass, s.stiffness), 0.5));
    });

    test('interactive uses the shorter 150ms duration (stiffer spring)', () {
      final fast = springDescriptionFor(RestageSpring.interactive);
      final smooth = springDescriptionFor(RestageSpring.smooth);
      expect(fast.stiffness, greaterThan(smooth.stiffness));
    });

    test('a malformed bounce >= 1 is clamped so the spring still settles', () {
      final s = springDescriptionFor(RestageSpring.smooth, bounceOverride: 5);
      expect(s.damping, greaterThan(0)); // positive damping => settles
      expect(s.damping.isFinite, isTrue);
    });

    test('a zero/negative duration is clamped — finite, positive stiffness',
        () {
      final s = springDescriptionFor(
        RestageSpring.smooth,
        durationOverride: Duration.zero,
      );
      expect(s.stiffness.isFinite, isTrue);
      expect(s.stiffness, greaterThan(0));
    });

    test('escape-hatch overrides are independent of the preset', () {
      // smooth + bounceOverride .3 must equal bouncy (same 500ms duration).
      final overridden =
          springDescriptionFor(RestageSpring.smooth, bounceOverride: 0.3);
      final bouncy = springDescriptionFor(RestageSpring.bouncy);
      expect(overridden.stiffness, closeTo(bouncy.stiffness, 0.01));
      expect(overridden.damping, closeTo(bouncy.damping, 0.01));
    });

    test('every preset yields a settling (positive-damping) spring', () {
      for (final preset in RestageSpring.values) {
        final s = springDescriptionFor(preset);
        expect(s.damping, greaterThan(0), reason: '$preset must settle');
        expect(s.stiffness, greaterThan(0), reason: '$preset stiffness');
      }
    });
  });
}
