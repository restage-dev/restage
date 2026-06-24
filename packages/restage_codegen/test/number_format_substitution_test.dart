import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The number/currency auto-substitution recognizer. A
/// `Text(NumberFormat.<ctor>(<const config>).format(<value>), <carry>)` idiom
/// on the real `package:intl/` NumberFormat rewrites to the equivalent
/// `RestagePrice` / `RestageFormattedNumber` catalog widget — **provably
/// equivalent (the widget runs the SAME NumberFormat constructor with the SAME
/// statically-extracted config) or it does not fire**. Every deferral is a
/// specific, named diagnostic; the rewrite never silently drops a property and
/// never substitutes a customer look-alike.
///
/// The faithful styled e2e (real catalog, `style` TextStyle-decompose, byte
/// round-trip) lives at the builder level; the differential output matrix lives
/// in `restage_core`. These translator tests pin the recognizer's fire / defer
/// decisions and the emitted node shape against a synthetic catalog.
void main() {
  final catalog = catalogWith([
    entry(
      name: 'RestagePrice',
      category: WidgetCategory.decoration,
      properties: [
        prop('value', PropertyType.real),
        prop('numberLocale', PropertyType.string),
        prop('symbol', PropertyType.string),
        prop('decimalDigits', PropertyType.integer),
        prop('maxLines', PropertyType.integer),
      ],
    ),
    entry(
      name: 'RestageFormattedNumber',
      category: WidgetCategory.decoration,
      properties: [
        prop('value', PropertyType.real),
        prop('numberLocale', PropertyType.string),
        prop('maxLines', PropertyType.integer),
      ],
    ),
    entry(
      name: 'Text',
      flutterType: 'package:flutter/src/widgets/text.dart#Text',
      properties: [prop('text', PropertyType.string, positional: true)],
    ),
  ]);

  final translator =
      ExpressionTranslator(catalog: catalog, helpers: HelperRegistry());

  /// Parses [body] as a resolved expression with intl + Flutter on the path
  /// (so `Text` resolves to `package:flutter/` and `NumberFormat` to
  /// `package:intl/`), translates it, and returns the DSL + flattened issues.
  Future<({String dsl, List<Issue> issues})> run(String body) async {
    final expr = await parseExpressionFromSourceForTest(
      '''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
Object x() => $body;
''',
      rootPackage: 'apps_examples',
    );
    final r = translator.translate(expr);
    return (dsl: r.dsl, issues: r.issues);
  }

  String messages(List<Issue> issues) =>
      issues.map((i) => i.message).join('\n');

  group('fires — equivalence-by-construction currency / decimal', () {
    test('Text(NumberFormat.currency(const config).format(v)) -> RestagePrice',
        () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', "
        'decimalDigits: 2).format(9.99))',
      );
      expect(r.dsl, contains('RestagePrice('));
      expect(r.dsl, contains('value: 9.99'));
      expect(r.dsl, contains('numberLocale: '));
      expect(r.dsl, contains('en_US'));
      expect(r.dsl, contains('symbol: '));
      expect(r.dsl, contains('decimalDigits: 2'));
      // No deferral / error — only the informational build notice.
      expect(
        r.issues.where((i) => !i.code.isInformational),
        isEmpty,
        reason: messages(r.issues),
      );
    });

    test('the rewrite emits the announced-rewrite build notice (info)',
        () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', "
        'decimalDigits: 2).format(9.99))',
      );
      final notice = r.issues
          .where((i) => i.code == IssueCode.idiomAutoSubstituted)
          .toList();
      expect(notice, hasLength(1));
      expect(notice.single.code.isInformational, isTrue);
      expect(notice.single.message, contains('RestagePrice'));
    });

    test(
        'Text(NumberFormat.decimalPattern(locale).format(v)) -> '
        'RestageFormattedNumber', () async {
      final r = await run(
        "Text(NumberFormat.decimalPattern('de_DE').format(1234.5))",
      );
      expect(r.dsl, contains('RestageFormattedNumber('));
      expect(r.dsl, contains('value: 1234.5'));
      expect(r.dsl, contains('de_DE'));
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
    });

    test(
        'plain Text(NumberFormat().format(v)) -> RestageFormattedNumber '
        '(numberLocale unset)', () async {
      final r = await run('Text(NumberFormat().format(1234.5))');
      expect(r.dsl, contains('RestageFormattedNumber('));
      expect(r.dsl, contains('value: 1234.5'));
      expect(r.dsl, isNot(contains('numberLocale:')));
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
    });

    test('carries an in-set Text property (maxLines)', () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', "
        'decimalDigits: 2).format(9.99), maxLines: 2)',
      );
      expect(r.dsl, contains('RestagePrice('));
      expect(r.dsl, contains('maxLines: 2'));
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
    });
  });

  group('defers — the look-alike defense (element-gated on package:intl/)', () {
    test(
        'a real Flutter Text wrapping a CUSTOMER NumberFormat is never '
        'substituted', () async {
      // No intl import: NumberFormat resolves to the in-source customer class;
      // Text still resolves to package:flutter/. The element gate withholds
      // the substitution — a look-alike must never become RestagePrice.
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/material.dart';
class NumberFormat {
  factory NumberFormat.currency({
    String? locale,
    String? symbol,
    int? decimalDigits,
  }) = NumberFormat._;
  NumberFormat._();
  String format(num n) => '';
}
Object x() => Text(
  NumberFormat.currency(locale: 'en_US', symbol: 'USD', decimalDigits: 2)
      .format(9.99),
);
''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.dsl, isNot(contains('RestagePrice')));
    });
  });

  group('defers — strict subset (simpleCurrency is not by-construction)', () {
    test(
        'Text(NumberFormat.simpleCurrency(...).format(v)) DEFERS (no '
        'RestagePrice node), naming the adopt-target', () async {
      final r = await run(
        "Text(NumberFormat.simpleCurrency(locale: 'en_US').format(9.99))",
      );
      expect(r.dsl, isNot(contains('RestagePrice(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(messages(r.issues), contains('RestagePrice'));
    });
  });

  group('defers — incomplete static config extraction (L1)', () {
    test('a dynamic (non-const) locale DEFERS, naming the param', () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: someLocale, symbol: r'$', "
        'decimalDigits: 2).format(9.99))',
      );
      expect(r.dsl, isNot(contains('RestagePrice(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(messages(r.issues), contains('locale'));
    });

    test('an unmappable currency param (name:) DEFERS, naming it', () async {
      // `name:` (the ISO code) has no faithful RestagePrice equivalent — the
      // widget forwards `symbol:`, not `name:`. Defer rather than guess.
      final r = await run(
        "Text(NumberFormat.currency(locale: 'en_US', name: 'USD').format(9))",
      );
      expect(r.dsl, isNot(contains('RestagePrice(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(messages(r.issues), contains('name'));
    });
  });

  group('defers — a runtime int value would null the catalog double slot', () {
    // The substitute decodes its `value` slot with `source.v<double>`, which
    // yields null for a runtime int (rendering empty) — whereas the original
    // `NumberFormat.format` accepts `num` and formats an int fine. So a
    // non-literal `int`/`num`-typed value must DEFER (never a wrong blob); a
    // double-typed value is safe. A clean-lowering state field exercises this:
    // it is the realistic raw-number-in-a-paywall case.
    test('a non-literal int-typed value DEFERS (never a wrong/empty render)',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
int count = 0;
Object x() => Text(NumberFormat.decimalPattern().format(count));
''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'count',
            isNumeric: false,
            initialValue: 0,
          ),
        ],
      );
      expect(r.dsl, isNot(contains('RestageFormattedNumber(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
    });

    test(
        'a non-literal double-typed value FIRES (no over-defer of the typed '
        'case)', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
double price = 9.99;
Object x() => Text(NumberFormat.decimalPattern().format(price));
''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(
        expr,
        rootState: [
          const CustomWidgetStateField(
            name: 'price',
            isNumeric: true,
            initialValue: 9.99,
          ),
        ],
      );
      expect(r.dsl, contains('RestageFormattedNumber('));
      expect(r.dsl, contains('value: state.price'));
      expect(r.issues.where((i) => !i.code.isInformational), isEmpty);
    });
  });

  group('defers — carry-all-or-defer (the highest never-emit-wrong risk)', () {
    test('an un-carried Text property (semanticsLabel) DEFERS, naming it',
        () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', "
        "decimalDigits: 2).format(9.99), semanticsLabel: 'price')",
      );
      expect(r.dsl, isNot(contains('RestagePrice(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(messages(r.issues), contains('semanticsLabel'));
    });

    test(
        'a widget-level Text.locale DEFERS — the glyph locale is not the '
        'format locale', () async {
      final r = await run(
        r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', "
        "decimalDigits: 2).format(9.99), locale: Locale('en'))",
      );
      expect(r.dsl, isNot(contains('RestagePrice(')));
      expect(r.issues.where((i) => !i.code.isInformational), isNotEmpty);
      expect(messages(r.issues), contains('locale'));
    });
  });
}
