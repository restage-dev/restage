import 'dart:convert';

import 'package:dart_style/dart_style.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';

final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

/// Emits an ordinary Widgetbook v4 story library from a total story plan.
String renderWidgetbookStorySource({
  required WidgetbookStoryPlan plan,
  required String packageName,
  required String sourcePath,
}) {
  final widget = plan.widget.entry;
  final className = plan.widget.className;
  final storyStem = _snakeCase(className);
  final inputName = '${className}StoryInput';
  final sourceUri = 'package:$packageName/${sourcePath.substring(4)}';
  final renderer = WidgetbookNativeDartRenderer(
    currentLibraryUri: sourceUri,
    currentLibraryAlias: 'restage_source',
    values: plan.nativeValues,
    additionalTypeUses: [
      for (final property in plan.properties)
        (
          type: property.dartType,
          sourcePath: '$sourcePath#$className.${property.property.name}',
        ),
    ],
    additionalBareSymbolImports: [
      DartBareSymbolImport(
        libraryUri: sourceUri,
        symbol: className,
        sourcePath: '$sourcePath#$className',
      ),
    ],
    bareSymbolReservations: [
      ...plan.widget.bareNamespaceReservations,
      DartBareSymbolReservation(
        libraryUri: sourceUri,
        symbol: className,
        source: 'source widget import at $sourcePath#$className',
      ),
      const DartBareSymbolReservation(
        symbol: 'widgetbook',
        source: 'Widgetbook import prefix',
      ),
      DartBareSymbolReservation(
        symbol: inputName,
        source: 'generated Widgetbook story input declaration',
      ),
      const DartBareSymbolReservation(
        symbol: 'meta',
        source: 'generated Widgetbook metadata declaration',
      ),
      const DartBareSymbolReservation(
        symbol: 'component',
        source: 'generated Widgetbook component declaration',
      ),
      const DartBareSymbolReservation(
        symbol: 'defaults',
        source: 'generated Widgetbook defaults declaration',
      ),
      const DartBareSymbolReservation(
        symbol: r'$RestageCatalog',
        source: 'generated Restage catalog declaration',
      ),
    ],
  );
  final propertyNames = <String, _RenderedPropertyNames>{
    for (final (index, property) in plan.properties.indexed)
      property.property.name: (
        choiceType: '_RestageChoice$index',
        wrapperType: '_RestageValue$index',
      ),
  };
  final imports = <String>{
    "import 'package:widgetbook/widgetbook.dart';",
    "import 'package:widgetbook/widgetbook.dart' as widgetbook;",
    "import '$sourceUri' show $className;",
    ...renderer.importDirectives,
  }.toList()
    ..sort(_importOrder);

  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln(
      '// ignore_for_file: library_private_types_in_public_api, unused_import',
    )
    ..writeln()
    ..writeln(imports.join('\n'))
    ..writeln()
    ..writeln("part '$storyStem.stories.g.dart';")
    ..writeln();
  writePropertyExclusionReport(
    out,
    plan.exclusions,
    symbolName: 'restageExclusions',
  );
  if (plan.exclusions.isNotEmpty) out.writeln();

  for (final property in plan.properties) {
    if (property is! WidgetbookStoryChoicePropertyPlan) continue;
    final names = propertyNames[property.property.name]!;
    out
      ..writeln('enum ${names.choiceType} {')
      ..writeln(
        property.choices.indexed
            .map((entry) => '  value${entry.$1},')
            .join('\n'),
      )
      ..writeln('}')
      ..writeln();
  }

  for (final property in plan.properties) {
    if (property is! WidgetbookStoryNativePropertyPlan) continue;
    final names = propertyNames[property.property.name]!;
    final type = renderer.renderType(property.dartType.nonNullable);
    out
      ..writeln('final class ${names.wrapperType} {')
      ..writeln('  const ${names.wrapperType}.absent()')
      ..writeln('      : hasValue = false,')
      ..writeln('        value = null;')
      ..writeln()
      ..writeln('  const ${names.wrapperType}(this.value) : hasValue = true;')
      ..writeln()
      ..writeln('  final bool hasValue;')
      ..writeln('  final $type? value;')
      ..writeln('}')
      ..writeln();
  }

  out
    ..writeln('class $inputName {')
    ..writeln('  const $inputName({')
    ..writeln('    this.description = ${_literal(widget.description)},')
    ..writeln('    this.usage = ${_literal(plan.widget.usage)},');
  for (final property in plan.properties) {
    out.writeln(
      '    ${_inputParameter(property, propertyNames, renderer)},',
    );
  }
  out
    ..writeln('  });')
    ..writeln()
    ..writeln('  final String description;')
    ..writeln('  final String usage;');
  for (final property in plan.properties) {
    out.writeln(
      '  final ${_inputType(property, propertyNames, renderer)} '
      '${property.property.name};',
    );
  }
  out
    ..writeln('}')
    ..writeln()
    ..writeln('const meta = widgetbook.Meta(')
    ..writeln('  restage_source.$className.new,')
    ..writeln('  argsType: $inputName.new,')
    ..writeln(');')
    ..writeln()
    ..writeln('const component = widgetbook.ComponentMeta(')
    ..writeln("  path: '${_escape(widget.category.name)}',")
    ..writeln(');')
    ..writeln()
    ..writeln('final defaults = _Defaults(')
    ..writeln('  builder: (context, args) => restage_source.$className(');
  for (final property in plan.properties) {
    final value = _hostValue(
      property,
      propertyNames,
      renderer,
    );
    out.writeln(
      property.positional
          ? '    $value,'
          : '    ${property.property.name}: $value,',
    );
  }
  out
    ..writeln('  ),')
    ..writeln(');')
    ..writeln();

  out
    ..writeln(r'final $RestageCatalog = _Story(')
    ..writeln('  args: _Args(')
    ..writeln('    description: _RestageMetadataArg(')
    ..writeln('      ${_literal(widget.description)},')
    ..writeln("      name: 'description',")
    ..writeln('    ),')
    ..writeln('    usage: _RestageMetadataArg(')
    ..writeln('      ${_literal(plan.widget.usage)},')
    ..writeln("      name: 'usage',")
    ..writeln('    ),');
  for (final property in plan.properties) {
    out.writeln(
      '    ${property.property.name}: '
      '${_arg(property, propertyNames, renderer)},',
    );
  }
  out.writeln('  ),');
  out
    ..writeln(');')
    ..writeln();

  _writeArgAdapters(out, plan.properties, renderer);
  return _formatter.format(out.toString());
}

