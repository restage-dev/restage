import 'dart:collection';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final class _Reader implements ValueReader {
  _Reader(this.data);
  final Map<String, Object?> data;
  final List<List<Object>> reads = [];
  Object? at(List<Object> path) {
    Object? v = data;
    for (final p in path) {
      v = p is int ? (v as List)[p] : (v as Map)[p];
    }
    return v;
  }

  @override
  Object? read(List<Object> path, ValueType type) {
    reads.add(path);
    return at(path);
  }

  @override
  int length(List<Object> path) => (at(path) as List).length;
}

final class _LazyContextParameters extends MapBase<String, Object?> {
  @override
  Iterable<String> get keys => ['context:device:screenWidth'];
  @override
  Object? operator [](Object? key) =>
      throw StateError('Unused native context was read');
  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('immutable');
  @override
  void clear() => throw UnsupportedError('immutable');
  @override
  Object? remove(Object? key) => throw UnsupportedError('immutable');
}

void main() {
  test('native key references require their exact inert declaration shape', () {
    BuilderProgram program(ValueType type) => BuilderProgram(
          values: ValueProgram(
              nodes: [ValueNode('capture', type, name: 'key')],
              root: 0,
              captures: {'key': type}),
          result: const BuilderResult.body(0, key: 0, keyType: 'nativeBinding'),
          bodyCount: 1,
        );
    expect(
        () => BuilderProgram.decode(
            program(nativeBindingReferenceValueType).encode()),
        returnsNormally);
    for (final type in [
      ValueType.string,
      const ValueType('record', fields: {'key': ValueType.string}),
      ValueType('record',
          nullable: true, fields: nativeBindingReferenceValueType.fields),
      ValueType('record', fields: {
        ...nativeBindingReferenceValueType.fields,
        'extra': ValueType.string
      }),
    ]) {
      expect(() => program(type).validate(), throwsFormatException);
    }
  });

  test('collection iteration never materializes unused context parameters', () {
    const values = ValueProgram(
        nodes: [
          ValueNode('literal', ValueType.integer, value: 2),
          ValueNode('literal', ValueType.boolean, value: false),
          ValueNode('parameter', ValueType.real,
              name: 'context:device:screenWidth'),
        ],
        root: 2,
        parameters: {
          'context:device:screenWidth': ValueType.real,
          'i': ValueType.integer
        });
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.forEach(
            0,
            'i',
            BuilderResult.branch(1, BuilderResult.body(0, values: {'width': 2}),
                BuilderResult.sequence([]))),
        bodyCount: 1,
        collection: true);
    expect(
        program.invokeAll(
            captures: _Reader({}), parameters: _LazyContextParameters()),
        isEmpty);
    expect(builderContextLocation('context:ancestor:2:theme:brightness'),
        (ancestorDepth: 2, name: 'context:theme:brightness'));
    expect(builderContextValueType('context:ancestor:2:theme:brightness')!.kind,
        'String');
    for (final name in [
      'context:ancestor:0:theme:brightness',
      'context:ancestor:01:theme:brightness',
      'context:ancestor:65:theme:brightness',
      'context:ancestor:1:theme:unknown'
    ]) {
      expect(builderContextValueType(name), isNull);
    }
  });
  test(
      'key generic types, explicit null presence and builtin metadata are validated',
      () {
    const nullable = ValueType('String', nullable: true);
    const values = ValueProgram(
        nodes: [ValueNode('literal', nullable, value: null)], root: 0);
    expect(
        () => const BuilderProgram(
                values: values,
                result: BuilderResult.body(0, key: 0),
                bodyCount: 1)
            .validate(),
        throwsFormatException);
    final nullableKey = BuilderProgram.decode(const BuilderProgram(
                values: values,
                result: BuilderResult.body(0, key: 0, keyType: 'String?'),
                bodyCount: 1)
            .encode())
        .invoke(captures: _Reader({}), parameters: {});
    expect(nullableKey.hasKey, isTrue);
    expect(nullableKey.projectedKey, isNull);
    expect(nullableKey.keyType, 'String?');
    expect(
        () => BuilderResult.fromJson(
            {'kind': 'body', 'body': 0, 'values': <String, int>{}, 'key': 0}),
        throwsFormatException);

    expect(
        () => const ValueProgram(nodes: [
              ValueNode('literal', ValueType.integer, value: 1),
              ValueNode('negate', ValueType.integer,
                  inputs: [0], name: 'unregistered')
            ], root: 1)
                .validate(),
        throwsFormatException);
  });

  test('nullable indexed callback checks termination before demanding item',
      () {
    const item = ValueType('record', fields: {'title': ValueType.string});
    const list = ValueType('list', item: item);
    const values = ValueProgram(
        nodes: [
          ValueNode('capture', list, name: 'items'),
          ValueNode('parameter', ValueType.integer, name: 'arg1'),
          ValueNode('length', ValueType.integer, inputs: [0]),
          ValueNode('>=', ValueType.boolean, inputs: [1, 2]),
          ValueNode('index', item, inputs: [0, 1]),
          ValueNode('field', ValueType.string, inputs: [4], name: 'title'),
        ],
        root: 5,
        captures: {'items': list},
        parameters: {'arg1': ValueType.integer});
    final program = BuilderProgram.decode(const BuilderProgram(
            values: values,
            result: BuilderResult.branch(3, BuilderResult.nullResult(),
                BuilderResult.body(0, values: {'title': 5})),
            bodyCount: 1,
            nullableResult: true)
        .encode());
    final reader = _Reader({
      'items': List.generate(10000, (i) => {'title': 'item $i'})
    });
    expect(program.invoke(captures: reader, parameters: {'arg1': 10000}).isNull,
        isTrue);
    expect(reader.reads, isEmpty);
    expect(program.invoke(captures: reader, parameters: {'arg1': 31}).values,
        {'title': 'item 31'});
    expect(reader.reads, [
      ['items', 31, 'title']
    ]);
  });
  test('lazy booleans and branches do not divide by zero', () {
    const nodes = [
      ValueNode('literal', ValueType.boolean, value: false),
      ValueNode('literal', ValueType.integer, value: 1),
      ValueNode('literal', ValueType.integer, value: 0),
      ValueNode('~/', ValueType.integer, inputs: [1, 2]),
      ValueNode('==', ValueType.boolean, inputs: [3, 1]),
      ValueNode('&&', ValueType.boolean, inputs: [0, 4]),
      ValueNode('conditional', ValueType.integer, inputs: [0, 3, 1])
    ];
    final reader = _Reader({});
    expect(
        ValueEvaluator(const ValueProgram(nodes: nodes, root: 5),
            captures: reader, parameters: {}).evaluate(),
        false);
    expect(
        ValueEvaluator(const ValueProgram(nodes: nodes, root: 6),
            captures: reader, parameters: {}).evaluate(),
        1);
  });
  test('null coalescing and eager immutable locals preserve Dart order', () {
    const nodes = [
      ValueNode('literal', ValueType.integer, value: 1),
      ValueNode('literal', ValueType.integer, value: 0),
      ValueNode('~/', ValueType.integer, inputs: [0, 1]),
      ValueNode('??', ValueType.integer, inputs: [0, 2])
    ];
    const values = ValueProgram(nodes: nodes, root: 3);
    final reader = _Reader({});
    expect(
        ValueEvaluator(values, captures: reader, parameters: {}).evaluate(), 1);
    expect(
        () => const BuilderProgram(
                values: values,
                result: BuilderResult.let(2, BuilderResult.body(0)),
                bodyCount: 1)
            .invoke(captures: reader, parameters: {}),
        throwsA(isA<IntegerDivisionByZeroException>()));
  });
  test('unknown operations, cycles and invalid parameter reads fail closed',
      () {
    for (final node in [
      const ValueNode('eval', ValueType.string),
      const ValueNode('parameter', ValueType.string, name: 'secret'),
      const ValueNode('!', ValueType.boolean, inputs: [0])
    ]) {
      expect(() => ValueProgram(nodes: [node], root: 0).validate(),
          throwsFormatException);
    }
  });
}
