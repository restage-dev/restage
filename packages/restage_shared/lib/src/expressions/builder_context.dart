import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:restage_shared/src/expressions/builder_program.dart';
import 'package:restage_shared/src/device/device_data_contract.dart';
import 'package:restage_shared/src/theme/theme_data_contract.dart';
import 'package:restage_shared/src/expressions/value_program.dart';

/// Nominal identity of the actual Flutter widget callback context.
const builderContextNativeValueType =
    ValueType.native('package:flutter/src/widgets/framework.dart#BuildContext');

/// Resolves a finite lexical native-context address to its local projection.
({int ancestorDepth, String name})? builderContextLocation(String name) {
  if (name.startsWith('context:ancestor:')) {
    final match =
        RegExp(r'^context:ancestor:([1-9][0-9]*):(device|theme):(.+)$')
            .firstMatch(name);
    if (match == null) return null;
    final depth = int.tryParse(match.group(1)!);
    if (depth == null || depth > 64) return null;
    return (
      ancestorDepth: depth,
      name: 'context:${match.group(2)}:${match.group(3)}'
    );
  }
  if (name.startsWith('context:device:') || name.startsWith('context:theme:'))
    return (ancestorDepth: 0, name: name);
  return null;
}

/// Exact color projection carried through native callback values.
const builderColorValueType = colorValueType;

/// Reserved presence projection for a nullable inherited text style.
const builderStylePresenceField = r'$present';

/// Resolves an installed callback-context projection's inert type.
ValueType? builderContextValueType(String name) {
  final location = builderContextLocation(name);
  if (location == null) return null;
  name = location.name;
  if (name.startsWith('context:device:')) {
    final path = name.substring('context:device:'.length);
    if (path == 'defaultTargetPlatform') return ValueType.string;
    return switch (kDeviceContractPathKinds[path]) {
      DeviceContractValueKind.size => ValueType.real,
      DeviceContractValueKind.boolean => ValueType.boolean,
      DeviceContractValueKind.token =>
        ValueType('String', nullable: path == 'countryCode'),
      null => null,
    };
  }
  if (name.startsWith('context:theme:')) {
    final path = name.substring('context:theme:'.length);
    final segments = path.split('.');
    if (segments.length == 3 &&
        segments.first == 'textTheme' &&
        kThemeContractTextThemeStyles.contains(segments[1]) &&
        segments.last == builderStylePresenceField) return ValueType.boolean;
    final nullable = path != 'brightness' && !path.startsWith('colorScheme.');
    return switch (kThemeContractPathKinds[path]) {
      ThemeContractValueKind.color =>
        ValueType('record', nullable: nullable, fields: colorValueType.fields),
      ThemeContractValueKind.fontWeight ||
      ThemeContractValueKind.textDecoration =>
        ValueType('int', nullable: nullable),
      ThemeContractValueKind.size => ValueType('double', nullable: nullable),
      ThemeContractValueKind.textList =>
        ValueType('list', nullable: nullable, item: ValueType.string),
      null => null,
      _ => ValueType('String', nullable: nullable),
    };
  }
  return null;
}

/// The finite native BoxConstraints projection available to callbacks.
const builderConstraintsValueType = ValueType('record', fields: {
  'minWidth': ValueType.real,
  'maxWidth': ValueType.real,
  'minHeight': ValueType.real,
  'maxHeight': ValueType.real,
  'hasBoundedWidth': ValueType.boolean,
  'hasBoundedHeight': ValueType.boolean,
  'hasTightWidth': ValueType.boolean,
  'hasTightHeight': ValueType.boolean,
  'isTight': ValueType.boolean,
  'biggest': ValueType('record',
      fields: {'width': ValueType.real, 'height': ValueType.real}),
  'smallest': ValueType('record',
      fields: {'width': ValueType.real, 'height': ValueType.real}),
});

/// Checks the program against the native callback before it can execute.
void validateBuilderProgramContract(
    BuilderProgram program, WidgetBuilderContract contract) {
  if (!contract.isSupported ||
      program.collection ||
      program.nullableResult != contract.nullableResult)
    throw const FormatException('Builder program differs from its callback');
  for (final parameter in program.values.parameters.entries) {
    if (parameter.key == callbackParameterName(0)) {
      if (!builderContextNativeValueType.accepts(parameter.value) ||
          parameter.value.nullable) {
        throw const FormatException('Native builder context type differs');
      }
      continue;
    }
    final contextType = builderContextValueType(parameter.key);
    if (contextType != null && parameter.value.accepts(contextType)) continue;
    if (parameter.key != callbackParameterName(1) ||
        contract.parameters.length != 2)
      throw const FormatException('Unknown native builder parameter');
    final expected = switch (contract.parameters.last) {
      WidgetBuilderParameter.boxConstraints => builderConstraintsValueType,
      WidgetBuilderParameter.orientation => ValueType.string,
      WidgetBuilderParameter.itemIndex => ValueType.integer,
      WidgetBuilderParameter.buildContext => null,
    };
    if (expected == null || !_builderProjectionFits(parameter.value, expected))
      throw const FormatException('Native builder parameter shape differs');
  }
}

bool _builderProjectionFits(ValueType projection, ValueType actual) {
  if (projection.kind != actual.kind || projection.nullable != actual.nullable)
    return false;
  if (projection.kind == 'record')
    return projection.fields.entries.every((field) =>
        actual.fields[field.key] != null &&
        _builderProjectionFits(field.value, actual.fields[field.key]!));
  return projection.accepts(actual);
}
