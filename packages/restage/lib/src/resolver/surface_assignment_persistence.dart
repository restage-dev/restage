import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Orders assignment writes and local erasure across configured generations.
abstract final class SurfaceAssignmentPersistence {
  static int _generation = 0;
  static Future<Object?>? _writes;
  static Future<void>? _ready;
  static (Object, StackTrace)? _failure;
  // Keys a failed removal dropped from the cache but may leave on the platform.
  static final Set<String> _unremoved = {};

  static int get generation => _generation;

  /// Discards volatile state after all work has settled, as a new process would.
  @visibleForTesting
  static void debugRestart() {
    _generation++;
    _writes = null;
    _ready = null;
    _failure = null;
    _unremoved.clear();
    _unsaved.clear();
  }

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
      _unsaved.add(key);
      final saved = await prefs.setString(key, value);
      if (saved) _unsaved.remove(key);
      return saved;
    });
  }

  // Keys whose last write in this process did not reach storage.
  static final Set<String> _unsaved = {};

  /// Whether the last write of [key] in this process did not reach storage.
  static bool isUnsaved(String key) => _unsaved.contains(key);

  /// Removes one retained value in the same order as writes.
  static Future<bool> remove(String key, {required int generation}) async {
    await ready;
    return _ordered(() async {
      if (generation != _generation) return false;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation) return false;
      return _remove(prefs, key);
    });
  }

  /// Invalidates pending writes immediately and erases after active writes end.
  /// The actor is installation-wide, so reset retires all SDK assignment scopes.
  static Future<void> forget({
    Future<void>? afterIdentityReset,
    Future<void> Function()? afterErasure,
  }) {
    final generation = ++_generation;
    _failure = null;
    return _ready = _ordered(() async {
      try {
        await afterIdentityReset;
        final prefs = await SharedPreferences.getInstance();
        // The cache is shared with the app and never reloaded: a reload would
        // drop writes made while it runs. Failed removals are retried instead.
        for (final key in {...prefs.getKeys(), ..._unremoved}) {
          if (key.startsWith('restage.assignmentRegistration.') ||
              key.startsWith('restage.assignment.')) {
            if (!await _remove(prefs, key)) {
              throw StateError('Assignment state could not be removed');
            }
          }
        }
        if (afterErasure != null) await afterErasure();
      } catch (error, stack) {
        if (generation == _generation) _failure = (error, stack);
        rethrow;
      } finally {
        // Completed operations need not retain their originating async context.
        if (generation == _generation) _ready = null;
      }
    });
  }

  static Future<bool> _remove(SharedPreferences prefs, String key) async {
    _unremoved.add(key);
    final removed = await prefs.remove(key);
    if (removed) _unremoved.remove(key);
    return removed;
  }
}
