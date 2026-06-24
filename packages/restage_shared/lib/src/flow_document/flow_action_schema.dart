// Flow action schemas are compact wire-contract DTOs; per-field docs would
// duplicate the canonical schema names.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:restage_shared/src/flow_document/flow_document_hash.dart';

sealed class FlowActionSchema {
  const FlowActionSchema();

  const factory FlowActionSchema.object(
    Map<String, FlowActionSchemaField> fields,
  ) = FlowObjectActionSchema;

  const factory FlowActionSchema.bool() = FlowBoolActionSchema;

  const factory FlowActionSchema.int() = FlowIntActionSchema;

  const factory FlowActionSchema.double() = FlowDoubleActionSchema;

  const factory FlowActionSchema.string() = FlowStringActionSchema;

  const factory FlowActionSchema.enumValues(List<String> values) =
      FlowEnumActionSchema;

  const factory FlowActionSchema.list(FlowActionSchema child) =
      FlowListActionSchema;

  const factory FlowActionSchema.nullable(FlowActionSchema child) =
      FlowNullableActionSchema;

  String get kind;

  static FlowContentHash hashFor({
    required String contractKind,
    required FlowActionSchema schema,
  }) {
    if (contractKind != 'args' && contractKind != 'result') {
      throw ArgumentError.value(
        contractKind,
        'contractKind',
        'Expected "args" or "result".',
      );
    }
    final canonicalJson = _canonicalJson(_schemaToJson(schema));
    return FlowContentHash.computeString('$contractKind\n$canonicalJson');
  }

  static Map<String, Object?> toJson(FlowActionSchema schema) {
    return _schemaToJson(schema);
  }

  static FlowActionSchema fromJson(
    Map<String, Object?> json, {
    String path = r'$',
  }) {
    return _schemaFromJson(json, path);
  }

  static List<FlowActionSchemaDiff> diff(
    FlowActionSchema expected,
    FlowActionSchema actual,
  ) {
    final diffs = <FlowActionSchemaDiff>[];
    _diffSchema(diffs, r'$', expected, actual);
    return diffs;
  }
}

final class FlowActionSchemaField {
  const FlowActionSchemaField({
    required this.required,
    required this.schema,
  });

  final bool required;
  final FlowActionSchema schema;
}

final class FlowObjectActionSchema extends FlowActionSchema {
  const FlowObjectActionSchema(this.fields);

  final Map<String, FlowActionSchemaField> fields;

  @override
  String get kind => 'object';
}

final class FlowBoolActionSchema extends FlowActionSchema {
  const FlowBoolActionSchema();

  @override
  String get kind => 'bool';
}

final class FlowIntActionSchema extends FlowActionSchema {
  const FlowIntActionSchema();

  @override
  String get kind => 'int';
}

final class FlowDoubleActionSchema extends FlowActionSchema {
  const FlowDoubleActionSchema();

  @override
  String get kind => 'double';
}

final class FlowStringActionSchema extends FlowActionSchema {
  const FlowStringActionSchema();

  @override
  String get kind => 'string';
}

final class FlowEnumActionSchema extends FlowActionSchema {
  const FlowEnumActionSchema(this.values);

  final List<String> values;

  @override
  String get kind => 'enum';
}

final class FlowListActionSchema extends FlowActionSchema {
  const FlowListActionSchema(this.child);

  final FlowActionSchema child;

  @override
  String get kind => 'list';
}

final class FlowNullableActionSchema extends FlowActionSchema {
  const FlowNullableActionSchema(this.child);

  final FlowActionSchema child;

  @override
  String get kind => 'nullable';
}

enum FlowActionSchemaDiffCode {
  missingField,
  extraField,
  fieldRequiredMismatch,
  kindMismatch,
  enumValueMismatch,
  nullableChildMismatch,
  listChildMismatch,
}

final class FlowActionSchemaDiff {
  const FlowActionSchemaDiff({
    required this.code,
    required this.path,
    required this.expected,
    required this.actual,
  });

  final FlowActionSchemaDiffCode code;
  final String path;
  final String? expected;
  final String? actual;

  @override
  bool operator ==(Object other) {
    return other is FlowActionSchemaDiff &&
        other.code == code &&
        other.path == path &&
        other.expected == expected &&
        other.actual == actual;
  }

  @override
  int get hashCode => Object.hash(code, path, expected, actual);

  @override
  String toString() {
    return 'FlowActionSchemaDiff($code at $path: expected $expected, '
        'actual $actual)';
  }
}

