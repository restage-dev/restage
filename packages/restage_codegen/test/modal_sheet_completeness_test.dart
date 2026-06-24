import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Modal sheet parameter completeness', () {
    test('showModalBottomSheet covers the current Flutter signature', () async {
      final signature = await _resolvedFlutterSignatureParamNames(
        ModalSheetFunction.showModalBottomSheet,
      );

      _expectDispositionCompleteness(
        function: ModalSheetFunction.showModalBottomSheet,
        signature: signature,
        mapped: const {
          'backgroundColor',
          'barrierLabel',
          'elevation',
          'shape',
          'clipBehavior',
          'barrierColor',
          'isScrollControlled',
          'scrollControlDisabledMaxHeightRatio',
          'isDismissible',
          'enableDrag',
          'showDragHandle',
          'useSafeArea',
          'anchorPoint',
        },
        builders: const {'builder'},
        animationStyles: const {'sheetAnimationStyle'},
        dropped: const {'context'},
        deferred: const {
          'constraints',
          'useRootNavigator',
          'routeSettings',
          'transitionAnimationController',
          'requestFocus',
        },
      );
    });

    test('showCupertinoSheet covers the current Flutter signature', () async {
      final signature = await _resolvedFlutterSignatureParamNames(
        ModalSheetFunction.showCupertinoSheet,
      );

      _expectDispositionCompleteness(
        function: ModalSheetFunction.showCupertinoSheet,
        signature: signature,
        mapped: const {
          'enableDrag',
          'showDragHandle',
        },
        builders: const {'builder'},
        pageBuilders: const {'pageBuilder'},
        dropped: const {'context'},
        deferred: const {
          'useNestedNavigation',
          'topGap',
        },
      );
    });

    test('every sheet function maps to a fixed presentation', () {
      for (final function in ModalSheetFunction.values) {
        expect(
          kModalSheetPresentation[function],
          isNotNull,
          reason: '$function must map to a fixed sheet presentation',
        );
      }
      expect(
        kModalSheetPresentation[ModalSheetFunction.showModalBottomSheet],
        'material',
      );
      expect(
        kModalSheetPresentation[ModalSheetFunction.showCupertinoSheet],
        'cupertino',
      );
    });
  });
}

Future<List<String>> _resolvedFlutterSignatureParamNames(
  ModalSheetFunction function,
) async {
  final expr = await parseExpressionFromSourceForTest(
    switch (function) {
      ModalSheetFunction.showModalBottomSheet => '''
import 'package:flutter/material.dart';

Object x(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const SizedBox(),
);
''',
      ModalSheetFunction.showCupertinoSheet => '''
import 'package:flutter/widgets.dart';
import 'package:flutter/cupertino.dart' as cupertino;

Object x(BuildContext context) => cupertino.showCupertinoSheet<void>(
  context: context,
  builder: (_) => const SizedBox(),
);
''',
    },
    rootPackage: 'apps_examples',
  );
  final invocation =
      expr is MethodInvocation ? expr : _MethodInvocationFinder.find(expr);
  expect(invocation, isNotNull);

  final element = invocation!.methodName.element;
  expect(element, isA<TopLevelFunctionElement>());
  final functionElement = element! as TopLevelFunctionElement;
  return [
    for (final parameter in functionElement.formalParameters)
      if (parameter.isNamed) parameter.name!,
  ];
}

void _expectDispositionCompleteness({
  required ModalSheetFunction function,
  required List<String> signature,
  required Set<String> mapped,
  required Set<String> dropped,
  required Set<String> deferred,
  Set<String> builders = const {},
  Set<String> pageBuilders = const {},
  Set<String> animationStyles = const {},
}) {
  final dispositions = kModalSheetArgumentDispositions[function];
  expect(dispositions, isNotNull);
  final table = dispositions!;

  expect(
    table.keys,
    unorderedEquals(signature),
    reason: '${function.name} must account for every current Flutter '
        'signature parameter in the production disposition table.',
  );

  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.map,
    mapped,
  );
  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.builder,
    builders,
  );
  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.pageBuilder,
    pageBuilders,
  );
  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.animationStyle,
    animationStyles,
  );
  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.drop,
    dropped,
  );
  _expectDisposition(
    table,
    ModalSheetArgumentDisposition.defer,
    deferred,
  );
  expect(dropped, {'context'});

  final classified = {
    ...mapped,
    ...builders,
    ...pageBuilders,
    ...animationStyles,
    ...dropped,
    ...deferred,
  };
  expect(classified, unorderedEquals(signature));
}

void _expectDisposition(
  Map<String, ModalSheetArgumentDisposition> table,
  ModalSheetArgumentDisposition disposition,
  Set<String> expected,
) {
  expect(
    {
      for (final entry in table.entries)
        if (entry.value == disposition) entry.key,
    },
    expected,
  );
}

class _MethodInvocationFinder extends RecursiveAstVisitor<void> {
  MethodInvocation? result;

  static MethodInvocation? find(AstNode node) {
    final finder = _MethodInvocationFinder();
    node.accept(finder);
    return finder.result;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    result ??= node;
    super.visitMethodInvocation(node);
  }
}
