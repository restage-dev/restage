import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/widget_collection_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _Reader implements ValueReader {
  _Reader(this.values);
  final Map<String, Object?> values;
  final List<String> reads = [];

  Object? _at(List<Object> path) {
    Object? result = values;
    for (final segment in path) {
      result = segment is int
          ? (result! as List)[segment]
          : (result! as Map)[segment];
    }
    return result;
  }

  @override
  int length(List<Object> path) {
    reads.add('${path.join('.')}.length');
    return (_at(path)! as List).length;
  }

  @override
  Object? read(List<Object> path, ValueType type) {
    if (const {'list', 'record'}.contains(type.kind)) {
      throw StateError('Unexpected aggregate read');
    }
    reads.add(path.join('.'));
    return _at(path);
  }
}

({BuilderProgram program, BuilderExpressionLowering expressions}) _compile(
  ListLiteral literal, {
  Expression Function(Expression)? resolve,
}) {
  final expressions = BuilderExpressionLowering(capture: (e) => e.toSource());
  var count = 0;
  final result = WidgetCollectionLowering(
    expressions: expressions,
    resolve: resolve,
    resultFor: (e) => BuilderResult.body(
      count++,
      values: {'label': expressions.lower(e)},
    ),
  ).lower(literal);
  final program = BuilderProgram(
    values: expressions.program(0),
    result: result,
    bodyCount: count,
    collection: true,
  );
  program.validate();
  return (program: program, expressions: expressions);
}

void main() {
  test(
      'for-in preserves nested lexical bindings, demand reads and source order',
      () async {
    final literal = await parseExpressionFromSourceForTest(r'''
class Row {
  final String title;
  final bool visible;
  final List<int> values;
  const Row(this.title, this.visible, this.values);
}
List<String> x(List<Row> rows, int divisor, bool show) => [
  'head',
  if (show) ...[
    for (final row in rows)
      if (row.visible) ...[
        '${row.title}:${12 ~/ divisor}',
        for (final row in row.values) 'inner$row',
        row.title,
      ] else 'hidden',
  ] else 'off',
  ...?(show ? ['tail'] : null),
  'done',
];
''') as ListLiteral;
    final compiled = _compile(literal);
    _Reader reader(bool show, int divisor) => _Reader({
          for (final capture in compiled.expressions.captureDsl.entries)
            capture.key: switch (capture.value) {
              'show' => show,
              'divisor' => divisor,
              'rows' => [
                  {
                    'title': 'a',
                    'visible': true,
                    'values': [7, 8]
                  },
                  {
                    'title': 'b',
                    'visible': false,
                    'values': [9]
                  },
                  {'title': 'c', 'visible': true, 'values': <int>[]},
                ],
              _ => throw StateError('Unexpected capture ${capture.value}'),
            },
        });
    List<Object?> invoke(_Reader reader) => compiled.program
        .invokeAll(captures: reader, parameters: {})
        .map((i) => i.values['label'])
        .toList();
    final selected = reader(true, 3);
    expect(invoke(selected), [
      'head',
      'a:4',
      'inner7',
      'inner8',
      'a',
      'hidden',
      'c:4',
      'c',
      'tail',
      'done',
    ]);
    final rows = compiled.expressions.captureDsl.entries
        .singleWhere((e) => e.value == 'rows')
        .key;
    expect(selected.reads, isNot(contains('$rows.1.title')));
    expect(selected.reads, isNot(contains('$rows.1.values.length')));
    expect(selected.reads.indexOf('$rows.0.title'),
        lessThan(selected.reads.indexOf('$rows.1.visible')));
    final skipped = reader(false, 0);
    expect(invoke(skipped), ['head', 'off', 'done']);
    expect(skipped.reads.toSet(), {
      compiled.expressions.captureDsl.entries
          .singleWhere((e) => e.value == 'show')
          .key,
    });
    expect(compiled.program.iterationParameters, hasLength(2));
    expect(compiled.expressions.bindings, isEmpty);
    expect(BuilderProgram.decode(compiled.program.encode()).collection, isTrue);
  });

  test('independent collection branches produce a linear result graph',
      () async {
    final literal = await parseExpressionFromSourceForTest('''
List<String> x(bool show) => [
  ${List.generate(18, (i) => "if (show) 'item$i'").join(',\n')},
];
''') as ListLiteral;
    final compiled = _compile(literal);
    int cost(BuilderResult result) =>
        1 + result.descendants.fold(0, (sum, c) => sum + cost(c));
    expect(compiled.program.bodyCount, 18);
    expect(cost(compiled.program.result), 55);
    expect(compiled.expressions.captureTypes, hasLength(1));
  });

  test('spread aliases resolve into the same graph and detect cycles',
      () async {
    final literal = await parseExpressionFromSourceForTest('''
const labels = ['one', 'two'];
List<String> x() => ['before', ...labels, 'after'];
''') as ListLiteral;
    final alias = (literal.root as CompilationUnit)
        .declarations
        .whereType<TopLevelVariableDeclaration>()
        .single
        .variables
        .variables
        .single
        .initializer!;
    final compiled = _compile(literal,
        resolve: (e) =>
            e is SimpleIdentifier && e.name == 'labels' ? alias : e);
    expect(
        compiled.program.invokeAll(
            captures: _Reader({}),
            parameters: {}).map((i) => i.values['label']),
        ['before', 'one', 'two', 'after']);
    final spread = (literal.elements[1] as SpreadElement).expression;
    expect(
        () => _compile(literal,
            resolve: (e) => identical(e, spread) ? literal : e),
        throwsA(isA<BuilderLoweringException>()));
  });

  test('unsupported loop forms and opaque widget spreads refuse at the source',
      () async {
    final counted = await parseExpressionFromSourceForTest(r'''
List<String> x() => [for (var i = 0; i < 3; i++) '$i'];
''') as ListLiteral;
    expect(
        () => _compile(counted),
        throwsA(isA<BuilderLoweringException>()
            .having((e) => e.node, 'source', same(counted.elements.single))));
    final opaque = await parseExpressionFromSourceForTest('''
List<String> x(List<String> widgets) => [...widgets];
''') as ListLiteral;
    expect(
        () => _compile(opaque),
        throwsA(isA<BuilderLoweringException>().having((e) => e.node, 'source',
            same((opaque.elements.single as SpreadElement).expression))));
  });
}
