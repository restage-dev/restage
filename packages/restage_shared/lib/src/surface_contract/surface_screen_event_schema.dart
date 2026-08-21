// The recursive shape algebra stays compact so related grammar clauses align.
// ignore_for_file: prefer_interpolation_to_compose_strings, require_trailing_commas
// ignore_for_file: lines_longer_than_80_chars, sort_constructors_first

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The sole supported recursive wire shapes for standalone-screen events.
enum SurfaceScreenEventScalarKind {
  /// A JSON boolean.
  boolean('bool'),

  /// A JSON integer.
  integer('int'),

  /// A finite JSON double.
  doubleValue('double'),

  /// A JSON string.
  string('string'),

  /// Any recursively valid JSON value.
  jsonValue('jsonValue');

  const SurfaceScreenEventScalarKind(this.wireName);

  /// Stable wire discriminator.
  final String wireName;

  /// Parses a stable wire discriminator.
  static SurfaceScreenEventScalarKind fromWireName(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('Unsupported event scalar kind "$value".');
  }
}

/// A closed event argument shape.
sealed class SurfaceScreenEventShape {
  const SurfaceScreenEventShape();

  /// Decodes one strict event shape object.
  factory SurfaceScreenEventShape.fromJson(Object? value,
      {String path = r'$'}) {
    final json = SurfaceContractJson.requireObject(value, path);
    final kind = SurfaceContractJson.requiredString(json, 'kind', path);
    switch (kind) {
      case 'bool':
      case 'int':
      case 'double':
      case 'string':
      case 'jsonValue':
        SurfaceContractJson.exactKeys(json, const {'kind'}, path);
        return SurfaceScreenEventScalarShapeV1(
          SurfaceScreenEventScalarKind.fromWireName(kind),
        );
      case 'nullable':
        SurfaceContractJson.exactKeys(json, const {'kind', 'value'}, path);
        return SurfaceScreenEventNullableShapeV1(
          SurfaceScreenEventShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'value', path),
            path: '$path.value',
          ),
        );
      case 'list':
        SurfaceContractJson.exactKeys(json, const {'kind', 'items'}, path);
        return SurfaceScreenEventListShapeV1(
          SurfaceScreenEventShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'items', path),
            path: '$path.items',
          ),
        );
      case 'map':
        SurfaceContractJson.exactKeys(json, const {'kind', 'values'}, path);
        return SurfaceScreenEventMapShapeV1(
          SurfaceScreenEventShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'values', path),
            path: '$path.values',
          ),
        );
      default:
        throw FormatException('Unsupported event shape kind "$kind".');
    }
  }

  /// The strict JSON representation used by the schema codec and hash.
  Map<String, Object?> toJson();

  /// Rejects a value outside this exact shape.
  void validate(Object? value, {String path = r'$'});
}

/// A scalar event shape.
@immutable
final class SurfaceScreenEventScalarShapeV1 extends SurfaceScreenEventShape {
  /// Creates a scalar shape.
  const SurfaceScreenEventScalarShapeV1(this.kind);

  /// Stable scalar kind.
  final SurfaceScreenEventScalarKind kind;

  @override
  Map<String, Object?> toJson() => {'kind': kind.wireName};

  @override
  void validate(Object? value, {String path = r'$'}) {
    switch (kind) {
      case SurfaceScreenEventScalarKind.boolean:
        if (value is! bool) _invalid(path, kind.wireName);
      case SurfaceScreenEventScalarKind.integer:
        if (value is! int) _invalid(path, kind.wireName);
      case SurfaceScreenEventScalarKind.doubleValue:
        if (value is! double || !value.isFinite) _invalid(path, kind.wireName);
      case SurfaceScreenEventScalarKind.string:
        if (value is! String) _invalid(path, kind.wireName);
        SurfaceContractJson.requireUnicodeScalars(value, path);
      case SurfaceScreenEventScalarKind.jsonValue:
        _validateJsonValue(value, path);
    }
  }
}

