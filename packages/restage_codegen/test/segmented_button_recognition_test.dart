@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/segmented_button_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pure AST recognition proofs for the vanilla-Flutter `SegmentedButton`
/// (`<String>`) idiom that lowers to the compiled `RestageSegmentedButton`
/// catalog widget.
/// The governing invariant: a clean, fully-extractable segmented button yields
/// a `SegmentedButtonRecognised` carrying the segments + selected values + the
/// callback in SOURCE order; **any** unparseable shape — a non-`String` (or
/// inferred non-`String`) generic, a dynamic / builder / spread segments, an
/// icon-only / non-literal-`Text` label, a missing value, a behavioral carrier
/// arg, or a duplicate value — defers the WHOLE widget loud with a
/// `SegmentedButtonDeferred`. The negatives are the point: a silently-dropped,
/// reordered, or mis-keyed segment in a remote selector is the one failure this
/// widget must not ship.
void main() {
  group('recogniseSegmentedButton — the canonical lower-able form', () {
    test('extracts segments + selected + onSelectionChanged in source order',
        () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'day', label: Text('Day')),
    ButtonSegment<String>(value: 'week', label: Text('Week')),
    ButtonSegment<String>(value: 'month', label: Text('Month')),
  ],
  selected: {'week'},
  onSelectionChanged: (Set<String> s) => onSelect(s),
)
''');

      final recognised = _expectRecognised(outcome);
      expect(recognised.segments, hasLength(3));
      expect(recognised.segments[0].value.toSource(), "'day'");
      expect(recognised.segments[0].label.toSource(), "'Day'");
      expect(recognised.segments[2].value.toSource(), "'month'");
      expect(recognised.selectedValues.map((e) => e.toSource()), ["'week'"]);
      expect(recognised.onSelectionChanged, isNotNull);
    });

    test('a list-literal selected (not a set) recognises', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'b', label: Text('B')),
  ],
  selected: <String>['a', 'b'],
)
''');
      final recognised = _expectRecognised(outcome);
      expect(
        recognised.selectedValues.map((e) => e.toSource()),
        ["'a'", "'b'"],
      );
    });

    test('a missing selected/onSelectionChanged recognises (display-only)',
        () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.selectedValues, isEmpty);
      expect(recognised.onSelectionChanged, isNull);
    });

    test('the declarative bools are carried when authored', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'b', label: Text('B')),
  ],
  selected: {'a', 'b'},
  multiSelectionEnabled: true,
  emptySelectionAllowed: true,
)
''');
      final recognised = _expectRecognised(outcome);
      expect(recognised.multiSelectionEnabled?.toSource(), 'true');
      expect(recognised.emptySelectionAllowed?.toSource(), 'true');
    });
  });

  group('recogniseSegmentedButton — the <T> gate', () {
    test('a resolved non-String generic defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<int>(
  segments: [
    ButtonSegment<int>(value: 1, label: Text('One')),
  ],
  selected: {1},
)
''');
      _expectDeferred(outcome, reasonContains: 'String-keyed');
    });

    test('an INFERRED non-String generic defers loud', () async {
      // No written `<int>`, but the analyzer infers `SegmentedButton<int>` from
      // the int segment value + selected — must defer just as an explicit
      // `<int>` does.
      final outcome = await _segmented('''
SegmentedButton(
  segments: [
    ButtonSegment(value: 1, label: Text('One')),
  ],
  selected: {1},
)
''');
      _expectDeferred(outcome, reasonContains: 'String-keyed');
    });

    test('an explicit <String> recognises', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: {'a'},
)
''');
      _expectRecognised(outcome);
    });
  });

  group('recogniseSegmentedButton — carry-all-or-defer-loud', () {
    test('a non-ButtonSegment leaf defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    Text('not a segment'),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'ButtonSegment');
    });

    test('an icon-only segment defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', icon: Icon(Icons.ac_unit)),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'icon');
    });

    test('an icon+label segment defers loud (icon would be dropped)', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(
      value: 'a', label: Text('A'), icon: Icon(Icons.ac_unit)),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'icon');
    });

    test('a non-literal-Text label defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: someWidget),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'literal Text');
    });

    test(
        'a styled Text label (extra args) defers loud — never a plain '
        'string that silently drops the style', () async {
      // The flat surface carries only the label STRING; a
      // `Text('Pro', style: ...)` would silently drop the style. Reject
      // (defer loud) rather than lower to a degraded plain label.
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(
      value: 'a',
      label: Text('Pro', style: TextStyle(color: Colors.red)),
    ),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'literal Text');
    });

    test('a missing value defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(label: Text('A')),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'value');
    });

    test('a behavioral carrier arg (enabled) defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A'), enabled: false),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'enabled');
    });

    test('a tooltip carrier arg defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A'), tooltip: 'tip'),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'tooltip');
    });

    test('a dynamic / builder segments list defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: buildSegments(),
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'static list literal');
    });

    test('a spread element in segments defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ...moreSegments,
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'static list literal');
    });

    test('an if-element in segments defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    if (showA) ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'b', label: Text('B')),
  ],
  selected: {'b'},
)
''');
      _expectDeferred(outcome, reasonContains: 'static list literal');
    });

    test('an empty segments list defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: <ButtonSegment<String>>[],
  selected: {},
)
''');
      _expectDeferred(outcome, reasonContains: 'non-empty');
    });

    test('a duplicate (literal) segment value defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
    ButtonSegment<String>(value: 'a', label: Text('Again')),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'duplicate');
    });

    test('a dynamic / non-literal selected collection defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: computeSelected(),
)
''');
      _expectDeferred(outcome, reasonContains: 'static set or list literal');
    });

    test('an unrecognized argument defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: {'a'},
  showSelectedIcon: false,
)
''');
      _expectDeferred(outcome, reasonContains: 'showSelectedIcon');
    });

    test('a positional argument defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  [ButtonSegment<String>(value: 'a', label: Text('A'))],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'positional');
    });

    test('a missing segments defers loud', () async {
      final outcome = await _segmented('''
