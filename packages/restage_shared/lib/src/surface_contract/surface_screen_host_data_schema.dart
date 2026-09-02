// The recursive shape algebra stays compact so related grammar clauses align.
// ignore_for_file: require_trailing_commas
// ignore_for_file: prefer_constructors_over_static_methods

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The sole supported scalar shapes for host-supplied render data.
enum SurfaceScreenHostDataScalarKind {
  /// A JSON boolean.
  boolean('bool'),

  /// A JSON integer.
  integer('int'),

  /// A finite JSON double.
  doubleValue('double'),

  /// A finite JSON number of either numeric kind.
  number('num'),

  /// A JSON string.
  string('string'),

  /// Any recursively valid JSON value.
  jsonValue('jsonValue');

  const SurfaceScreenHostDataScalarKind(this.wireName);

  /// Stable wire discriminator.
  final String wireName;

  /// Parses a stable wire discriminator.
  static SurfaceScreenHostDataScalarKind fromWireName(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('Unsupported host data scalar kind "$value".');
  }
}

/// A closed host-data value shape.
sealed class SurfaceScreenHostDataShape {
  const SurfaceScreenHostDataShape();

  /// Decodes one strict host-data shape object.
  factory SurfaceScreenHostDataShape.fromJson(Object? value,
      {String path = r'$'}) {
    final json = SurfaceContractJson.requireObject(value, path);
    final kind = SurfaceContractJson.requiredString(json, 'kind', path);
    switch (kind) {
      case 'bool':
      case 'int':
      case 'double':
      case 'num':
      case 'string':
      case 'jsonValue':
        SurfaceContractJson.exactKeys(json, const {'kind'}, path);
        return SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.fromWireName(kind),
        );
      case 'nullable':
        SurfaceContractJson.exactKeys(json, const {'kind', 'value'}, path);
        return SurfaceScreenHostDataNullableShapeV1(
          SurfaceScreenHostDataShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'value', path),
            path: '$path.value',
          ),
        );
      case 'list':
        SurfaceContractJson.exactKeys(json, const {'kind', 'items'}, path);
        return SurfaceScreenHostDataListShapeV1(
          SurfaceScreenHostDataShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'items', path),
            path: '$path.items',
          ),
        );
      case 'map':
        SurfaceContractJson.exactKeys(json, const {'kind', 'values'}, path);
        return SurfaceScreenHostDataMapShapeV1(
          SurfaceScreenHostDataShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'values', path),
            path: '$path.values',
          ),
        );
      case 'object':
        SurfaceContractJson.exactKeys(json, const {'kind', 'fields'}, path);
        final raw = SurfaceContractJson.requireObject(
          SurfaceContractJson.requiredValue(json, 'fields', path),
          '$path.fields',
        );
        return SurfaceScreenHostDataObjectShapeV1(<String,
            SurfaceScreenHostDataShape>{
          for (final key in raw.keys)
            key: SurfaceScreenHostDataShape.fromJson(
              raw[key],
              path: '$path.fields.$key',
            ),
        });
      default:
        throw FormatException('Unsupported host data shape kind "$kind".');
    }
  }

  /// The strict JSON representation used by the schema codec and hash.
  Map<String, Object?> toJson();
}

/// A scalar host-data shape.
@immutable
final class SurfaceScreenHostDataScalarShapeV1
    extends SurfaceScreenHostDataShape {
  /// Creates a scalar shape.
  const SurfaceScreenHostDataScalarShapeV1(this.kind);

  /// Stable scalar kind.
  final SurfaceScreenHostDataScalarKind kind;

  @override
  Map<String, Object?> toJson() => {'kind': kind.wireName};
}

/// A host-data shape whose value may be absent.
@immutable
final class SurfaceScreenHostDataNullableShapeV1
    extends SurfaceScreenHostDataShape {
  /// Creates a nullable wrapper around [value].
  const SurfaceScreenHostDataNullableShapeV1(this.value);

  /// The shape carried when the value is present.
  final SurfaceScreenHostDataShape value;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'nullable', 'value': value.toJson()};
}

/// A host-data list shape.
@immutable
final class SurfaceScreenHostDataListShapeV1
    extends SurfaceScreenHostDataShape {
  /// Creates a list shape whose elements are [items].
  const SurfaceScreenHostDataListShapeV1(this.items);

  /// The exact shape of every element.
  final SurfaceScreenHostDataShape items;

  @override
  Map<String, Object?> toJson() => {'kind': 'list', 'items': items.toJson()};
}

/// A string-keyed host-data map shape.
@immutable
final class SurfaceScreenHostDataMapShapeV1 extends SurfaceScreenHostDataShape {
  /// Creates a map shape whose values are [values].
  const SurfaceScreenHostDataMapShapeV1(this.values);

  /// The exact shape of every value.
  final SurfaceScreenHostDataShape values;

  @override
  Map<String, Object?> toJson() => {'kind': 'map', 'values': values.toJson()};
}

