import 'package:restage_codegen/src/const_folding.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Resolves [source] (which must define `Object x() => <expr>;`) and folds
/// the returned expression.
Future<Object?> _fold(String source) async =>
    tryFoldConstant(await parseExpressionFromSourceForTest(source));

void main() {
  group('tryFoldConstant', () {
    test('folds an integer literal', () async {
      expect(await _fold('Object x() => 42;'), 42);
    });

    test('folds a const variable reference', () async {
      expect(
        await _fold('const double kGap = 16; Object x() => kGap;'),
        16.0,
      );
    });

    test('folds const arithmetic', () async {
      expect(
        await _fold('const int a = 4; const int b = 3; Object x() => a * b;'),
        12,
      );
    });

    test('folds a unary minus over a const', () async {
      expect(await _fold('const int g = 8; Object x() => -g;'), -8);
    });

    test('folds const string concatenation', () async {
      expect(
        await _fold(
          'const String a = "x"; const String b = "y"; Object x() => a + b;',
        ),
        'xy',
      );
    });

    test('returns null for a runtime value', () async {
      expect(await _fold('int counter = 0; Object x() => counter;'), isNull);
    });

    test('returns null for a non-arithmetic operator', () async {
      expect(
        await _fold('const int a = 4; const int b = 3; Object x() => a == b;'),
        isNull,
      );
    });

    test('returns null for an enum constant', () async {
      expect(await _fold('enum E { a, b } Object x() => E.a;'), isNull);
    });

    test('returns null for truncating division by zero (does not throw)',
        () async {
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a ~/ b;'),
        isNull,
      );
    });

    test('returns null for modulo by zero (does not throw)', () async {
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a % b;'),
        isNull,
      );
    });

    test('returns null for a non-finite division result', () async {
      // 1 / 0 is double.infinity — no valid RFW numeric literal.
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a / b;'),
        isNull,
      );
    });

    test('returns null for a non-finite constant reference', () async {
      expect(
        await _fold('const double k = double.infinity; Object x() => k;'),
        isNull,
      );
    });

    test('returns null for an operation on a non-finite operand', () async {
      // `infinity ~/ 2` throws in Dart — a non-finite operand must be
      // rejected before the operation runs.
      expect(
        await _fold(
          'const double k = double.infinity; '
          'const int b = 2; Object x() => k ~/ b;',
        ),
        isNull,
      );
    });

    test('returns null for a non-finite double literal (overflow)', () async {
      // `1e400` parses to a non-finite double (Infinity). The `DoubleLiteral`
      // arm must filter it like its sibling fold arms (`decodeConstScalar`,
      // `_foldBinary`) so the state-field / setState path — which consumes
      // folds directly, bypassing the translator's emit guard — can never
      // capture a bare `Infinity`.
      expect(await _fold('Object x() => 1e400;'), isNull);
    });

    test('returns null for a negative non-finite double literal', () async {
      // `-1e400` folds through the unary-minus arm over the same non-finite
      // `DoubleLiteral`; the operand filter makes the whole expression null.
      expect(await _fold('Object x() => -1e400;'), isNull);
    });
  });
}
