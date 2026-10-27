import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final class _Reader implements ValueReader {
  @override
  int length(List<Object> path) => throw StateError('Unexpected capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected capture');
}

final class _ReadCount implements ValueOperation {
  int calls = 0;
  @override
  String get name => 'test.read';
  @override
  int get capability => 19;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {}
  @override
  Object evaluate(List<Object?> inputs, Object? options) => ++calls;
}

final class _Deferred implements RegistryValueOperation {
  final callbacks = <Object? Function()>[];
  @override
  String get name => 'test.defer';
  @override
  int get capability => 19;
  ValueProgram program(Object? encoded, ValueOperationContext context) =>
      ValueProgram.decode(encoded! as String,
          operations: context.operations, context: context.nested());
  @override
  Iterable<ValueProgram> nestedPrograms(
          ValueNode node, ValueOperationContext context) =>
      [program(node.value, context)];
  @override
  void validateWithContext(
      ValueNode node, List<ValueType> inputs, ValueOperationContext context) {
    program(node.value, context);
  }

  @override
  Object evaluateWithContext(
      List<Object?> inputs, Object? options, ValueOperationContext context) {
    final nested = program(options, context);
    callbacks.add(() => ValueEvaluator(nested,
            captures: _Reader(),
            parameters: {},
            operations: context.operations,
            context: context.nested())
        .evaluate());
    return 0;
  }

  @override
  void validate(ValueNode node, List<ValueType> inputs) =>
      throw UnimplementedError();
  @override
  Object evaluate(List<Object?> inputs, Object? options) =>
      throw UnimplementedError();
}

void main() {
  test('deferred callbacks retain live cells and separate parent invocations',
      () {
    const nested = ValueProgram(
        nodes: [ValueNode('local.read', ValueType.integer, name: 'factor')],
        root: 0,
        outerLocals: {'factor': ValueType.integer});
    final deferred = _Deferred();
    final operations = {'test.defer': deferred};
    final program = ValueProgram(locals: const {
      'factor': ValueType.integer
    }, nodes: [
      const ValueNode('literal', ValueType.integer, value: 1),
      const ValueNode('local.write', ValueType.integer,
          inputs: [0], name: 'factor'),
      ValueNode('test.defer', ValueType.integer, value: nested.encode()),
      const ValueNode('literal', ValueType.integer, value: 2),
      const ValueNode('local.write', ValueType.integer,
          inputs: [3], name: 'factor'),
      const ValueNode('let', ValueType.integer, inputs: [2, 4]),
      const ValueNode('let', ValueType.integer, inputs: [1, 5]),
    ], root: 6);
    final first = ValueEvaluator(program,
        captures: _Reader(), parameters: {}, operations: operations);
    expect(first.evaluate(), 2);
    expect(deferred.callbacks.single(), 2);
    first.frame.write('factor', 3);
    expect(deferred.callbacks.single(), 3);
    final second = ValueEvaluator(program,
        captures: _Reader(), parameters: {}, operations: operations);
    expect(second.evaluate(), 2);
    expect(deferred.callbacks.map((read) => read()), [3, 2]);
    expect(valueProgramRequiredCapability(program, operations: operations), 24);
  });
  test(
      'builder fork retains bound values but never hoists arbitrary cache entries',
      () {
    final count = _ReadCount();
    const values = ValueProgram(
        nodes: [
          ValueNode('test.read', ValueType.integer),
          ValueNode('test.read', ValueType.integer),
          ValueNode('literal', ValueType.integer, value: 2),
          ValueNode('+', ValueType.integer, inputs: [0, 1]),
        ],
        root: 3,
        parameters: {'i': ValueType.integer});
    const program = BuilderProgram(
        values: values,
        bodyCount: 1,
        collection: true,
        result: BuilderResult.let(
            0,
            BuilderResult.sequence([
              BuilderResult.body(0, values: {'value': 1}),
              BuilderResult.forEach(
                  2, 'i', BuilderResult.body(0, values: {'value': 3})),
            ])));
    final outputs = program.invokeAll(
        captures: _Reader(), parameters: {}, operations: {'test.read': count});
    expect(outputs.map((output) => output.values['value']), [2, 4, 5]);
    expect(count.calls, 4);
  });
  test('fork shares initialized outer locals and allocates iteration locals',
      () {
    const program = ValueProgram(locals: {
      'outer': ValueType.integer,
      'inner': ValueType.integer
    }, nodes: [
      ValueNode('literal', ValueType.integer, value: 1),
      ValueNode('local.write', ValueType.integer, name: 'outer', inputs: [0]),
      ValueNode('local.read', ValueType.integer, name: 'outer'),
    ], root: 1);
    final parent = ValueEvaluator(program, captures: _Reader(), parameters: {});
    parent.evaluate();
    final first = parent.fork(parameters: {});
    first.frame.write('outer', 2);
    first.frame.write('inner', 10);
    final second = parent.fork(parameters: {});
    expect(second.evaluate(2), 2);
    expect(() => second.frame.read('inner'), throwsStateError);
    second.frame.write('inner', 20);
    expect(first.frame.read('inner'), 10);
  });
  test('forged local slots and capture types fail closed', () {
    const program = ValueProgram(
        nodes: [ValueNode('local.read', ValueType.integer, name: 'unknown')],
        root: 0);
    expect(program.validate, throwsFormatException);
    const outer = ValueProgram(
        nodes: [ValueNode('local.read', ValueType.integer, name: 'known')],
        root: 0,
        outerLocals: {'known': ValueType.integer});
    expect(outer.validate, throwsFormatException);
    expect(
        () => outer.validate(
            context: const ValueOperationContext(
                locals: {'known': ValueType.string})),
        throwsFormatException);
  });
}
