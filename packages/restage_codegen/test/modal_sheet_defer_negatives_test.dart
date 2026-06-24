import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'modal_sheet_test_helpers.dart';

void main() {
  group('Modal sheet fatal-defer negatives', () {
    for (final scenario in <({String name, String builder})>[
      (
        name: 'conditional builder',
        builder:
            "builder: (_) => condition ? const Text('A') : const Text('B')",
      ),
      (
        name: 'builder reads its context argument',
        builder: 'builder: (context) => Text(context.toString())',
      ),
      (
        name: 'builder returns different subtrees',
        builder: '''
builder: (_) {
  if (condition) return const Text('A');
  return const Text('B');
}
''',
      ),
      (
        name: 'bound builder identifier',
        builder: 'builder: sheetBuilder',
      ),
    ]) {
      test('${scenario.name} fatal-defers with modalSheetFormUnsupported',
          () async {
        final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    ${scenario.builder},
  ),
  child: const Text('Open'),
)
''');

        expectModalSheetUnsupported(result);
      });
    }

    test('Navigator.pop(context, result) fatal-defers with the named code',
        () async {
      final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ElevatedButton(
      onPressed: () => Navigator.pop(context, true),
      child: const Text('Close'),
    ),
  ),
  child: const Text('Open'),
)
''');

      expectModalSheetUnsupported(result, messageContains: 'Navigator.pop');
    });

    test('Navigator.pop(context) lowers to closing the synthetic flag',
        () async {
      final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ElevatedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    ),
  ),
  child: const Text('Open'),
)
''');

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains('onPressed: set state._restageSheet0Open = false'),
      );
    });

    test('a customer Navigator.pop look-alike is not lowered as close',
        () async {
      // `Navigator` here is a shadowing parameter, not the framework class, so
      // its `pop` must NOT be recognised as the in-sheet close form. The
      // unlowerable inline control then defers loud — never a silent close.
      final expr = await parseExpressionFromSourceForTest(
        '''
import 'dart:async';
import 'package:flutter/material.dart';

Object x(BuildContext context, {required dynamic Navigator}) => ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ElevatedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    ),
  ),
  child: const Text('Open'),
);
''',
        rootPackage: 'apps_examples',
      );
      final result = translateModalSheetRoot(expr);

      expect(result.issues, isNotEmpty);
      expect(
        result.dsl,
        isNot(contains('set state._restageSheet0Open = false')),
      );
    });

    for (final scenario in <({String name, String callback})>[
      (
        name: 'async await',
        callback: '''
() async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet'),
  );
}
''',
      ),
      (
        name: 'then chain',
        callback: '''
() => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const Text('Sheet'),
).then((_) {})
''',
      ),
      (
        name: 'unawaited wrapper',
        callback: '''
() {
  unawaited(showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet'),
  ));
}
''',
      ),
      (
        name: 'assignment',
        callback: '''
() {
  final result = showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet'),
  );
}
''',
      ),
    ]) {
      test('Future-result use at trigger (${scenario.name}) fatal-defers',
          () async {
        final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: ${scenario.callback},
  child: const Text('Open'),
)
''');

        expectModalSheetUnsupported(
          result,
          messageContains: 'result value cannot be observed',
        );
      });
    }

    for (final scenario in <({String name, String argument})>[
      (
        name: 'transitionAnimationController',
        argument: 'transitionAnimationController: controller,',
      ),
      (
        name: 'constraints',
        argument: 'constraints: constraints,',
      ),
      (
        name: 'useRootNavigator',
        argument: 'useRootNavigator: true,',
      ),
      (
        name: 'routeSettings',
        argument: 'routeSettings: routeSettings,',
      ),
      (
        name: 'requestFocus',
        argument: 'requestFocus: false,',
      ),
    ]) {
      test('material no-faithful-slot arg ${scenario.name} fatal-defers',
          () async {
        final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    ${scenario.argument}
    builder: (_) => const Text('Sheet'),
  ),
  child: const Text('Open'),
)
''');

        expectModalSheetUnsupported(result, messageContains: scenario.name);
      });
    }

    for (final scenario in <({String name, String argument})>[
      (
        name: 'useNestedNavigation',
        argument: 'useNestedNavigation: true,',
      ),
      (
        name: 'topGap',
        argument: 'topGap: 0.5,',
      ),
    ]) {
      test('cupertino no-faithful-slot arg ${scenario.name} fatal-defers',
          () async {
        final result = await translateModalSheetSource('''
ElevatedButton(
  onPressed: () => cupertino.showCupertinoSheet<void>(
    context: context,
    ${scenario.argument}
    builder: (_) => const Text('Sheet'),
  ),
  child: const Text('Open'),
)
''');

        expectModalSheetUnsupported(result, messageContains: scenario.name);
      });
    }

    test('non-recognisable trigger slot fatal-defers with the named code',
        () async {
      final result = await translateModalSheetSource('''
GestureDetector(
  onLongPress: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet'),
  ),
  child: const Text('Open'),
)
''');

      expectModalSheetUnsupported(result);
    });

    test('two recognised sheet triggers in one root fatal-defer as ambiguous',
        () async {
      final result = await translateModalSheetSource('''
Column(
  children: [
    ElevatedButton(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const Text('First'),
      ),
      child: const Text('Open first'),
    ),
    ElevatedButton(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const Text('Second'),
      ),
      child: const Text('Open second'),
    ),
  ],
)
''');

      expectModalSheetUnsupported(result, messageContains: 'only one');
    });
  });
}

void expectModalSheetUnsupported(
  TranslationResult result, {
  String? messageContains,
}) {
  expect(result.dsl, isEmpty);
  expect(
    result.issues.map((issue) => issue.code),
    contains(IssueCode.modalSheetFormUnsupported),
  );
  if (messageContains != null) {
    expect(
      result.issues.map((issue) => issue.message).join('\n'),
      contains(messageContains),
    );
  }
}