SegmentedButton<String>(
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'segments');
    });

    test('a named constructor defers loud', () async {
      // SegmentedButton has only the unnamed constructor today; a future named
      // one must defer rather than silently mis-lower.
      final outcome = await _segmented('''
SegmentedButton<String>.adaptive(
  segments: [
    ButtonSegment<String>(value: 'a', label: Text('A')),
  ],
  selected: {'a'},
)
''');
      _expectDeferred(outcome, reasonContains: 'named constructor');
    });
  });
}

Future<SegmentedButtonOutcome> _segmented(String construction) async {
  return recogniseSegmentedButton(await _creationOf(construction));
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

RecognisedSegmentedButton _expectRecognised(SegmentedButtonOutcome outcome) {
  expect(
    outcome,
    isA<SegmentedButtonRecognised>(),
    reason: outcome is SegmentedButtonDeferred
        ? 'unexpected defer: ${outcome.reason}'
        : null,
  );
  return (outcome as SegmentedButtonRecognised).recognised;
}

void _expectDeferred(
  SegmentedButtonOutcome outcome, {
  String? reasonContains,
}) {
  expect(outcome, isA<SegmentedButtonDeferred>());
  final deferred = outcome as SegmentedButtonDeferred;
  expect(deferred.reason, isNotEmpty);
  if (reasonContains != null) {
    expect(deferred.reason, contains(reasonContains));
  }
}

const String _preamble = '''
import 'package:flutter/material.dart';

final bool showA = true;
final Widget someWidget = const SizedBox();
List<ButtonSegment<String>> buildSegments() => const [];
List<ButtonSegment<String>> moreSegments = const [];
Set<String> computeSelected() => const {};
void onSelect(Set<String> s) {}
''';