/// A host-data object shape with a fixed field set.
///
/// Fields are held in ascending key order, so reordering an authored
/// declaration is not a contract change while adding or retyping a field is.
@immutable
final class SurfaceScreenHostDataObjectShapeV1
    extends SurfaceScreenHostDataShape {
  /// Creates an object shape from [fields], canonicalized to key order.
  factory SurfaceScreenHostDataObjectShapeV1(
    Map<String, SurfaceScreenHostDataShape> fields,
  ) {
    if (fields.isEmpty) {
      throw const FormatException('A host data object shape requires a field.');
    }
    final keys = fields.keys.toList()..sort();
    for (final key in keys) {
      SurfaceContractJson.requireUnicodeScalars(key, 'host data field');
      if (key.isEmpty) {
        throw const FormatException('A host data field key must be nonempty.');
      }
    }
    return SurfaceScreenHostDataObjectShapeV1
        ._(<String, SurfaceScreenHostDataShape>{
      for (final key in keys) key: fields[key]!,
    });
  }

  const SurfaceScreenHostDataObjectShapeV1._(this.fields);

  /// Declared fields in ascending key order.
  final Map<String, SurfaceScreenHostDataShape> fields;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'object',
        'fields': <String, Object?>{
          for (final entry in fields.entries) entry.key: entry.value.toJson(),
        },
      };
}

/// The complete set of host-supplied inputs one screen declares.
///
/// Inputs are held in ascending name order so the encoding, and therefore the
/// contract hash, does not depend on authored parameter order.
@immutable
final class SurfaceScreenHostDataSchema {
  /// Creates a schema from [inputs], canonicalized to name order.
  factory SurfaceScreenHostDataSchema(
    Map<String, SurfaceScreenHostDataShape> inputs,
  ) {
    final names = inputs.keys.toList()..sort();
    for (final name in names) {
      SurfaceContractJson.requireUnicodeScalars(name, 'host data input');
      if (name.isEmpty) {
        throw const FormatException('A host data input name must be nonempty.');
      }
    }
    return SurfaceScreenHostDataSchema._(<String, SurfaceScreenHostDataShape>{
      for (final name in names) name: inputs[name]!,
    });
  }

  const SurfaceScreenHostDataSchema._(this.inputs);

  /// The schema of a screen that declares no host-supplied input.
  const SurfaceScreenHostDataSchema.empty()
      : inputs = const <String, SurfaceScreenHostDataShape>{};

  /// Schema version of this wire form.
  static const int schemaVersion = 1;

  /// Declared inputs in ascending name order.
  final Map<String, SurfaceScreenHostDataShape> inputs;

  /// Whether this screen declares no host-supplied input at all.
  bool get isEmpty => inputs.isEmpty;

  /// The strict JSON representation used by the codec and the hash.
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'inputs': <String, Object?>{
          for (final entry in inputs.entries) entry.key: entry.value.toJson(),
        },
      };

  /// Decodes a schema strictly.
  static SurfaceScreenHostDataSchema fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
      json,
      const {'schemaVersion', 'inputs'},
      r'$',
    );
    final version =
        SurfaceContractJson.requiredInt(json, 'schemaVersion', r'$');
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported host data schemaVersion $version.',
      );
    }
    final raw = SurfaceContractJson.requireObject(
      SurfaceContractJson.requiredValue(json, 'inputs', r'$'),
      r'$.inputs',
    );
    return SurfaceScreenHostDataSchema(<String, SurfaceScreenHostDataShape>{
      for (final name in raw.keys)
        name: SurfaceScreenHostDataShape.fromJson(
          raw[name],
          path: r'$.inputs.' + name,
        ),
    });
  }
}

/// Strict codec for [SurfaceScreenHostDataSchema].
abstract final class SurfaceScreenHostDataSchemaV1Codec {
  /// Decodes a schema from a decoded JSON value.
  static SurfaceScreenHostDataSchema decode(Object? value) =>
      SurfaceScreenHostDataSchema.fromJson(value);

  /// Decodes a schema from a JSON document.
  static SurfaceScreenHostDataSchema decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface screen host data schema',
        ),
      );

  /// Encodes a schema to wire JSON.
  static Map<String, Object?> encode(SurfaceScreenHostDataSchema schema) =>
      schema.toJson();

  /// Encodes a schema to a canonical JSON document.
  static String encodeCanonicalJson(SurfaceScreenHostDataSchema schema) =>
      SurfaceContractJson.encode(encode(schema));
}

/// Canonical V1 content hash of one screen's host-data contract.
abstract final class SurfaceScreenHostDataContractHash {
  static const String _domain = 'restage.surface-screen-host-data';

  /// Produces the exact V1 canonical JSON preimage.
  static List<int> preimage(SurfaceScreenHostDataSchema schema) => <int>[
        ...ascii.encode(_domain),
        0,
        ...ascii.encode('v1'),
        0,
        ...utf8.encode(
            SurfaceScreenHostDataSchemaV1Codec.encodeCanonicalJson(schema)),
      ];

  /// Produces the stable `sha256:<64 lowercase hex>` contract hash, or null
  /// when the screen declares no host data at all.
  ///
  /// A screen that declares nothing has no host-data component in its
  /// contract, which is what keeps its fingerprint identical to a build made
  /// before host data existed.
  static String? hash(SurfaceScreenHostDataSchema schema) =>
      schema.isEmpty ? null : SurfaceContractJson.hash(preimage(schema));
}