Map<String, Object?> _schemaToJson(FlowActionSchema schema) {
  switch (schema) {
    case FlowObjectActionSchema(:final fields):
      return {
        'kind': schema.kind,
        'fields': {
          for (final entry in fields.entries)
            entry.key: {
              'required': entry.value.required,
              'schema': _schemaToJson(entry.value.schema),
            },
        },
      };
    case FlowEnumActionSchema(:final values):
      return {
        'kind': schema.kind,
        'values': _canonicalEnumValues(values),
      };
    case FlowListActionSchema(:final child):
      return {
        'kind': schema.kind,
        'child': _schemaToJson(child),
      };
    case FlowNullableActionSchema(:final child):
      return {
        'kind': schema.kind,
        'child': _schemaToJson(child),
      };
    case FlowBoolActionSchema() ||
          FlowIntActionSchema() ||
          FlowDoubleActionSchema() ||
          FlowStringActionSchema():
      return {'kind': schema.kind};
  }
}

FlowActionSchema _schemaFromJson(Map<String, Object?> json, String path) {
  final kind = _requiredString(json, 'kind', path);
  switch (kind) {
    case 'object':
      _rejectUnknownKeys(json, const {'fields', 'kind'}, path);
      final fieldsJson = _requiredObject(json, 'fields', path);
      return FlowActionSchema.object({
        for (final entry in fieldsJson.entries)
          entry.key: _schemaFieldFromJson(
            _asObject(entry.value, '$path.fields.${entry.key}'),
            '$path.fields.${entry.key}',
          ),
      });
    case 'bool':
      _rejectUnknownKeys(json, const {'kind'}, path);
      return const FlowActionSchema.bool();
    case 'int':
      _rejectUnknownKeys(json, const {'kind'}, path);
      return const FlowActionSchema.int();
    case 'double':
      _rejectUnknownKeys(json, const {'kind'}, path);
      return const FlowActionSchema.double();
    case 'string':
      _rejectUnknownKeys(json, const {'kind'}, path);
      return const FlowActionSchema.string();
    case 'enum':
      _rejectUnknownKeys(json, const {'kind', 'values'}, path);
      final values = _requiredList(json, 'values', path).map((value) {
        if (value is String) return value;
        throw FormatException('Field "$path.values" must contain strings.');
      }).toList();
      return FlowActionSchema.enumValues(_canonicalEnumValues(values));
    case 'list':
      _rejectUnknownKeys(json, const {'child', 'kind'}, path);
      return FlowActionSchema.list(
        _schemaFromJson(_requiredObject(json, 'child', path), '$path.child'),
      );
    case 'nullable':
      _rejectUnknownKeys(json, const {'child', 'kind'}, path);
      return FlowActionSchema.nullable(
        _schemaFromJson(_requiredObject(json, 'child', path), '$path.child'),
      );
    default:
      throw FormatException('Unsupported action schema kind "$kind".');
  }
}

FlowActionSchemaField _schemaFieldFromJson(
  Map<String, Object?> json,
  String path,
) {
  _rejectUnknownKeys(json, const {'required', 'schema'}, path);
  return FlowActionSchemaField(
    required: _requiredBool(json, 'required', path),
    schema: _schemaFromJson(
      _requiredObject(json, 'schema', path),
      '$path.schema',
    ),
  );
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowedKeys,
  String path,
) {
  final unknownKeys = json.keys.where((key) => !allowedKeys.contains(key));
  if (unknownKeys.isEmpty) return;
  throw FormatException('Unsupported field "$path.${unknownKeys.first}".');
}

Object? _required(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$path.$key".');
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Field "$path.$key" cannot be null.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key, String path) {
  final value = _required(json, key, path);
  if (value is String) return value;
  throw FormatException('Field "$path.$key" must be a string.');
}

bool _requiredBool(Map<String, Object?> json, String key, String path) {
  final value = _required(json, key, path);
  if (value is bool) return value;
  throw FormatException('Field "$path.$key" must be a bool.');
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> json,
  String key,
  String path,
) {
  return _asObject(_required(json, key, path), '$path.$key');
}

Map<String, Object?> _asObject(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    throw FormatException('Field "$path" must use string object keys.');
  }
  throw FormatException('Field "$path" must be an object.');
}

List<Object?> _requiredList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _required(json, key, path);
  if (value is List<Object?>) return value;
  throw FormatException('Field "$path.$key" must be a list.');
}

String _canonicalJson(Object? value) {
  return jsonEncode(_sortJsonValue(value));
}

Object? _sortJsonValue(Object? value) {
  switch (value) {
    case null:
      return null;
    case String() || bool() || int():
      return value;
    case double():
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'value', 'Expected a finite number.');
      }
      return value;
    case List<Object?>():
      return [for (final item in value) _sortJsonValue(item)];
    case Map<String, Object?>():
      final keys = value.keys.toList()..sort();
      return {
        for (final key in keys) key: _sortJsonValue(value[key]),
      };
    case Map():
      throw ArgumentError.value(
        value,
        'value',
        'JSON object keys must be strings.',
      );
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported JSON value type ${value.runtimeType}.',
      );
  }
}

