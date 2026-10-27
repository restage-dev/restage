import 'package:restage_shared/src/expressions/builder_context.dart';
import 'package:restage_shared/src/expressions/value_program.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Native scalar callback values exclude opaque widget implementations.
bool isScalarCallbackParameterValueType(String name, ValueType type) => name ==
        callbackParameterName(0)
    ? type.kind == 'record' &&
        !type.nullable &&
        type.fields.isNotEmpty &&
        type.fields.entries.every((field) =>
            const {'String', 'int', 'double', 'num', 'bool'}
                .contains(field.value.kind) &&
            (field.key == 'value' && type.fields.length == 1 ||
                field.key ==
                    '${field.value.kind}${field.value.nullable ? '?' : ''}'))
    : name == callbackParameterName(1) && type.kind == 'int' && !type.nullable;

/// Checks the native signature of an already validated integer value program.
void validateScalarCallbackProgramContract(
  ValueProgram program,
  ScalarCallbackContract contract,
) {
  if (!contract.isSupported ||
      program.root < 0 ||
      program.root >= program.nodes.length ||
      !ValueType('int', nullable: contract.nullableResult)
          .accepts(program.nodes[program.root].type)) {
    throw const FormatException('Scalar program differs from its callback.');
  }
  for (final parameter in program.parameters.entries) {
    final contextType = builderContextValueType(parameter.key);
    if (contextType != null && parameter.value.accepts(contextType)) continue;
    final name = callbackParameterName(contract.parameters.length == 1 ? 0 : 1);
    if (parameter.key != name ||
        !isScalarCallbackParameterValueType(name, parameter.value)) {
      throw const FormatException('Unknown native scalar callback parameter.');
    }
  }
}
