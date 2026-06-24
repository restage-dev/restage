import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/draggable_sheet_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('recogniseDraggableSheetBuilder — the canonical lower-able form', () {
    test(
        'expression body: SingleChildScrollView(controller: sc, child: X) '
        'recognises X as the child content', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(controller: sc, '
        'child: Column(children: []))',
      );
      expect(outcome, isA<DraggableSheetRecognised>());
      expect(
        (outcome as DraggableSheetRecognised).content.toSource(),
        'Column(children: [])',
      );
    });

    test('block body with a single return recognises the same content',
        () async {
      final outcome = await _recognise(
        '(context, sc) { return SingleChildScrollView(controller: sc, '
        'child: Text("hi")); }',
      );
      expect(outcome, isA<DraggableSheetRecognised>());
      expect(
        (outcome as DraggableSheetRecognised).content.toSource(),
        'Text("hi")',
      );
    });

    test('a key argument on the scroll view is allowed (dropped)', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(key: k, controller: sc, '
        'child: Text("x"))',
      );
      expect(outcome, isA<DraggableSheetRecognised>());
      expect(
        (outcome as DraggableSheetRecognised).content.toSource(),
        'Text("x")',
      );
    });
  });

  group('recogniseDraggableSheetBuilder — strict-arg-subset (correction #2)',
      () {
    for (final arg in const [
      'padding: EdgeInsets.zero',
      'physics: const NeverScrollableScrollPhysics()',
      'reverse: true',
      'scrollDirection: Axis.horizontal',
      'primary: false',
      'clipBehavior: Clip.none',
      'dragStartBehavior: DragStartBehavior.down',
    ]) {
      test('a SingleChildScrollView carrying `$arg` fatal-defers', () async {
        final outcome = await _recognise(
          '(context, sc) => SingleChildScrollView(controller: sc, $arg, '
          'child: Text("x"))',
        );
        expect(outcome, isA<DraggableSheetDeferred>());
        expect(
          (outcome as DraggableSheetDeferred).reason,
          kDraggableSheetScrollViewArgUnsupportedReason,
        );
      });
    }
  });

  group('recogniseDraggableSheetBuilder — non-canonical scroll bodies', () {
    test(
        'ListView(controller: sc, children: [...]) fatal-defers '
        '(correction #1 — NOT lowered to a bare Column)', () async {
      final outcome = await _recognise(
        '(context, sc) => ListView(controller: sc, children: [Text("a")])',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test('a body that ignores the controller (0 references) fatal-defers',
        () async {
      final outcome = await _recognise(
        '(context, sc) => Column(children: [Text("a")])',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test('CustomScrollView(controller: sc, slivers: [...]) fatal-defers',
        () async {
      final outcome = await _recognise(
        '(context, sc) => CustomScrollView(controller: sc, slivers: [])',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test(
        'a SingleChildScrollView whose controller is not the sc formal '
        'fatal-defers', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(controller: other, '
        'child: Text("x"))',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test('the sc formal referenced more than once fatal-defers', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(controller: sc, '
        'child: Builder(builder: (c) => Text(sc.toString())))',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test(
        'the sc formal captured into the child only (scroll view has no '
        'controller) fatal-defers', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(child: '
        'ListView(controller: sc, children: []))',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });

    test('a SingleChildScrollView with no child fatal-defers', () async {
      final outcome = await _recognise(
        '(context, sc) => SingleChildScrollView(controller: sc)',
      );
      expect(outcome, isA<DraggableSheetDeferred>());
      expect(
        (outcome as DraggableSheetDeferred).reason,
        kDraggableSheetScrollableChildUnsupportedReason,
      );
    });
  });

  group('recogniseDraggableSheetBuilder — malformed builders (NotRecognised)',
      () {
    test('a non-closure builder is not recognised', () async {
      final outcome = await _recognise('someBuilder');
      expect(outcome, isA<DraggableSheetNotRecognised>());
    });

    test('an async builder is not recognised', () async {
      final outcome = await _recognise(
        '(context, sc) async => SingleChildScrollView(controller: sc, '
        'child: Text("x"))',
      );
      expect(outcome, isA<DraggableSheetNotRecognised>());
    });

    test('a single-parameter builder (wrong arity) is not recognised',
        () async {
      final outcome = await _recognise(
        '(context) => SingleChildScrollView(child: Text("x"))',
      );
      expect(outcome, isA<DraggableSheetNotRecognised>());
    });

    test('a multi-statement block body is not recognised', () async {
      final outcome = await _recognise(
        '(context, sc) { final x = 1; '
        'return SingleChildScrollView(controller: sc, child: Text("x")); }',
      );
      expect(outcome, isA<DraggableSheetNotRecognised>());
    });

    test('a conditional return is not recognised', () async {
      final outcome = await _recognise(
        '(context, sc) => cond '
        '? SingleChildScrollView(controller: sc, child: Text("a")) '
        ': Text("b")',
      );
      expect(outcome, isA<DraggableSheetNotRecognised>());
    });
  });

  group('disposition table', () {
    test('covers the current Flutter DraggableScrollableSheet signature',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      // Resolves the live Flutter signature through the heavier
      // Flutter-resolution build harness, which is slow on a cold cache.
      final signature = await _resolvedDraggableSheetParamNames();
      expect(
        kDraggableSheetArgumentDispositions.keys,
        unorderedEquals(signature),
        reason: 'the disposition table must account for every current Flutter '
            'DraggableScrollableSheet constructor parameter',
      );
    });

    test('classifies each parameter as the design specifies', () {
      Set<String> withDisposition(DraggableSheetArgumentDisposition d) => {
            for (final e in kDraggableSheetArgumentDispositions.entries)
              if (e.value == d) e.key,
          };
      expect(
        withDisposition(DraggableSheetArgumentDisposition.map),
        {
          'initialChildSize',
          'minChildSize',
          'maxChildSize',
          'expand',
          'snap',
          'snapAnimationDuration',
        },
      );
      expect(
        withDisposition(DraggableSheetArgumentDisposition.builder),
        {'builder'},
      );
      expect(withDisposition(DraggableSheetArgumentDisposition.drop), {'key'});
      expect(
        withDisposition(DraggableSheetArgumentDisposition.snapSizes),
        {'snapSizes'},
      );
      expect(
        withDisposition(
          DraggableSheetArgumentDisposition.shouldCloseOnMinExtent,
        ),
        {'shouldCloseOnMinExtent'},
      );
      expect(
        withDisposition(DraggableSheetArgumentDisposition.controller),
        {'controller'},
      );
    });
  });

  group('reason strings are actionable and internal-doc-free', () {
    final reasons = <String>[
      kDraggableSheetSnapSizesUnsupportedReason,
      kDraggableSheetControllerUnsupportedReason,
      kDraggableSheetShouldCloseOnMinExtentReason,
      kDraggableSheetBuilderUnsupportedReason,
      kDraggableSheetScrollableChildUnsupportedReason,
      kDraggableSheetScrollViewArgUnsupportedReason,
    ];

    test('every reason is non-empty', () {
      for (final reason in reasons) {
        expect(reason, isNotEmpty);
      }
    });

    test('the scrollable-child + scroll-view-arg reasons name the escape', () {
      // A dev who wrapped the scroll view should be told the canonical form.
      expect(
        kDraggableSheetScrollableChildUnsupportedReason,
        contains('SingleChildScrollView'),
      );
      expect(
        kDraggableSheetScrollViewArgUnsupportedReason,
        contains('SingleChildScrollView'),
      );
    });
  });
}

Future<DraggableSheetBuilderOutcome> _recognise(String builderSource) async {
  final builder = await parseExpressionForTest(builderSource);
  return recogniseDraggableSheetBuilder(builder);
}

Future<List<String>> _resolvedDraggableSheetParamNames() async {
  final expr = await parseExpressionFromSourceForTest(
    '''
import 'package:flutter/widgets.dart';

Object x() => DraggableScrollableSheet(
  builder: (context, scrollController) => const SizedBox(),
);
''',
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
