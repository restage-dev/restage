import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// M-CUT1.3 — the formatting-defer diagnostic. A `NumberFormat(...).format(x)`
/// idiom on the real `package:intl/` NumberFormat defers cleanly and NAMES the
/// catalog widget to adopt (RestagePrice / RestageFormattedNumber), plus the
/// pre-localized `localizedPrice` for store prices. A resolved CUSTOMER class
/// named NumberFormat is NOT intl — the element gate withholds the adopt
/// target (the look-alike defense), so it gets only the generic defer.
void main() {
  late ExpressionTranslator translator;

  setUp(() {
    translator = ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );
  });

  Future<({String dsl, String messages})> run(String body) async {
    final r = translator.translate(
      await parseExpressionFromSourceForTest('''
import 'package:intl/intl.dart';
Object x() => $body;
'''),
    );
    return (dsl: r.dsl, messages: r.issues.map((i) => i.message).join('\n'));
  }

  group('currency idiom -> RestagePrice adopt-target', () {
    test(
        'NumberFormat.currency(...).format(x) names RestagePrice and '
        'localizedPrice, and defers (no DSL)', () async {
      final r = await run(
        "NumberFormat.currency(locale: 'en_US', symbol: 'USD', "
        'decimalDigits: 2).format(1234.5)',
      );
      expect(r.dsl, isEmpty);
      expect(r.messages, contains('RestagePrice'));
      expect(r.messages, contains('localizedPrice'));
    });

    test('NumberFormat.simpleCurrency(...).format(x) names RestagePrice',
        () async {
      final r = await run(
        "NumberFormat.simpleCurrency(locale: 'en_US').format(9.99)",
      );
      expect(r.dsl, isEmpty);
      expect(r.messages, contains('RestagePrice'));
    });
  });

  group('decimal idiom -> RestageFormattedNumber adopt-target', () {
    test('plain NumberFormat().format(x) names RestageFormattedNumber',
        () async {
      final r = await run('NumberFormat().format(1234.5)');
      expect(r.dsl, isEmpty);
      expect(r.messages, contains('RestageFormattedNumber'));
      // not a currency idiom — does not push localizedPrice.
      expect(r.messages, isNot(contains('localizedPrice')));
    });

    test(
        'NumberFormat.decimalPattern(locale).format(x) names '
        'RestageFormattedNumber', () async {
      final r =
          await run("NumberFormat.decimalPattern('de_DE').format(1234.5)");
      expect(r.dsl, isEmpty);
      expect(r.messages, contains('RestageFormattedNumber'));
    });
  });

  group('the look-alike defense (element-gated on package:intl/)', () {
    test(
        'a resolved CUSTOMER NumberFormat.currency look-alike gets only the '
        'generic defer — never named the adopt-target', () async {
      // A customer class named NumberFormat resolves to a non-intl library;
      // the element gate withholds the adopt-target. (Naming an intl-specific
      // widget for a coincidental look-alike would be a value-wrong hint.)
      final r = translator.translate(
        await parseExpressionFromSourceForTest('''
class NumberFormat {
  factory NumberFormat.currency({
    String? locale,
    String? symbol,
    int? decimalDigits,
  }) = NumberFormat._;
  NumberFormat._();
  String format(num n) => '';
}
Object x() => NumberFormat.currency(
  locale: 'en_US', symbol: 'USD', decimalDigits: 2,
).format(1234.5);
'''),
      );
      expect(r.dsl, isEmpty);
      expect(r.issues, isNotEmpty);
      expect(
        r.issues.map((i) => i.message).join('\n'),
        isNot(contains('RestagePrice')),
      );
    });
  });

  group('non-whitelisted constructors stay generic (no adopt-target yet)', () {
    test(
        'NumberFormat.percentPattern(...).format(x) is not adopted in this '
        'cut', () async {
      final r = await run("NumberFormat.percentPattern('en_US').format(0.25)");
      expect(r.dsl, isEmpty);
      expect(r.messages, isNot(contains('RestagePrice')));
      expect(r.messages, isNot(contains('RestageFormattedNumber')));
    });
  });
}
