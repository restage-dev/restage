import 'package:restage_shared/src/surface_contract/native_binding_contract.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_host_data_schema.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/expressions/value_program.dart';

/// Invokes only an installed adapter selected by its declared binding.
typedef NativeCallInvoker = Object? Function(
    String binding,
    NativeBindingContract contract,
    List<Object?> inputs,
    Map<String, String> captures,
    ValueLocalFrame frame);

/// One closed operation shared by validation and native execution.
final class NativeCallValueOperation implements RegistryValueOperation {
  NativeCallValueOperation(Map<String, NativeBindingContract> declarations,
      {this.invoke})
      : declarations = Map.unmodifiable(declarations);
  final Map<String, NativeBindingContract> declarations;
  final NativeCallInvoker? invoke;
  @override
  String get name => 'native.call';
  @override
  int get capability => 24;

  (String, NativeBindingContract, Map<String, String>) _options(Object? value) {
    final json =
        SurfaceContractJson.requireObject(value, 'native call options');
    SurfaceContractJson.exactKeys(
        json, {'binding', 'contract', 'captures'}, 'native call options');
    final binding = SurfaceContractJson.requiredString(
        json, 'binding', 'native call options');
    final contract = NativeBindingContract.fromJson(json['contract']);
    if (contract.call == null ||
        declarations[binding] != contract ||
        contract.call!.implementation.isEmpty) {
      throw const FormatException(
          'Native call declaration is unavailable or incompatible');
    }
    final captures =
        SurfaceContractJson.requireObject(json['captures'], 'native captures');
    if (captures.values.any((value) => value is! String)) {
      throw const FormatException('Invalid native capture slot');
    }
    return (binding, contract, captures.cast<String, String>());
  }

  @override
  void validate(ValueNode node, List<ValueType> inputs) =>
      validateWithContext(node, inputs, const ValueOperationContext());
  @override
  void validateWithContext(
      ValueNode node, List<ValueType> inputs, ValueOperationContext context) {
    final (_, contract, captures) = _options(node.value);
    final call = contract.call!;
    if (node.name != null ||
        inputs.length != call.inputs.length ||
        !node.type.accepts(call.result) ||
        !call.result.accepts(node.type) ||
        captures.length != call.captures.length) {
      throw const FormatException('Invalid native call signature');
    }
    for (var i = 0; i < inputs.length; i++) {
      if (!call.inputs[i].accepts(inputs[i])) {
        throw const FormatException('Invalid native call input');
      }
    }
    for (final capture in call.captures.entries) {
      final local = context.locals[captures[capture.key]];
      if (local == null ||
          !local.accepts(capture.value) ||
          !capture.value.accepts(local)) {
        throw const FormatException('Invalid native call capture');
      }
    }
  }

  @override
  Iterable<ValueProgram> nestedPrograms(
          ValueNode node, ValueOperationContext context) =>
      const [];
  @override
  Object? evaluate(List<Object?> inputs, Object? options) =>
      throw StateError('Native calls require lexical context');
  @override
  Object? evaluateWithContext(
      List<Object?> inputs, Object? options, ValueOperationContext context) {
    final (binding, contract, captures) = _options(options);
    final call = contract.call!;
    final values = List<Object?>.of(inputs);
    if (values.length != call.inputs.length ||
        Iterable<int>.generate(values.length)
            .any((i) => !call.inputs[i].matches(values[i]))) {
      throw StateError('Invalid native call operands');
    }
    final implementation = invoke;
    if (implementation == null || context.frame == null) {
      throw StateError('Native call implementation is unavailable');
    }
    final result =
        implementation(binding, contract, values, captures, context.frame!);
    if (!call.result.matches(result))
      throw StateError('Invalid native call result');
    return result;
  }
}

/// Builds validation operations from the screen's installed binding declarations.
Map<String, ValueOperation> nativeCallOperations(
    SurfaceScreenHostDataSchema schema, Map<String, ValueOperation> base) {
  final declarations = {
    for (final entry in schema.inputs.entries)
      if (entry.value
          case SurfaceScreenHostDataNativeBindingShapeV1(:final contract)
          when contract.call != null)
        entry.key: contract,
  };
  return {...base, 'native.call': NativeCallValueOperation(declarations)};
}