typedef _RenderedPropertyNames = ({
  String choiceType,
  String wrapperType,
});

String _inputParameter(
  WidgetbookStoryPropertyPlan property,
  Map<String, _RenderedPropertyNames> names,
  WidgetbookNativeDartRenderer renderer,
) {
  final name = property.property.name;
  return switch (property) {
    WidgetbookStoryEventPropertyPlan(:final callback) =>
      'this.$name = ${callback.constructorDefault != null}',
    WidgetbookStoryChoicePropertyPlan(:final seed) =>
      'this.$name = ${names[name]!.choiceType}.value'
          '${_choiceIndex(property, seed, renderer)}',
    WidgetbookStoryNativePropertyPlan() =>
      'this.$name = const ${names[name]!.wrapperType}.absent()',
    WidgetbookStoryEditablePropertyPlan(:final seed) =>
      'this.$name = ${renderer.renderValue(seed)}',
  };
}

String _inputType(
  WidgetbookStoryPropertyPlan property,
  Map<String, _RenderedPropertyNames> names,
  WidgetbookNativeDartRenderer renderer,
) =>
    switch (property) {
      WidgetbookStoryEventPropertyPlan() => 'bool',
      WidgetbookStoryChoicePropertyPlan() =>
        names[property.property.name]!.choiceType,
      WidgetbookStoryNativePropertyPlan() =>
        names[property.property.name]!.wrapperType,
      WidgetbookStoryEditablePropertyPlan() =>
        renderer.renderType(property.dartType),
    };

