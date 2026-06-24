// An integer-state equality chain lowers to a native N-arm `switch` keyed on
// the int field. Only `<intStateField> == <intLiteral>` lowers (equality-only
// this increment); `!=`/`<`/`>`, a non-literal RHS, and the
// literal-on-the-left form defer with a named diagnostic — never a silent
// wrong/degraded blob. Same-field arms flatten into one switch; a
// different-field arm recurses to its OWN nested switch and can never be
// absorbed into the outer switch's arm set.
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator translator() => ExpressionTranslator(
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

  // An int state field is captured isNumeric:false (only double/num are
  // numeric) with an int initialValue — emitted as a bare int, so the switch
  // keys on int literals.
  const tier = CustomWidgetStateField(
    name: 'selectedTier',
    isNumeric: false,
    initialValue: 0,
  );
  const plan = CustomWidgetStateField(
    name: 'selectedPlan',
    isNumeric: false,
    initialValue: 0,
  );

  group('int-state equality chains lower to a native N-arm switch', () {
    test('a 3-tier chain flattens to one switch keyed on the int field',
        () async {
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'A' "
        ": selectedTier == 1 ? 'B' : 'C')",
      );
      final result = translator().translate(expr, rootState: [tier]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'text: switch state.selectedTier '
          '{ 0: "A", 1: "B", default: "C" }',
        ),
      );
    });

    test('a single comparison in a 2-arm conditional lowers to a 2-arm switch',
        () async {
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'A' : 'B')",
      );
      final result = translator().translate(expr, rootState: [tier]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains('text: switch state.selectedTier { 0: "A", default: "B" }'),
      );
    });

    test('a 4-arm tier-strip chain flattens to one switch', () async {
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'Basic' "
        ": selectedTier == 1 ? 'Premium' "
        ": selectedTier == 2 ? 'Premium+' : 'Enterprise')",
      );
      final result = translator().translate(expr, rootState: [tier]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'switch state.selectedTier { 0: "Basic", 1: "Premium", '
          '2: "Premium+", default: "Enterprise" }',
        ),
      );
    });

    test('the int state field emits as a bare int in the root state', () async {
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'A' : 'B')",
      );
      final result = translator().translate(expr, rootState: [tier]);
      expect(result.rootWidgetState['selectedTier'], '0');
    });

    test('an int-switch arm carrying a price helper still lowers (composes)',
        () async {
      final expr = await parseExpressionForTest(
        'Text(text: selectedTier == 0 '
        "? paywallPriceFor(slot: 'a') : paywallPriceFor(slot: 'b'))",
      );
      final result = translator().translate(expr, rootState: [tier]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'switch state.selectedTier { '
          '0: data.products.a.localizedPrice, '
          'default: data.products.b.localizedPrice }',
        ),
      );
    });
  });

  group('strictness: only `<intField> == <intLiteral>` lowers', () {
    Future<List<Issue>> issuesFor(
      String body, {
      List<CustomWidgetStateField> state = const [tier],
    }) async {
      final expr = await parseExpressionForTest('Text(text: $body)');
      return translator().translate(expr, rootState: state).issues;
    }

    test('`!=` on an int state field defers with a named diagnostic', () async {
      final issues = await issuesFor("selectedTier != 0 ? 'A' : 'B'");
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.intStateConditionUnsupported),
      );
    });

    test('`<` on an int state field defers named', () async {
      final issues = await issuesFor("selectedTier < 1 ? 'A' : 'B'");
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.intStateConditionUnsupported),
      );
    });

    test('a non-literal RHS defers named', () async {
      final issues = await issuesFor(
        "selectedTier == selectedPlan ? 'A' : 'B'",
        state: [tier, plan],
      );
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.intStateConditionUnsupported),
      );
    });

    test('the literal-on-the-left form defers named', () async {
      final issues = await issuesFor("0 == selectedTier ? 'A' : 'B'");
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.intStateConditionUnsupported),
      );
    });

    test('a bool-state condition is unchanged (still a bool 2-arm switch)',
        () async {
      const annual = CustomWidgetStateField(
        name: 'annual',
        isNumeric: false,
        initialValue: true,
      );
      final expr = await parseExpressionForTest(
        "Text(text: annual ? 'A' : 'B')",
      );
      final result = translator().translate(expr, rootState: [annual]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains('switch state.annual { true: "A", false: "B" }'),
      );
    });
  });

  group('recurse-per-field: two-axis chains key each switch on its own field',
      () {
    test('a two-axis chain keys EACH switch on its own field', () async {
      // `tier==0 ? A : (plan==1 ? B : C)` — the terminal else is a DIFFERENT
      // field; it recurses to its own nested switch.
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'Tier0' "
        ": selectedPlan == 1 ? 'Plan1' : 'Else')",
      );
      final result = translator().translate(expr, rootState: [tier, plan]);
      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains(
          'switch state.selectedTier { 0: "Tier0", '
          'default: switch state.selectedPlan '
          '{ 1: "Plan1", default: "Else" } }',
        ),
      );
    });

    test(
        'a different-field arm is NEVER absorbed into the '
        "outer switch's arm set", () async {
      final expr = await parseExpressionForTest(
        "Text(text: selectedTier == 0 ? 'Tier0' "
        ": selectedPlan == 1 ? 'Plan1' : 'Else')",
      );
      final result = translator().translate(expr, rootState: [tier, plan]);
      // The mis-flatten would key selectedPlan's `1` arm under selectedTier.
      expect(
        result.dsl,
        isNot(contains('switch state.selectedTier { 0: "Tier0", 1:')),
      );
    });
  });
}
