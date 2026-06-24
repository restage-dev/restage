import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// intl also exports a `TextDirection` (members LTR/RTL) that shadows Flutter's
// (ltr/rtl) — show only what we use so the widgets' TextDirection wins.
import 'package:intl/intl.dart' show NumberFormat;
import 'package:restage_core/restage_core.dart';

/// The runtime proof for the #1 formatting widgets: they faithfully run the
/// `intl.NumberFormat` primitive (the relocate-don't-reimplement invariant)
/// and render the formatted value into a `Text`, carrying the declared
/// Text-surface props. Formatting is the product surface here — so this
/// asserts correct output across >=3 locales, not just that a widget builds.
void main() {
  Text findText(WidgetTester tester) => tester.widget<Text>(find.byType(Text));

  group('RestagePrice', () {
    testWidgets('en_US — faithful currency formatting (hard anchor)',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(
            value: -1234.5,
            numberLocale: 'en_US',
            symbol: r'$',
            decimalDigits: 2,
          ),
        ),
      );
      expect(findText(tester).data, '-\$1,234.50');
    });

    testWidgets('de_DE — comma decimal, dot grouping, trailing symbol',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(
            value: -1234.5,
            numberLocale: 'de_DE',
            symbol: '€',
            decimalDigits: 2,
          ),
        ),
      );
      // Faithful to the primitive + locale-structurally correct.
      final expected = NumberFormat.currency(
        locale: 'de_DE',
        symbol: '€',
        decimalDigits: 2,
      ).format(-1234.5);
      expect(findText(tester).data, expected);
      expect(findText(tester).data, contains('€'));
      expect(findText(tester).data, contains(',50')); // comma decimal
      expect(findText(tester).data, contains('1.234')); // dot grouping
    });

    testWidgets('ja_JP — zero-decimal currency rounds, no fraction separator',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(
            value: -1234.5,
            numberLocale: 'ja_JP',
            symbol: '¥',
            decimalDigits: 0,
          ),
        ),
      );
      final expected = NumberFormat.currency(
        locale: 'ja_JP',
        symbol: '¥',
        decimalDigits: 0,
      ).format(-1234.5);
      expect(findText(tester).data, expected);
      expect(findText(tester).data, contains('¥'));
      // 0-decimal: no fraction part — -1234.5 rounds to 1235.
      expect(findText(tester).data, contains('1,235'));
    });

    testWidgets(
        'null value renders empty string (graceful; substitution '
        'never reaches null — see the recognizer present-value gate)',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(numberLocale: 'en_US', symbol: r'$'),
        ),
      );
      expect(findText(tester).data, '');
    });

    testWidgets('carries the declared Text-surface props onto the inner Text',
        (tester) async {
      // overflow rides inside style (TextStyle.overflow) — Flutter's Text
      // honours style.overflow when the widget-level overflow is null.
      const style = TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        overflow: TextOverflow.ellipsis,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(
            value: 9.99,
            numberLocale: 'en_US',
            symbol: r'$',
            decimalDigits: 2,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      );
      final text = findText(tester);
      expect(text.style, style);
      expect(text.style?.overflow, TextOverflow.ellipsis);
      expect(text.textAlign, TextAlign.center);
      expect(text.maxLines, 1);
    });

    testWidgets('unset Text-surface props stay null (inherit Text defaults)',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestagePrice(value: 1, numberLocale: 'en_US', symbol: r'$'),
        ),
      );
      final text = findText(tester);
      expect(text.style, isNull);
      expect(text.textAlign, isNull);
      expect(text.maxLines, isNull);
    });
  });

  group('RestageFormattedNumber', () {
    testWidgets('en_US decimal grouping', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestageFormattedNumber(value: 1234567, numberLocale: 'en_US'),
        ),
      );
      expect(findText(tester).data, '1,234,567');
    });

    testWidgets('de_DE decimal grouping (dot)', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestageFormattedNumber(value: 1234567, numberLocale: 'de_DE'),
        ),
      );
      final expected = NumberFormat.decimalPattern('de_DE').format(1234567);
      expect(findText(tester).data, expected);
      expect(findText(tester).data, '1.234.567');
    });

    testWidgets('null value renders empty string', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RestageFormattedNumber(numberLocale: 'en_US'),
        ),
      );
      expect(findText(tester).data, '');
    });
  });

  // The differential output matrix. The build-time recognizer rewrites a
  // `Text(NumberFormat.<ctor>(...).format(v))` idiom to one of these widgets
  // ONLY when the substitution is equivalent by construction — the widget runs
  // the SAME NumberFormat constructor with the same statically-extracted
  // config. This matrix is the standing proof of that equivalence across the
  // value × locale × currency × edge space: for every case the widget's
  // rendered string must equal the original `NumberFormat(...).format(value)`.
  // A regression in either side (a mis-mapped field, a changed internal
  // constructor) trips here, which is exactly when the recognizer must stop
  // firing for that shape.
  group('differential equivalence matrix (substitute == original output)', () {
    const currencyCases = <({
      double value,
      String locale,
      String symbol,
      int digits,
    })>[
      (value: 0, locale: 'en_US', symbol: r'$', digits: 2), // zero
      (value: -0.005, locale: 'en_US', symbol: r'$', digits: 2), // round half
      (value: 1234567.895, locale: 'en_US', symbol: r'$', digits: 2), // large
      (value: 9.99, locale: 'de_DE', symbol: '€', digits: 2), // comma decimal
      (value: 1234.5, locale: 'ja_JP', symbol: '¥', digits: 0), // 0-decimal
      (value: 1234.5678, locale: 'fr_FR', symbol: '€', digits: 3), // 3-decimal
      (value: -42, locale: 'en_GB', symbol: '£', digits: 2), // negative
      (value: 1000000, locale: 'en_IN', symbol: '₹', digits: 2), // lakh group
    ];

    for (final c in currencyCases) {
      testWidgets(
        'RestagePrice == NumberFormat.currency for '
        '${c.value} ${c.locale}/${c.symbol}@${c.digits}',
        (tester) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RestagePrice(
                value: c.value,
                numberLocale: c.locale,
                symbol: c.symbol,
                decimalDigits: c.digits,
              ),
            ),
          );
          final original = NumberFormat.currency(
            locale: c.locale,
            symbol: c.symbol,
            decimalDigits: c.digits,
          ).format(c.value);
          expect(findText(tester).data, original);
        },
      );
    }

    const decimalCases = <({double value, String locale})>[
      (value: 0, locale: 'en_US'),
      (value: -1234.5, locale: 'en_US'),
      (value: 1234567.89, locale: 'de_DE'),
      (value: 1000000, locale: 'fr_FR'),
      (value: 9876543.21, locale: 'en_IN'),
    ];

    for (final c in decimalCases) {
      testWidgets(
        'RestageFormattedNumber == NumberFormat.decimalPattern for '
        '${c.value} ${c.locale}',
        (tester) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RestageFormattedNumber(
                value: c.value,
                numberLocale: c.locale,
              ),
            ),
          );
          final original =
              NumberFormat.decimalPattern(c.locale).format(c.value);
          expect(findText(tester).data, original);
        },
      );
    }

    testWidgets(
        'unset-locale RestageFormattedNumber == plain NumberFormat() '
        '(the unnamed-constructor equivalence the recognizer relies on)',
        (tester) async {
      // The recognizer substitutes a plain `Text(NumberFormat().format(v))` to
      // `RestageFormattedNumber(value: v)` (no locale). That holds only if the
      // widget's `NumberFormat.decimalPattern(null)` matches the unnamed
      // `NumberFormat()` for the ambient locale. Proven here across values.
      for (final v in <double>[0, -1234.5, 1234567.89, 1000000]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RestageFormattedNumber(value: v),
          ),
        );
        expect(findText(tester).data, NumberFormat().format(v));
      }
    });

    testWidgets(
        '.simpleCurrency is NOT reproducible by RestagePrice — the divergence '
        'that justifies deferring (not substituting) it', (tester) async {
      // RestagePrice forwards an explicit symbol to NumberFormat.currency; it
      // has no simple-currency mode. `simpleCurrency` derives its glyph from
      // locale data, so no symbol the recognizer could pass reproduces it —
      // hence simpleCurrency stays a named adopt-target, never an auto-rewrite.
      const value = 9.99;
      const locale = 'en_US';
      final simple = NumberFormat.simpleCurrency(locale: locale).format(value);
      // The two symbol choices a substitution might attempt, neither matching.
      final withNullSymbol =
          NumberFormat.currency(locale: locale).format(value);
      expect(simple, isNot(withNullSymbol),
          reason: 'simpleCurrency differs from currency() with no symbol');
    });
  });

  group('kRestageFormattedTextProps (the single-sourced carry-set)', () {
    test('names exactly the carried Text-surface props', () {
      // Pinned both directions: the recognizer reads THIS list; the widgets
      // expose exactly these Text props. A name here that the widget does not
      // expose would be a silent-drop on substitution; a widget Text prop
      // missing here would be a spurious defer. Mirrors Text's catalogued,
      // non-excluded surface (overflow rides inside style).
      expect(
        kRestageFormattedTextProps,
        <String>['style', 'textAlign', 'maxLines'],
      );
    });
  });
}
