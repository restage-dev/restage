@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/toggle_buttons_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pure AST recognition proofs for the vanilla-Flutter `ToggleButtons(...)`
/// idiom that lowers to the compiled `RestageToggleButtons` catalog widget.
/// The governing invariant: a clean, fully-extractable toggle set yields a
/// `ToggleButtonsRecognised` carrying the children + the parallel isSelected
/// flags in source order; **any** unparseable shape — and crucially any
/// LITERAL length mismatch between `children` and `isSelected` — defers the
/// WHOLE widget loud with a `ToggleButtonsDeferred`, never a partial or
/// silently-misaligned set. The negatives are the point: a silently-dropped,
/// reordered, or misaligned toggle in a remote multi-toggle is the one failure
/// this widget must not ship.
void main() {
  group('recogniseToggleButtons — the canonical lower-able form', () {
    test('extracts children + isSelected in source order + onPressed',
        () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false, true],
  onPressed: (int i) => onPress(i),
  children: [Text('Bold'), Text('Italic'), Text('Underline')],
)
''');

      final recognised = _expectRecognised(outcome);
      // children / isSelected are the whole list-literal expressions, carrying
      // their elements in source order for the slot translators.
      expect(
        recognised.children.toSource(),
        "[Text('Bold'), Text('Italic'), Text('Underline')]",
      );
      expect(recognised.isSelected.toSource(), '[true, false, true]');
      expect(recognised.onPressed, isNotNull);
    });

    test('a missing onPressed (display-only) recognises with null onPressed',
        () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false],
  children: [Text('A'), Text('B')],
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.children.toSource(), "[Text('A'), Text('B')]");
      expect(recognised.onPressed, isNull);
    });
  });

  group('recogniseToggleButtons — layer-(a) defer-loud', () {
    test('a LITERAL length mismatch defers loud (the load-bearing guard)',
        () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false],
  children: [Text('A'), Text('B'), Text('C')],
)
''');
      _expectDeferred(outcome, reasonContains: 'length');
    });

    test('a non-bool isSelected entry defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, maybe],
  children: [Text('A'), Text('B')],
)
''');
      _expectDeferred(outcome);
    });

    test('a dynamic (non-literal) isSelected defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: flags,
  children: [Text('A'), Text('B')],
)
''');
      _expectDeferred(outcome, reasonContains: 'isSelected');
    });

    test('a spread element in isSelected defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, ...more],
  children: [Text('A'), Text('B')],
)
''');
      _expectDeferred(outcome);
    });

    test('a dynamic (non-list) children defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false],
  children: buildChildren(),
)
''');
      _expectDeferred(outcome, reasonContains: 'children');
    });

    test('a spread element in children defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false],
  children: [Text('A'), ...rest],
)
''');
      _expectDeferred(outcome);
    });

    test('empty children defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [],
  children: [],
)
''');
      _expectDeferred(outcome);
    });

    test('a missing isSelected defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  children: [Text('A')],
)
''');
      _expectDeferred(outcome, reasonContains: 'isSelected');
    });

    test('a missing children defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true],
)
''');
      _expectDeferred(outcome, reasonContains: 'children');
    });

    test('an unrecognized argument defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  isSelected: [true, false],
  children: [Text('A'), Text('B')],
  borderColor: someColor,
)
''');
      _expectDeferred(outcome, reasonContains: 'borderColor');
    });

    test('a positional argument defers loud', () async {
      final outcome = await _toggle('''
ToggleButtons(
  [Text('A')],
  isSelected: [true],
)
''');
      _expectDeferred(outcome, reasonContains: 'positional');
    });
  });
}

Future<ToggleButtonsOutcome> _toggle(String construction) async {
  return recogniseToggleButtons(await _creationOf(construction));
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

RecognisedToggleButtons _expectRecognised(ToggleButtonsOutcome outcome) {
  expect(
    outcome,
    isA<ToggleButtonsRecognised>(),
    reason: outcome is ToggleButtonsDeferred
        ? 'unexpected defer: ${outcome.reason}'
        : null,
  );
  return (outcome as ToggleButtonsRecognised).recognised;
}

void _expectDeferred(ToggleButtonsOutcome outcome, {String? reasonContains}) {
  expect(outcome, isA<ToggleButtonsDeferred>());
  final deferred = outcome as ToggleButtonsDeferred;
  expect(deferred.reason, isNotEmpty);
  if (reasonContains != null) {
    expect(deferred.reason, contains(reasonContains));
  }
}

const String _preamble = '''
import 'package:flutter/material.dart';

final List<bool> flags = const [true, false];
final List<bool> more = const [false];
final List<Widget> rest = const [];
final bool maybe = true;
final Color someColor = const Color(0xFF000000);
void onPress(int i) {}
List<Widget> buildChildren() => const [];
''';
