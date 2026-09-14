import 'package:shared_preferences/shared_preferences.dart';

/// Orders assignment writes and local erasure across configured generations.
abstract final class SurfaceAssignmentPersistence {
  static int _generation = 0;
  static Future<Object?>? _writes;
  static Future<void>? _ready;
  static (Object, StackTrace)? _failure;

  static int get generation => _generation;

  /// New readers and writers must observe successful local erasure first.
  static Future<void> get ready {
    final failure = _failure;
    if (failure != null) return Future<void>.error(failure.$1, failure.$2);
    return _ready ?? Future<void>.value();
  }

  static Future<T> _ordered<T>(Future<T> Function() action) {
    final previous = _writes;
    late final Future<T> result;
    Future<T> execute() async {
      try {
        return await action();
      } finally {
        if (identical(_writes, result)) _writes = null;
      }
    }

    result = previous == null
        ? execute()
        : previous.then((_) => execute(),
            onError: (Object _, StackTrace __) => execute());
    _writes = result;
    result.ignore();
    return result;
  }

  static Future<bool> writeString(
    String key,
    String value, {
    required int generation,
  }) async {
    await ready;
    return _ordered(() async {
      if (generation != _generation) return false;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation) return false;
      return prefs.setString(key, value);
    });
  }

  /// Invalidates pending writes immediately and erases after active writes end.
  /// The actor is installation-wide, so reset retires all SDK assignment scopes.
  static Future<void> forget({Future<void>? afterIdentityReset}) {
    final generation = ++_generation;
    _failure = null;
    return _ready = _ordered(() async {
      try {
        await afterIdentityReset;
        final prefs = await SharedPreferences.getInstance();
        // Failed platform writes/removals can still alter the preferences cache.
        await prefs.reload();
        for (final key in prefs.getKeys()) {
          if (key.startsWith('restage.assignmentRegistration.') ||
              key.startsWith('restage.assignment.')) {
            if (!await prefs.remove(key)) {
              throw StateError('Assignment state could not be removed');
            }
          }
        }
      } catch (error, stack) {
        if (generation == _generation) _failure = (error, stack);
        rethrow;
      } finally {
        // Completed operations need not retain their originating async context.
        if (generation == _generation) _ready = null;
      }
    });
  }
}
