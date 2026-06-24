/// Converts a signed amount in micros of a currency's major unit to micros
/// of USD, using an exact decimal conversion rate. All arithmetic is integer
/// / `BigInt` — no `double` ever touches a money value — so the result is
/// exact and reproducible.
///
/// `usdRate` is USD-major per 1 foreign-major, given as a non-negative decimal
/// string (e.g. `"0.0066"`). Because both sides are micros of the *major*
/// unit, the conversion never divides by a minor-unit divisor: a zero-decimal
/// currency (e.g. JPY, KRW) converts exactly the same way as a two-decimal
/// one, and the historical "treat micros as minor units and divide by 100"
/// error class cannot occur.
///
/// Rounding is round-half-to-even (banker's rounding) at the micros boundary,
/// and the conversion is sign-symmetric: a negative amount converts to the
/// exact negation of its positive twin. USD is the identity — its rate must be
/// exactly `1`. The result is bounds-checked into a signed 64-bit integer; an
/// amount that would overflow yields [FoldUsdOverflow] rather than wrapping.
library;

import 'package:meta/meta.dart';

/// The result of [foldEntryUsd].
@immutable
sealed class FoldUsd {
  const FoldUsd();
}

/// A successful conversion to [usdMicros] (signed micros of USD).
@immutable
final class FoldUsdValue extends FoldUsd {
  /// Wraps the converted [usdMicros].
  const FoldUsdValue(this.usdMicros);

  /// The converted amount in signed micros of USD.
  final int usdMicros;

  @override
  bool operator ==(Object other) =>
      other is FoldUsdValue && other.usdMicros == usdMicros;

  @override
  int get hashCode => usdMicros.hashCode;

  @override
  String toString() => 'FoldUsdValue($usdMicros)';
}

/// The conversion would overflow a signed 64-bit integer — the caller holds
/// rather than billing a wrapped number.
@immutable
final class FoldUsdOverflow extends FoldUsd {
  /// Const constructor for the overflow result.
  const FoldUsdOverflow();

  @override
  bool operator ==(Object other) => other is FoldUsdOverflow;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'FoldUsdOverflow()';
}

/// The largest value representable by a signed 64-bit integer (`2^63 − 1`),
/// as a [BigInt] so the overflow bound is exact on every compilation target.
/// Written as a shift rather than the `int` literal `0x7FFFFFFFFFFFFFFF`,
/// which is not exactly representable on the web (JS) target and fails to
/// compile there.
final BigInt _int64Max = (BigInt.one << 63) - BigInt.one;

/// Converts [signedAmountMicros] (signed micros of [currency]'s major unit) to
/// signed micros of USD via [usdRate].
///
/// Throws a [StateError] if [currency] is USD and [usdRate] is not exactly `1`
/// (USD must be the identity). Throws a [FormatException] if [usdRate] is not a
/// non-negative plain decimal string. Returns [FoldUsdOverflow] if the
/// converted value would not fit a signed 64-bit integer.
FoldUsd foldEntryUsd({
  required int signedAmountMicros,
  required String currency,
  required String usdRate,
}) {
  final (:num, :den) = _parseDecimalRate(usdRate);
  final micros = BigInt.from(signedAmountMicros);

  if (currency == 'USD') {
    // USD is the identity: the rate must be exactly 1 (num == den). A non-1
    // USD rate is a data/programming error, not a recoverable hold.
    if (num != den) {
      throw StateError('USD must convert at rate 1, got "$usdRate".');
    }
    if (micros.abs() > _int64Max) {
      return const FoldUsdOverflow();
    }
    return FoldUsdValue(signedAmountMicros);
  }

  // Magnitude only — the sign is re-applied after rounding so a negative
  // amount is the exact negation of its positive twin (half-even is
  // sign-symmetric).
  final magnitude = _roundHalfEvenDiv(micros.abs() * num, den);
  final signed = signedAmountMicros < 0 ? -magnitude : magnitude;

  if (signed.abs() > _int64Max) {
    return const FoldUsdOverflow();
  }
  return FoldUsdValue(signed.toInt());
}

/// Whether [rate] is a strictly-positive plain decimal string — the only kind
/// of conversion rate that can be applied safely.
///
/// Returns `false` for a non-decimal, signed, empty, or whitespace string
/// (anything [foldEntryUsd] would reject with a [FormatException]) and also for
/// an exactly-zero rate (`"0"`, `"0.0"`, …): a zero rate converts every amount
/// to zero, which would silently under-count rather than convert. Callers use
/// this both to reject a bad rate at the boundary (before it is stored) and to
/// fail closed at conversion time if an unvalidated rate is ever encountered.
bool isPositiveDecimalRate(String rate) {
  final BigInt numerator;
  try {
    numerator = _parseDecimalRate(rate).num;
  } on FormatException {
    return false;
  }
  return numerator > BigInt.zero;
}

/// Parses a non-negative plain decimal string to an exact rational
/// `(num, den = 10^scale)`. Rejects signs, exponents, and anything but digits
/// and a single optional `.`.
({BigInt num, BigInt den}) _parseDecimalRate(String rate) {
  if (rate.isEmpty) {
    throw FormatException('Empty rate string', rate);
  }
  final dot = rate.indexOf('.');
  final String intPart;
  final String fracPart;
  if (dot < 0) {
    intPart = rate;
    fracPart = '';
  } else {
    if (rate.indexOf('.', dot + 1) >= 0) {
      throw FormatException('Rate has more than one decimal point', rate);
    }
    intPart = rate.substring(0, dot);
    fracPart = rate.substring(dot + 1);
  }
  if (intPart.isEmpty && fracPart.isEmpty) {
    throw FormatException('Rate has no digits', rate);
  }
  if (!_isAllDigits(intPart) || !_isAllDigits(fracPart)) {
    throw FormatException('Rate must be a non-negative plain decimal', rate);
  }
  final digits = '$intPart$fracPart';
  return (
    num: BigInt.parse(digits.isEmpty ? '0' : digits),
    den: BigInt.from(10).pow(fracPart.length),
  );
}

bool _isAllDigits(String s) {
  for (var i = 0; i < s.length; i += 1) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) {
      return false;
    }
  }
  return true;
}

/// Integer division of a non-negative [numerator] by a positive [denominator],
/// rounded half-to-even (banker's rounding).
BigInt _roundHalfEvenDiv(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  final remainder = numerator % denominator;
  final twiceRemainder = remainder * BigInt.two;
  if (twiceRemainder < denominator) {
    return quotient;
  }
  if (twiceRemainder > denominator) {
    return quotient + BigInt.one;
  }
  return quotient.isEven ? quotient : quotient + BigInt.one;
}
