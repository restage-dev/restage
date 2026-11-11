import 'package:restage_shared/src/expressions/value_program.dart';

/// Which kind of program input a [ValueScopeMiss] is about.
enum ValueScopeBinding {
  /// A value the program captures from its scope.
  capture,

  /// A value the caller passes when it evaluates the program.
  parameter,
}

/// Why a program's declared input does not fit the declared facts.
enum ValueScopeMissKind {
  /// No fact of that binding kind has this name.
  unknown,

  /// The fact's type cannot satisfy the declared type.
  typeMismatch,
}

/// One declared capture or parameter that the facts cannot supply.
final class ValueScopeMiss {
  /// A declared input with no fact of the same binding kind.
  const ValueScopeMiss.unknown(this.name, this.binding, this.declared)
      : kind = ValueScopeMissKind.unknown,
        available = null;

  /// A declared input whose fact has a type [declared] does not accept.
  const ValueScopeMiss.typeMismatch(
    this.name,
    this.binding,
    this.declared,
    ValueType this.available,
  ) : kind = ValueScopeMissKind.typeMismatch;

  /// The declared capture or parameter name.
  final String name;

  /// Whether [name] is a capture or a parameter.
  final ValueScopeBinding binding;

  /// Why the facts cannot supply [name].
  final ValueScopeMissKind kind;

  /// The type the program declares for [name].
  final ValueType declared;

  /// The type of the fact named [name], or null when there is none.
  final ValueType? available;

  @override
  String toString() => switch (available) {
        null => '${binding.name} $name: not a declared fact',
        final available => '${binding.name} $name: declared '
            '${declared.toJson()}, available ${available.toJson()}',
      };
}

/// The captures and parameters of [program] that the facts cannot supply.
///
/// A capture is matched only against [captures] and a parameter only against
/// [parameters]. A fact fits when the declared type accepts its type. The list
/// is empty when every declared input fits.
List<ValueScopeMiss> scopeMisses(
  ValueProgram program, {
  Map<String, ValueType> captures = const {},
  Map<String, ValueType> parameters = const {},
}) =>
    [
      ..._misses(program.captures, captures, ValueScopeBinding.capture),
      ..._misses(program.parameters, parameters, ValueScopeBinding.parameter),
    ];

Iterable<ValueScopeMiss> _misses(
  Map<String, ValueType> declared,
  Map<String, ValueType> facts,
  ValueScopeBinding binding,
) sync* {
  for (final MapEntry(key: name, value: type) in declared.entries) {
    final available = facts[name];
    if (available == null) {
      yield ValueScopeMiss.unknown(name, binding, type);
    } else if (!type.accepts(available)) {
      yield ValueScopeMiss.typeMismatch(name, binding, type, available);
    }
  }
}

/// The result of [evaluateOrMissing] when the program could not produce one.
final class ValueMissing {
  const ValueMissing._();

  @override
  String toString() => 'valueMissing';
}

/// Returned by [evaluateOrMissing] when an input is missing or evaluation
/// fails.
const ValueMissing valueMissing = ValueMissing._();

/// Validates and evaluates [program] over the given facts, returning
/// [valueMissing] instead of throwing.
///
/// The result is [valueMissing] when a declared capture or parameter has no
/// entry in the map for its binding ([captures] or [parameters]), whatever its
/// declared nullability, and when a value inside a fact is absent or has the
/// wrong shape at any depth. A field present with null stays null. [onError]
/// receives evaluation failures; an error it throws is ignored. Record and list
/// results are returned as plain maps and lists.
Object? evaluateOrMissing(
  ValueProgram program, {
  Map<String, Object?> captures = const {},
  Map<String, Object?> parameters = const {},
  Map<String, ValueOperation> operations = const {},
  void Function(Object error, StackTrace stack)? onError,
}) {
  if (!program.captures.keys.every(captures.containsKey) ||
      !program.parameters.keys.every(parameters.containsKey)) {
    return valueMissing;
  }
  try {
    return _plain(
      ValueEvaluator(
        program,
        captures: _FactReader(captures),
        parameters: parameters,
        operations: operations,
      ).evaluate(),
    );
  } on _MissingFact {
    return valueMissing;
  } on Object catch (error, stack) {
    try {
      onError?.call(error, stack);
    } on Object catch (_) {}
    return valueMissing;
  }
}

Object? _plain(Object? value) => switch (value) {
      final Map<String, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries) key: _plain(value),
        },
      final List<Object?> list => [for (final item in list) _plain(item)],
      _ => value,
    };

final class _MissingFact implements Exception {
  const _MissingFact();
}

final class _FactReader implements ValueReader {
  const _FactReader(this.facts);

  final Map<String, Object?> facts;

  // The value at [path]; throws [_MissingFact] when any step is absent or
  // cannot be indexed.
  Object? _at(List<Object> path) {
    Object? current = facts;
    for (final key in path) {
      current = switch ((current, key)) {
        (final Map<Object?, Object?> map, final String key)
            when map.containsKey(key) =>
          map[key],
        (final List<Object?> list, final int index)
            when index >= 0 && index < list.length =>
          list[index],
        _ => throw const _MissingFact(),
      };
    }
    return current;
  }

  @override
  Object? read(List<Object> path, ValueType type) {
    final value = _at(path);
    if (value == null) return null;
    return switch (type.kind) {
      'record' when value is Map => ValueRecordView(this, path, type.fields),
      'list' when value is List => ValueListView(this, path, type.item!),
      _ when type.matches(value) => value,
      _ => throw const _MissingFact(),
    };
  }

  @override
  int length(List<Object> path) => switch (_at(path)) {
        final List<Object?> list => list.length,
        _ => throw const _MissingFact(),
      };
}