/// A nullable event shape.
@immutable
final class SurfaceScreenEventNullableShapeV1 extends SurfaceScreenEventShape {
  /// Creates a nullable shape.
  const SurfaceScreenEventNullableShapeV1(this.value);

  /// The non-null value shape.
  final SurfaceScreenEventShape value;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'nullable', 'value': value.toJson()};

  @override
  void validate(Object? value, {String path = r'$'}) {
    if (value != null) this.value.validate(value, path: path);
  }
}

/// A list event shape.
@immutable
final class SurfaceScreenEventListShapeV1 extends SurfaceScreenEventShape {
  /// Creates a list shape.
  const SurfaceScreenEventListShapeV1(this.items);

  /// Shape of every list item.
  final SurfaceScreenEventShape items;

  @override
  Map<String, Object?> toJson() => {'kind': 'list', 'items': items.toJson()};

  @override
  void validate(Object? value, {String path = r'$'}) {
    if (value is! List) _invalid(path, 'list');
    final list = value;
    for (var index = 0; index < list.length; index += 1) {
      items.validate(list[index], path: '$path[$index]');
    }
  }
}

/// A string-keyed map event shape.
@immutable
final class SurfaceScreenEventMapShapeV1 extends SurfaceScreenEventShape {
  /// Creates a map shape.
  const SurfaceScreenEventMapShapeV1(this.values);

  /// Shape of every map value.
  final SurfaceScreenEventShape values;

  @override
  Map<String, Object?> toJson() => {'kind': 'map', 'values': values.toJson()};

  @override
  void validate(Object? value, {String path = r'$'}) {
    final map = _stringKeyedMap(value, path);
    for (final entry in map.entries) {
      values.validate(entry.value, path: '$path.${entry.key}');
    }
  }
}

/// The argument wrapping required for one event.
sealed class SurfaceScreenEventArguments {
  const SurfaceScreenEventArguments();

  /// Stable wrapping discriminator.
  String get encoding;

  /// Encodes the strict argument declaration.
  Map<String, Object?> toJson();

  /// Validates an emitted argument map.
  void validate(Map<String, Object?> arguments, {required String eventId});

  factory SurfaceScreenEventArguments.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    final encoding = SurfaceContractJson.requiredString(json, 'encoding', path);
    switch (encoding) {
      case 'none':
        SurfaceContractJson.exactKeys(json, const {'encoding'}, path);
        return const SurfaceScreenEventNoArguments();
      case 'object':
        SurfaceContractJson.exactKeys(json, const {'encoding', 'shape'}, path);
        final shape = SurfaceScreenEventShape.fromJson(
          SurfaceContractJson.requiredValue(json, 'shape', path),
          path: '$path.shape',
        );
        if (shape is! SurfaceScreenEventMapShapeV1) {
          throw FormatException(
              'Object event arguments at "$path" require a map shape.');
        }
        return SurfaceScreenEventObjectArguments(shape);
      case 'value':
        SurfaceContractJson.exactKeys(json, const {'encoding', 'shape'}, path);
        return SurfaceScreenEventValueArguments(
          SurfaceScreenEventShape.fromJson(
            SurfaceContractJson.requiredValue(json, 'shape', path),
            path: '$path.shape',
          ),
        );
      default:
        throw FormatException(
            'Unsupported event argument encoding "$encoding".');
    }
  }
}

/// A `SurfaceEvent<void>` argument contract.
@immutable
final class SurfaceScreenEventNoArguments extends SurfaceScreenEventArguments {
  /// Creates a no-argument declaration.
  const SurfaceScreenEventNoArguments();

  @override
  String get encoding => 'none';

  @override
  Map<String, Object?> toJson() => {'encoding': encoding};

