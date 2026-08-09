import 'package:meta/meta.dart';

/// Resolved Dart type identity used by a reconstructed constant.
@immutable
sealed class DartTypeIdentity {
  /// Creates an importable named type identity.
  const factory DartTypeIdentity({
    required String libraryUri,
    required String symbolName,
    List<DartTypeIdentity> typeArguments,
    bool nullable,
  }) = DartNamedTypeIdentity;

  const DartTypeIdentity._({required this.nullable});

  /// Whether the type carries an outer nullable suffix.
  final bool nullable;
}

/// Importable identity for a named Dart type.
@immutable
final class DartNamedTypeIdentity extends DartTypeIdentity {
  /// Creates an importable named type identity.
  const DartNamedTypeIdentity({
    required this.libraryUri,
    required this.symbolName,
    this.typeArguments = const [],
    super.nullable = false,
  }) : super._();

  /// Defining library URI.
  final String libraryUri;

  /// Public declaration name.
  final String symbolName;

  /// Instantiated type arguments, in declaration order.
  final List<DartTypeIdentity> typeArguments;

  @override
  bool operator ==(Object other) =>
      other is DartNamedTypeIdentity &&
      other.libraryUri == libraryUri &&
      other.symbolName == symbolName &&
      other.nullable == nullable &&
      _listEquals(other.typeArguments, typeArguments);

  @override
  int get hashCode => Object.hash(
        libraryUri,
        symbolName,
        nullable,
        Object.hashAll(typeArguments),
      );
}

/// One named field in a structural Dart record type.
@immutable
final class DartRecordTypeNamedField {
  /// Creates a named record-type field.
  const DartRecordTypeNamedField(this.name, this.type);

  /// Field name used for canonical name-based record identity.
  final String name;

  /// Exact resolved field type.
  final DartTypeIdentity type;

  @override
  bool operator ==(Object other) =>
      other is DartRecordTypeNamedField &&
      other.name == name &&
      other.type == type;

  @override
  int get hashCode => Object.hash(name, type);
}

/// Structural identity for a Dart record type.
@immutable
final class DartRecordTypeIdentity extends DartTypeIdentity {
  /// Creates a structural record type identity.
  const DartRecordTypeIdentity({
    this.positional = const [],
    this.named = const [],
    super.nullable = false,
  }) : super._();

  /// Positional field types in declaration order.
  final List<DartTypeIdentity> positional;

  /// Named field types.
  ///
  /// Valid identities compare and hash these fields in ascending name order,
  /// independent of the order supplied to the constructor.
  final List<DartRecordTypeNamedField> named;

  @override
  bool operator ==(Object other) =>
      other is DartRecordTypeIdentity &&
      other.nullable == nullable &&
      _listEquals(other.positional, positional) &&
      _namedListEquals(other.named, named, (field) => field.name);

  @override
  int get hashCode => Object.hash(
        nullable,
        Object.hashAll(positional),
        _namedListHash(named, (field) => field.name),
      );
}

/// Lossless, target-independent representation of a reconstructable Dart const.
sealed class DartConstValue {
  const DartConstValue();
}

/// The constant `null`.
@immutable
final class DartConstNull extends DartConstValue {
  /// Creates the null constant.
  const DartConstNull();

  @override
  bool operator ==(Object other) => other is DartConstNull;

  @override
  int get hashCode => 0;
}

/// A portable bool, int, finite double, or String constant.
@immutable
final class DartConstScalar extends DartConstValue {
  /// Creates a scalar constant.
  const DartConstScalar(this.value);

  /// Scalar value.
  final Object value;

  @override
  bool operator ==(Object other) =>
      other is DartConstScalar && _scalarEquals(other.value, value);

  @override
  int get hashCode => _scalarHash(value);
}

/// A public importable top-level, class-static, extension-static, or enum
/// constant, or a public top-level/static function tear-off.
@immutable
final class DartConstReference extends DartConstValue {
  /// Creates an importable constant or function reference.
  const DartConstReference({
    required this.libraryUri,
    required this.member,
    this.owner,
  });

  /// Defining library URI.
  final String libraryUri;

  /// Enclosing public declaration, or `null` for a top-level constant or
  /// function.
  final String? owner;

  /// Public constant or function member name.
  final String member;

  @override
  bool operator ==(Object other) =>
      other is DartConstReference &&
      other.libraryUri == libraryUri &&
      other.owner == owner &&
      other.member == member;

  @override
  int get hashCode => Object.hash(libraryUri, owner, member);
}

/// One named argument to a reconstructed const invocation or record.
@immutable
final class DartConstNamedValue {
  /// Creates a named value.
  const DartConstNamedValue(this.name, this.value);

  /// Argument or record-field name.
  final String name;

  /// Reconstructed value.
  final DartConstValue value;

