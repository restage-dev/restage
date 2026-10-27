import 'dart:collection';

import 'package:restage_shared/src/expressions/collection_operations.dart';

import 'package:restage_shared/src/expressions/value_program.dart';

/// Installed collection operations used by native index callbacks.
const Map<String, ValueOperation> kGridValueOperations = {
  'grid.indexWhere': _IndexWhere(),
};

final class _IndexWhere implements RegistryValueOperation {
  const _IndexWhere();
  @override
  String get name => 'grid.indexWhere';
  @override
  int get capability => 20;

  ValueProgram _program(Object? options, ValueOperationContext context) {
    if (options is! String) {
      throw const FormatException('Index predicate must be a value program');
    }
    if (context.depth >= 32) {
      throw const FormatException('Index predicate exceeds its nesting limit');
    }
    return ValueProgram.decode(options,
        operations: context.operations, context: context.nested());
  }

  @override
  Iterable<ValueProgram> nestedPrograms(
          ValueNode node, ValueOperationContext context) =>
      [_program(node.value, context)];

  @override
  void validate(ValueNode node, List<ValueType> inputs) => validateWithContext(
      node,
      inputs,
      const ValueOperationContext(operations: kGridValueOperations));

  @override
  void validateWithContext(
      ValueNode node, List<ValueType> inputs, ValueOperationContext context) {
    if (inputs.isEmpty ||
        inputs.first.kind != 'list' ||
        inputs.first.nullable ||
        node.type.kind != 'int' ||
        node.type.nullable) {
      throw const FormatException('Invalid index predicate inputs');
    }
    final predicate = _program(node.value, context);
    if (predicate.captures.isNotEmpty ||
        predicate.nodes[predicate.root].type.kind != 'bool' ||
        predicate.nodes[predicate.root].type.nullable ||
        predicate.parameters.length != inputs.length ||
        predicate.parameters['item']?.accepts(inputs.first.item!) != true) {
      throw const FormatException('Invalid index predicate program');
    }
    for (var i = 1; i < inputs.length; i++) {
      final parameter = predicate.parameters['outer${i - 1}'];
      if (parameter == null || !parameter.accepts(inputs[i])) {
        throw const FormatException('Invalid index predicate binding');
      }
    }
  }

  @override
  Object evaluate(List<Object?> inputs, Object? options) => evaluateWithContext(
      inputs,
      options,
      const ValueOperationContext(operations: kGridValueOperations));

  @override
  Object evaluateWithContext(
      List<Object?> inputs, Object? options, ValueOperationContext context) {
    final list = inputs.first! as List;
    final program = _program(options, context);
    return list.indexWhere((item) =>
        invokeClosedValueCallback(
            program, _PredicateParameters(item, inputs), context) ==
        true);
  }
}

final class _PredicateParameters extends MapBase<String, Object?> {
  _PredicateParameters(this.item, this.inputs);
  final Object? item;
  final List<Object?> inputs;
  @override
  Iterable<String> get keys sync* {
    yield 'item';
    for (var i = 1; i < inputs.length; i++) {
      yield 'outer${i - 1}';
    }
  }

  @override
  Object? operator [](Object? name) {
    if (name == 'item') return item;
    if (name is! String || !name.startsWith('outer')) return null;
    final index = int.tryParse(name.substring(5));
    return index == null || index < 0 || index + 1 >= inputs.length
        ? null
        : inputs[index + 1];
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable predicate parameters');
  @override
  void clear() => throw UnsupportedError('Immutable predicate parameters');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable predicate parameters');
}
