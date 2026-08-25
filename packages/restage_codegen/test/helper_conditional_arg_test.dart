import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator priceTranslator() => ExpressionTranslator(
        catalog: catalogWith([
          entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
          entry(
            name: 'GestureDetector',
            properties: [
              prop('onTap', PropertyType.event),
              prop('child', PropertyType.widget),
            ],
          ),
        ]),
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );

  const annualBool = CustomWidgetStateField(
    name: 'annual',
    isNumeric: false,
    initialValue: true,
  );
  const planBool = CustomWidgetStateField(
    name: 'plan',
    isNumeric: false,
    initialValue: true,
  );

  test('rejects a conditional paywallPriceFor argument', () async {
    final expr = await parseExpressionForTest(
      'Text(text: paywallPriceFor(slot: '
      "annual ? 'pro_annual' : 'pro_monthly'))",
    );
    final result = priceTranslator().translate(expr, rootState: [annualBool]);
    expect(
      result.issues.map((issue) => issue.code),
      [IssueCode.unsupportedCommerceAuthoring],
    );
    expect(
      result.dsl,
      isNot(contains('data.products')),
    );
  });

  test('rejects a nested conditional paywallPriceFor argument', () async {
    final expr = await parseExpressionForTest(
      'Text(text: paywallPriceFor(slot: '
      "plan ? annual ? 'pa' : 'pm' : annual ? 'ba' : 'bm'))",
    );
    final result = priceTranslator().translate(
      expr,
      rootState: [planBool, annualBool],
    );
    expect(
      result.issues.map((issue) => issue.code),
      [IssueCode.unsupportedCommerceAuthoring],
    );
    expect(
      result.dsl,
      isNot(contains('data.products')),
    );
  });

  test('rejects a conditional paywallPurchase argument', () async {
    final expr = await parseExpressionForTest(
      "GestureDetector(onTap: paywallPurchase(slot: annual ? 'a' : 'b'))",
    );
    final result = priceTranslator().translate(expr, rootState: [annualBool]);
    expect(
      result.issues.map((issue) => issue.code),
      [IssueCode.unsupportedCommerceAuthoring],
    );
    expect(
      result.dsl,
      isNot(contains('restage.purchase')),
    );
  });
}
