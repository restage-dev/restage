// A state-conditional argument inside a VALUE-REFERENCE helper call.
//
// `paywallPriceFor(slot: cond ? 'a' : 'b')` previously emitted malformed DSL:
// the value helper interpolates its slot into a reference PATH
// (`data.products.$id.localizedPrice`), and a ternary slot lowered to a
// `switch …` landing inside that path —
// `data.products.switch state.X {…}.localizedPrice` — which fails to parse
// (a self-described codegen bug). Distribute the conditional OVER the helper
// so each branch produces a full reference — exactly the switch-of-references
// the inverted idiom (`cond ? paywallPriceFor('a') : paywallPriceFor('b')`)
// already produced. EVENT helpers (voidCallback) keep their committed
// pass-through (the switch sits in a value position there).
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
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

  test(
      'a conditional slot in paywallPriceFor distributes into a switch of '
      'references (the inverted-idiom output, valid DSL)', () async {
    final expr = await parseExpressionForTest(
      'Text(text: paywallPriceFor(slot: '
      "annual ? 'pro_annual' : 'pro_monthly'))",
    );
    final result = priceTranslator().translate(expr, rootState: [annualBool]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains(
        'text: switch state.annual { '
        'true: data.products.pro_annual.localizedPrice, '
        'false: data.products.pro_monthly.localizedPrice }',
      ),
    );
  });

  test('a nested two-axis conditional slot distributes into a nested switch',
      () async {
    // Unparenthesized nested ternary (right-assoc) — independent of the
    // parenthesis unwrap.
    final expr = await parseExpressionForTest(
      'Text(text: paywallPriceFor(slot: '
      "plan ? annual ? 'pa' : 'pm' : annual ? 'ba' : 'bm'))",
    );
    final result =
        priceTranslator().translate(expr, rootState: [planBool, annualBool]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains(
        'switch state.plan { '
        'true: switch state.annual { '
        'true: data.products.pa.localizedPrice, '
        'false: data.products.pm.localizedPrice }, '
        'false: switch state.annual { '
        'true: data.products.ba.localizedPrice, '
        'false: data.products.bm.localizedPrice } }',
      ),
    );
  });

  test(
      'REGRESSION: a conditional slot in paywallPurchase (an event helper) '
      'keeps the committed switch-in-value-position form', () async {
    final expr = await parseExpressionForTest(
      "GestureDetector(onTap: paywallPurchase(slot: annual ? 'a' : 'b'))",
    );
    final result = priceTranslator().translate(expr, rootState: [annualBool]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains(
        'onTap: event "restage.purchase" '
        '{ slot: switch state.annual { true: "a", false: "b" } }',
      ),
    );
  });
}
