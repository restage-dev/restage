import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves installed native integer callback signatures, including aliases.
ScalarCallbackContract? scalarCallbackContractFor(DartType type) {
  if (type is! FunctionType || type.typeParameters.isNotEmpty) return null;
  final result = type.returnType;
  if (!_is(result, 'dart:core', 'int', nullable: true)) return null;
  final parameters = <ScalarCallbackParameter>[];
  for (final parameter in type.formalParameters) {
    if (!parameter.isRequiredPositional) return null;
    final input = parameter.type;
    final kind = switch (input) {
      _ when _is(input, 'package:flutter/src/foundation/key.dart', 'Key') =>
        ScalarCallbackParameter.valueKey,
      _
          when _is(
            input,
            'package:flutter/src/widgets/framework.dart',
            'Widget',
          ) =>
        ScalarCallbackParameter.widget,
      _ when _is(input, 'dart:core', 'int') =>
        ScalarCallbackParameter.itemIndex,
      _ => null,
    };
    if (kind == null) return null;
    parameters.add(kind);
  }
  final contract = ScalarCallbackContract(
    parameters: List.unmodifiable(parameters),
    nullableResult: result.nullabilitySuffix == NullabilitySuffix.question,
  );
  return contract.isSupported ? contract : null;
}

bool _is(DartType type, String library, String name, {bool nullable = false}) =>
    type is InterfaceType &&
    (nullable || type.nullabilitySuffix == NullabilitySuffix.none) &&
    type.element.name == name &&
    type.element.library.uri.toString() == library;