  @override
  bool operator ==(Object other) =>
      other is DartConstNamedValue &&
      other.name == name &&
      other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

/// A public const-constructor invocation.
@immutable
final class DartConstInvocation extends DartConstValue {
  /// Creates an invocation constant.
  const DartConstInvocation({
    required this.type,
    this.constructorName,
    this.positional = const [],
    this.named = const [],
  });

  /// Instantiated result type.
  final DartTypeIdentity type;

  /// Public named constructor, or `null` for the unnamed constructor.
  final String? constructorName;

  /// Positional argument values.
  final List<DartConstValue> positional;

  /// Named argument values.
  ///
  /// Valid invocations compare and hash these arguments in ascending name
  /// order, independent of the order supplied to the constructor.
  final List<DartConstNamedValue> named;

  @override
  bool operator ==(Object other) =>
      other is DartConstInvocation &&
      other.type == type &&
      other.constructorName == constructorName &&
      _listEquals(other.positional, positional) &&
      _namedListEquals(other.named, named, (argument) => argument.name);

  @override
  int get hashCode => Object.hash(
        type,
        constructorName,
        Object.hashAll(positional),
        _namedListHash(named, (argument) => argument.name),
      );
}

/// A const list.
@immutable
final class DartConstList extends DartConstValue {
  /// Creates a list constant.
  const DartConstList(this.values, {this.type});

  /// Elements in source order.
  final List<DartConstValue> values;

  /// Full instantiated source type, or `null` for a legacy decoded value.
  final DartTypeIdentity? type;

  @override
  bool operator ==(Object other) =>
      other is DartConstList &&
      other.type == type &&
      _listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(values));
}

/// A const set.
@immutable
final class DartConstSet extends DartConstValue {
  /// Creates a set constant.
  const DartConstSet(this.values, {this.type});

  /// Elements in iteration order.
  final List<DartConstValue> values;

  /// Full instantiated source type, or `null` for a legacy decoded value.
  final DartTypeIdentity? type;

  @override
  bool operator ==(Object other) =>
      other is DartConstSet &&
      other.type == type &&
      _listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(values));
}

/// One key/value pair in a const map.
@immutable
final class DartConstMapEntry {
  /// Creates a map entry.
  const DartConstMapEntry(this.key, this.value);

  /// Constant key.
  final DartConstValue key;

  /// Constant value.
  final DartConstValue value;

  @override
  bool operator ==(Object other) =>
      other is DartConstMapEntry && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);
}

/// A const map.
@immutable
final class DartConstMap extends DartConstValue {
  /// Creates a map constant.
  const DartConstMap(this.entries, {this.type});

  /// Entries in iteration order.
  final List<DartConstMapEntry> entries;

  /// Full instantiated source type, or `null` for a legacy decoded value.
  final DartTypeIdentity? type;

  @override
  bool operator ==(Object other) =>
      other is DartConstMap &&
      other.type == type &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(entries));
}

/// A const record.
@immutable
final class DartConstRecord extends DartConstValue {
  /// Creates a record constant.
  const DartConstRecord({this.positional = const [], this.named = const []});

  /// Positional fields in declaration order.
  final List<DartConstValue> positional;

  /// Named fields.
  ///
  /// Valid records compare and hash these fields in ascending name order,
  /// independent of the order supplied to the constructor.
  final List<DartConstNamedValue> named;

  @override
  bool operator ==(Object other) =>
      other is DartConstRecord &&
      _listEquals(other.positional, positional) &&
      _namedListEquals(other.named, named, (field) => field.name);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(positional),
        _namedListHash(named, (field) => field.name),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _namedListEquals<T>(
  List<T> a,
  List<T> b,
  String Function(T value) nameOf,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  final aByName = <String, T>{for (final value in a) nameOf(value): value};
  final bByName = <String, T>{for (final value in b) nameOf(value): value};
  if (aByName.length != a.length || bByName.length != b.length) {
    // Duplicate names are invalid at the schema boundary. Preserve
    // order-sensitive model semantics for such invalid standalone values so
    // equality and hashing retain a well-defined contract.
    return _listEquals(a, b);
  }
  for (final entry in aByName.entries) {
    if (bByName[entry.key] != entry.value) return false;
  }
  return true;
}

int _namedListHash<T>(
  List<T> values,
  String Function(T value) nameOf,
) {
  final byName = <String, T>{
    for (final value in values) nameOf(value): value,
  };
  if (byName.length != values.length) return Object.hashAll(values);
  final names = byName.keys.toList()..sort();
  return Object.hashAll([for (final name in names) byName[name]]);
}

bool _scalarEquals(Object a, Object b) {
  if (a.runtimeType != b.runtimeType) return false;
  if (a is double) {
    final other = b as double;
    if (a == 0 && other == 0) return a.isNegative == other.isNegative;
    return a == b;
  }
  return a == b;
}

int _scalarHash(Object value) {
  if (value is double) {
    return Object.hash(
      double,
      value,
      value == 0 ? value.isNegative : null,
    );
  }
  return Object.hash(value.runtimeType, value);
}
