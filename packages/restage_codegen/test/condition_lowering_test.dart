// Every condition lowers to a composition of RFW `switch`, the only
// conditional the data language has. Each fragment is asserted to parse.
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator translator() => ExpressionTranslator(
        catalog: catalogWith([
          entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
          entry(name: 'SizedBox', properties: []),
          entry(
            name: 'Column',
            childrenSlot: ChildrenSlot.list,
            properties: [prop('children', PropertyType.widgetList)],
          ),
          entry(
            name: 'Wrap',
            childrenSlot: ChildrenSlot.list,
            properties: [prop('children', PropertyType.widgetList)],
          ),
          entry(
            name: 'AppBar',
            properties: [
              prop('title', PropertyType.widget),
              prop('actions', PropertyType.widgetList),
            ],
          ),
          entry(
            name: 'Visibility',
            properties: [
              prop('visible', PropertyType.boolean),
              prop('child', PropertyType.widget),
            ],
          ),
          entry(
            name: 'Switch',
            properties: [prop('value', PropertyType.boolean)],
          ),
        ]),
        helpers: HelperRegistry(),
      );

  const isPro = CustomWidgetStateField(
    name: 'isPro',
    isNumeric: false,
    initialValue: true,
  );
  const trialUsed = CustomWidgetStateField(
    name: 'trialUsed',
    isNumeric: false,
    initialValue: false,
  );
  const plan = CustomWidgetStateField(
    name: 'plan',
    isNumeric: false,
    initialValue: 'annual',
  );
  const tier = CustomWidgetStateField(
    name: 'tier',
    isNumeric: false,
    initialValue: 0,
  );

  const allState = [isPro, trialUsed, plan, tier];

  Future<TranslationResult> lower(String body) async {
    final expr = await parseExpressionForTest(body);
    return translator().translate(expr, rootState: allState);
  }

  /// Asserts the fragment parses as an RFW library and returns it.
  String parsed(TranslationResult result) {
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    fmt.parseLibraryFile(emitPaywallLibrary(result.dsl));
    return result.dsl;
  }

  group('negation and boolean composition', () {
    test('`!bool` swaps the arms of the bool switch', () async {
      final result = await lower("Text(text: !isPro ? 'A' : 'B')");
      expect(
        parsed(result),
        contains('switch state.isPro { true: "B", false: "A" }'),
      );
    });

    test('a double negation returns to the original arm order', () async {
      final result = await lower("Text(text: !(!isPro) ? 'A' : 'B')");
      expect(
        parsed(result),
        contains('switch state.isPro { true: "A", false: "B" }'),
      );
    });

    test('`&&` nests the right switch under the left true arm', () async {
      final result = await lower("Text(text: isPro && !trialUsed ? 'A' : 'B')");
      expect(
        parsed(result),
        contains(
          'switch state.isPro { true: switch state.trialUsed '
          '{ true: "B", false: "A" }, false: "B" }',
        ),
      );
    });

    test('`||` nests the right switch under the left false arm', () async {
      final result = await lower("Text(text: isPro || trialUsed ? 'A' : 'B')");
      expect(
        parsed(result),
        contains(
          'switch state.isPro { true: "A", false: switch state.trialUsed '
          '{ true: "A", false: "B" } }',
        ),
      );
    });

    test('`!(a && b)` swaps the arms of the whole composition', () async {
      final result =
          await lower("Text(text: !(isPro && trialUsed) ? 'A' : 'B')");
      expect(
        parsed(result),
        contains(
          'switch state.isPro { true: switch state.trialUsed '
          '{ true: "B", false: "A" }, false: "A" }',
        ),
      );
    });

    test('a nested `a && (b || c)` lowers through the same lowerer', () async {
      final result = await lower(
        "Text(text: isPro && (trialUsed || plan == 'annual') ? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains(
          'switch state.isPro { true: switch state.trialUsed { true: "A", '
          'false: switch state.plan { "annual": "A", default: "B" } }, '
          'false: "B" }',
        ),
      );
    });

    test('an int-state equality composes as a 2-arm keyed switch', () async {
      final result = await lower("Text(text: tier == 1 && isPro ? 'A' : 'B')");
      expect(
        parsed(result),
        contains(
          'switch state.tier { 1: switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );
    });
  });

  group('string equality', () {
    test('`==` against a String state field keys the switch', () async {
      final result = await lower("Text(text: plan == 'annual' ? 'A' : 'B')");
      expect(
        parsed(result),
        contains('switch state.plan { "annual": "A", default: "B" }'),
      );
    });

    test('the literal-on-the-left form lowers identically', () async {
      final result = await lower("Text(text: 'annual' == plan ? 'A' : 'B')");
      expect(
        parsed(result),
        contains('switch state.plan { "annual": "A", default: "B" }'),
      );
    });

    test('`!=` swaps the arms', () async {
      final result = await lower("Text(text: plan == 'annual' ? 'A' : 'B')");
      final negated = await lower("Text(text: plan != 'annual' ? 'B' : 'A')");
      expect(parsed(result), parsed(negated));
    });

    test('a same-reference chain flattens into one N-arm switch', () async {
      final result = await lower(
        "Text(text: plan == 'annual' ? 'A' "
        ": plan == 'monthly' ? 'B' : 'C')",
      );
      expect(
        parsed(result),
        contains(
          'switch state.plan { "annual": "A", "monthly": "B", default: "C" }',
        ),
      );
    });

    test('a string equality composes under `&&`', () async {
      final result = await lower(
        "Text(text: plan == 'annual' && isPro ? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains(
          'switch state.plan { "annual": switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );
    });

    test('a non-literal right-hand side refuses loudly', () async {
      final result = await lower("Text(text: plan == isPro ? 'A' : 'B')");
      expect(result.issues, isNotEmpty);
      expect(result.dsl, isNot(contains('switch state.plan')));
    });

    test('a whole-object comparison refuses loudly', () async {
      final result = await lower("Text(text: plan == tier ? 'A' : 'B')");
      expect(result.issues, isNotEmpty);
      expect(result.dsl, isNot(contains('switch')));
    });

    test('an unlowerable operand inside `&&` refuses loudly', () async {
      final result = await lower(
        "Text(text: isPro && plan == unknownThing ? 'A' : 'B')",
      );
      expect(result.issues, isNotEmpty);
      expect(result.dsl, isNot(contains('switch state.isPro')));
    });
  });

  group('int-state `!=`', () {
    test('lowers to the swapped 2-arm form', () async {
      final result = await lower("Text(text: tier != 1 ? 'A' : 'B')");
      expect(
        parsed(result),
        contains('switch state.tier { 1: "B", default: "A" }'),
      );
    });

    test('`<` still defers with the named diagnostic', () async {
      final result = await lower("Text(text: tier < 1 ? 'A' : 'B')");
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.intStateConditionUnsupported),
      );
    });
  });

  group('run-time collection-`if`', () {
    test('an else-less `if` becomes a switch with an empty false arm',
        () async {
      final result = await lower(
        "Column(children: [Text(text: 'a'), if (isPro) Text(text: 'b')])",
      );
      expect(
        parsed(result),
        'Column(children: [Text(text: "a"), ...for presence in '
        'switch state.isPro { true: [0], false: [] }: Text(text: "b")])',
      );
    });

    test('an `if … else` puts each branch on its own arm', () async {
      final result = await lower(
        "Column(children: [if (isPro) Text(text: 'b') else Text(text: 'c')])",
      );
      expect(
        parsed(result),
        'Column(children: [switch state.isPro '
        '{ true: Text(text: "b"), false: Text(text: "c") }])',
      );
    });

    test('a composed condition lowers through the same lowerer', () async {
      final result = await lower(
        'Column(children: '
        "[if (!trialUsed && isPro) Text(text: 'b')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch state.trialUsed '
        '{ true: [], false: switch state.isPro { true: [0], false: [] } }: '
        'Text(text: "b")])',
      );
    });

    test('a const-folded condition still unrolls statically', () async {
      final result = await lower(
        "Column(children: [if (true) Text(text: 'b'), if (false) "
        "Text(text: 'c')])",
      );
      expect(parsed(result), 'Column(children: [Text(text: "b")])');
    });

    test('a spread body refuses loudly', () async {
      final result = await lower(
        "Column(children: [if (isPro) ...[Text(text: 'b')]])",
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });

    test('an else-less `if` in a non-widget list lowers', () async {
      final expr = await parseExpressionForTest('[if (isPro) 1, 2]');
      final result = translator().translate(expr, rootState: allState);
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(
        result.dsl,
        '[...for presence in switch state.isPro '
        '{ true: [0], false: [] }: 1, 2]',
      );
    });

    test('an else-less `if` in a string list lowers', () async {
      final expr = await parseExpressionForTest("[if (isPro) 'a', 'b']");
      final result = translator().translate(expr, rootState: allState);
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(
        result.dsl,
        '[...for presence in switch state.isPro '
        '{ true: [0], false: [] }: "a", "b"]',
      );
    });

    test('an `if … else` in a non-widget list lowers', () async {
      final expr = await parseExpressionForTest('[if (isPro) 1 else 2, 3]');
      final result = translator().translate(expr, rootState: allState);
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.dsl, '[switch state.isPro { true: 1, false: 2 }, 3]');
    });

    test('an unlowerable condition refuses loudly', () async {
      final result = await lower(
        "Column(children: [if (unknownThing) Text(text: 'b')])",
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });
  });

  group('conditions bound directly to a boolean slot', () {
    test('a composition lowers to switches selecting true or false', () async {
      final result = await lower(
        "Visibility(visible: !trialUsed && isPro, child: Text(text: 'a'))",
      );
      expect(
        parsed(result),
        contains(
          'visible: switch state.trialUsed { true: false, '
          'false: switch state.isPro { true: true, false: false } }',
        ),
      );
    });

    test('a string equality lowers at a boolean slot', () async {
      final result = await lower("Switch(value: plan == 'annual')");
      expect(
        parsed(result),
        contains('value: switch state.plan { "annual": true, default: false }'),
      );
    });

    test('an int-state equality lowers at a boolean slot', () async {
      final result = await lower('Switch(value: tier != 1)');
      expect(
        parsed(result),
        contains('value: switch state.tier { 1: false, default: true }'),
      );
    });

    test('a bare bool reference is unchanged', () async {
      final result = await lower('Switch(value: isPro)');
      expect(parsed(result), 'Switch(value: state.isPro)');
    });

    test('an unlowerable condition at a boolean slot refuses loudly', () async {
      final result = await lower('Switch(value: !unknownThing)');
      expect(result.issues, isNotEmpty);
      expect(result.dsl, isNot(contains('switch')));
    });
  });

  group('the collection-`if` in other list slots and nested', () {
    test('lowers in a non-`children` widget-list slot', () async {
      final result = await lower(
        "AppBar(title: Text(text: 't'), "
        "actions: [if (isPro) Text(text: 'b')])",
      );
      expect(
        parsed(result),
        contains(
          'actions: [...for presence in switch state.isPro '
          '{ true: [0], false: [] }: Text(text: "b")]',
        ),
      );
    });

    test('lowers in a second list-bearing widget', () async {
      final result = await lower(
        "Wrap(children: [if (isPro) Text(text: 'b') else Text(text: 'c')])",
      );
      expect(
        parsed(result),
        'Wrap(children: [switch state.isPro '
        '{ true: Text(text: "b"), false: Text(text: "c") }])',
      );
    });

    test('a nested `if` inside an `if` nests the switches', () async {
      final result = await lower(
        "Column(children: [if (isPro) if (!trialUsed) Text(text: 'b')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch state.isPro '
        '{ true: switch state.trialUsed { true: [], false: [0] }, '
        'false: [] }: Text(text: "b")])',
      );
    });

    test('a nested `if … else` inside an `if` keeps both inner arms', () async {
      final result = await lower(
        'Column(children: [if (isPro) '
        "if (trialUsed) Text(text: 'b') else Text(text: 'c')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch state.isPro '
        '{ true: switch state.trialUsed { true: [0], false: [] }, false: [] }: '
        'Text(text: "b"), ...for presence in switch state.isPro '
        '{ true: switch state.trialUsed { true: [], false: [0] }, false: [] }: '
        'Text(text: "c")])',
      );
    });

    test('an `else if` chain nests on the false arm', () async {
      final result = await lower(
        "Column(children: [if (isPro) Text(text: 'b') "
        "else if (trialUsed) Text(text: 'c')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch state.isPro '
        '{ true: [0], false: [] }: Text(text: "b"), '
        '...for presence in switch state.isPro { true: [], '
        'false: switch state.trialUsed { true: [0], false: [] } }: '
        'Text(text: "c")])',
      );
    });

    test('a spread inside a nested `if` refuses loudly', () async {
      final result = await lower(
        'Column(children: '
        "[if (isPro) if (trialUsed) ...[Text(text: 'b')]])",
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.unsupportedCollectionFlow),
      );
    });
  });

  group('the ambient brightness as a condition operand', () {
    test('composes under `&&` with a state reference', () async {
      final result = await lower(
        'Text(text: Theme.of(context).brightness == Brightness.dark && isPro '
        "? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains(
          'switch data.theme.brightness { "dark": switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );
    });

    test('negates', () async {
      final result = await lower(
        'Text(text: !(Theme.of(context).brightness == Brightness.dark) '
        "? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains(
          'switch data.theme.brightness { "dark": "B", default: "A" }',
        ),
      );
    });

    test('lowers bound directly to a boolean slot', () async {
      final result = await lower(
        'Visibility(visible: '
        'Theme.of(context).brightness == Brightness.dark, '
        "child: Text(text: 'a'))",
      );
      expect(
        parsed(result),
        contains(
          'visible: switch data.theme.brightness '
          '{ "dark": true, default: false }',
        ),
      );
    });

    test('gates a collection-`if`', () async {
      final result = await lower(
        'Column(children: [if '
        '(Theme.of(context).brightness == Brightness.dark) '
        "Text(text: 'night')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch data.theme.brightness '
        '{ "dark": [0], default: [] }: Text(text: "night")])',
      );
    });

    test('gates a collection-`if` through a composition', () async {
      final result = await lower(
        'Column(children: [if '
        '(Theme.of(context).brightness == Brightness.light || isPro) '
        "Text(text: 'a')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch data.theme.brightness '
        '{ "light": [0], default: switch state.isPro '
        '{ true: [0], false: [] } }: Text(text: "a")])',
      );
    });
  });

  group('device data as a condition operand', () {
    test('a platform equality composes under `&&`', () async {
      final result = await lower(
        'Text(text: defaultTargetPlatform == TargetPlatform.iOS && isPro '
        "? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains(
          'switch data.device.platform { "iOS": switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );
    });

    test('a bare platform flag composes under `&&`', () async {
      final result = await lower("Text(text: kIsWeb && isPro ? 'A' : 'B')");
      expect(
        parsed(result),
        contains(
          'switch data.device.platform { "web": switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );
    });

    test('a platform equality negates', () async {
      final result = await lower(
        'Text(text: !(defaultTargetPlatform == TargetPlatform.iOS) '
        "? 'A' : 'B')",
      );
      expect(
        parsed(result),
        contains('switch data.device.platform { "iOS": "B", default: "A" }'),
      );
    });

    test('lowers bound directly to a boolean slot', () async {
      final result = await lower(
        'Visibility(visible: '
        'defaultTargetPlatform == TargetPlatform.iOS, '
        "child: Text(text: 'a'))",
      );
      expect(
        parsed(result),
        contains(
          'visible: switch data.device.platform '
          '{ "iOS": true, default: false }',
        ),
      );
    });

    test('an orientation match composes and gates a collection-`if`', () async {
      final composed = await lower(
        'Text(text: MediaQuery.orientationOf(context) == '
        "Orientation.portrait && isPro ? 'A' : 'B')",
      );
      expect(
        parsed(composed),
        contains(
          'switch data.device.orientation { "portrait": switch state.isPro '
          '{ true: "A", false: "B" }, default: "B" }',
        ),
      );

      final gated = await lower(
        'Column(children: [if '
        '(MediaQuery.orientationOf(context) == Orientation.landscape) '
        "Text(text: 'wide')])",
      );
      expect(
        parsed(gated),
        'Column(children: [...for presence in switch data.device.orientation '
        '{ "landscape": [0], default: [] }: Text(text: "wide")])',
      );
    });

    test('a language subtag gates a collection-`if`', () async {
      final result = await lower(
        'Column(children: [if '
        "(Localizations.localeOf(context).languageCode == 'fr') "
        "Text(text: 'Bonjour')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch data.device.languageCode '
        '{ "fr": [0], default: [] }: Text(text: "Bonjour")])',
      );
    });

    test('a language subtag gates a collection-`if` through a composition',
        () async {
      final result = await lower(
        'Column(children: [if '
        "(Localizations.localeOf(context).languageCode == 'fr' || isPro) "
        "Text(text: 'a')])",
      );
      expect(
        parsed(result),
        'Column(children: [...for presence in switch data.device.languageCode '
        '{ "fr": [0], default: switch state.isPro '
        '{ true: [0], false: [] } }: Text(text: "a")])',
      );
    });
  });
}
