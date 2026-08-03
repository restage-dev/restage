// Unit proofs for the constraint repair.
//
// `safeConstraints` is a pure function over an already-assembled value, so it is
// pinned here, exhaustively, including the arms a wire is unlikely to reach but
// a tampered one can. That it actually runs on the value the generated factories
// hand to layout is a separate fact, proved end-to-end against a real wire in
// `layout_value_repair_render_test.dart` — a fake `DataSource` would only prove
// the fake.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

void main() {
  group('RestageDecoders.safeConstraints', () {
    test('leaves a legal constraint untouched', () {
      const legal = BoxConstraints(
        minWidth: 100,
        maxWidth: 200,
        minHeight: 10,
        maxHeight: 50,
      );

      expect(RestageDecoders.safeConstraints(legal), legal);
    });

    test('leaves the unbounded default untouched', () {
      const unbounded = BoxConstraints();

      expect(RestageDecoders.safeConstraints(unbounded), unbounded);
      expect(RestageDecoders.safeConstraints(unbounded).maxWidth, isNot(0));
    });

    test('raises an inverted maximum to meet its minimum', () {
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(
          minWidth: 500,
          maxWidth: 10,
          minHeight: 400,
          maxHeight: 20,
        ),
      );

      expect(repaired.minWidth, 500);
      expect(repaired.maxWidth, 500);
      expect(repaired.minHeight, 400);
      expect(repaired.maxHeight, 400);
      expect(repaired.isNormalized, isTrue);
    });

    test('floors a negative minimum at zero', () {
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(minWidth: -40, minHeight: -40),
      );

      expect(repaired.minWidth, 0);
      expect(repaired.minHeight, 0);
      expect(repaired.isNormalized, isTrue);
    });

    test('drops a negative maximum to a tight zero', () {
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(maxWidth: -40, maxHeight: -40),
      );

      expect(repaired.maxWidth, 0);
      expect(repaired.maxHeight, 0);
      expect(repaired.isNormalized, isTrue);
    });

    test('floors an infinite minimum at zero, unlike an infinite maximum', () {
      // The asymmetry is the point, and it took a real exploit to settle it.
      //
      // An infinite MAXIMUM means "unbounded" — every box knows how to lay that
      // out, and it is preserved. An infinite MINIMUM means "you must be at
      // least infinitely large", which only survives while an ancestor bounds
      // the axis. It was preserved once, on the argument that
      // `BoxConstraints.expand()` is a legal shape that carries one. But put it
      // on an axis a parent has left unbounded — a `Row` gives its non-flex
      // children exactly that — and the child is laid out at an infinite extent,
      // whose offset and overflow are `Infinity` arithmetic resolving to `NaN`,
      // inside the layout phase, in release, where no boundary can see it.
      //
      // And the trade bought nothing: no authoring path can produce an infinite
      // minimum — the build-time toolchain rejects a non-finite real outright,
      // and nothing lowers to `.expand()` — so the only thing carrying one is a
      // corrupt or hostile wire, which is exactly what must not reach that NaN.
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(
          minWidth: double.infinity,
          minHeight: double.infinity,
        ),
      );

      expect(repaired.minWidth, 0);
      expect(repaired.minHeight, 0);
      expect(repaired.maxWidth, double.infinity);
      expect(repaired.maxHeight, double.infinity);
      expect(repaired.isNormalized, isTrue);
    });

    test('floors a NaN minimum at zero', () {
      final repaired = RestageDecoders.safeConstraints(
        BoxConstraints(minWidth: double.nan, minHeight: double.nan),
      );

      expect(repaired.minWidth, 0);
      expect(repaired.minHeight, 0);
      expect(repaired.isNormalized, isTrue);
    });

    test('preserves an infinite maximum — unbounded is legal', () {
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(minWidth: 10, minHeight: 10),
      );

      expect(repaired.maxWidth, double.infinity);
      expect(repaired.maxHeight, double.infinity);
      expect(repaired.isNormalized, isTrue);
    });

    test('repairs every NaN — a minimum to zero, a maximum to unbounded', () {
      final repaired = RestageDecoders.safeConstraints(
        const BoxConstraints(
          minWidth: double.nan,
          maxWidth: double.nan,
          minHeight: double.nan,
          maxHeight: double.nan,
        ),
      );

      expect(repaired.minWidth, 0);
      expect(repaired.maxWidth, double.infinity);
      expect(repaired.minHeight, 0);
      expect(repaired.maxHeight, double.infinity);
      expect(repaired.isNormalized, isTrue);
      expect(repaired.hasBoundedWidth, isFalse);
    });

    test('a repaired constraint is always one layout will accept', () {
      const hostile = <BoxConstraints>[
        BoxConstraints(minWidth: 500, maxWidth: 10),
        BoxConstraints(minWidth: -1, maxWidth: double.nan),
        BoxConstraints(minHeight: double.negativeInfinity, maxHeight: -5),
        BoxConstraints(
          minWidth: double.nan,
          maxWidth: double.negativeInfinity,
          minHeight: double.infinity,
          maxHeight: double.nan,
        ),
      ];

      for (final constraints in hostile) {
        final repaired = RestageDecoders.safeConstraints(constraints);
        expect(repaired.isNormalized, isTrue, reason: '$constraints');
        expect(repaired.debugAssertIsValid(), isTrue, reason: '$constraints');
      }
    });
  });
}
