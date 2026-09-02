import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _kTestLibraryOrigin = 'package:restage_codegen';

final HelperDefinition _eventHelper = HelperDefinition(
  name: 'paywallEvent',
  libraryOrigin: _kTestLibraryOrigin,
  returnCategory: HelperReturnCategory.voidCallback,
  translate: (args) => 'event ${args.positional.single} {}',
);

void main() {
  test('for-each over a list literal expands in order', () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [for (final item in const [1, 2, 3]) item];
    ''');
    final result = expandCollectionElement(
      _singleCollectionElement(expression),
    );

    expect(result, isA<CollectionUnrollExpansion>());
    final expansion = result as CollectionUnrollExpansion;
    expect(
      expansion.occurrences
          .map((occurrence) => occurrence.authoredExpression.toSource())
          .toList(),
      ['item', 'item', 'item'],
    );
    expect(
      expansion.occurrences
          .map((occurrence) => occurrence.bindings.values.single.toSource())
          .toList(),
      ['1', '2', '3'],
    );

    final translated = _scalarTranslator().translate(expression);
    expect(translated.dsl, '[1, 2, 3]');
    expect(translated.issues, isEmpty);
  });

  test('nested static loops expand in outer and inner order', () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [
        for (final a in const [1, 2])
          for (final b in const [10, 20]) [a, b],
      ];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.dsl, '[[1, 10], [1, 20], [2, 10], [2, 20]]');
    expect(result.issues, isEmpty);
  });

  test('only a resolved run-time for carries its template occurrence',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x(List<String> values, bool enabled) => [
        for (final value in values) value,
        ...values,
        if (enabled) 'enabled',
      ];
    ''');
    final traversal = traverseCollectionList(expression as ListLiteral);

    expect(traversal.entries, hasLength(3));
    final forRefusal = (traversal.entries[0] as CollectionListRefusal).refusal;
    final spreadRefusal =
        (traversal.entries[1] as CollectionListRefusal).refusal;
    final ifRefusal = (traversal.entries[2] as CollectionListRefusal).refusal;
    final candidate = forRefusal.runtimeLoop;

    expect(forRefusal.reason, CollectionUnrollRefusal.runtimeValue);
    expect(candidate, isNotNull);
    expect(candidate!.iterable.toSource(), 'values');
    expect(candidate.identifier, 'value');
    expect(candidate.template.authoredExpression.toSource(), 'value');
    expect(candidate.template.terminalExpression.toSource(), 'value');
    expect(
      identical(
        candidate.binding,
        (candidate.template.terminalExpression as SimpleIdentifier).element,
      ),
      isTrue,
    );
    expect(
      candidate.template.structuralPath.map((step) => step.kind),
      [
        CollectionStructuralOccurrenceKind.listElement,
        CollectionStructuralOccurrenceKind.loopTemplate,
      ],
    );
    expect(
      candidate.template.structuralPath.map((step) => step.ordinal),
      [0, 0],
    );
    expect(spreadRefusal.reason, CollectionUnrollRefusal.runtimeValue);
    expect(spreadRefusal.runtimeLoop, isNull);
    expect(ifRefusal.reason, CollectionUnrollRefusal.runtimeValue);
    expect(ifRefusal.runtimeLoop, isNull);
  });

  test('a loop variable lowers inside a nested widget argument', () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => Column(
        children: [
          for (final text in const ['first', 'second']) Text(text: text),
        ],
      );
    ''');
    final children = (expression as MethodInvocation)
        .argumentList
        .arguments
        .whereType<NamedExpression>()
        .single
        .expression as ListLiteral;
    expect(inspectTypedList(children), isA<CollectionTypedListElement>());
    final result = _widgetTranslator(HelperRegistry()).translate(expression);

    expect(
      result.dsl,
      'Column(children: [Text(text: "first"), Text(text: "second")])',
    );
    expect(result.issues, isEmpty);
  });

  test('a callback-free static collection-for body expands', () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => Column(
        children: [
          for (final name in const ['first', 'second'])
            GestureDetector(child: Text(text: name)),
        ],
      );
    ''');
    final result = _widgetTranslator(HelperRegistry()).translate(expression);

    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      'Column(children: [GestureDetector(child: Text(text: "first")), '
      'GestureDetector(child: Text(text: "second"))])',
    );
  });

  test('a callback in a collection-for body refuses before event lowering',
      () async {
    const source = '''
void Function() paywallEvent(String name) => () {};

Object x() => Column(
  children: [
    for (final name in const ['first', 'second'])
      GestureDetector(
        child: Text(text: name),
        onTap: paywallEvent(name),
      ),
  ],
);''';
    final expression = await parseExpressionFromSourceForTest(source);
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(
      expression,
      sourcePath: 'lib/collection_callback_location.dart',
      lineInfo: LineInfo.fromContent(source),
    );

    expect(result.issues, hasLength(1));
    final issue = result.issues.single;
    expect(issue.code, IssueCode.unsupportedCollectionFlow);
    expect(
      issue.message,
      allOf(
        contains('is unsupported'),
        contains('bind the list to host-supplied data where supported'),
      ),
    );
    expect(
      issue.location,
      startsWith('lib/collection_callback_location.dart:5:'),
    );
    expect(
      issue.location,
      isNot(startsWith('lib/collection_callback_location.dart:4:')),
    );
    expect(result.dsl, 'Column(children: [])');
    expect(result.dsl, isNot(contains('event "first"')));
    expect(result.dsl, isNot(contains('event "second"')));
    expect(result.dsl, isNot(contains('GestureDetector')));
  });

  test('a constant-false collection branch skips callback inspection',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      void Function() paywallEvent(String name) => () {};

      Object x() => Column(
        children: [
          for (final name in const ['first', 'second'])
            if (false)
              GestureDetector(
                child: Text(text: name),
                onTap: paywallEvent(name),
              ),
        ],
      );
    ''');
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, 'Column(children: [])');
    expect(result.dsl, isNot(contains('event ')));
  });

  test('a loop-bound false branch skips callback inspection', () async {
    final expression = await parseExpressionFromSourceForTest('''
      void Function() paywallEvent(String name) => () {};

      Object x() => Column(
        children: [
          for (final include in const [false, false])
            if (include)
              GestureDetector(
                child: Text(text: 'unused'),
                onTap: paywallEvent('tap'),
              ),
        ],
      );
    ''');
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, 'Column(children: [])');
    expect(result.dsl, isNot(contains('event ')));
  });

  test('a constant-true collection branch refuses a repeated callback',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      void Function() paywallEvent(String name) => () {};

      Object x() => Column(
        children: [
          for (final name in const ['first', 'second'])
            if (true)
              GestureDetector(
                child: Text(text: name),
                onTap: paywallEvent(name),
              ),
        ],
      );
    ''');
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(expression);

    expect(result.dsl, 'Column(children: [])');
    expect(result.dsl, isNot(contains('event ')));
    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      contains('share one callback identity'),
    );
  });

  test('a loop-bound true branch refuses a repeated callback', () async {
    final expression = await parseExpressionFromSourceForTest('''
      void Function() paywallEvent(String name) => () {};

      Object x() => Column(
        children: [
          for (final include in const [true, true])
            if (include)
              GestureDetector(
                child: Text(text: 'used'),
                onTap: paywallEvent('tap'),
              ),
        ],
      );
    ''');
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(expression);

    expect(result.dsl, 'Column(children: [])');
    expect(result.dsl, isNot(contains('event ')));
    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      contains('share one callback identity'),
    );
  });

  test('a hand-unrolled callback body still lowers', () async {
    final expression = await parseExpressionFromSourceForTest('''
      void Function() paywallEvent(String name) => () {};

      Object x() => Column(
        children: [
          GestureDetector(
            child: Text(text: 'first'),
            onTap: paywallEvent('first'),
          ),
          GestureDetector(
            child: Text(text: 'second'),
            onTap: paywallEvent('second'),
          ),
        ],
      );
    ''');
    final helpers = HelperRegistry()..registerAll([_eventHelper]);
    final result = _widgetTranslator(helpers).translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, contains('event "first"'));
    expect(result.dsl, contains('event "second"'));
  });

  test('an admitted leaf carries its resolved source and structural path',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class TileSet {
  const TileSet(this.tile);
  final Widget tile;
}
class Probe extends Widget {
  const Probe();
  static const terminal = Text(text: 'resolved');
  static const group = TileSet(terminal);

  Widget pass(Widget child) => child;

  Widget build(BuildContext context) {
    final local = pass(group.tile);
    return Column(children: [if (true) local]);
  }
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );

    expect(traversal.entries, hasLength(1));
    final occurrence =
        (traversal.entries.single as CollectionListElement).occurrence;
    expect(occurrence.authoredExpression.toSource(), 'local');
    expect(occurrence.terminalExpression.toSource(), "Text(text: 'resolved')");
    expect(
      occurrence.sourceProvenance.map((step) => step.kind),
      [
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.helper,
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.receiver,
        CollectionSemanticSourceKind.constDeclaration,
        CollectionSemanticSourceKind.constObjectField,
        CollectionSemanticSourceKind.constDeclaration,
      ],
    );
    expect(
      occurrence.identitySourceProvenance.map((step) => step.kind),
      occurrence.sourceProvenance.map((step) => step.kind),
    );
    expect(occurrence.bindings, hasLength(2));
    expect(
      occurrence.structuralPath.map((step) => step.kind),
      [
        CollectionStructuralOccurrenceKind.listElement,
        CollectionStructuralOccurrenceKind.selectedThen,
      ],
    );
    expect(occurrence.structuralPath.map((step) => step.ordinal), [0, 0]);
  });

  test('expanded direct sources keep only semantic entrances', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class TileSet {
  const TileSet(this.tile);
  final Widget tile;
}
class Probe extends Widget {
  const Probe();
  static const terminal = Text(text: 'resolved');
  static const group = TileSet(terminal);

  Widget pass(Widget child) => child;

  Widget build(BuildContext context) {
    final local = pass(group.tile);
    return Column(
        children: [
          (local),
          opaque(),
          if (true) const Text(text: 'selected'),
        ],
      );
  }
}
''');
    final localInitializer = probe.inlined.localBindings.values.single;
    final semantics = CollectionSemanticProbe(
      bindingFor: (identifier) =>
          probe.inlined.localBindings[identifier.element],
      helperFor: (invocation) {
        final definition = probe.inlined.helpers[invocation.methodName.element];
        if (definition == null) return null;
        final bindings = bindHelperArguments(
          definition.params,
          invocation.argumentList.arguments.toList(),
        );
        if (bindings == null) return null;
        return CollectionResolvedHelper(
          body: definition.body,
          parameterBindings: bindings,
        );
      },
      sourceFor: (expression) =>
          expression.toSource() == 'opaque()' ? localInitializer : null,
    );
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: semantics,
    );

    final localOccurrence =
        (traversal.entries.first as CollectionListElement).occurrence;
    final sourceOccurrence =
        (traversal.entries[1] as CollectionListElement).occurrence;
    expect(localOccurrence.isDirectListElement, isTrue);
    expect(sourceOccurrence.isDirectListElement, isTrue);
    expect(
      localOccurrence.sourceProvenance.map((step) => step.kind),
      [
        CollectionSemanticSourceKind.parentheses,
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.helper,
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.receiver,
        CollectionSemanticSourceKind.constDeclaration,
        CollectionSemanticSourceKind.constObjectField,
        CollectionSemanticSourceKind.constDeclaration,
      ],
    );
    expect(
      localOccurrence.identitySourceProvenance.map((step) => step.kind),
      [CollectionSemanticSourceKind.helper],
    );
    expect(
      sourceOccurrence.sourceProvenance.map((step) => step.kind),
      [
        CollectionSemanticSourceKind.source,
        CollectionSemanticSourceKind.helper,
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.receiver,
        CollectionSemanticSourceKind.constDeclaration,
        CollectionSemanticSourceKind.constObjectField,
        CollectionSemanticSourceKind.constDeclaration,
      ],
    );
    expect(
      sourceOccurrence.identitySourceProvenance.map((step) => step.kind),
      [CollectionSemanticSourceKind.helper],
    );
  });

  test('direct source kinds match ordinary locator semantics', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget { const Text(); }
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class Probe extends Widget {
  const Probe();
  Widget action() => const Text();
  Widget build(BuildContext context) => Column(
        children: [action(), if (true) const Text()],
      );
}
''');
    final occurrence = (traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    ).entries.first as CollectionListElement)
        .occurrence;
    final helper = occurrence.sourceProvenance.single.element;
    if (helper is! ExecutableElement) {
      throw StateError('The helper entrance did not resolve.');
    }
    final widget = (occurrence.terminalExpression as InstanceCreationExpression)
        .constructorName
        .type
        .element;
    if (widget is! InterfaceElement) {
      throw StateError('The widget entrance did not resolve.');
    }
    final root = MeasurementOccurrenceScope.root(
      'package:restage_codegen/_collection_probe.dart#Probe',
    );
    final plainLocator = root.widget(widget).structuralOccurrenceKey;
    final helperLocator =
        root.enterHelper(helper).widget(widget).structuralOccurrenceKey;

    for (final kind in CollectionSemanticSourceKind.values) {
      final direct = CollectionSemanticOccurrence(
        authoredExpression: occurrence.authoredExpression,
        terminalExpression: occurrence.terminalExpression,
        bindings: occurrence.bindings,
        sourceProvenance: [
          CollectionSemanticSourceStep(
            kind: kind,
            source: occurrence.authoredExpression,
            target: occurrence.terminalExpression,
            element:
                kind == CollectionSemanticSourceKind.helper ? helper : null,
          ),
        ],
        structuralPath: occurrence.structuralPath,
      );
      final locator = root
          .enterCollectionOccurrence(direct)
          .widget(widget)
          .structuralOccurrenceKey;
      expect(
        locator,
        kind == CollectionSemanticSourceKind.helper
            ? helperLocator
            : plainLocator,
        reason: kind.name,
      );
    }

    final selected = CollectionSemanticOccurrence(
      authoredExpression: occurrence.authoredExpression,
      terminalExpression: occurrence.terminalExpression,
      bindings: occurrence.bindings,
      sourceProvenance: [
        CollectionSemanticSourceStep(
          kind: CollectionSemanticSourceKind.constDeclaration,
          source: occurrence.authoredExpression,
          target: occurrence.terminalExpression,
        ),
      ],
      structuralPath: [
        occurrence.structuralPath.single,
        CollectionStructuralOccurrenceStep(
          kind: CollectionStructuralOccurrenceKind.selectedThen,
          node: occurrence.authoredExpression,
          ordinal: 0,
        ),
      ],
    );
    expect(
      root
          .enterCollectionOccurrence(selected)
          .widget(widget)
          .structuralOccurrenceKey,
      'package:restage_codegen/_collection_probe.dart#Probe|'
      'collection:listElement[0]|collection:selectedThen[0]|'
      'source:constDeclaration[0]|'
      'widget:package:restage_codegen/_collection_probe.dart#Text',
    );
  });

  test('a bound const-object receiver reaches its exact widget field',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class ActionSet {
  const ActionSet(this.widget);
  final Widget widget;
}
class Probe extends Widget {
  const Probe();
  static const set = ActionSet(Text(text: 'accepted'));

  List<Widget> select(ActionSet source) => [if (true) source.widget];

  Widget build(BuildContext context) =>
      Column(children: [...select(set)]);
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );
    final result = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(traversal.entries, hasLength(1));
    final occurrence =
        (traversal.entries.single as CollectionListElement).occurrence;
    expect(
      occurrence.terminalExpression.toSource(),
      "Text(text: 'accepted')",
    );
    expect(
      occurrence.sourceProvenance.map((step) => step.kind),
      containsAllInOrder([
        CollectionSemanticSourceKind.binding,
        CollectionSemanticSourceKind.constDeclaration,
        CollectionSemanticSourceKind.constObjectField,
      ]),
    );
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('Text(text: "accepted")'));
  });

  test('a targeted virtual helper stays unresolved', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class Provider {
  List<Widget> actions() => [const Text(text: 'base')];
}
class Derived extends Provider {
  @override
  List<Widget> actions() => [const Text(text: 'derived')];
}
Provider provider() => Derived();
class Probe extends Widget {
  const Probe();

  Widget build(BuildContext context) =>
      Column(children: [...provider().actions()]);
}
''');
    final result = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.dsl, isNot(contains('"base"')));
    expect(result.dsl, isNot(contains('"derived"')));
  });

  test('own static and top-level helpers preserve their exact values',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
List<Widget> topLevelActions() => [const Text(text: 'top')];
class Helpers {
  static List<Widget> actions() => [const Text(text: 'static')];
}
class Probe extends Widget {
  const Probe();

  List<Widget> ownActions() => [const Text(text: 'own')];

  Widget build(BuildContext context) => Column(
    children: [
      ...ownActions(),
      ...Helpers.actions(),
      ...topLevelActions(),
    ],
  );
}
''');
    final result = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      'Column(children: [Text(text: "own"), Text(text: "static"), '
      'Text(text: "top")])',
    );
  });

  test('an explicit new receiver does not substitute a mutable field',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class Holder {
  Holder(this.widget) {
    widget = const Text(text: 'actual');
  }
  Widget widget;
}
class Probe extends Widget {
  const Probe();

  List<Widget> select(Holder source) => [if (true) source.widget];

  Widget build(BuildContext context) => Column(
    children: [...select(new Holder(const Text(text: 'passed')))],
  );
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );
    final result = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(traversal.entries, hasLength(1));
    final occurrence =
        (traversal.entries.single as CollectionListElement).occurrence;
    expect(occurrence.terminalExpression.toSource(), 'source.widget');
    expect(result.issues, isNotEmpty);
    expect(result.dsl, isNot(contains('"passed"')));
  });

  test('an implicit const receiver substitutes its exact field', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class Holder {
  const Holder(this.widget);
  final Widget widget;
}
class Probe extends Widget {
  const Probe();

  Widget build(BuildContext context) => Column(
    children: [
      for (final source in const [Holder(Text(text: 'accepted'))])
        source.widget,
    ],
  );
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );
    final result = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(traversal.entries, hasLength(1));
    final occurrence =
        (traversal.entries.single as CollectionListElement).occurrence;
    expect(
      occurrence.terminalExpression.toSource(),
      "Text(text: 'accepted')",
    );
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('Text(text: "accepted")'));
  });

  test('a mixed receiver preserves its runtime alternative', () async {
    final probe = await _mixedReceiverProbe();
    final children = _childrenList(probe.expression);
    final semantics = _collectionSemanticsFor(probe);
    final traversal = traverseCollectionList(
      children,
      semantics: semantics,
    );
    final translated = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(translated.dsl, 'Column(children: [])');
    expect(translated.issues, hasLength(1));
    expect(translated.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(translated.dsl, isNot(contains('"constant"')));
    expect(translated.dsl, isNot(contains('"runtime"')));
    expect(traversal.entries, hasLength(1));
    final refusal = (traversal.entries.single as CollectionListRefusal).refusal;
    expect(refusal.reason, CollectionUnrollRefusal.runtimeValue);
    expect(
      refusal.detail,
      'A spread of a value known only at run time is unsupported. Spread a '
      'list literal, or supply the list through the host-data channel.',
    );
  });

  test('a mixed receiver keeps callbacks from its runtime alternative',
      () async {
    final probe = await _mixedReceiverProbe();
    final spread =
        _childrenList(probe.expression).elements.single as SpreadElement;

    expect(
      _collectionSemanticsFor(probe).callbacksIn(
        spread.expression,
        budget: CollectionUnrollBudget(),
      ),
      CollectionCallbackProbeResult.present,
    );
  });

  test('receiver cycles and work exhaustion preserve the authored access',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}
class Probe extends Widget {
  const Probe();

  WidgetSet first() => second();
  WidgetSet second() => first();

  Widget build(BuildContext context) => Column(
    children: [...first().widgets],
  );
}
''');
    final spread =
        _childrenList(probe.expression).elements.single as SpreadElement;
    final semantics = _collectionSemanticsFor(probe);
    final cycled = semantics.resolve(
      spread.expression,
      const {},
      CollectionUnrollBudget(),
    );
    final exhausted = semantics.resolve(
      spread.expression,
      const {},
      CollectionUnrollBudget(workCeiling: 1),
    );

    expect(cycled.expression, same(spread.expression));
    expect(cycled.cycleDetected, isTrue);
    expect(cycled.workLimitExceeded, isFalse);
    expect(exhausted.expression, same(spread.expression));
    expect(exhausted.workLimitExceeded, isTrue);
  });

  test('two const receiver alternatives remain ambiguous', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}
class Probe extends Widget {
  const Probe(this.selectFirst);
  final bool selectFirst;

  Widget build(BuildContext context) => Column(
    children: [
      ...(selectFirst
            ? const WidgetSet(<Widget>[Text(text: 'first')])
            : const WidgetSet(<Widget>[Text(text: 'second')]))
          .widgets,
    ],
  );
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );
    final translated = _widgetTranslator(HelperRegistry()).translate(
      probe.expression,
    );

    expect(traversal.entries, hasLength(1));
    expect(
      (traversal.entries.single as CollectionListRefusal).refusal.reason,
      CollectionUnrollRefusal.runtimeValue,
    );
    expect(translated.dsl, 'Column(children: [])');
    expect(translated.issues, hasLength(1));
    expect(translated.dsl, isNot(contains('"first"')));
    expect(translated.dsl, isNot(contains('"second"')));
  });

  test('one callback-bearing source occurrence remains admitted', () async {
    final result = await _translateInlinedProbe('''
  Widget tile(String name) => GestureDetector(
    child: Text(text: name),
    onTap: paywallEvent(name),
  );

  List<Widget> actions(Widget child) => [child];

  Widget build(BuildContext context) {
    final values = actions(tile('tap'));
    return Column(children: [...values]);
  }
''');

    expect(result.issues, isEmpty);
    expect(result.widgetDefinitions['Probe'], contains('event "tap"'));
  });

  test('converging callback alternatives remain one source occurrence',
      () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
typedef VoidCallback = void Function();
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text(this.text);
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class GestureDetector extends Widget {
  const GestureDetector({this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;
}
class Probe extends Widget {
  const Probe(this.selectFirst);
  final bool selectFirst;

  List<Widget> actions(VoidCallback callback) => [
        GestureDetector(
          onTap: selectFirst ? callback : callback,
          child: const Text('Tap'),
        ),
      ];

  Widget build(BuildContext context) =>
      Column(children: [...actions(() {})]);
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
    );

    expect(traversal.entries, hasLength(1));
    expect(traversal.entries.single, isA<CollectionListElement>());
  });

  test('two callback slots sharing one source refuse at traversal', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
typedef VoidCallback = void Function();
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text(this.text);
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class GestureDetector extends Widget {
  const GestureDetector({this.onTap, this.onDoubleTap, required this.child});
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget child;
}
class Probe extends Widget {
  const Probe();

  List<Widget> actions(VoidCallback callback) => [
        GestureDetector(
          onTap: callback,
          onDoubleTap: callback,
          child: const Text('Tap'),
        ),
      ];

  Widget build(BuildContext context) =>
      Column(children: [...actions(() {})]);
}
''');
    final session = CollectionSemanticTraversalSession();
    final ordinaryRefusal = session.admitOrdinaryLeaf(
      probe.expression,
      _collectionSemanticsFor(probe),
    );
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
      session: session,
    );

    expect(ordinaryRefusal, isNull);
    expect(traversal.entries, hasLength(1));
    final refusal = (traversal.entries.single as CollectionListRefusal).refusal;
    expect(refusal.reason, CollectionUnrollRefusal.callbackSourceReused);
  });

  test('ordinary widget entrances refuse one source bound to two slots',
      () async {
    final cases = <String, String>{
      'direct root': '''
  static void activate() {}
  static const void Function() callback = activate;

  Widget build(BuildContext context) => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: callback,
    onDoubleTap: callback,
  );
''',
      'scalar child': '''
  static void activate() {}
  static const void Function() callback = activate;

  Widget build(BuildContext context) => GestureDetector(
    child: GestureDetector(
      child: const Text(text: 'tap'),
      onTap: callback,
      onDoubleTap: callback,
    ),
  );
''',
      'helper root': '''
  Widget action(void Function() callback) => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: callback,
    onDoubleTap: callback,
  );

  Widget build(BuildContext context) => action(() {});
''',
      'helper child': '''
  Widget action(void Function() callback) => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: callback,
    onDoubleTap: callback,
  );

  Widget build(BuildContext context) => GestureDetector(
    child: action(() {}),
  );
''',
    };

    for (final MapEntry(key: name, value: members) in cases.entries) {
      final result = await _translateInlinedProbe(members);

      expect(result.dsl, 'Probe', reason: name);
      expect(result.widgetDefinitions, isEmpty, reason: name);
      expect(result.issues, hasLength(1), reason: name);
      expect(
        result.issues.single.code,
        IssueCode.unsupportedCollectionFlow,
        reason: name,
      );
      expect(
        result.issues.single.message,
        contains('static collection source is reused'),
        reason: name,
      );
    }
  });

  test('ordinary widget entrances accept distinct and convergent callbacks',
      () async {
    final distinct = await _translateInlinedProbe('''
  Widget build(BuildContext context) => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: paywallEvent('tap'),
    onDoubleTap: paywallEvent('double'),
  );
''');
    final convergent = await _translateInlinedProbe('''
  Widget action(bool first, void Function() callback) => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: first ? callback : callback,
  );

  Widget build(BuildContext context) => action(true, paywallEvent('tap'));
''');

    expect(distinct.issues, isEmpty);
    expect(distinct.widgetDefinitions['Probe'], contains('onTap: event '));
    expect(
      distinct.widgetDefinitions['Probe'],
      contains('onDoubleTap: event '),
    );
    expect(convergent.issues, isEmpty);
    expect(
      convergent.widgetDefinitions['Probe'],
      contains(
        'onTap: switch true { true: event "tap" {}, '
        'false: event "tap" {} }',
      ),
    );
  });

  test('a reused callback-bearing source refuses at shared traversal',
      () async {
    final result = await _translateInlinedProbe('''
  Widget tile(String name) => GestureDetector(
    child: Text(text: name),
    onTap: paywallEvent(name),
  );

  List<Widget> actions(Widget child) => [child];

  Widget build(BuildContext context) {
    final values = actions(tile('tap'));
    return Column(children: [...values, ...values]);
  }
''');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      contains('static collection source is reused'),
    );
    expect(result.widgetDefinitions['Probe'], contains('event "tap"'));
  });

  test('callback identity spans expanded and ordinary sibling lists', () async {
    final result = await _translateInlinedProbe('''
  Widget action() => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: paywallEvent('tap'),
  );

  List<Widget> actions() => [action()];

  Widget build(BuildContext context) => Column(
    children: [
      Column(children: [...actions()]),
      Column(children: [action()]),
    ],
  );
''');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      contains('static collection source is reused'),
    );
    expect(
      RegExp('event "tap"')
          .allMatches(result.widgetDefinitions['Probe'] ?? '')
          .length,
      1,
    );
  });

  test('each inline emission attempt owns an independent callback identity',
      () async {
    final results = await _attemptInlinedProbe(
      '''
  Widget action() => GestureDetector(
    child: const Text(text: 'tap'),
    onTap: paywallEvent('tap'),
  );

  List<Widget> actions() => [action()];

  Widget build(BuildContext context) => Column(children: [...actions()]);
''',
      names: const ['FirstProbe', 'SecondProbe'],
    );

    expect(results, hasLength(2));
    expect(results[0].issues, isEmpty);
    expect(results[1].issues, isEmpty);
    expect(results[0].widgetDefinitions['FirstProbe'], contains('event "tap"'));
    expect(
      results[1].widgetDefinitions['SecondProbe'],
      contains('event "tap"'),
    );
  });

  test('invoked method selectors are not callback values', () async {
    final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class Probe extends Widget {
  const Probe();

  Widget build(BuildContext context) {
    final label = 42.toString();
    return Column(
      children: [
        Text(text: label),
        Text(text: label),
      ],
    );
  }
}
''');
    final traversal = traverseCollectionList(
      _childrenList(probe.expression),
      semantics: _collectionSemanticsFor(probe),
      session: CollectionSemanticTraversalSession(),
    );

    expect(traversal.entries, hasLength(2));
    expect(traversal.entries, everyElement(isA<CollectionListElement>()));
  });

  test('a callback behind a local alias refuses before repeated emission',
      () async {
    final result = await _translateInlinedProbe('''
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      child: Text(text: 'same'),
      onTap: paywallEvent('tap'),
    );
    return Column(
      children: [for (final index in const [0, 1]) tile],
    );
  }
