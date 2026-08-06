import 'package:meta/meta.dart';

/// Typed validation constraints for one catalog property.
///
/// The known fields mirror JSON Schema keywords supported by the catalog
/// toolchain. [allowedValues] uses the wire keyword `enum`. Unknown wire
/// keywords are retained in [extensions] so a constraints-aware reader can
/// decode and re-encode a newer constraint object without silently erasing it.
///
/// The default constructor is const for annotation authoring. Its
/// [extensions] map is always empty: unknown wire data must enter through
/// [RestageConstraints.withExtensions], which recursively copies and freezes
/// both extensions and allowed values. Collection literals used in a const
/// annotation are transitively const. As with the package's other const model
/// constructors, a list supplied to a non-const invocation of this constructor
/// remains the caller's collection and is revalidated at production codec
/// boundaries.
@immutable
final class RestageConstraints {
  /// Creates author-authored constraints with no unknown wire extensions.
  const RestageConstraints({
    this.minimum,
    this.exclusiveMinimum,
    this.maximum,
    this.exclusiveMaximum,
    this.allowedValues,
    this.pattern,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
  }) : extensions = const <String, Object?>{};

  /// Creates constraints while recursively copying and freezing wire data.
  ///
  /// The catalog decoder uses this path even when [extensions] is empty so an
  /// untrusted decoded [allowedValues] list cannot be mutated through either
  /// an input alias or this object's public getters.
  factory RestageConstraints.withExtensions({
    num? minimum,
    num? exclusiveMinimum,
    num? maximum,
    num? exclusiveMaximum,
    List<Object?>? allowedValues,
    String? pattern,
    int? minLength,
    int? maxLength,
    int? minItems,
    int? maxItems,
    Map<String, Object?> extensions = const <String, Object?>{},
  }) =>
      RestageConstraints._(
        minimum: minimum,
        exclusiveMinimum: exclusiveMinimum,
        maximum: maximum,
        exclusiveMaximum: exclusiveMaximum,
        allowedValues: allowedValues == null
            ? null
            : List<Object?>.unmodifiable(
                allowedValues.map<Object?>(_deepFreeze),
              ),
        pattern: pattern,
        minLength: minLength,
        maxLength: maxLength,
        minItems: minItems,
        maxItems: maxItems,
        extensions: Map<String, Object?>.unmodifiable({
          for (final entry in extensions.entries)
            entry.key: _deepFreeze(entry.value),
        }),
      );

  const RestageConstraints._({
    required this.minimum,
    required this.exclusiveMinimum,
    required this.maximum,
    required this.exclusiveMaximum,
    required this.allowedValues,
    required this.pattern,
    required this.minLength,
    required this.maxLength,
    required this.minItems,
    required this.maxItems,
    required this.extensions,
  });

  /// Canonical empty constraint set used by property-model defaults.
  static const RestageConstraints empty = RestageConstraints();

  /// Inclusive numeric lower bound.
  final num? minimum;

  /// Exclusive numeric lower bound.
  final num? exclusiveMinimum;

  /// Inclusive numeric upper bound.
  final num? maximum;

  /// Exclusive numeric upper bound.
  final num? exclusiveMaximum;

  /// Allowed JSON scalar values. Encoded with the JSON Schema keyword `enum`.
  ///
  /// `null` means absent. A present list is validated as non-empty,
  /// duplicate-free, and compatible with the owning property's scalar type at
  /// the production codec boundary.
  final List<Object?>? allowedValues;

  /// JSON Schema regular-expression pattern for a string value.
  final String? pattern;

  /// Inclusive minimum string length.
  final int? minLength;

  /// Inclusive maximum string length.
  final int? maxLength;

  /// Inclusive minimum list item count.
  final int? minItems;

  /// Inclusive maximum list item count.
  final int? maxItems;

  /// Recursively immutable unknown JSON Schema keywords and values.
  ///
  /// Known keywords can never live here on a valid catalog. The decoder
  /// removes them before construction, and the production encoder rejects a
  /// locally constructed collision.
  final Map<String, Object?> extensions;

  /// Whether this value carries no known or unknown constraints.
  bool get isEmpty =>
      minimum == null &&
      exclusiveMinimum == null &&
      maximum == null &&
      exclusiveMaximum == null &&
      allowedValues == null &&
      pattern == null &&
      minLength == null &&
      maxLength == null &&
      minItems == null &&
      maxItems == null &&
      extensions.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestageConstraints &&
          other.minimum == minimum &&
          other.exclusiveMinimum == exclusiveMinimum &&
          other.maximum == maximum &&
          other.exclusiveMaximum == exclusiveMaximum &&
          _deepEquals(other.allowedValues, allowedValues) &&
          other.pattern == pattern &&
          other.minLength == minLength &&
          other.maxLength == maxLength &&
          other.minItems == minItems &&
          other.maxItems == maxItems &&
          _deepEquals(other.extensions, extensions);

  @override
  int get hashCode => Object.hash(
        minimum,
        exclusiveMinimum,
        maximum,
        exclusiveMaximum,
        _deepHash(allowedValues),
        pattern,
        minLength,
        maxLength,
        minItems,
        maxItems,
        _deepHash(extensions),
      );
}

Object? _deepFreeze(Object? value) {
  if (value is List) {
    return List<Object?>.unmodifiable(value.map<Object?>(_deepFreeze));
  }
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable({
      for (final entry in value.entries)
        _deepFreeze(entry.key): _deepFreeze(entry.value),
    });
  }
  return value;
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_deepEquals(left[i], right[i])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map<int>(_deepHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map<int>(
        (entry) => Object.hash(
          _deepHash(entry.key),
          _deepHash(entry.value),
        ),
      ),
    );
  }
  return value.hashCode;
}
