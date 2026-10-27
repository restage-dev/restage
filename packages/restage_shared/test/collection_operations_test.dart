import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('collections retain native identity and opaque container refusals', () {
    const native = ValueType.native('example.Model');
    const other = ValueType.native('example.Other');
    expect(ValueType.fromJson(native.toJson()).accepts(native), isTrue);
    expect(native.accepts(other), isFalse);
    expect(isNativeCollectionItem(native), isFalse);
    for (final type in [
      const ValueType('list', item: native),
      const ValueType('iterable', item: native),
      const ValueType('record', fields: {'model': native}),
    ]) {
      final program = ValueProgram(
          nodes: [ValueNode('parameter', type, name: 'p')],
          parameters: {'p': type},
          root: 0);
      expect(program.validate, throwsFormatException);
    }
    for (final op in ['==', '!=', 'string']) {
      final program = ValueProgram(nodes: [
        const ValueNode('parameter', native, name: 'p'),
        ValueNode(op, op == 'string' ? ValueType.string : ValueType.boolean,
            inputs: op == 'string' ? [0] : [0, 0]),
      ], parameters: const {
        'p': native
      }, root: 1);
      expect(program.validate, throwsFormatException, reason: op);
    }
  });
  test('lazy collection callbacks retain the installed native call registry',
      () {
    const contract = NativeBindingContract(
        type: 'example.Double',
        call: NativeCallContract(
            inputs: [ValueType.integer],
            result: ValueType.integer,
            implementation: 'double-v1'));
    var calls = 0;
    final operations = <String, ValueOperation>{
      ...kCollectionValueOperations,
      'native.call': NativeCallValueOperation({'double': contract},
          invoke: (binding, declaration, inputs, captures, frame) {
        calls++;
        return (inputs.single! as int) * 2;
      }),
    };
    final callback = ValueProgram(nodes: [
      const ValueNode('parameter', ValueType.integer, name: 'arg0'),
      ValueNode('native.call', ValueType.integer, inputs: [
        0
      ], value: {
        'binding': 'double',
        'contract': contract.toJson(),
        'captures': <String, String>{},
      }),
    ], parameters: const {
      'arg0': ValueType.integer
    }, root: 1);
    final program = ValueProgram(nodes: [
      const ValueNode('literal', ValueType.integer, value: 3),
      const ValueNode('list', ValueType('list', item: ValueType.integer),
          inputs: [0]),
      ValueNode('collection.map',
          const ValueType('iterable', item: ValueType.integer),
          inputs: [
            1
          ],
          value: {
            'arguments': <int>[],
            'item': ValueType.integer.toJson(),
            'callbacks': [
              {'program': callback.encode(), 'bindings': <int>[]},
            ]
          }),
    ], root: 2);
    final decoded =
        ValueProgram.decode(program.encode(), operations: operations);
    expect(valueProgramRequiredCapability(decoded, operations: operations), 24);
    final result = ValueEvaluator(decoded,
            captures: _NoCaptures(), parameters: {}, operations: operations)
        .evaluate()! as Iterable;
    expect(calls, 0);
    expect(result.length, 1);
    expect(calls, 0);
    expect(result.toList(), [6]);
    expect(result.toList(), [6]);
    expect(calls, 2);
  });
  test('internal iterable cannot enter through literals or external inputs',
      () {
    const iterable = ValueType('iterable', item: ValueType.integer);
    for (final program in [
      const ValueProgram(
          nodes: [ValueNode('literal', iterable, value: <int>[])], root: 0),
      const ValueProgram(
          nodes: [ValueNode('capture', iterable, name: 'c')],
          root: 0,
          captures: {'c': iterable}),
      const ValueProgram(
          nodes: [ValueNode('parameter', iterable, name: 'p')],
          root: 0,
          parameters: {'p': iterable}),
    ]) expect(program.validate, throwsFormatException);
  });
  test('forged sort cannot mutate a borrowed native list', () {
    final values = [3, 1, 2];
    final sort = kCollectionValueOperations['collection.sort']!;
    expect(
        () => sort.evaluate([
              values
            ], {
              'arguments': <int>[],
              'callbacks': <Object?>[],
              'item': ValueType.integer.toJson()
            }),
        throwsStateError);
    expect(values, [3, 1, 2]);
  });
  test('collection types retain shape depth and literal restrictions', () {
    expect(
        () => ValueType.fromJson({'kind': 'iterable'}), throwsFormatException);
    expect(
        ValueType.fromJson(
                const ValueType('iterable', item: ValueType.integer).toJson())
            .item
            ?.kind,
        'int');
  });
}

final class _NoCaptures implements ValueReader {
  @override
  int length(List<Object> path) => throw StateError('Unexpected capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected capture');
}
