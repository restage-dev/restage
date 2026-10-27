import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final class _EqualsTwo implements ValueOperation {
  int validations = 0;
  @override
  String get name => 'test.equalsTwo';
  @override
  int get capability => 23;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    validations++;
    if (inputs.length != 1 ||
        inputs.single.kind != 'int' ||
        node.type.kind != 'bool')
      throw const FormatException('Invalid test operation');
  }

  @override
  Object evaluate(List<Object?> inputs, Object? options) => inputs.single == 2;
}

final class _EmptyReader implements ValueReader {
  @override
  int length(List<Object> path) => 0;
  @override
  Object? read(List<Object> path, ValueType type) => type.kind == 'list'
      ? ValueListView(this, path, type.item!)
      : throw StateError('An unused outer value was read');
}

void main() {
  test('nested predicate validation and evaluation use the installed registry',
      () {
    const predicate = ValueProgram(
        nodes: [
          ValueNode('parameter', ValueType.integer, name: 'item'),
          ValueNode('test.equalsTwo', ValueType.boolean, inputs: [0]),
        ],
        root: 1,
        parameters: {'item': ValueType.integer});
    final program = ValueProgram(nodes: [
      const ValueNode('literal', ValueType.integer, value: 1),
      const ValueNode('literal', ValueType.integer, value: 2),
      const ValueNode('list', ValueType('list', item: ValueType.integer),
          inputs: [0, 1]),
      ValueNode('grid.indexWhere', ValueType.integer,
          inputs: const [2], value: predicate.encode()),
    ], root: 3);
    final operation = _EqualsTwo();
    final operations = {...kGridValueOperations, operation.name: operation};
    final decoded =
        ValueProgram.decode(program.encode(), operations: operations);
    expect(
        ValueEvaluator(decoded,
                captures: _EmptyReader(),
                parameters: const {},
                operations: operations)
            .evaluate(),
        1);
    expect(operation.validations, greaterThan(0));
    expect(valueProgramRequiredCapability(program, operations: operations), 23);
    expect(() => program.validate(operations: kGridValueOperations),
        throwsFormatException);
  });

  test('empty predicates leave outer values and key casts unused', () {
    const list = ValueType('list', item: ValueType.integer);
    const predicate = ValueProgram(
        nodes: [
          ValueNode('parameter', ValueType.integer, name: 'item'),
          ValueNode('parameter', ValueType.integer, name: 'outer0'),
          ValueNode('==', ValueType.boolean, inputs: [0, 1]),
        ],
        root: 2,
        parameters: {'item': ValueType.integer, 'outer0': ValueType.integer});
    final program = ValueProgram(
        nodes: [
          const ValueNode('capture', list, name: 'c0'),
          const ValueNode('literal', ValueType.integer, value: 0),
          const ValueNode('index', ValueType.integer, inputs: [0, 1]),
          ValueNode('grid.indexWhere', ValueType.integer,
              inputs: const [0, 2], value: predicate.encode()),
        ],
        root: 3,
        captures: const {'c0': list});
    expect(
        ValueEvaluator(program,
                captures: _EmptyReader(),
                parameters: const {},
                operations: kGridValueOperations)
            .evaluate(),
        -1);
  });

  test('key projection contract admits exact nullable scalar fields only', () {
    for (final kind in ['String', 'int', 'double', 'num', 'bool']) {
      for (final nullable in [false, true]) {
        final type = ValueType(kind, nullable: nullable);
        expect(
            isScalarCallbackParameterValueType(
                'arg0',
                ValueType('record',
                    fields: {'$kind${nullable ? '?' : ''}': type})),
            isTrue);
      }
    }
    expect(
        isScalarCallbackParameterValueType('arg0',
            const ValueType('record', fields: {'int': ValueType.number})),
        isFalse);
    expect(
        isScalarCallbackParameterValueType('arg0',
            const ValueType('record', fields: {'Object': ValueType.string})),
        isFalse);
  });
}
