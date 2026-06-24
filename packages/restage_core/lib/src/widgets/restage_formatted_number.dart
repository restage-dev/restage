import 'package:flutter/widgets.dart';
// `intl` also exports a `TextDirection` (members `LTR`/`RTL`) that would shadow
// Flutter's (`ltr`/`rtl`); show only the formatter so Flutter's wins here.
import 'package:intl/intl.dart' show NumberFormat;

// The carried-`Text`-surface set the widgets below expose is defined once in
// the shared catalog package so the build-time recognizer (which lives in a
// separate, non-Flutter package and cannot import these widgets) reads the
// same source of truth. Re-exported here so the carry-set travels with the
// widgets that honour it.
export 'package:restage_shared/restage_shared.dart'
    show kRestageFormattedTextProps;

/// Formats a currency [value] for display using locale-aware number
/// formatting, then renders it as text.
///
/// Equivalent, by construction, to
/// `Text(NumberFormat.currency(locale: numberLocale, symbol: symbol,
/// decimalDigits: decimalDigits).format(value), …)` — the widget relocates the
/// formatting call into compiled code so a paywall can express a formatted
/// price declaratively. [value] is the amount to format (typically a runtime
/// data value such as a product price); the formatting configuration is
/// inert data. A null [value] renders the empty string.
///
/// The number-symbol data `intl` uses is synchronous, so no locale-data
/// initialization is required.
class RestagePrice extends StatelessWidget {
  /// Creates a currency-formatting text widget.
  const RestagePrice({
    super.key,
    this.value,
    this.numberLocale,
    this.symbol,
    this.decimalDigits,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// The amount to format. Null renders the empty string.
  final double? value;

  /// The locale whose conventions govern number formatting — grouping, the
  /// decimal mark, digit shaping, and symbol placement (e.g. `en_US`, `de_DE`,
  /// `ja_JP`). Null uses the ambient default locale.
  ///
  /// This is the *number-formatting* locale, distinct from a text style's
  /// `locale` (which selects glyphs); the two are different concerns and are
  /// kept as separate properties.
  final String? numberLocale;

  /// The currency symbol or sign to show (e.g. `$`, `€`, `¥`). Null uses the
  /// locale's default currency symbol.
  final String? symbol;

  /// The number of fraction digits (e.g. `2` for most currencies, `0` for JPY,
  /// `3` for KWD). Null uses the locale's default for the currency.
  final int? decimalDigits;

  /// Text style applied to the rendered value. Visual overflow is taken from
  /// the style (`TextStyle.overflow`).
  final TextStyle? style;

  /// Horizontal alignment of the rendered value.
  final TextAlign? textAlign;

  /// Maximum number of lines for the rendered value.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final formatted = value == null
        ? ''
        : NumberFormat.currency(
            locale: numberLocale,
            symbol: symbol,
            decimalDigits: decimalDigits,
          ).format(value);
    return Text(
      formatted,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}

/// Formats a numeric [value] for display using locale-aware decimal
/// formatting, then renders it as text.
///
/// Equivalent, by construction, to
/// `Text(NumberFormat.decimalPattern(numberLocale).format(value), …)` — the
/// non-currency sibling of [RestagePrice], for figures such as counts or
/// savings amounts. A null [value] renders the empty string.
class RestageFormattedNumber extends StatelessWidget {
  /// Creates a decimal-formatting text widget.
  const RestageFormattedNumber({
    super.key,
    this.value,
    this.numberLocale,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// The number to format. Null renders the empty string.
  final double? value;

  /// The locale whose conventions govern number formatting — grouping and the
  /// decimal mark (e.g. `en_US`, `de_DE`). Null uses the ambient default
  /// locale.
  ///
  /// This is the *number-formatting* locale, distinct from a text style's
  /// glyph `locale`.
  final String? numberLocale;

  /// Text style applied to the rendered value. Visual overflow is taken from
  /// the style (`TextStyle.overflow`).
  final TextStyle? style;

  /// Horizontal alignment of the rendered value.
  final TextAlign? textAlign;

  /// Maximum number of lines for the rendered value.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final formatted = value == null
        ? ''
        : NumberFormat.decimalPattern(numberLocale).format(value);
    return Text(
      formatted,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}