void _diffSchema(
  List<FlowActionSchemaDiff> diffs,
  String path,
  FlowActionSchema expected,
  FlowActionSchema actual,
) {
  if (expected.kind != actual.kind) {
    diffs.add(
      FlowActionSchemaDiff(
        code: FlowActionSchemaDiffCode.kindMismatch,
        path: path,
        expected: expected.kind,
        actual: actual.kind,
      ),
    );
    return;
  }

  switch ((expected, actual)) {
    case (
        FlowObjectActionSchema(fields: final expectedFields),
        FlowObjectActionSchema(fields: final actualFields),
      ):
      _diffObjectFields(diffs, path, expectedFields, actualFields);
    case (
        FlowEnumActionSchema(values: final expectedValues),
        FlowEnumActionSchema(values: final actualValues),
      ):
      _diffEnumValues(diffs, path, expectedValues, actualValues);
    case (
        FlowListActionSchema(child: final expectedChild),
        FlowListActionSchema(child: final actualChild),
      ):
      _diffWrappedChild(
        diffs,
        '$path[]',
        FlowActionSchemaDiffCode.listChildMismatch,
        expectedChild,
        actualChild,
      );
    case (
        FlowNullableActionSchema(child: final expectedChild),
        FlowNullableActionSchema(child: final actualChild),
      ):
      _diffWrappedChild(
        diffs,
        '$path?',
        FlowActionSchemaDiffCode.nullableChildMismatch,
        expectedChild,
        actualChild,
      );
    case (
            FlowBoolActionSchema(),
            FlowBoolActionSchema(),
          ) ||
          (
            FlowIntActionSchema(),
            FlowIntActionSchema(),
          ) ||
          (
            FlowDoubleActionSchema(),
            FlowDoubleActionSchema(),
          ) ||
          (
            FlowStringActionSchema(),
            FlowStringActionSchema(),
          ):
      return;
    default:
      throw StateError('Matched schema kinds reached incompatible nodes.');
  }
}

void _diffObjectFields(
  List<FlowActionSchemaDiff> diffs,
  String path,
  Map<String, FlowActionSchemaField> expected,
  Map<String, FlowActionSchemaField> actual,
) {
  final names = {...expected.keys, ...actual.keys}.toList()..sort();
  for (final name in names) {
    final fieldPath = '$path.$name';
    final expectedField = expected[name];
    final actualField = actual[name];
    if (expectedField == null) {
      diffs.add(
        FlowActionSchemaDiff(
          code: FlowActionSchemaDiffCode.extraField,
          path: fieldPath,
          expected: null,
          actual: 'field',
        ),
      );
      continue;
    }
    if (actualField == null) {
      diffs.add(
        FlowActionSchemaDiff(
          code: FlowActionSchemaDiffCode.missingField,
          path: fieldPath,
          expected: 'field',
          actual: null,
        ),
      );
      continue;
    }
    if (expectedField.required != actualField.required) {
      diffs.add(
        FlowActionSchemaDiff(
          code: FlowActionSchemaDiffCode.fieldRequiredMismatch,
          path: '$fieldPath.required',
          expected: expectedField.required.toString(),
          actual: actualField.required.toString(),
        ),
      );
    }
    _diffSchema(diffs, fieldPath, expectedField.schema, actualField.schema);
  }
}

void _diffEnumValues(
  List<FlowActionSchemaDiff> diffs,
  String path,
  List<String> expected,
  List<String> actual,
) {
  expected = _canonicalEnumValues(expected);
  actual = _canonicalEnumValues(actual);
  final maxLength =
      expected.length > actual.length ? expected.length : actual.length;
  for (var index = 0; index < maxLength; index += 1) {
    final expectedValue = index < expected.length ? expected[index] : null;
    final actualValue = index < actual.length ? actual[index] : null;
    if (expectedValue == actualValue) {
      continue;
    }
    diffs.add(
      FlowActionSchemaDiff(
        code: FlowActionSchemaDiffCode.enumValueMismatch,
        path: '$path[$index]',
        expected: expectedValue,
        actual: actualValue,
      ),
    );
  }
}

List<String> _canonicalEnumValues(List<String> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'Enum values cannot be empty.');
  }
  final sorted = values.toList()..sort();
  for (var i = 1; i < sorted.length; i += 1) {
    if (sorted[i] == sorted[i - 1]) {
      throw ArgumentError.value(
        values,
        'values',
        'Enum values must be unique.',
      );
    }
  }
  return sorted;
}

void _diffWrappedChild(
  List<FlowActionSchemaDiff> diffs,
  String path,
  FlowActionSchemaDiffCode code,
  FlowActionSchema expected,
  FlowActionSchema actual,
) {
  if (expected.kind != actual.kind) {
    diffs.add(
      FlowActionSchemaDiff(
        code: code,
        path: path,
        expected: expected.kind,
        actual: actual.kind,
      ),
    );
    return;
  }
  _diffSchema(diffs, path, expected, actual);
}
