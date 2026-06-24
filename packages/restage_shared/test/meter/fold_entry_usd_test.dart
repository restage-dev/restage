import 'package:restage_shared/meter.dart';
import 'package:test/test.dart';

/// Exercises the single signed-micros → USD-micros conversion: exact decimal
/// arithmetic (no double), round-half-to-even at the micros boundary,
/// sign-symmetric, USD identity, and a 64-bit overflow guard.
void main() {
  group('foldEntryUsd', () {
    test('USD is the identity (rate must be 1)', () {
      expect(
        foldEntryUsd(
          signedAmountMicros: 1990000,
          currency: 'USD',
          usdRate: '1',
        ),
        const FoldUsdValue(1990000),
      );
      // A negative USD amount negates exactly.
      expect(
        foldEntryUsd(
          signedAmountMicros: -1990000,
          currency: 'USD',
          usdRate: '1',
        ),
        const FoldUsdValue(-1990000),
      );
    });

    test('a USD rate other than 1 is a programming/data error', () {
      expect(
        () => foldEntryUsd(
          signedAmountMicros: 100,
          currency: 'USD',
          usdRate: '1.5',
        ),
        throwsStateError,
      );
    });

    test('zero-decimal currency converts with no minor-unit divisor (no /100)',
        () {
      // ¥990 == 990 * 1e6 micros; rate is USD per 1 yen.
      // 990_000_000 * 0.0066 = 990_000_000 * 66 / 10_000 = 6_534_000 exactly.
      expect(
        foldEntryUsd(
          signedAmountMicros: 990000000,
          currency: 'JPY',
          usdRate: '0.0066',
        ),
        const FoldUsdValue(6534000),
        reason: 'micros are major-unit-scaled; a /100 would give 65_340',
      );
    });

    test("rounds half-to-even (banker's) at the micros boundary", () {
      // 15 * 0.1 = 1.5 -> tie -> round to even -> 2.
      expect(
        foldEntryUsd(signedAmountMicros: 15, currency: 'EUR', usdRate: '0.1'),
        const FoldUsdValue(2),
      );
      // 25 * 0.1 = 2.5 -> tie -> round to even -> 2.
      expect(
        foldEntryUsd(signedAmountMicros: 25, currency: 'EUR', usdRate: '0.1'),
        const FoldUsdValue(2),
      );
      // 16 * 0.1 = 1.6 -> up -> 2 ; 14 * 0.1 = 1.4 -> down -> 1.
      expect(
        foldEntryUsd(signedAmountMicros: 16, currency: 'EUR', usdRate: '0.1'),
        const FoldUsdValue(2),
      );
      expect(
        foldEntryUsd(signedAmountMicros: 14, currency: 'EUR', usdRate: '0.1'),
        const FoldUsdValue(1),
      );
    });

    test(
        'is sign-symmetric: a negative amount is the exact negation of its '
        'positive twin (incl. at a rounding tie)', () {
      for (final micros in [15, 25, 16, 14, 1990000, 7]) {
        final pos = foldEntryUsd(
          signedAmountMicros: micros,
          currency: 'EUR',
          usdRate: '0.1',
        );
        final neg = foldEntryUsd(
          signedAmountMicros: -micros,
          currency: 'EUR',
          usdRate: '0.1',
        );
        expect(pos, isA<FoldUsdValue>());
        expect(neg, isA<FoldUsdValue>());
        expect(
          (neg as FoldUsdValue).usdMicros,
          -(pos as FoldUsdValue).usdMicros,
          reason: 'micros=$micros must negate exactly',
        );
      }
    });

    test('overflowing Int64 holds (never wraps)', () {
      // int64Max * 2 exceeds Int64.
      expect(
        foldEntryUsd(
          signedAmountMicros: 9223372036854775807,
          currency: 'EUR',
          usdRate: '2',
        ),
        isA<FoldUsdOverflow>(),
      );
    });

    test('overflowing USD identity amount holds before returning a value', () {
      expect(
        foldEntryUsd(
          signedAmountMicros: -9223372036854775807 - 1,
          currency: 'USD',
          usdRate: '1',
        ),
        isA<FoldUsdOverflow>(),
      );
    });

    test('a malformed rate string is a programming/data error', () {
      expect(
        () => foldEntryUsd(
          signedAmountMicros: 100,
          currency: 'EUR',
          usdRate: '0.0x6',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('isPositiveDecimalRate', () {
    test('accepts a strictly-positive plain decimal', () {
      expect(isPositiveDecimalRate('1'), isTrue);
      expect(isPositiveDecimalRate('1.08'), isTrue);
      expect(isPositiveDecimalRate('0.0066'), isTrue);
      expect(isPositiveDecimalRate('0.000001'), isTrue);
    });

    test(r'rejects zero (a zero rate would silently bill $0)', () {
      expect(isPositiveDecimalRate('0'), isFalse);
      expect(isPositiveDecimalRate('0.0'), isFalse);
      expect(isPositiveDecimalRate('0.000'), isFalse);
    });

    test('rejects a non-decimal / signed / empty string', () {
      expect(isPositiveDecimalRate('abc'), isFalse);
      expect(isPositiveDecimalRate('-1'), isFalse);
      expect(isPositiveDecimalRate('1.0x'), isFalse);
      expect(isPositiveDecimalRate('1.2.3'), isFalse);
      expect(isPositiveDecimalRate(''), isFalse);
      expect(isPositiveDecimalRate(' 1 '), isFalse);
    });
  });
}
