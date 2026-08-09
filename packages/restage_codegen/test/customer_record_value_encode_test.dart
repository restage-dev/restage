import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('customer record value encode', () {
    test(
        'an admitted named record emits a canonical label-keyed map with '
        'slot-aware values', () async {
      final expr = await parseExpressionFromSourceForTest('''
        enum Tone { soft, loud }

        ({String title, int step, Tone tone, double width}) x() => (
          title: 'Hello',
          step: 2,
          tone: Tone.soft,
          width: 24,
        );
      ''');
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        '{step: 2, title: "Hello", tone: "soft", width: 24.0}',
      );
    });

    test('a positional record literal defers loud', () async {
      final expr = await parseExpressionFromSourceForTest('''
        (String, int) x() => ('Hello', 2);
      ''');
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isNotEmpty);
      expect(result.dsl, '');
    });

    test('a record outside the admitted boundary defers loud', () async {
      final expr = await parseExpressionFromSourceForTest('''
        ({String? title}) x() => (title: null);
      ''');
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isNotEmpty);
      expect(result.dsl, '');
    });

    test('one deferred label suppresses the whole record', () async {
      final expr = await parseExpressionFromSourceForTest('''
        String unavailable() => 'not encodable';

        ({String aGood, String zBad}) x() => (
          aGood: 'encoded first',
          zBad: unavailable(),
        );
      ''');
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isNotEmpty);
      expect(result.dsl, '');
    });

    test('a non-const prefixed getter is diagnosed, not stringified', () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Config {
          static String get currentLabel => 'runtime';
        }

        String x() => Config.currentLabel;
      ''');
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(expr);

      expect(result.dsl, '');
      expect(
        result.issues,
        contains(
          isA<Issue>().having(
            (issue) => issue.code,
            'code',
            IssueCode.unresolvedIdentifier,
          ),
        ),
      );
    });

    test('a bad prefixed record label suppresses the complete record',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Config {
          static String get currentLabel => 'runtime';
        }

        ({String good, String label}) x() => (
          good: 'authored',
          label: Config.currentLabel,
        );
      ''');
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(expr);

      expect(result.issues, isNotEmpty);
      expect(result.dsl, '');
      expect(result.dsl, isNot(contains('currentLabel')));
    });
  });
}