String _hostValue(
  WidgetbookStoryPropertyPlan property,
  Map<String, _RenderedPropertyNames> names,
  WidgetbookNativeDartRenderer renderer,
) {
  final name = property.property.name;
  switch (property) {
    case WidgetbookStoryEventPropertyPlan(:final callback):
      final closure = callback.parameterCount == 0 ? '() {}' : '(_) {}';
      final defaultValue = callback.constructorDefault;
      final active =
          defaultValue == null ? closure : renderer.renderValue(defaultValue);
      if (callback.nullable) return 'args.$name ? $active : null';
      return defaultValue == null ? closure : 'args.$name ? $active : $closure';
    case WidgetbookStoryChoicePropertyPlan(:final choices):
      final choice = names[name]!.choiceType;
      return 'switch (args.$name) { '
          '${choices.indexed.map(
                (entry) => '$choice.value${entry.$1} => '
                    '${renderer.renderValue(entry.$2)}',
              ).join(', ')} }';
    case WidgetbookStoryNativePropertyPlan(:final seed):
      final present =
          property.dartType.nullable ? 'args.$name.value' : 'args.$name.value!';
      return 'args.$name.hasValue ? $present : '
          '${renderer.renderValue(seed)}';
    case WidgetbookStoryEditablePropertyPlan():
      return 'args.$name';
  }
}

String _arg(
  WidgetbookStoryPropertyPlan property,
  Map<String, _RenderedPropertyNames> names,
  WidgetbookNativeDartRenderer renderer,
) {
  final description = _literal(property.description);
  final value = switch (property) {
    WidgetbookStoryEventPropertyPlan(:final callback) =>
      '${callback.constructorDefault != null}',
    WidgetbookStoryEditablePropertyPlan(:final seed) ||
    WidgetbookStoryChoicePropertyPlan(:final seed) ||
    WidgetbookStoryNativePropertyPlan(:final seed) =>
      renderer.renderValue(seed),
  };
  final nullable = property.dartType.nullable;
  return switch (property) {
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.string,
    ) =>
      '${nullable ? '_RestageNullableStringArg' : '_RestageStringArg'}'
          '($value, description: $description)',
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.boolean,
    ) ||
    WidgetbookStoryEventPropertyPlan() =>
      '${_boolArgName(property, nullable: nullable)}'
          '($value, description: $description)',
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.integer,
    ) =>
      '${nullable ? '_RestageNullableIntArg' : '_RestageIntArg'}'
          '($value${_intStyle(property)}, description: $description)',
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.real,
    ) =>
      '${nullable ? '_RestageNullableDoubleArg' : '_RestageDoubleArg'}'
          '($value${_doubleStyle(property)}, '
          'description: $description)',
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.color,
    ) =>
      '${nullable ? '_RestageNullableColorArg' : '_RestageColorArg'}'
          '($value, description: $description)',
    WidgetbookStoryEditablePropertyPlan(
      editableControl: WidgetbookStoryEditableControl.duration,
    ) =>
      '${nullable ? '_RestageNullableDurationArg' : '_RestageDurationArg'}'
          '($value, description: $description)',
    WidgetbookStoryChoicePropertyPlan(
      :final seed,
      :final choiceLabels,
    ) =>
      '_RestageEnumArg<${names[property.property.name]!.choiceType}>('
          '${names[property.property.name]!.choiceType}.value'
          '${_choiceIndex(property, seed, renderer)}, '
          'values: ${names[property.property.name]!.choiceType}.values, '
          'labelBuilder: (value) => switch (value) { '
          '${choiceLabels.indexed.map(
                (entry) => '${names[property.property.name]!.choiceType}.'
                    'value${entry.$1} => ${_literal(entry.$2)}',
              ).join(', ')} }, '
          'description: $description)',
    WidgetbookStoryNativePropertyPlan() =>
      '_RestageConstArg<${names[property.property.name]!.wrapperType}>('
          '${names[property.property.name]!.wrapperType}($value), '
          'description: $description)',
  };
}

