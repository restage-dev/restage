part of 'builder_binding.dart';

// Decoded programs by their text and by what validated them, so a rebuild
// decodes and validates each program once. Bounded, oldest first out.
final class _ProgramCache<T extends Object> {
  _ProgramCache(this._decode);

  final T Function(String encoded, Map<String, ValueOperation> operations,
      ValueOperationContext? context) _decode;
  final _entries = <_ProgramKey, T>{};
  static const _limit = 512;

  T decode(String encoded,
      {required Map<String, ValueOperation> operations,
      ValueOperationContext? context}) {
    final key = _ProgramKey(encoded, operations, context);
    // A hit leaves the stored key in place: the lookup key holds the
    // operations themselves, and with them the mount's native values.
    final hit = _entries[key];
    if (hit != null) return hit;
    _debugDecodes++;
    final program = _decode(encoded, operations, context);
    _entries[key.stored()] = program;
    if (_entries.length > _limit) _entries.remove(_entries.keys.first);
    return program;
  }
}

int _debugDecodes = 0;

/// How many programs were decoded rather than found in the cache.
@visibleForTesting
int get debugProgramDecodes => _debugDecodes;

final _builderPrograms = _ProgramCache<BuilderProgram>((encoded, operations,
        context) =>
    BuilderProgram.decode(encoded, operations: operations, context: context));

final _valuePrograms = _ProgramCache<ValueProgram>(
    (encoded, operations, context) =>
        ValueProgram.decode(encoded, operations: operations, context: context));

// What a program's validation reads: its text, each operation (a native call
// by its declarations, any other by identity), the visible locals and depth.
// A lookup reads the operations in place; a stored key keeps only their
// declarations and identities.
final class _ProgramKey {
  _ProgramKey(this.encoded, Map<String, ValueOperation> this._live,
      ValueOperationContext? context)
      : _parts = null,
        locals = switch (context?.locals) {
          null || Map(isEmpty: true) => '',
          final locals => jsonEncode({
              for (final MapEntry(:key, :value) in locals.entries)
                key: value.toJson(),
            }),
        },
        depth = context?.depth ?? 0 {
    var hash = Object.hash(encoded, locals, depth);
    for (final MapEntry(:key, :value) in _live!.entries) {
      hash = Object.hash(hash, key, _partHash(value));
    }
    hashCode = hash;
  }

  _ProgramKey._stored(
      this.encoded, this._parts, this.locals, this.depth, this.hashCode)
      : _live = null;

  final String encoded;
  final Map<String, ValueOperation>? _live;
  final List<Object>? _parts;
  final String locals;
  final int depth;

  @override
  late final int hashCode;

  _ProgramKey stored() => _ProgramKey._stored(
      encoded,
      _parts ??
          [
            for (final MapEntry(:key, :value) in _live!.entries) ...[
              key,
              switch (value) {
                final NativeCallValueOperation call =>
                  _Declarations(call.declarations),
                _ => _Same(value),
              },
            ],
          ],
      locals,
      depth,
      hashCode);

  static int _partHash(ValueOperation operation) => switch (operation) {
        final NativeCallValueOperation call =>
          _Declarations.hashOf(call.declarations),
        _ => identityHashCode(operation),
      };

  @override
  bool operator ==(Object other) {
    if (other is! _ProgramKey ||
        hashCode != other.hashCode ||
        encoded != other.encoded ||
        locals != other.locals ||
        depth != other.depth) {
      return false;
    }
    final (stored, live) = _parts != null ? (this, other) : (other, this);
    final parts = stored._parts;
    final operations = live._live;
    if (parts == null || operations == null) {
      return listEquals(_parts, other._parts);
    }
    if (parts.length != operations.length * 2) return false;
    var index = 0;
    for (final MapEntry(:key, :value) in operations.entries) {
      final part = parts[index + 1];
      if (parts[index] != key ||
          !switch ((part, value)) {
            (
              final _Declarations declared,
              final NativeCallValueOperation call
            ) =>
              mapEquals(declared.declarations, call.declarations),
            (final _Same same, _) => identical(same.value, value),
            _ => false,
          }) {
        return false;
      }
      index += 2;
    }
    return true;
  }
}

final class _Same {
  _Same(this.value);

  final Object value;

  @override
  int get hashCode => identityHashCode(value);

  @override
  bool operator ==(Object other) =>
      other is _Same && identical(value, other.value);
}

final class _Declarations {
  _Declarations(this.declarations);

  final Map<String, NativeBindingContract> declarations;

  static int hashOf(Map<String, NativeBindingContract> declarations) =>
      Object.hashAllUnordered([
        for (final MapEntry(:key, :value) in declarations.entries)
          Object.hash(key, value),
      ]);

  @override
  late final int hashCode = hashOf(declarations);

  @override
  bool operator ==(Object other) =>
      other is _Declarations && mapEquals(declarations, other.declarations);
}