''');

    _expectCallbackRefusal(result);
  });

  test('a callback in a loop-bound widget refuses before repeated emission',
      () async {
    final result = await _translateInlinedProbe('''
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      child: Text(text: 'same'),
      onTap: paywallEvent('tap'),
    );
    return Column(
      children: [for (final repeated in [tile, tile]) repeated],
    );
  }
''');

    _expectCallbackRefusal(result);
  });

  test('a callback in an inlined helper body refuses before repetition',
      () async {
    final result = await _translateInlinedProbe('''
  Widget tile(String name) => GestureDetector(
    child: Text(text: name),
    onTap: paywallEvent(name),
  );

  Widget build(BuildContext context) => Column(
    children: [
      for (final name in const ['first', 'second']) tile(name),
    ],
  );
''');

    _expectCallbackRefusal(result);
  });

  test('a helper body containing a callback refuses repeated emission',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [for (final index in const [0, 1]) tile(index)];
    ''');
    final callback = await parseExpressionForTest('() {}');
    final semantics = CollectionSemanticProbe(
      helperFor: (invocation) => invocation.methodName.name == 'tile'
          ? CollectionResolvedHelper(
              body: callback,
              parameterBindings: const {},
            )
          : null,
    );
    final result = expandCollectionElement(
      _singleCollectionElement(expression),
      semantics: semantics,
    );

    expect(result, isA<CollectionUnrollRefused>());
    expect(
      (result as CollectionUnrollRefused).reason,
      CollectionUnrollRefusal.callbackInRepeatedBody,
    );
  });

  test('a callback behind an inlined helper parameter refuses', () async {
    final result = await _translateInlinedProbe('''
  Widget identity(Widget child) => child;

  Widget build(BuildContext context) {
    final tile = GestureDetector(
      child: Text(text: 'same'),
      onTap: paywallEvent('tap'),
    );
    return Column(
      children: [
        for (final index in const [0, 1]) identity(tile),
      ],
    );
  }
''');

    _expectCallbackRefusal(result);
  });

  test('a callback behind a const source refuses before repetition', () async {
    final result = await _translateInlinedProbe('''
  static void handleTap() {}
  static const tile = GestureDetector(
    child: Text(text: 'same'),
    onTap: handleTap,
  );

  Widget build(BuildContext context) => Column(
    children: [for (final index in const [0, 1]) tile],
  );
''');

    _expectCallbackRefusal(result);
  });

  test('a callback behind a nested const source refuses before repetition',
      () async {
    final result = await _translateInlinedProbe('''
  static void handleTap() {}
  static const tiles = TileSet(
    GestureDetector(
      child: Text(text: 'same'),
      onTap: handleTap,
    ),
  );

  Widget build(BuildContext context) => Column(
    children: [for (final index in const [0, 1]) tiles.tile],
  );
''');

    _expectCallbackRefusal(result);
  });

  test('semantic callback resolution terminates through a binding cycle',
      () async {
    final first = await parseExpressionForTest('second');
    final second = await parseExpressionForTest('true ? first : (() {})');
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [for (final index in const [0, 1]) first];
    ''');
    final semantics = CollectionSemanticProbe(
      bindingFor: (identifier) => switch (identifier.name) {
        'first' => first,
        'second' => second,
        _ => null,
      },
    );
    final result = expandCollectionElement(
      _singleCollectionElement(expression),
      semantics: semantics,
    );

    expect(result, isA<CollectionUnrollRefused>());
    expect(
      (result as CollectionUnrollRefused).reason,
      CollectionUnrollRefusal.callbackInRepeatedBody,
    );
  });

  test('numeric-list refusal follows a leading local alias', () async {
    final result = await _translateInlinedProbe('''
  Widget build(BuildContext context) {
    final stops = ([for (final stop in const [0, 1]) stop]);
    return GradientBox(
      gradient: LinearGradient(
        colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
        stops: stops,
      ),
    );
  }
''');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      'Collection elements in a numeric list are unsupported; '
      'write the values out.',
    );
    expect(
      result.widgetDefinitions['Probe'],
      isNot(contains('stops: [0, 1]')),
    );
  });

  test('numeric-list refusal follows an inlined helper parameter', () async {
    final result = await _translateInlinedProbe('''
  Widget gradient(List<double> stops) => GradientBox(
    gradient: LinearGradient(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops,
    ),
  );

  Widget build(BuildContext context) => gradient(
    ([for (final stop in const [0, 1]) stop]),
  );
''');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.widgetDefinitions['Probe'],
      isNot(contains('stops: [0, 1]')),
    );
  });

  test('numeric-list refusal follows an inlined helper result', () async {
    final result = await _translateInlinedProbe('''
  List<double> stops() => ([
    for (final stop in const [0, 1]) stop,
  ]);

  Widget build(BuildContext context) => GradientBox(
    gradient: LinearGradient(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops(),
    ),
  );
''');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.widgetDefinitions['Probe'],
      isNot(contains('stops: [0, 1]')),
    );
  });

  for (final gradientName in ['LinearGradient', 'SweepGradient']) {
    test('$gradientName helper results preserve numeric-list boundaries',
        () async {
      final result = await _translateInlinedProbe('''
  static const stopSet = StopSet(<double>[
    if (true) 0,
    1,
  ]);

  List<double> stops() => stopSet.values;

  Widget build(BuildContext context) => GradientBox(
    gradient: $gradientName(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops(),
    ),
  );
''');

      expect(
        result.widgetDefinitions['Probe'],
        isNot(contains('stops: [0, 1]')),
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(
        result.issues.single.message,
        'Collection elements in a numeric list are unsupported; '
        'write the values out.',
      );
    });
  }

  final gradientCases = <({String name, String type})>[
    (name: 'LinearGradient', type: 'linear'),
    (name: 'RadialGradient', type: 'radial'),
    (name: 'SweepGradient', type: 'sweep'),
  ];

  for (final gradient in gradientCases) {
    test('${gradient.name} emits a parameterized stops helper', () async {
      final result = await _translateInlinedProbe('''
  List<double> stops(double first) => [first, 1];

  Widget build(BuildContext context) => GradientBox(
    gradient: ${gradient.name}(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops(0.5),
    ),
  );
''');

      expect(result.issues, isEmpty);
      expect(
        result.widgetDefinitions['Probe'],
        'GradientBox(gradient: {type: "${gradient.type}", '
        'colors: [0xFF000000, 0xFFFFFFFF], stops: [0.5, 1.0]})',
      );
    });

    test('${gradient.name} emits a nested stops helper', () async {
      final result = await _translateInlinedProbe('''
  List<double> innerStops(double value) => [value, 1];
  List<double> stops(double first) => innerStops(first);

  Widget build(BuildContext context) => GradientBox(
    gradient: ${gradient.name}(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops(0.5),
    ),
  );
''');

      expect(result.issues, isEmpty);
      expect(
        result.widgetDefinitions['Probe'],
        'GradientBox(gradient: {type: "${gradient.type}", '
        'colors: [0xFF000000, 0xFFFFFFFF], stops: [0.5, 1.0]})',
      );
    });
  }

  final activeListCases = <({String label, String members})>[
    (
      label: 'a direct list',
      members: '''
  Widget build(BuildContext context) => GradientBox(
    gradient: LinearGradient(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: const [0, 1],
    ),
  );
''',
    ),
    (
      label: 'a parenthesized list',
      members: '''
  Widget build(BuildContext context) => GradientBox(
    gradient: LinearGradient(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: (([0, 1])),
    ),
  );
''',
    ),
    (
      label: 'a local list alias',
      members: '''
  Widget build(BuildContext context) {
    final stops = [0, 1];
    return GradientBox(
      gradient: LinearGradient(
        colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
        stops: stops,
      ),
    );
  }
''',
    ),
    (
      label: 'an active helper parameter',
      members: '''
  Widget gradient(List<double> stops) => GradientBox(
    gradient: LinearGradient(
      colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
      stops: stops,
    ),
  );

  Widget build(BuildContext context) => gradient([0, 1]);
''',
    ),
  ];

  for (final listCase in activeListCases) {
    test('${listCase.label} keeps per-element double coercion', () async {
      final result = await _translateInlinedProbe(listCase.members);

      expect(result.issues, isEmpty);
      expect(
        result.widgetDefinitions['Probe'],
        'GradientBox(gradient: {type: "linear", '
        'colors: [0xFF000000, 0xFFFFFFFF], stops: [0.0, 1.0]})',
      );
    });
  }

  test('a parameterized generic typed-list helper keeps authored translation',
      () async {
    final result = await _translateInlinedProbe('''
  List<Color> colors(Color first) => [first, const Color(0xFFFFFFFF)];

  Widget build(BuildContext context) => GradientBox(
    gradient: LinearGradient(
      colors: colors(const Color(0xFF000000)),
      stops: const [0, 1],
    ),
  );
''');

    expect(result.issues, isEmpty);
    expect(
      result.widgetDefinitions['Probe'],
      'GradientBox(gradient: {type: "linear", '
      'colors: [0xFF000000, 0xFFFFFFFF], stops: [0.0, 1.0]})',
    );
  });

  test('collection-if expands true, false, and const conditions', () async {
    final translator = _scalarTranslator();
    final trueResult = translator.translate(
      await parseExpressionForTest('[if (true) 1]'),
    );
    final falseResult = translator.translate(
      await parseExpressionForTest('[if (false) 1, 2]'),
    );
    final constResult = translator.translate(
      await parseExpressionFromSourceForTest('''
        const bool includeValue = true;
        Object x() => [if (includeValue) 3];
      '''),
    );

    expect(trueResult.dsl, '[1]');
    expect(trueResult.issues, isEmpty);
    expect(falseResult.dsl, '[2]');
    expect(falseResult.issues, isEmpty);
    expect(constResult.dsl, '[3]');
    expect(constResult.issues, isEmpty);
  });

  test('a collection-if over a build-environment constant refuses', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/foundation.dart';

Object x() => [if (kDebugMode) 1, 2];
''',
        rootPackage: 'apps_examples',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('known only at run time'));
    expect(result.dsl, '[2]');
    expect(result.dsl, isNot(contains('1')));
  });

  test('a collection-if over each build-mode constant refuses', () async {
    final translator = _scalarTranslator();
    for (final name in ['kReleaseMode', 'kProfileMode', 'kIsWeb']) {
      final result = translator.translate(
        await parseExpressionFromSourceForTest(
          '''
import 'package:flutter/foundation.dart';

Object x() => [if ($name) 1, 2];
''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(result.issues, hasLength(1), reason: name);
      expect(
        result.issues.single.code,
        IssueCode.unsupportedCollectionFlow,
        reason: name,
      );
      expect(result.dsl, '[2]', reason: name);
    }
  });

  test(
      'a collection-if over a constant derived from the build environment '
      'refuses', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/foundation.dart';

const bool showExtras = kDebugMode;

Object x() => [if (showExtras) 1, 2];
''',
        rootPackage: 'apps_examples',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.dsl, '[2]');
  });

  test('a spread of a list literal splices its elements', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionForTest('[0, ...const [1, 2], 3]'),
    );

    expect(result.dsl, '[0, 1, 2, 3]');
    expect(result.issues, isEmpty);
  });

  test('collection controls follow helper bodies and argument bindings',
      () async {
    final result = await _translateInlinedProbe('''
  List<String> labels(String value) => [value];
  List<Widget> tiles(String value) => [Text(text: value)];
  bool include(bool value) => value;

  Widget build(BuildContext context) => Column(
    children: [
      for (final label in labels('loop')) Text(text: label),
      ...tiles('spread'),
      if (include(true)) Text(text: 'if'),
    ],
  );
''');

    expect(result.issues, isEmpty);
    expect(
      result.widgetDefinitions['Probe'],
      'Column(children: [Text(text: "loop"), Text(text: "spread"), '
      'Text(text: "if")])',
    );
  });

  test('nested iterables resolve through active loop bindings', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest('''
        Object x() => [
          for (final values in const [[1, 2], [3]])
            for (final value in values) [values, value],
        ];
      '''),
    );

    expect(result.issues, isEmpty);
    expect(result.dsl, '[[[1, 2], 1], [[1, 2], 2], [[3], 3]]');
  });

  test('spreads resolve through active loop bindings', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest('''
        Object x() => [
          for (final values in const [[1, 2], [3]]) ...values,
        ];
      '''),
    );

    expect(result.issues, isEmpty);
    expect(result.dsl, '[1, 2, 3]');
  });

  test('collection-if conditions resolve through active loop bindings',
      () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest('''
        Object x() => [
          for (final include in const [true, false, true])
            if (include) include,
        ];
      '''),
    );

    expect(result.issues, isEmpty);
    expect(result.dsl, '[true, true]');
  });

  test('nested loop bindings shadow without corrupting the outer iterable',
      () async {
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest('''
        Object x() => [
          for (final value in const [[1, 2], [3]])
            for (final value in value) value,
        ];
      '''),
    );

    expect(result.issues, isEmpty);
    expect(result.dsl, '[1, 2, 3]');
  });

  test('a null-aware spread reports its unsupported shape', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionForTest('[...?const [1]]'),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('...?'));
  });

  test('a C-style collection-for reports its unsupported shape', () async {
    final result = _scalarTranslator().translate(
      await parseExpressionForTest(
        '[for (var index = 0; index < 2; index += 1) index]',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('C-style'));
  });

  test('a loop over constructor data reports a run-time value', () async {
    final expression = await parseExpressionFromSourceForTest('''
      class Source {
        const Source(this.items);

        final List<int> items;
      }

      Object x(Source source) => [
        for (final item in source.items) item,
      ];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('known only at run time'));
    expect(result.dsl, '[]');
    expect(result.dsl, isNot(contains('item')));
    expect(result.dsl, isNot(contains('source')));
  });

  test('a const-list alias expands in a collection-for', () async {
    final expression = await parseExpressionFromSourceForTest('''
      const items = <int>[1, 2];
      Object x() => [for (final item in items) item];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, '[1, 2]');
  });

  test('a const-list alias expands in a spread', () async {
    final expression = await parseExpressionFromSourceForTest('''
      const items = <int>[1, 2];
      Object x() => [...items];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, '[1, 2]');
  });

  test('a const non-list alias reports its shape in a collection-for',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      class Items extends Iterable<int> {
        const Items();

        @override
        Iterator<int> get iterator => const <int>[].iterator;
      }

      const items = Items();
      Object x() => [for (final item in items) item];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('statically known non-list'));
    expect(
      result.issues.single.message,
      isNot(contains('known only at run time')),
    );
    expect(result.dsl, '[]');
  });

  test('a const non-list alias reports its shape in a spread', () async {
    final expression = await parseExpressionFromSourceForTest('''
      class Items extends Iterable<int> {
        const Items();

        @override
        Iterator<int> get iterator => const <int>[].iterator;
      }

      const items = Items();
      Object x() => [...items];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('statically known non-list'));
    expect(
      result.issues.single.message,
      isNot(contains('known only at run time')),
    );
    expect(result.dsl, '[]');
  });

  test('a loop over a static set reports an unsupported shape', () async {
    const source = '''
Object x() => [
  for (final item in const <int>{1, 2}) item,
];''';
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(source),
      sourcePath: 'lib/static_set_collection.dart',
      lineInfo: LineInfo.fromContent(source),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('statically known non-list'));
    expect(
      result.issues.single.message,
      isNot(contains('known only at run time')),
    );
    expect(
      result.issues.single.location,
      startsWith('lib/static_set_collection.dart:2:'),
    );
  });

  test('a spread of a static set reports an unsupported shape', () async {
    const source = '''
Object x() => [
  ...const <int>{1, 2},
];''';
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(source),
      sourcePath: 'lib/static_set_spread.dart',
      lineInfo: LineInfo.fromContent(source),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('statically known non-list'));
    expect(
      result.issues.single.message,
      isNot(contains('known only at run time')),
    );
    expect(
      result.issues.single.location,
      startsWith('lib/static_set_spread.dart:2:'),
    );
  });

  test('a loop over a resolved Iterable construction reports its shape',
      () async {
    const source = '''
class Items extends Iterable<int> {
  const Items();

  @override
  Iterator<int> get iterator => const <int>[].iterator;
}

Object x() => [
  for (final item in const Items()) item,
];''';
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(source),
      sourcePath: 'lib/static_iterable_collection.dart',
      lineInfo: LineInfo.fromContent(source),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      'A collection-for requires a list literal, but this iterable is a '
      'statically known non-list value.',
    );
    expect(
      result.issues.single.location,
      startsWith('lib/static_iterable_collection.dart:9:'),
    );
  });

  test('a spread of a resolved Iterable construction reports its shape',
      () async {
    const source = '''
class Items extends Iterable<int> {
  const Items();

  @override
  Iterator<int> get iterator => const <int>[].iterator;
}

Object x() => [
  ...const Items(),
];''';
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(source),
      sourcePath: 'lib/static_iterable_spread.dart',
      lineInfo: LineInfo.fromContent(source),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(
      result.issues.single.message,
      'A spread requires a list literal, but this value is a statically known '
      'non-list value.',
    );
    expect(
      result.issues.single.location,
      startsWith('lib/static_iterable_spread.dart:9:'),
    );
  });

  test('an uncertain Iterable value retains the run-time diagnostic', () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x(Iterable<int> items) => [
        for (final item in items) item,
        ...items,
      ];
    ''');
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, hasLength(2));
    expect(
      result.issues.map((issue) => issue.message),
      everyElement(contains('known only at run time')),
    );
    expect(
      result.issues.map((issue) => issue.message),
      everyElement(isNot(contains('statically known non-list'))),
    );
  });

  test(
    'a loop over a method-call chain reports its unsupported shape',
    () async {
      final expression = await parseExpressionFromSourceForTest('''
      Object x() => [
        for (final item in (const [1, 2]).map((value) => value)) item,
      ];
    ''');
      final result = _scalarTranslator().translate(expression);

      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(result.issues.single.message, contains('method call'));
    },
  );

  test('an oversized nested expansion reports the ceiling', () async {
    final values = List<String>.generate(
      32,
      (index) => '$index',
    ).join(', ');
    final expression = await parseExpressionFromSourceForTest(
      'Object x() => [for (final first in const [$values]) '
      'for (final second in const [$values]) first];',
    );
    final unrollResult = expandCollectionElement(
      _singleCollectionElement(expression),
    );
    final result = _scalarTranslator().translate(expression);

    expect(unrollResult, isA<CollectionUnrollRefused>());
    final refusal = unrollResult as CollectionUnrollRefused;
    expect(refusal.reason, CollectionUnrollRefusal.ceilingExceeded);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[]');
  });

  test('the ceiling applies across collection elements in one list', () async {
    final outer = List<String>.generate(21, (index) => '$index').join(', ');
    final inner = List<String>.generate(25, (index) => '$index').join(', ');
    final expression = await parseExpressionFromSourceForTest(
      'Object x() => [ '
      'for (final a in const [$outer]) '
      'for (final b in const [$inner]) 1, '
      'for (final c in const [$outer]) '
      'for (final d in const [$inner]) 2, '
      '];',
    );
    final result = _scalarTranslator().translate(expression);
    final expected = List<String>.filled(525, '1').join(', ');

    expect(result.issues, hasLength(1));
    expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[$expected]');
  });

  test('exactly 1000 expanded children are accepted', () async {
    final values = _integerSequence(1000);
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        'Object x() => [for (final value in const [$values]) value];',
      ),
    );

    expect(result.issues, isEmpty);
    expect(result.dsl, '[${_integerSequence(1000)}]');
  });

  for (final count in [1000, 1001]) {
    test('$count plain generic elements preserve authored bytes', () async {
      final values = _integerSequence(count);
      final expression = await parseExpressionForTest('[$values]');
      final issues = <Issue>[];
      final emission = emitTypedList(
        expression,
        (source, _) => source.toSource(),
        issues,
        'plain-generic',
      );

      expect(issues, isEmpty);
      expect(emission, '[$values]');
    });

    test('$count plain numeric elements preserve double coercion', () async {
      final values = _integerSequence(count);
      final expression = await parseExpressionForTest('[$values]');
      final issues = <Issue>[];
      final emission = emitDoubleList(
        expression,
        (source, _) => source.toSource(),
        (source, _) => '${(source as IntegerLiteral).value}.0',
        (source) => DoubleListSourceResolution(
          source: source,
          disposition: DoubleListSourceDisposition.ordinary,
        ),
        issues,
        'plain-numeric',
      );

      expect(issues, isEmpty);
      expect(
        emission,
        '[${List<String>.generate(count, (index) => '$index.0').join(', ')}]',
      );
    });
  }

  test('1001 expanded children are refused', () async {
    final values = _integerSequence(1001);
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        'Object x() => [for (final value in const [$values]) value];',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[]');
  });

  test('1000 expanded children plus a trailing plain child are refused',
      () async {
    final values = _integerSequence(1000);
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        'Object x() => [for (final value in const [$values]) value, 1000];',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[${_integerSequence(1000)}]');
  });

  test('sibling collection lists keep independent emission ceilings', () async {
    final values = _integerSequence(1000);
    final result = _widgetTranslator(HelperRegistry()).translate(
      await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';

Object x() => Column(
  children: [
    Row(children: [
      for (final value in const [0]) SizedBox(),
    ]),
    Row(children: [
      for (final value in const [$values]) SizedBox(),
    ]),
  ],
);
'''),
    );

    expect(result.issues, isEmpty);
    expect(RegExp(r'SizedBox\(').allMatches(result.dsl), hasLength(1001));
  });

  test('a leading plain child is charged before a 1000-child expansion',
      () async {
    final values = _integerSequence(1000);
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        'Object x() => [-1, '
        'for (final value in const [$values]) value];',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[-1]');
  });

  test('plain children after a false collection-if still use the list budget',
      () async {
    final values = _integerSequence(1001);
    final result = _scalarTranslator().translate(
      await parseExpressionFromSourceForTest(
        'Object x() => [if (false) -1, $values];',
      ),
    );

    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('1000'));
    expect(result.dsl, '[${_integerSequence(1000)}]');
  });

  test('callback inspection shares traversal work across repeated expressions',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [
        for (final item in const [1, 2, 3]) [item, item],
      ];
    ''');
    final result = expandCollectionElement(
      _singleCollectionElement(expression),
      budget: CollectionUnrollBudget(emittedCeiling: 100, workCeiling: 8),
      semantics: CollectionSemanticProbe(),
    );

    expect(result, isA<CollectionUnrollRefused>());
    expect(
      (result as CollectionUnrollRefused).reason,
      CollectionUnrollRefusal.workLimitExceeded,
    );
  });

  test('one list budget counts collection, source, binding, and callback work',
      () async {
    final expression = await parseExpressionFromSourceForTest('''
      Object x() => [for (final item in items) item];
    ''');
    final source = await parseExpressionForTest('alias');
    final extra = await parseExpressionForTest('extra');
    final list = await parseExpressionForTest('[1]');
    final semantics = CollectionSemanticProbe(
      sourceFor: (expression) => switch (expression.toSource()) {
        'items' => source,
        'alias' => list,
        _ => null,
      },
    );

    final atLimit = expandCollectionElement(
      _singleCollectionElement(expression),
      semantics: semantics,
      budget: CollectionUnrollBudget(workCeiling: 8),
    );
    final overLimit = expandCollectionElement(
      _singleCollectionElement(expression),
      semantics: CollectionSemanticProbe(
        sourceFor: (expression) => switch (expression.toSource()) {
          'items' => source,
          'alias' => extra,
          'extra' => list,
          _ => null,
        },
      ),
      budget: CollectionUnrollBudget(workCeiling: 8),
    );

    expect(atLimit, isA<CollectionUnrollExpansion>());
    expect((atLimit as CollectionUnrollExpansion).occurrences, hasLength(1));
    expect(overLimit, isA<CollectionUnrollRefused>());
    expect(
      (overLimit as CollectionUnrollRefused).reason,
      CollectionUnrollRefusal.workLimitExceeded,
    );
  });

  test('callback AST nodes consume semantic work', () async {
    final expression = await parseExpressionForTest('1');
    final semantics = CollectionSemanticProbe();

    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 0),
      ),
      CollectionCallbackProbeResult.workLimitExceeded,
    );
    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 1),
      ),
      CollectionCallbackProbeResult.absent,
    );
  });

  test('parenthesis edges consume semantic work', () async {
    final expression = await parseExpressionForTest('(1)');
    final semantics = CollectionSemanticProbe();

    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 2),
      ),
      CollectionCallbackProbeResult.workLimitExceeded,
    );
    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 3),
      ),
      CollectionCallbackProbeResult.absent,
    );
  });

  test('helper edges consume semantic work', () async {
    final expression = await parseExpressionForTest('helper()');
    final body = await parseExpressionForTest('1');
    final semantics = CollectionSemanticProbe(
      helperFor: (_) => CollectionResolvedHelper(
        body: body,
        parameterBindings: const {},
      ),
    );

    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 2),
      ),
      CollectionCallbackProbeResult.workLimitExceeded,
    );
    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 3),
      ),
      CollectionCallbackProbeResult.absent,
    );
  });

  test('conditional edges consume semantic work', () async {
    final expression = await parseExpressionForTest('true ? 1 : 2');
    final semantics = CollectionSemanticProbe();

    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 4),
      ),
      CollectionCallbackProbeResult.workLimitExceeded,
    );
    expect(
      semantics.callbacksIn(
        expression,
        budget: CollectionUnrollBudget(workCeiling: 5),
      ),
      CollectionCallbackProbeResult.absent,
    );
  });

  test('zero-output Cartesian traversal is bounded independently', () async {
    final values = _integerSequence(16);
    final expression = await parseExpressionFromSourceForTest(
      'Object x() => [\n'
      'for (final a in const [$values]) '
      'for (final b in const [$values]) '
      'for (final c in const [$values]) '
      'if (false) a];',
    );
    final unroll = expandCollectionElement(
      _singleCollectionElement(expression),
    );
    final result = _scalarTranslator().translate(expression);

    expect(unroll, isA<CollectionUnrollRefused>());
    expect(
      (unroll as CollectionUnrollRefused).reason,
      CollectionUnrollRefusal.workLimitExceeded,
    );
    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('static expansion steps'));
    expect(result.dsl, '[]');
  });

  test('plain siblings share work remaining after zero-output flow', () async {
    final loopValues = _integerSequence(15);
    final plainValues = _integerSequence(770);
    final expression = await parseExpressionFromSourceForTest(
      'Object x() => [\n'
      'for (final a in const [$loopValues]) '
      'for (final b in const [$loopValues]) '
      'for (final c in const [$loopValues]) '
      'if (false) a, $plainValues];',
    );
    final result = _scalarTranslator().translate(expression);

    expect(result.issues, hasLength(1));
    expect(result.issues.single.message, contains('static expansion steps'));
    expect(result.dsl, '[${_integerSequence(769)}]');
  });

  test(
    'a refusal points at the offending element rather than its list',
    () async {
      const source = 'final values = <int>[];\n'
          'Object x() => [\n'
          '  for (final value in values) value,\n'
          '];';
      final expression = await parseExpressionFromSourceForTest(source);
      final result = _scalarTranslator().translate(
        expression,
        sourcePath: 'lib/collection_location.dart',
        lineInfo: LineInfo.fromContent(source),
      );

      expect(result.issues, hasLength(1));
      expect(
        result.issues.single.location,
        startsWith('lib/collection_location.dart:3:'),
      );
      expect(
        result.issues.single.location,
        isNot(startsWith('lib/collection_location.dart:2:')),
      );
    },
  );

  test(
    'a loop variable shadows a same-named constructor parameter',
    () async {
      final expression = await parseExpressionFromSourceForTest('''
      Object x(String label) => [
        for (final label in const ['inside']) label,
      ];
    ''');
      final result = _scalarTranslator().translate(expression);

      expect(result.dsl, '["inside"]');
      expect(result.dsl, isNot(contains('args.label')));
      expect(result.issues, isEmpty);
    },
  );

  test(
    'loop bindings shadow same-named top-level constants in scalar and '
    'slot paths',
    () async {
      final expression = await parseExpressionFromSourceForTest(
        '''
import 'package:flutter/widgets.dart';

const String label = 'outside';
const MainAxisAlignment alignment = MainAxisAlignment.end;

Object x() => Column(
  children: [
    for (final label in const ['inside']) Text(text: label),
    for (final alignment in const [MainAxisAlignment.center])
      Column(
        mainAxisAlignment: alignment,
        children: const [],
      ),
  ],
);
''',
        rootPackage: 'apps_examples',
      );
      final result = _widgetTranslator(HelperRegistry()).translate(expression);

      expect(result.issues, isEmpty);
      _expectShadowedLoopOutput(result.dsl);
    },
  );

  test(
    'loop bindings shadow custom-widget arguments in scalar and slot paths',
    () async {
      final expression = await _parseProbeBuildExpressionForTest('''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Collection fixture.',
)
class Probe extends StatelessWidget {
  const Probe({required this.label, required this.alignment});