  @override
  void validate(Map<String, Object?> arguments, {required String eventId}) {
    if (arguments.isNotEmpty) {
      throw FormatException('Event "$eventId" does not accept arguments.');
    }
  }
}

/// A `SurfaceEvent<Map<String, T>>` argument contract.
@immutable
final class SurfaceScreenEventObjectArguments
    extends SurfaceScreenEventArguments {
  /// Creates an object argument declaration.
  SurfaceScreenEventObjectArguments(this.shape) {
    if (shape is! SurfaceScreenEventMapShapeV1) {
      throw const FormatException(
          'Object event arguments require a map shape.');
    }
  }

  /// Required argument-map shape.
  final SurfaceScreenEventShape shape;

  @override
  String get encoding => 'object';

  @override
  Map<String, Object?> toJson() => {
        'encoding': encoding,
        'shape': shape.toJson(),
      };

  @override
  void validate(Map<String, Object?> arguments, {required String eventId}) {
    shape.validate(arguments, path: 'event "$eventId" arguments');
  }
}

/// A non-map, non-void event argument contract.
@immutable
final class SurfaceScreenEventValueArguments
    extends SurfaceScreenEventArguments {
  /// Creates a value argument declaration.
  const SurfaceScreenEventValueArguments(this.shape);

  /// Required value shape.
  final SurfaceScreenEventShape shape;

  @override
  String get encoding => 'value';

  @override
  Map<String, Object?> toJson() => {
        'encoding': encoding,
        'shape': shape.toJson(),
      };

  @override
  void validate(Map<String, Object?> arguments, {required String eventId}) {
    if (arguments.length != 1 || !arguments.containsKey('value')) {
      throw FormatException(
        'Event "$eventId" requires exactly one "value" argument.',
      );
    }
    shape.validate(arguments['value'], path: 'event "$eventId" value');
  }
}

/// One named standalone-screen event declaration.
@immutable
final class SurfaceScreenEvent {
  /// Creates an event declaration.
  SurfaceScreenEvent({
    required this.id,
    required this.arguments,
  }) {
    if (id.isEmpty) {
      throw const FormatException('Surface screen event IDs cannot be empty.');
    }
    SurfaceContractJson.requireUnicodeScalars(id, 'event ID');
  }

  /// Stable emitted event name.
  final String id;

  /// Exact wire argument contract.
  final SurfaceScreenEventArguments arguments;

  /// Strict JSON representation.
  Map<String, Object?> toJson() => {
        'id': id,
        'arguments': arguments.toJson(),
      };
}

/// Complete strict V1 standalone-screen event schema.
@immutable
final class SurfaceScreenEventSchema {
  /// Creates and canonically orders a schema.
  factory SurfaceScreenEventSchema({
    required List<SurfaceScreenEvent> events,
  }) {
    final ids = <String>{};
    final canonical = List<SurfaceScreenEvent>.of(events);
    for (final event in canonical) {
      if (!ids.add(event.id)) {
        throw FormatException(
            'Duplicate surface screen event ID "${event.id}".');
      }
    }
    canonical.sort(
        (left, right) => SurfaceContractJson.compareUtf8(left.id, right.id));
    return SurfaceScreenEventSchema._(List.unmodifiable(canonical));
  }

  const SurfaceScreenEventSchema._(this.events);

  /// The frozen schema version.
  static const int schemaVersion = 1;

  /// Events in canonical raw-UTF-8 ID order.
  final List<SurfaceScreenEvent> events;

  /// Validates one emitted event before a generated conversion decoder runs.
  void validateEvent(String name, Map<String, Object?> arguments) {
    SurfaceContractJson.requireUnicodeScalars(name, 'event name');
    final event = _byId(name);
    if (event == null) {
      throw FormatException('Unexpected surface screen event "$name".');
    }
    event.arguments.validate(arguments, eventId: name);
  }

  SurfaceScreenEvent? _byId(String id) {
    for (final event in events) {
      if (event.id == id) return event;
    }
    return null;
  }
}

