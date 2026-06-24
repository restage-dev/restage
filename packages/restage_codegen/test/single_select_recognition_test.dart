@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/single_select_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pure AST recognition proofs for the two vanilla-Flutter single-select idioms
/// that lower to the compiled `RestageRadioGroup` / `RestageDropdown` catalog
/// widgets. The governing invariant: a clean, fully-extractable group yields a
/// `SingleSelectRecognised` carrying the `{value, label}` pairs in source
/// order; **any** unparseable shape defers the WHOLE widget loud with a
/// `SingleSelectDeferred` — never a partial or silently-wrong group. The
/// negatives are the point: a silently-dropped or wrong option in a remote
/// radio/dropdown is the one failure this widget must not ship.
void main() {
  group('recogniseRadioGroup — the canonical lower-able form', () {
    test('extracts {value, label} pairs in source order + selected + onChanged',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: selectedPlan,
  onChanged: (String? v) => onSelect(v),
  child: Column(children: [
    RadioListTile<String>(value: 'monthly', title: Text('Monthly')),
    RadioListTile<String>(value: 'annual', title: Text('Annual')),
  ]),
)
''');

      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(2));
      expect(_value(recognised.options[0]), "'monthly'");
      expect(_label(recognised.options[0]), "'Monthly'");
      expect(_value(recognised.options[1]), "'annual'");
      expect(_label(recognised.options[1]), "'Annual'");
      expect(recognised.selected?.toSource(), 'selectedPlan');
      expect(recognised.onChanged, isNotNull);
    });

    test('a bare list literal child (no Column wrapper) is accepted', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: [
    RadioListTile<String>(value: 'a', title: Text('A')),
    RadioListTile<String>(value: 'b', title: Text('B')),
  ],
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(2));
      expect(_value(recognised.options.first), "'a'");
    });

    test('a ListView(children:) child is accepted', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: ListView(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(1));
    });

    test(
        'a missing groupValue (unselected group) recognises with null selected',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.selected, isNull);
      expect(recognised.onChanged, isNotNull);
    });

    test('a RadioListTile with a behavioral arg (enabled) defers the group',
        () async {
      // `enabled: false` makes a remote option un-tappable; the flat
      // single-select has no per-option enabled, so silently dropping it would
      // render the option enabled. Carry-all-or-defer: the WHOLE group defers
      // loud (named) rather than ship a wrong-behavior option.
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A'), enabled: false),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'enabled');
    });

    test('a RadioListTile with an onTap behavioral arg defers the whole group',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A'), onTap: doTap),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'onTap');
    });
  });

  group('recogniseRadioGroup — all-or-defer-loud negatives', () {
    test('a non-list / dynamic builder child defers the WHOLE widget',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Builder(builder: (c) => Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ])),
)
''');
      _expectDeferred(outcome);
    });

    test('a ListView.builder (dynamic itemBuilder) child defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: ListView.builder(itemCount: 2, itemBuilder: (c, i) => Text('x')),
)
''');
      _expectDeferred(outcome);
    });

    test('a child list with a spread element defers (not a static list)',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    ...buildTiles(),
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a child list with an `if` collection element defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    if (showA) RadioListTile<String>(value: 'a', title: Text('A')),
    RadioListTile<String>(value: 'b', title: Text('B')),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a non-RadioListTile leaf (a bare Radio) defers the whole group',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    Radio<String>(value: 'a'),
    RadioListTile<String>(value: 'b', title: Text('B')),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a RadioListTile with a non-literal-Text title defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Row(children: [Text('A')])),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a RadioListTile with a Text.rich title defers (no flat label)',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text.rich(TextSpan(text: 'A'))),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a RadioListTile missing its value defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(title: Text('A')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'value');
    });

    test('a RadioListTile missing its title (label) defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a'),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a RadioListTile.adaptive (named constructor) leaf defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>.adaptive(value: 'a', title: Text('A')),
  ]),
)
''');
      _expectDeferred(outcome);
    });

    test('a duplicate static option value defers (never a wrong group)',
        () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
    RadioListTile<String>(value: 'a', title: Text('A again')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'duplicate');
    });

    test('an empty option set defers (at least one option required)', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: []),
)
''');
      _expectDeferred(outcome, reasonContains: 'at least one');
    });

    test('a missing child defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(groupValue: sel, onChanged: onSel)
''');
      _expectDeferred(outcome, reasonContains: 'child');
    });

    test('an unrecognised argument defers the whole widget, named', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  mouseCursor: SystemMouseCursors.click,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'mouseCursor');
    });

    test('a positional argument defers', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  positionalThing,
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'positional');
    });
  });

  group('recogniseDropdown — the canonical lower-able form', () {
    test('extracts {value, label} pairs in source order + selected + onChanged',
        () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: (String? v) => onPick(v),
  items: [
    DropdownMenuItem<String>(value: 'usd', child: Text('US Dollar')),
    DropdownMenuItem<String>(value: 'eur', child: Text('Euro')),
    DropdownMenuItem<String>(value: 'gbp', child: Text('Pound')),
  ],
)
''');

      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(3));
      expect(_value(recognised.options[0]), "'usd'");
      expect(_label(recognised.options[0]), "'US Dollar'");
      expect(_value(recognised.options[2]), "'gbp'");
      expect(_label(recognised.options[2]), "'Pound'");
      expect(recognised.selected?.toSource(), 'chosen');
      expect(recognised.onChanged, isNotNull);
    });

    test('a DropdownMenuItem with a behavioral arg (enabled) defers', () async {
      // `enabled: false` on a DropdownMenuItem makes that option un-selectable;
      // the flat single-select cannot express it, so dropping it would render
      // the option selectable. The WHOLE widget defers loud (named).
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    DropdownMenuItem<String>(value: 'a', child: Text('A'), enabled: false),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'enabled');
    });
  });

  group('recogniseDropdown — all-or-defer-loud negatives', () {
    test('a non-list-literal items (a helper call) defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(value: chosen, onChanged: onPick, items: buildItems())
''');
      _expectDeferred(outcome, reasonContains: 'static list literal');
    });

    test('an items list with a spread element defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    ...buildItems(),
    DropdownMenuItem<String>(value: 'a', child: Text('A')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'spreads');
    });

    test('an items list with a `for` collection element defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    for (final c in currencies)
      DropdownMenuItem<String>(value: c, child: Text(c)),
  ],
)
''');
      _expectDeferred(outcome);
    });

    test('a non-DropdownMenuItem entry defers the whole list', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    SomeOtherItem(value: 'a'),
    DropdownMenuItem<String>(value: 'b', child: Text('B')),
  ],
)
''');
      _expectDeferred(outcome);
    });

    test('a DropdownMenuItem with a non-literal-Text child defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    DropdownMenuItem<String>(value: 'a', child: Icon(Icons.star)),
  ],
)
''');
      _expectDeferred(outcome);
    });

    test('a DropdownMenuItem missing its value defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    DropdownMenuItem<String>(child: Text('A')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'value');
    });

    test('a DropdownMenuItem missing its child (label) defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    DropdownMenuItem<String>(value: 'a'),
  ],
)
''');
      _expectDeferred(outcome);
    });

    test('a duplicate static option value defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  items: [
    DropdownMenuItem<String>(value: 'a', child: Text('A')),
    DropdownMenuItem<String>(value: 'a', child: Text('A2')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'duplicate');
    });

    test('a missing items list defers', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(value: chosen, onChanged: onPick)
''');
      _expectDeferred(outcome, reasonContains: 'items');
    });

    test('an empty items list defers (at least one option required)', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(value: chosen, onChanged: onPick, items: [])
''');
      _expectDeferred(outcome, reasonContains: 'at least one');
    });

    test('an unrecognised argument defers the whole widget, named', () async {
      final outcome = await _dropdown('''
DropdownButton<String>(
  value: chosen,
  onChanged: onPick,
  elevation: 4,
  items: [
    DropdownMenuItem<String>(value: 'a', child: Text('A')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'elevation');
    });
  });

  group('type-argument gate — only the String-keyed widget lowers', () {
    test('a resolved RadioGroup<int> defers loud (String-keyed only)',
        () async {
      // The compiled `RestageRadioGroupString` reads each option value as a
      // String; a `<int>` group would have its values silently mis-keyed or
      // dropped. The type-argument gate defers the whole widget loud.
      final outcome = await _radio('''
RadioGroup<int>(
  groupValue: 1,
  onChanged: (int? v) {},
  child: Column(children: [
    RadioListTile<int>(value: 1, title: Text('One')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'int');
    });

    test('a resolved DropdownButton<int> defers loud', () async {
      final outcome = await _dropdown('''
DropdownButton<int>(
  value: 1,
  onChanged: (int? v) {},
  items: [
    DropdownMenuItem<int>(value: 1, child: Text('One')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'int');
    });

    test('a resolved DropdownButton<Object> defers loud', () async {
      // A `<Object>` group can carry mixed String/int values; the String widget
      // would silently drop the non-String ones. Defer loud.
      final outcome = await _dropdown('''
DropdownButton<Object>(
  value: 'a',
  onChanged: (Object? v) {},
  items: [
    DropdownMenuItem<Object>(value: 'a', child: Text('A')),
    DropdownMenuItem<Object>(value: 1, child: Text('One')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'Object');
    });

    test('a resolved RadioGroup<String> still recognises', () async {
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(1));
    });

    test('an INFERRED DropdownButton<int> (no written <T>) defers loud',
        () async {
      // No syntactic `<int>` is written, but the analyzer infers
      // `DropdownButton<int>` from the int `value` / item values. A gate keyed
      // on the syntactic type-argument list would see no `<T>`, name-fall-back,
      // and recognise — lowering an int group into the String-keyed widget,
      // which silently drops/mis-keys the values. Gating on the RESOLVED static
      // type catches the inferred specialization and defers loud.
      final outcome = await _dropdown('''
DropdownButton(
  value: 1,
  onChanged: (int? v) {},
  items: [
    DropdownMenuItem(value: 1, child: Text('One')),
    DropdownMenuItem(value: 2, child: Text('Two')),
  ],
)
''');
      _expectDeferred(outcome, reasonContains: 'int');
    });

    test('an INFERRED RadioGroup<int> (no written <T>) defers loud', () async {
      // The RadioGroup counterpart of the inferred-generic gate: int leaves
      // infer `RadioGroup<int>` with no written `<T>`. The resolved-type gate
      // defers loud rather than mis-key the values into the String widget.
      final outcome = await _radio('''
RadioGroup(
  groupValue: 1,
  onChanged: (int? v) {},
  child: Column(children: [
    RadioListTile(value: 1, title: Text('One')),
  ]),
)
''');
      _expectDeferred(outcome, reasonContains: 'int');
    });

    test('a DropdownButton<PlanId> (String-aliased typedef) recognises',
        () async {
      // `PlanId` is a typedef for `String`; the analyzer resolves the
      // specialization to `DropdownButton<String>`, so the resolved-type gate
      // recognises (the values are real Strings the compiled widget carries
      // faithfully). The gate must see THROUGH the alias, not reject it on the
      // syntactic lexeme `PlanId`.
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/material.dart';

typedef PlanId = String;

Object x() => DropdownButton<PlanId>(
  value: 'monthly',
  onChanged: (PlanId? v) {},
  items: const [
    DropdownMenuItem<PlanId>(value: 'monthly', child: Text('Monthly')),
    DropdownMenuItem<PlanId>(value: 'annual', child: Text('Annual')),
  ],
);
''',
        rootPackage: 'apps_examples',
      );
      final outcome = recogniseDropdown(expr as InstanceCreationExpression);
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(2));
    });
  });

  group('framework-identity leaf gate (resolved input)', () {
    test('a resolved Flutter RadioListTile + Text group recognises', () async {
      final outcome = await _resolvedRadio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: (String? v) {},
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
    RadioListTile<String>(value: 'b', title: Text('B')),
  ]),
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(2));
    });

    test('a customer look-alike RadioListTile leaf defers (element gate)',
        () async {
      // Customer classes named RadioGroup / RadioListTile / Column / Text that
      // resolve to a non-flutter library: the leaf gate withholds recognition
      // (a coincidental name is not the framework carrier), deferring the whole
      // group rather than carrying a look-alike leaf as a real option. The
      // outer-widget framework gate lives in the dispatch arm; here we prove
      // recogniser's own leaf gate defers on a resolved non-flutter carrier.
      final expr = await parseExpressionFromSourceForTest('''
class RadioGroup<T> {
  const RadioGroup({this.groupValue, this.onChanged, this.child});
  final T? groupValue;
  final Object? onChanged;
  final Object? child;
}

class RadioListTile<T> {
  const RadioListTile({this.value, this.title});
  final T? value;
  final Object? title;
}

class Column {
  const Column({this.children});
  final List<Object>? children;
}

class Text {
  const Text(this.data);
  final String data;
}

Object x() => RadioGroup<String>(
  groupValue: 'a',
  onChanged: (String? v) {},
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
);
''');
      final outcome = recogniseRadioGroup(expr as InstanceCreationExpression);
      _expectDeferred(outcome);
    });

    test('a customer Column look-alike wrapper defers (wrapper element gate)',
        () async {
      // The leaves are the REAL Flutter RadioListTile / Text, but the children
      // are wrapped in a CUSTOMER class named `Column` (resolving to a
      // non-flutter library) that could reorder / filter / inject rows. The
      // wrapper element gate withholds recognition — treating a look-alike
      // container as a static Flutter container would silently lower a
      // reordered or dropped option set. The whole group defers loud.
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/material.dart' as m;

// A customer container literally named `Column`, resolving to THIS library
// (not package:flutter). It could reorder / drop its children.
class Column {
  const Column({this.children});
  final List<Object>? children;
}

m.Widget x() => m.RadioGroup<String>(
  groupValue: 'a',
  onChanged: (String? v) {},
  child: Column(children: [
    m.RadioListTile<String>(value: 'a', title: m.Text('A')),
  ]),
);
''',
        rootPackage: 'apps_examples',
      );
      final outcome = recogniseRadioGroup(expr as InstanceCreationExpression);
      _expectDeferred(outcome);
    });

    test('a real Flutter Column wrapper with real leaves recognises', () async {
      // The positive control for the wrapper gate: the same shape with the REAL
      // Flutter `Column` recognises (the wrapper gate must not over-reject the
      // framework container).
      final outcome = await _radio('''
RadioGroup<String>(
  groupValue: sel,
  onChanged: onSel,
  child: Column(children: [
    RadioListTile<String>(value: 'a', title: Text('A')),
  ]),
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.options, hasLength(1));
    });
  });
}

// --- harness ---------------------------------------------------------------

// A real-Flutter-resolved parse is required: an unresolved parse renders a
// `Foo<T>(...)` construction as a `MethodInvocation` (the parser cannot tell a
// constructor call from a function call without resolution), and the leaf
// recogniser keys on `InstanceCreationExpression`. Resolving under
// `package:flutter` also exercises the element-gated leaf-carrier path on the
// real `RadioListTile` / `DropdownMenuItem` / `Text`. The preamble declares the
// inert identifiers the fixtures reference (`sel`, `onSel`, …) so they resolve
// cleanly rather than introducing parse ambiguity.
const String _preamble = '''
import 'package:flutter/material.dart';

const String? sel = 'a';
const String? selectedPlan = 'monthly';
const String? chosen = 'usd';
final List<String> currencies = const ['usd', 'eur'];
final bool showA = true;
void onSel(String? v) {}
void onSelect(String? v) {}
void onPick(String? v) {}
void onTap() {}
void doTap() {}
List<RadioListTile<String>> buildTiles() => const [];
List<DropdownMenuItem<String>> buildItems() => const [];
''';

/// Resolves a `RadioGroup(...)` construction under real `package:flutter` and
/// runs the recogniser against the resolved creation expression.
Future<SingleSelectOutcome> _radio(String construction) async {
  return recogniseRadioGroup(await _creationOf(construction));
}

/// Resolves a `DropdownButton(...)` construction under real `package:flutter`
/// and runs the recogniser against the resolved creation expression.
Future<SingleSelectOutcome> _dropdown(String construction) async {
  return recogniseDropdown(await _creationOf(construction));
}

Future<InstanceCreationExpression> _creationOf(String construction) async {
  final expr = await parseExpressionFromSourceForTest(
    '$_preamble\nObject x() => $construction;',
    rootPackage: 'apps_examples',
  );
  if (expr is! InstanceCreationExpression) {
    throw StateError(
      'expected an InstanceCreationExpression but got ${expr.runtimeType} '
      'for: $construction',
    );
  }
  return expr;
}

/// Resolves a `RadioGroup(...)` construction under a real `package:flutter`
/// import so the leaf element gate (`libraryIsFlutter`) is exercised on real
/// framework carriers.
Future<SingleSelectOutcome> _resolvedRadio(String construction) async {
  return _radio(construction);
}

RecognisedSingleSelect _expectRecognised(SingleSelectOutcome outcome) {
  expect(
    outcome,
    isA<SingleSelectRecognised>(),
    reason: outcome is SingleSelectDeferred
        ? 'unexpected defer: ${outcome.reason}'
        : null,
  );
  return (outcome as SingleSelectRecognised).recognised;
}

void _expectDeferred(SingleSelectOutcome outcome, {String? reasonContains}) {
  expect(outcome, isA<SingleSelectDeferred>());
  final deferred = outcome as SingleSelectDeferred;
  expect(deferred.reason, isNotEmpty);
  if (reasonContains != null) {
    expect(deferred.reason, contains(reasonContains));
  }
}

String _value(RecognisedSelectionOption option) => option.value.toSource();
String _label(RecognisedSelectionOption option) => option.label.toSource();