  final String label;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final label in const ['inside']) Text(text: label),
      for (final alignment in const [MainAxisAlignment.center])
        Column(
          mainAxisAlignment: alignment,
          children: const [],
        ),
    ],
  );
}
''');
      final result = _widgetTranslator(HelperRegistry()).translate(expression);

      expect(result.issues, isEmpty);
      _expectShadowedLoopOutput(result.dsl);
    },
  );

  test(
    'loop bindings shadow leading build locals in scalar and slot paths',
    () async {
      final expression = await _parseProbeBuildExpressionForTest('''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Collection fixture.',
)
class Probe extends StatelessWidget {
  const Probe();

  @override
  Widget build(BuildContext context) {
    final String label = 'outside';
    final MainAxisAlignment alignment = MainAxisAlignment.end;
    return Column(
      children: [
        for (final label in const ['inside']) Text(text: label),
        for (final alignment in const [MainAxisAlignment.center])
          Column(
            mainAxisAlignment: alignment,
            children: const [],
          ),
      ],
    );
  }
}
''');
      final result = _widgetTranslator(HelperRegistry()).translate(expression);

      expect(result.issues, isEmpty);
      _expectShadowedLoopOutput(result.dsl);
    },
  );

  test('an authored collection-for matches a hand-written list', () async {
    final translator = _scalarTranslator();
    final unrolledResult = translator.translate(
      await parseExpressionFromSourceForTest('''
        Object x() => [for (final value in const [1, 2, 3]) value];
      '''),
    );
    final handWrittenResult = translator.translate(
      await parseExpressionForTest('[1, 2, 3]'),
    );

    expect(unrolledResult.issues, isEmpty);
    expect(handWrittenResult.issues, isEmpty);
    expect(unrolledResult.dsl, handWrittenResult.dsl);
  });
}

ExpressionTranslator _scalarTranslator() => ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );

ExpressionTranslator _widgetTranslator(HelperRegistry helpers) {
  return ExpressionTranslator(
    catalog: catalogWith([
      entry(
        name: 'Text',
        category: WidgetCategory.decoration,
        properties: [
          prop('text', PropertyType.string, required: true),
        ],
      ),
      entry(
        name: 'Column',
        childrenSlot: ChildrenSlot.list,
        properties: [
          prop('children', PropertyType.widgetList),
          prop('mainAxisAlignment', PropertyType.enumValue),
        ],
      ),
      entry(
        name: 'Row',
        childrenSlot: ChildrenSlot.list,
        properties: [
          prop('children', PropertyType.widgetList),
        ],
      ),
      entry(
        name: 'SizedBox',
        category: WidgetCategory.decoration,
        properties: const [],
      ),
      entry(
        name: 'GestureDetector',
        properties: [
          prop('child', PropertyType.widget),
          prop('onTap', PropertyType.event),
        ],
      ),
    ]),
    helpers: helpers,
  );
}

CollectionElement _singleCollectionElement(Expression expression) {
  final literal = expression as ListLiteral;
  return literal.elements.single;
}

ListLiteral _childrenList(Expression expression) {
  final construction = expression as InstanceCreationExpression;
  final argument = construction.argumentList.arguments
      .whereType<NamedExpression>()
      .singleWhere((argument) => argument.name.label.name == 'children');
  return argument.expression as ListLiteral;
}

Future<_ResolvedBuildProbe> _mixedReceiverProbe() =>
    _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class GestureDetector extends Widget {
  const GestureDetector({required this.child, this.onTap, this.onDoubleTap});
  final Widget child;
  final void Function()? onTap;
  final void Function()? onDoubleTap;
}
class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}
class Probe extends Widget {
  const Probe(this.selectConstant);
  final bool selectConstant;

  Widget build(BuildContext context) => Column(
    children: [
      ...(selectConstant
            ? const WidgetSet(<Widget>[Text(text: 'constant')])
            : WidgetSet(<Widget>[
                GestureDetector(
                  child: const Text(text: 'runtime'),
                  onTap: () {},
                ),
              ]))
          .widgets,
    ],
  );
}
''');