String _boolArgName(
  WidgetbookStoryPropertyPlan property, {
  required bool nullable,
}) =>
    nullable && property.control != WidgetbookStoryControl.event
        ? '_RestageNullableBoolArg'
        : '_RestageBoolArg';

int _choiceIndex(
  WidgetbookStoryChoicePropertyPlan property,
  WidgetbookNativeValuePlan value,
  WidgetbookNativeDartRenderer renderer,
) {
  final rendered = renderer.renderValue(value);
  final index = property.choices.indexWhere(
    (choice) => renderer.renderValue(choice) == rendered,
  );
  if (index < 0) {
    throw StateError(
      "Widgetbook value for '${property.property.name}' is not one of its "
      'finite choices.',
    );
  }
  return index;
}

String _intStyle(WidgetbookStoryPropertyPlan property) {
  final constraints = property.constraints;
  final lower = constraints.minimum ?? constraints.exclusiveMinimum;
  final upper = constraints.maximum ?? constraints.exclusiveMaximum;
  if (lower == null || upper == null) return '';
  var minimum = lower.ceil();
  var maximum = upper.floor();
  if (constraints.exclusiveMinimum != null && minimum == lower) minimum++;
  if (constraints.exclusiveMaximum != null && maximum == upper) maximum--;
  if (minimum >= maximum) return '';
  return ', style: widgetbook.SliderIntArgStyle( '
      'min: $minimum, max: $maximum, '
      'divisions: ${maximum - minimum})';
}

String _doubleStyle(WidgetbookStoryPropertyPlan property) {
  final constraints = property.constraints;
  if (constraints.exclusiveMinimum != null ||
      constraints.exclusiveMaximum != null ||
      constraints.minimum == null ||
      constraints.maximum == null ||
      constraints.minimum! >= constraints.maximum!) {
    return '';
  }
  final minimum = constraints.minimum!.toDouble();
  final maximum = constraints.maximum!.toDouble();
  return ', style: widgetbook.SliderDoubleArgStyle( '
      'min: $minimum, max: $maximum, '
      'divisions: 100)';
}