/// Strict JSON codec for [SurfaceScreenEventSchema].
abstract final class SurfaceScreenEventSchemaV1Codec {
  /// Decodes one schema object.
  static SurfaceScreenEventSchema decode(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
        json, const {'schemaVersion', 'events'}, r'$');
    final version =
        SurfaceContractJson.requiredInt(json, 'schemaVersion', r'$');
    if (version != SurfaceScreenEventSchema.schemaVersion) {
      throw FormatException(
          'Unsupported surface screen event schemaVersion $version.');
    }
    final rawEvents = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'events', r'$'),
      r'$.events',
    );
    final events = <SurfaceScreenEvent>[];
    for (var index = 0; index < rawEvents.length; index += 1) {
      final path = r'$.events[' + index.toString() + ']';
      final event = SurfaceContractJson.requireObject(rawEvents[index], path);
      SurfaceContractJson.exactKeys(event, const {'id', 'arguments'}, path);
      events.add(
        SurfaceScreenEvent(
          id: SurfaceContractJson.requiredString(event, 'id', path),
          arguments: SurfaceScreenEventArguments.fromJson(
            SurfaceContractJson.requiredValue(event, 'arguments', path),
            path: '$path.arguments',
          ),
        ),
      );
    }
    return SurfaceScreenEventSchema(events: events);
  }

  /// Decodes strict schema JSON.
  static SurfaceScreenEventSchema decodeJson(String source) => decode(
      SurfaceContractJson.decode(source, label: 'surface screen event schema'));

  /// Encodes the schema as the canonical JSON object used by its hash.
  static Map<String, Object?> encode(SurfaceScreenEventSchema schema) => {
        'schemaVersion': SurfaceScreenEventSchema.schemaVersion,
        'events': <Object?>[for (final event in schema.events) event.toJson()],
      };

  /// Encodes strict canonical schema JSON without whitespace or a trailing newline.
  static String encodeCanonicalJson(SurfaceScreenEventSchema schema) =>
      SurfaceContractJson.encode(encode(schema));
}

/// Canonical SHA-256 encoder for [SurfaceScreenEventSchema].
abstract final class SurfaceScreenEventContractHash {
  static const String _domain = 'restage.surface-screen-events';

  /// Produces the exact V1 canonical JSON preimage.
  static List<int> preimage(SurfaceScreenEventSchema schema) => <int>[
        ...ascii.encode(_domain),
        0,
        ...ascii.encode('v1'),
        0,
        ...utf8.encode(
            SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(schema)),
      ];

  /// Produces the stable `sha256:<64 lowercase hex>` contract hash.
  static String hash(SurfaceScreenEventSchema schema) =>
      SurfaceContractJson.hash(preimage(schema));
}

Map<String, Object?> _stringKeyedMap(Object? value, String path) {
  if (value is! Map) _invalid(path, 'string-keyed map');
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) _invalid(path, 'string-keyed map');
    final key = entry.key as String;
    SurfaceContractJson.requireUnicodeScalars(key, '$path key');
    map[key] = entry.value;
  }
  return map;
}

void _validateJsonValue(Object? value, String path) {
  switch (value) {
    case null:
    case bool():
    case int():
      return;
    case double():
      if (!value.isFinite) _invalid(path, 'jsonValue');
      return;
    case String():
      SurfaceContractJson.requireUnicodeScalars(value, path);
      return;
    case List():
      for (var index = 0; index < value.length; index += 1) {
        _validateJsonValue(value[index], '$path[$index]');
      }
      return;
    case Map():
      final map = _stringKeyedMap(value, path);
      for (final entry in map.entries) {
        _validateJsonValue(entry.value, '$path.${entry.key}');
      }
      return;
    default:
      _invalid(path, 'jsonValue');
  }
}

Never _invalid(String path, String expected) =>
    throw FormatException('Expected "$path" to match $expected.');
