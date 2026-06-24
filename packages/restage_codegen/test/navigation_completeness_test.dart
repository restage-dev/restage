@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Navigation route parameter completeness', () {
    test('MaterialPageRoute covers the current Flutter signature', () async {
      final signature = await _resolvedRouteSignatureParamNames(
        NavigationRouteType.materialPageRoute,
      );

      _expectDispositionCompleteness(
        routeType: NavigationRouteType.materialPageRoute,
        signature: signature,
        builders: const {'builder'},
        deferred: const {
          'settings',
          'requestFocus',
          'maintainState',
          'fullscreenDialog',
          'allowSnapshotting',
          'barrierDismissible',
          'traversalEdgeBehavior',
          'directionalTraversalEdgeBehavior',
        },
      );
    });

    test('CupertinoPageRoute covers the current Flutter signature', () async {
      final signature = await _resolvedRouteSignatureParamNames(
        NavigationRouteType.cupertinoPageRoute,
      );

      _expectDispositionCompleteness(
        routeType: NavigationRouteType.cupertinoPageRoute,
        signature: signature,
        builders: const {'builder'},
        deferred: const {
          'title',
          'settings',
          'requestFocus',
          'maintainState',
          'fullscreenDialog',
          'allowSnapshotting',
          'barrierDismissible',
        },
      );
    });
  });
}

Future<List<String>> _resolvedRouteSignatureParamNames(
  NavigationRouteType routeType,
) async {
  final expr = await parseExpressionFromSourceForTest(
    switch (routeType) {
      NavigationRouteType.materialPageRoute => '''
import 'package:flutter/material.dart';

Object x() => MaterialPageRoute<void>(
  builder: (_) => const SizedBox(),
);
''',
      NavigationRouteType.cupertinoPageRoute => '''
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';

Object x() => CupertinoPageRoute<void>(
  builder: (_) => const SizedBox(),
);
''',
    },
    rootPackage: 'apps_examples',
  );
  final creation = expr as InstanceCreationExpression;
  final element = creation.constructorName.element;
  expect(element, isA<ConstructorElement>());
  return [
    for (final parameter in element!.formalParameters)
      if (parameter.isNamed) parameter.name!,
  ];
}

void _expectDispositionCompleteness({
  required NavigationRouteType routeType,
  required List<String> signature,
  required Set<String> builders,
  required Set<String> deferred,
}) {
  final dispositions = kRouteArgumentDispositions[routeType];
  expect(dispositions, isNotNull);
  final table = dispositions!;

  expect(
    table.keys,
    unorderedEquals(signature),
    reason: '${routeType.name} must account for every current Flutter '
        'constructor parameter in the production disposition table.',
  );

  _expectDisposition(
    table,
    RouteArgumentDisposition.builder,
    builders,
  );
  _expectDisposition(
    table,
    RouteArgumentDisposition.defer,
    deferred,
  );

  expect(
    {...builders, ...deferred},
    unorderedEquals(signature),
  );
}

void _expectDisposition(
  Map<String, RouteArgumentDisposition> table,
  RouteArgumentDisposition disposition,
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