void _writeArgAdapters(
  StringBuffer out,
  List<WidgetbookStoryPropertyPlan> properties,
  WidgetbookNativeDartRenderer renderer,
) {
  final controls = {for (final property in properties) property.control};
  out
    ..writeln('mixin _RestageArgDescription<T> on widgetbook.Arg<T> {')
    ..writeln('  String get restageDescription;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  String? get description => restageDescription;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'final class _RestageMetadataArg extends widgetbook.Arg<String>',
    )
    ..writeln('    with widgetbook.NoFields<String> {')
    ..writeln('  _RestageMetadataArg(super.value, {required super.name});')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  String get description => value;')
    ..writeln('}')
    ..writeln();

  if (controls.contains(WidgetbookStoryControl.string)) {
    _simpleAdapter(
      out,
      '_RestageStringArg',
      'widgetbook.StringArg',
      'String',
    );
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.string &&
          property.dartType.nullable,
    )) {
      _simpleAdapter(
        out,
        '_RestageNullableStringArg',
        'widgetbook.NullableStringArg',
        'String?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.boolean) ||
      controls.contains(WidgetbookStoryControl.event)) {
    _simpleAdapter(out, '_RestageBoolArg', 'widgetbook.BoolArg', 'bool');
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.boolean &&
          property.dartType.nullable,
    )) {
      _simpleAdapter(
        out,
        '_RestageNullableBoolArg',
        'widgetbook.NullableBoolArg',
        'bool?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.integer)) {
    _styledAdapter(
      out,
      '_RestageIntArg',
      'widgetbook.IntArg',
      'int',
    );
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.integer &&
          property.dartType.nullable,
    )) {
      _styledAdapter(
        out,
        '_RestageNullableIntArg',
        'widgetbook.NullableIntArg',
        'int?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.real)) {
    _styledAdapter(
      out,
      '_RestageDoubleArg',
      'widgetbook.DoubleArg',
      'double',
    );
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.real &&
          property.dartType.nullable,
    )) {
      _styledAdapter(
        out,
        '_RestageNullableDoubleArg',
        'widgetbook.NullableDoubleArg',
        'double?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.color)) {
    final colorType = renderer.renderType(
      properties
          .firstWhere(
            (property) => property.control == WidgetbookStoryControl.color,
          )
          .dartType
          .nonNullable,
    );
    _simpleAdapter(
      out,
      '_RestageColorArg',
      'widgetbook.ColorArg',
      colorType,
    );
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.color &&
          property.dartType.nullable,
    )) {
      _simpleAdapter(
        out,
        '_RestageNullableColorArg',
        'widgetbook.NullableColorArg',
        '$colorType?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.duration)) {
    _simpleAdapter(
      out,
      '_RestageDurationArg',
      'widgetbook.DurationArg',
      'Duration',
    );
    if (properties.any(
      (property) =>
          property.control == WidgetbookStoryControl.duration &&
          property.dartType.nullable,
    )) {
      _simpleAdapter(
        out,
        '_RestageNullableDurationArg',
        'widgetbook.NullableDurationArg',
        'Duration?',
      );
    }
  }
  if (controls.contains(WidgetbookStoryControl.choice)) {
    out
      ..writeln('final class _RestageEnumArg<T extends Enum>')
      ..writeln('    extends widgetbook.EnumArg<T>')
      ..writeln('    with _RestageArgDescription<T> {')
      ..writeln('  _RestageEnumArg(')
      ..writeln('    super.value, {')
      ..writeln('    required super.values,')
      ..writeln('    required super.labelBuilder,')
      ..writeln('    required String description,')
      ..writeln('  }) : restageDescription = description;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  final String restageDescription;')
      ..writeln('}')
      ..writeln();
  }
  if (controls.contains(WidgetbookStoryControl.native)) {
    out
      ..writeln(
        'final class _RestageConstArg<T> extends widgetbook.ConstArg<T>',
      )
      ..writeln('    with _RestageArgDescription<T> {')
      ..writeln('  _RestageConstArg(')
      ..writeln('    super.value, {')
      ..writeln('    required String description,')
      ..writeln('  }) : restageDescription = description;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  final String restageDescription;')
      ..writeln('}')
      ..writeln();
  }
}

void _simpleAdapter(
  StringBuffer out,
  String name,
  String parent,
  String valueType,
) {
  out
    ..writeln('final class $name extends $parent')
    ..writeln('    with _RestageArgDescription<$valueType> {')
    ..writeln('  $name(super.value, {required String description})')
    ..writeln('      : restageDescription = description;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String restageDescription;')
    ..writeln('}')
    ..writeln();
}

void _styledAdapter(
  StringBuffer out,
  String name,
  String parent,
  String valueType,
) {
  out
    ..writeln('final class $name extends $parent')
    ..writeln('    with _RestageArgDescription<$valueType> {')
    ..writeln('  $name(')
    ..writeln('    super.value, {')
    ..writeln('    // ignore: unused_element_parameter')
    ..writeln('    super.style,')
    ..writeln('    required String description,')
    ..writeln('  }) : restageDescription = description;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String restageDescription;')
    ..writeln('}')
    ..writeln();
}

int _importOrder(String left, String right) {
  int rank(String value) => value.contains('package:widgetbook/')
      ? 0
      : value.contains('package:flutter/')
          ? 1
          : 2;
  final byRank = rank(left).compareTo(rank(right));
  return byRank != 0 ? byRank : left.compareTo(right);
}

String _literal(Object? value) => jsonEncode(value).replaceAll(r'$', r'\$');

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    )
    .toLowerCase();

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');
