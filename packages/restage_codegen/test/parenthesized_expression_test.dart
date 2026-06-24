// Parenthesized expressions are unwrapped uniformly at every dispatch
// site. `(cond ? a : b)` rejected where the identical unparenthesized form
// built a correct nested switch — a pure paren-stripping gap. The asymmetry
// guard is load-bearing: a parenthesized conditional at a NUMERIC slot must
// still route through the slot-aware per-branch double coercion, not emit
// bare ints the runtime `v<double>` decode silently nulls.
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator translator() => ExpressionTranslator(
        catalog: catalogWith([
          entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
          entry(
            name: 'SizedBox',
            properties: [
              prop('width', PropertyType.length),
              prop('child', PropertyType.widget),
            ],
          ),
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

  const annual = CustomWidgetStateField(
    name: 'annual',
    isNumeric: false,
    initialValue: true,
  );
  const business = CustomWidgetStateField(
    name: 'business',
    isNumeric: false,
    initialValue: true,
  );

  test('a parenthesized ternary lowers like the unparenthesized form',
      () async {
    final expr =
        await parseExpressionForTest("Text(text: (annual ? 'A' : 'B'))");
    final result = translator().translate(expr, rootState: [annual]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains('text: switch state.annual { true: "A", false: "B" }'),
    );
  });

  test('a two-axis parenthesized nested conditional builds the nested switch',
      () async {
    // A two-axis purchase slot, parenthesized (the idiomatic
    // way to write it).
    final expr = await parseExpressionForTest(
      'GestureDetector(onTap: paywallPurchase(slot: '
      "business ? (annual ? 'business_annual' : 'business_monthly') "
      ": (annual ? 'plus_annual' : 'plus_monthly')))",
    );
    final result = translator().translate(expr, rootState: [business, annual]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains(
        'slot: switch state.business { '
        'true: switch state.annual { '
        'true: "business_annual", false: "business_monthly" }, '
        'false: switch state.annual { '
        'true: "plus_annual", false: "plus_monthly" } }',
      ),
    );
  });

  test(
      'ASYMMETRY GUARD: a parenthesized conditional at a numeric slot keeps '
      'the per-branch double coercion (not bare ints)', () async {
    final expr =
        await parseExpressionForTest('SizedBox(width: (annual ? 0 : 8))');
    final result = translator().translate(expr, rootState: [annual]);
    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      contains('width: switch state.annual { true: 0.0, false: 8.0 }'),
    );
  });
}