CollectionSemanticProbe _collectionSemanticsFor(_ResolvedBuildProbe probe) =>
    CollectionSemanticProbe(
      bindingFor: (identifier) =>
          probe.inlined.localBindings[identifier.element],
      helperFor: (invocation) {
        final definition = probe.inlined.helpers[invocation.methodName.element];
        if (definition == null) return null;
        final bindings = bindHelperArguments(
          definition.params,
          invocation.argumentList.arguments.toList(),
        );
        if (bindings == null) return null;
        return CollectionResolvedHelper(
          body: definition.body,
          parameterBindings: bindings,
        );
      },
    );

String _integerSequence(int count) =>
    List<String>.generate(count, (index) => '$index').join(', ');

Future<TranslationResult> _translateInlinedProbe(String members) async =>
    (await _attemptInlinedProbe(members)).single;

Future<List<TranslationResult>> _attemptInlinedProbe(
  String members, {
  List<String> names = const ['Probe'],
}) async {
  final probe = await _parseResolvedProbeBuildForTest('''
class BuildContext {}
abstract class Widget { const Widget(); }
class Text extends Widget {
  const Text({required this.text});
  final String text;
}
class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}
class GestureDetector extends Widget {
  const GestureDetector({required this.child, this.onTap});
  final Widget child;
  final void Function()? onTap;
}
class TileSet {
  const TileSet(this.tile);
  final Widget tile;
}
class Color {
  const Color(this.value);
  final int value;
}
class LinearGradient {
  const LinearGradient({required this.colors, this.stops});
  final List<Color> colors;
  final List<double>? stops;
}
class RadialGradient {
  const RadialGradient({required this.colors, this.stops});
  final List<Color> colors;
  final List<double>? stops;
}
class SweepGradient {
  const SweepGradient({required this.colors, this.stops});
  final List<Color> colors;
  final List<double>? stops;
}
class StopSet {
  const StopSet(this.values);
  final List<double> values;
}
class GradientBox extends Widget {
  const GradientBox({required this.gradient});
  final LinearGradient gradient;
}
void Function() paywallEvent(String name) => () {};
class Probe extends Widget {
  const Probe();
$members
}
''');
  const key = 'package:restage_codegen/_collection_probe.dart#Probe';
  final classification = ComposableWidget(
    key,
    requiredMechanisms: const {},
    composedCustomWidgets: const [],
  );
  final helpers = HelperRegistry()..registerAll([_eventHelper]);
  final translator = ExpressionTranslator.forTesting(
    catalog: catalogWith([
      entry(
        name: 'Text',
        category: WidgetCategory.decoration,
        properties: [
          prop('text', PropertyType.string, required: true),
        ],
      ),
      entry(
        name: 'Column',
        childrenSlot: ChildrenSlot.list,
        properties: [prop('children', PropertyType.widgetList)],
      ),
      entry(
        name: 'GestureDetector',
        properties: [
          prop('child', PropertyType.widget),
          prop('onTap', PropertyType.event),
          prop('onDoubleTap', PropertyType.event),
        ],
      ),
      entry(
        name: 'GradientBox',
        properties: [prop('gradient', PropertyType.gradient)],
      ),
    ]),
    helpers: helpers,
    frameworkLibraryPredicate: (element) =>
        syntheticFrameworkLibrary(element) ||
        element?.library?.identifier ==
            'package:restage_codegen/_collection_probe.dart',
  );
  return [
    for (final name in names)
      translator.attemptInlineEmit(
        classification,
        CustomWidgetBlueprint(
          classKey: key,
          rfwName: name,
          buildExpression: probe.expression,
          params: const [],
          inlined: probe.inlined,
        ),
      ),
  ];
}

