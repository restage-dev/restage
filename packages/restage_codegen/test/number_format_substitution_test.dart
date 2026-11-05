import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final translator = ExpressionTranslator(
    catalog: catalogWith([
      entry(
        name: 'Text',
        flutterType: 'package:flutter/src/widgets/text.dart#Text',
        properties: [
          prop('text', PropertyType.string, positional: true),
          prop('maxLines', PropertyType.integer),
          prop('semanticsLabel', PropertyType.string),
          prop('locale', PropertyType.locale),
        ],
      ),
    ]),
    helpers: HelperRegistry(),
  );

  Future<TranslationResult> run(
    String body, {
    String declarations = '',
    List<CustomWidgetStateField> state = const [],
    bool mount = false,
  }) async {
    final expr = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
$declarations
Object x() => $body;
''', rootPackage: 'apps_examples');
    return translator.translate(expr, rootState: state, hoistInMount: mount);
  }

  void expectNative(TranslationResult result) {
    expect(
      result.issues.where((i) => !i.code.isBuildNotice),
      isEmpty,
      reason: result.issues.map((i) => i.message).join('\n'),
    );
    expect(result.dsl, startsWith('Text('));
    expect(result.dsl, contains('intl.number.format'));
    expect(result.dsl, isNot(contains('RestagePrice(')));
    expect(result.dsl, isNot(contains('RestageFormattedNumber(')));
    expect(
      result.issues.map((i) => i.code),
      isNot(contains(IssueCode.idiomAutoSubstituted)),
    );
  }

  test('currency and decimal formatting remain native Text values', () async {
    for (final body in [
      r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2).format(9.99))",
      "Text(NumberFormat.decimalPattern('de_DE').format(1234.5))",
      'Text(NumberFormat().format(1234.5))',
      "Text(NumberFormat.simpleCurrency(locale: 'en_US').format(9.99))",
      "Text(NumberFormat.currency(locale: 'en_US', name: 'USD').format(9))",
    ]) {
      expectNative(await run(body));
    }
  });

  test('all authored Text properties remain on Text', () async {
    final result = await run(
      r"Text(NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2).format(9.99), maxLines: 2, semanticsLabel: 'price', locale: Locale('en'))",
    );
    expectNative(result);
    expect(result.dsl, contains('maxLines: 2'));
    expect(result.dsl, contains('semanticsLabel: "price"'));
    expect(result.dsl, contains('locale:'));
  });

  test(
    'resolved Flutter keys retain the ordinary constructor treatment',
    () async {
      final result = await run(
        "Text(NumberFormat().format(1234.5), key: const ValueKey<String>('formatted-number'))",
        mount: true,
      );
      // This catalog's Text can't carry a key, so the Text renders from the
      // app with its key rather than becoming a substituted widget.
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.islands.map((island) => island.widget), ['Text']);
      expect(result.islands.single.reason?.message, contains('Key binding'));
      expect(result.dsl, isNot(contains('RestagePrice(')));
      expect(result.dsl, isNot(contains('RestageFormattedNumber(')));
    },
  );

  test(
    'both int and double state values keep their native numeric type',
    () async {
      for (final (type, value) in [('int', 1), ('double', 9.99)]) {
        final result = await run(
          'Text(NumberFormat.decimalPattern().format(amount))',
          declarations: '$type amount = $value;',
          state: [
            CustomWidgetStateField(
              name: 'amount',
              isNumeric: type == 'double',
              initialValue: value,
            ),
          ],
        );
        expectNative(result);
        expect(result.dsl, contains('state.amount'));
      }
    },
  );

  test('unresolved runtime configuration remains a located refusal', () async {
    final result = await run(
      'Text(NumberFormat.currency(locale: unknownLocale).format(9.99))',
    );
    expect(result.issues.where((i) => !i.code.isBuildNotice), isNotEmpty);
    expect(result.dsl, isNot(contains('intl.number.format')));
  });

  test(
    'a resolved NumberFormat lookalike never becomes an intl value',
    () async {
      final expr = await parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
class NumberFormat {
  NumberFormat.currency();
  String format(num value) => 'custom';
}
Object x() => Text(NumberFormat.currency().format(9.99));
''', rootPackage: 'apps_examples');
      final result = translator.translate(expr);
      expect(result.dsl, isNot(contains('intl.number')));
      expect(result.issues.where((i) => !i.code.isBuildNotice), isNotEmpty);
    },
  );
}
