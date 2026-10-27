import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves installed Flutter widget callback signatures, including aliases.
WidgetBuilderContract? widgetBuilderContractFor(DartType type) {
  if (type is! FunctionType || type.typeParameters.isNotEmpty) return null;
  final result = type.returnType;
  if (!_is(
    result,
    'package:flutter/src/widgets/framework.dart',
    'Widget',
    nullable: true,
  )) {
    return null;
  }
  final parameters = <WidgetBuilderParameter>[];
  for (final parameter in type.formalParameters) {
    if (!parameter.isRequiredPositional) return null;
    final input = parameter.type;
    final kind = switch (input) {
      _
          when _is(
            input,
            'package:flutter/src/widgets/framework.dart',
            'BuildContext',
          ) =>
        WidgetBuilderParameter.buildContext,
      _
          when _is(
            input,
            'package:flutter/src/rendering/box.dart',
            'BoxConstraints',
          ) =>
        WidgetBuilderParameter.boxConstraints,
      _
          when _is(
            input,
            'package:flutter/src/widgets/media_query.dart',
            'Orientation',
          ) =>
        WidgetBuilderParameter.orientation,
      _ when _is(input, 'dart:core', 'int') => WidgetBuilderParameter.itemIndex,
      _ => null,
    };
    if (kind == null) return null;
    parameters.add(kind);
  }
  final contract = WidgetBuilderContract(
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