void _expectCallbackRefusal(TranslationResult result) {
  expect(result.issues, hasLength(1));
  expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
  expect(result.issues.single.message, contains('share one callback identity'));
  expect(result.widgetDefinitions['Probe'], 'Column(children: [])');
  expect(result.widgetDefinitions['Probe'], isNot(contains('event "tap"')));
}

void _expectShadowedLoopOutput(String dsl) {
  expect(
    dsl,
    'Column(children: [Text(text: "inside"), '
    'Column(mainAxisAlignment: "center", children: [])])',
  );
  expect(dsl, isNot(contains('args.')));
  expect(dsl, isNot(contains('"outside"')));
  expect(dsl, isNot(contains('"end"')));
}

Future<Expression> _parseProbeBuildExpressionForTest(String source) async {
  final probe = await _parseResolvedProbeBuildForTest(
    source,
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  return probe.expression;
}

Future<_ResolvedBuildProbe> _parseResolvedProbeBuildForTest(
  String source, {
  String rootPackage = 'restage_codegen',
  bool includeFlutter = false,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
    includeFlutter: includeFlutter,
  );
  final assetKey = '$rootPackage|lib/_collection_probe.dart';
  readerWriter.testing.writeString(AssetId.parse(assetKey), source);

  _ResolvedBuildProbe? result;
  await testBuilder(
    _BuildExpressionCapturingBuilder(
      onLibrary: (library) async {
        final resolved = await library.session.getResolvedLibraryByElement(
          library,
        );
        if (resolved is! ResolvedLibraryResult) return;
        final probe = library.classes.firstWhere(
          (element) => element.name == 'Probe',
        );
        final declaration =
            resolved.getFragmentDeclaration(probe.firstFragment)?.node;
        if (declaration is! ClassDeclaration) return;
        final build = declaration.body.members
            .whereType<MethodDeclaration>()
            .firstWhere((member) => member.name.lexeme == 'build');
        final expression = _returnedExpression(build.body);
        if (expression == null) return;
        final localBindings = <Element, Expression>{};
        if (build.body case BlockFunctionBody(:final block)) {
          for (final statement
              in block.statements.whereType<VariableDeclarationStatement>()) {
            for (final variable in statement.variables.variables) {
              final element = variable.declaredFragment?.element;
              final initializer = variable.initializer;
              if (element != null && initializer != null) {
                localBindings[element] = initializer;
              }
            }
          }
        }
        final helperDefinitions = <Element, HelperDef>{};
        for (final member
            in declaration.body.members.whereType<MethodDeclaration>()) {
          if (member.name.lexeme == 'build') continue;
          final element = member.declaredFragment?.element;
          final body = _returnedExpression(member.body);
          if (element is ExecutableElement && body != null) {
            helperDefinitions[element] = HelperDef(
              params: element.formalParameters.toList(),
              body: body,
            );
          }
        }
        result = _ResolvedBuildProbe(
          expression: expression,
          inlined: InlinedDefinitions(
            localBindings: localBindings,
            helpers: helperDefinitions,
          ),
        );
      },
      allowedAssetIds: {AssetId.parse(assetKey)},
    ),
    {assetKey: source},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );
  if (result == null) {
    throw StateError('Failed to parse Probe.build expression from source.');
  }
  return result!;
}

Expression? _returnedExpression(FunctionBody body) {
  if (body is ExpressionFunctionBody) return body.expression;
  if (body is BlockFunctionBody) {
    for (final statement in body.block.statements) {
      if (statement is ReturnStatement && statement.expression != null) {
        return statement.expression;
      }
    }
  }
  return null;
}

final class _ResolvedBuildProbe {
  const _ResolvedBuildProbe({
    required this.expression,
    required this.inlined,
  });

  final Expression expression;
  final InlinedDefinitions inlined;
}

final class _BuildExpressionCapturingBuilder implements Builder {
  _BuildExpressionCapturingBuilder({
    required this.onLibrary,
    required this.allowedAssetIds,
  });

  final Future<void> Function(LibraryElement library) onLibrary;
  final Set<AssetId> allowedAssetIds;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.collectionprobe'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (!allowedAssetIds.contains(step.inputId)) return;
    await onLibrary(await step.inputLibrary);
  }
}
