import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:rfw/rfw.dart';

/// The `DynamicContent` root key host-supplied render data is published under.
const String kContextDataKey = 'context';

/// Maximum nested map or list depth below the context root.
const int _maxContextNestingDepth = 32;

/// Maximum retained normalized nodes, including the context root.
const int _maxContextNodes = 10000;

/// Maximum inspected map entries and list elements per normalization.
const int _maxContextInspectedEntries = 100000;

final Object _omittedContextValue = Object();
final Object _failedContextCollection = Object();

final class _ContextCycleFailure {
  const _ContextCycleFailure(this.collection, this.path);

  final Object collection;
  final String path;
}

/// Controls how invalid context values are handled during normalization.
@visibleForTesting
final class ContextNormalizationPolicy {
  const ContextNormalizationPolicy({
    required this.throwOnViolation,
    required this.reportError,
  });

  final bool throwOnViolation;
  final void Function(FlutterErrorDetails details) reportError;
}

final ContextNormalizationPolicy _defaultContextNormalizationPolicy =
    ContextNormalizationPolicy(
  throwOnViolation: kDebugMode,
  reportError: FlutterError.reportError,
);

/// Immutable, normalized host-supplied render data.
final class ContextSnapshot {
  ContextSnapshot._(this._value);

  final Map<String, Object?> _value;

  /// Creates normalized data from [raw], omitting nulls and compacting lists.
  /// [previous] is only an allocation optimization, never a correctness input.
  factory ContextSnapshot.of(
    Map<String, Object?> raw, {
    ContextSnapshot? previous,
    @visibleForTesting ContextNormalizationPolicy? policy,
  }) {
    final normalized = _ContextNormalizer(
      policy ?? _defaultContextNormalizationPolicy,
    ).normalize(raw);
    if (previous != null && _deepEquals(normalized, previous.value)) {
      return previous;
    }
    return ContextSnapshot._(normalized);
  }

  /// The normalized, deeply unmodifiable render-context map.
  Map<String, Object?> get value => _value;

  @override
  bool operator ==(Object other) {
    return other is ContextSnapshot && _deepEquals(_value, other._value);
  }

  @override
  int get hashCode => _deepHash(_value);

  @override
  String toString() => 'ContextSnapshot($_value)';
}

final class RestageContextSnapshotScope extends InheritedWidget {
  const RestageContextSnapshotScope({
    super.key,
    required this.snapshot,
    required super.child,
  });

  final ContextSnapshot? snapshot;

  static RestageContextSnapshotScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RestageContextSnapshotScope>();

  @override
  bool updateShouldNotify(RestageContextSnapshotScope oldWidget) =>
      !identical(snapshot, oldWidget.snapshot);
}

enum _ContextPublisherState {
  never,
  published,
  withdrawn,
  unknown,
}

final class _ContextPublication {
  _ContextPublication.pending();

  _ContextPublication.ready(this.snapshot);

  late final ContextSnapshot? snapshot;
}

/// Publishes context snapshots to one [DynamicContent] target.
final class ContextPublisher {
  ContextPublisher(
    this._target, {
    @visibleForTesting ContextNormalizationPolicy? normalizationPolicy,
  }) : _normalizationPolicy =
            normalizationPolicy ?? _defaultContextNormalizationPolicy;

  final DynamicContent _target;
  final ContextNormalizationPolicy _normalizationPolicy;
  bool _isPublishing = false;
  final Queue<_ContextPublication> _pendingPublications =
      Queue<_ContextPublication>();
  _ContextPublisherState _state = _ContextPublisherState.never;
  ContextSnapshot? _lastPublished;

  /// The snapshot currently known to be published by this publisher.
  ContextSnapshot? get lastPublished {
    return _state == _ContextPublisherState.published ? _lastPublished : null;
  }

  /// Normalizes and publishes [context] to this publisher's target.
  void publish(Map<String, Object?>? context) {
    final publication = _ContextPublication.pending();
    final startsDrain = _reserve(publication);
    try {
      publication.snapshot = context == null
          ? null
          : ContextSnapshot.of(
              context,
              previous: lastPublished,
              policy: _normalizationPolicy,
            );
    } catch (_) {
      _discardFrom(publication);
      if (startsDrain) {
        _pendingPublications.clear();
        _isPublishing = false;
      }
      rethrow;
    }
    if (startsDrain) {
      _drain();
    }
  }

  /// Publishes a normalized [snapshot] to this publisher's target.
  void publishSnapshot(ContextSnapshot? snapshot) {
    final publication = _ContextPublication.ready(snapshot);
    if (_reserve(publication)) {
      _drain();
    }
  }

  bool _reserve(_ContextPublication publication) {
    _pendingPublications.addLast(publication);
    if (_isPublishing) {
      return false;
    }
    _isPublishing = true;
    return true;
  }

  void _discardFrom(_ContextPublication publication) {
    while (_pendingPublications.isNotEmpty) {
      if (identical(_pendingPublications.removeLast(), publication)) {
        return;
      }
    }
  }

  void _drain() {
    try {
      while (_pendingPublications.isNotEmpty) {
        _apply(_pendingPublications.removeFirst().snapshot);
      }
    } finally {
      _pendingPublications.clear();
      _isPublishing = false;
    }
  }

  void _apply(ContextSnapshot? snapshot) {
    if (snapshot == null) {
      switch (_state) {
        case _ContextPublisherState.never:
        case _ContextPublisherState.withdrawn:
          return;
        case _ContextPublisherState.published:
          if (lastPublished?.value.isEmpty ?? false) {
            _lastPublished = null;
            _state = _ContextPublisherState.withdrawn;
            return;
          }
          _withdraw();
          return;
        case _ContextPublisherState.unknown:
          _withdraw();
          return;
      }
    }

    if (lastPublished == snapshot) {
      return;
    }
    _publish(snapshot);
  }

  void _publish(ContextSnapshot snapshot) {
    _state = _ContextPublisherState.unknown;
    _target.update(kContextDataKey, snapshot.value);
    _lastPublished = snapshot;
    _state = _ContextPublisherState.published;
  }

  void _withdraw() {
    _state = _ContextPublisherState.unknown;
    _target.update(kContextDataKey, const <String, Object?>{});
    _lastPublished = null;
    _state = _ContextPublisherState.withdrawn;
  }
}

final class _ContextNormalizer {
  _ContextNormalizer(this._policy);

  final ContextNormalizationPolicy _policy;
  final Set<Object> _activeContainers = HashSet<Object>.identity();
  final Set<Object> _reportedCyclicContainers = HashSet<Object>.identity();
  int _retainedNodes = 0;
  int _inspectedEntries = 0;
  bool _nodeLimitReported = false;
  bool _inspectionLimitReported = false;

  Map<String, Object?> normalize(Map<String, Object?> raw) {
    final normalized = _normalizeMap(raw, kContextDataKey, 0);
    return normalized is Map<String, Object?>
        ? normalized
        : const <String, Object?>{};
  }

  Object? _normalizeMap(
    Map<Object?, Object?> raw,
    String path,
    int depth,
  ) {
    final retainedNodesBefore = _retainedNodes;
    if (!_acceptDepth(path, depth)) return _failedContextCollection;
    if (!_activeContainers.add(raw)) {
      return _ContextCycleFailure(raw, path);
    }
    var completed = false;
    try {
      if (!_retainNode(path)) return _failedContextCollection;

      final normalized = <String, Object?>{};
      final retainedNodesByKey = <String, int>{};
      final Iterator<Object?> iterator;
      try {
        iterator = raw.keys.iterator;
      } catch (_) {
        return _omitUnreadableCollection(path);
      }
      while (true) {
        final bool hasNext;
        try {
          hasNext = iterator.moveNext();
        } catch (_) {
          return _omitUnreadableCollection(path);
        }
        if (!hasNext) break;
        if (!_inspectEntry(path)) return _failedContextCollection;
        final Object? rawKey;
        try {
          rawKey = iterator.current;
        } catch (_) {
          return _omitUnreadableCollection(path);
        }
        if (rawKey is! String) {
          _reportInvalidContextKey(path, rawKey);
          continue;
        }
        final Object? rawValue;
        try {
          rawValue = raw[rawKey];
        } catch (_) {
          return _omitUnreadableCollection(path);
        }
        final valuePath = _mapValuePath(path, rawKey);
        final hadPreviousValue = normalized.containsKey(rawKey);
        final previousRetainedNodes = retainedNodesByKey[rawKey] ?? 0;
        _retainedNodes -= previousRetainedNodes;
        final retainedNodesBeforeValue = _retainedNodes;
        final value = _normalizeValue(rawValue, valuePath, depth);
        if (value is _ContextCycleFailure) {
          if (identical(value.collection, raw)) {
            _reportCyclicCollection(value);
            return _failedContextCollection;
          }
          return value;
        }
        if (identical(value, _omittedContextValue) ||
            identical(value, _failedContextCollection)) {
          if (hadPreviousValue) normalized.remove(rawKey);
          retainedNodesByKey.remove(rawKey);
          continue;
        }
        if (value is! Map && value is! List && !_retainNode(valuePath)) {
          return _failedContextCollection;
        }
        normalized[rawKey] = value;
        retainedNodesByKey[rawKey] = _retainedNodes - retainedNodesBeforeValue;
      }
      final result = Map<String, Object?>.unmodifiable(normalized);
      completed = true;
      return result;
    } finally {
      _activeContainers.remove(raw);
      if (!completed) _retainedNodes = retainedNodesBefore;
    }
  }

  Object? _normalizeList(
    List<Object?> raw,
    String path,
    int depth,
  ) {
    final retainedNodesBefore = _retainedNodes;
    if (!_acceptDepth(path, depth)) return _failedContextCollection;
    if (!_activeContainers.add(raw)) {
      return _ContextCycleFailure(raw, path);
    }
    var completed = false;
    try {
      if (!_retainNode(path)) return _failedContextCollection;

      final normalized = <Object?>[];
      var index = 0;
      while (true) {
        final int length;
        try {
          length = raw.length;
        } catch (_) {
          return _omitUnreadableCollection(path);
        }
        if (index >= length) break;
        if (!_inspectEntry(path)) return _failedContextCollection;
        final Object? rawValue;
        try {
          rawValue = raw[index];
        } catch (_) {
          return _omitUnreadableCollection(path);
        }
        final valuePath = '$path[$index]';
        final value = _normalizeValue(rawValue, valuePath, depth);
        if (value is _ContextCycleFailure) {
          if (identical(value.collection, raw)) {
            _reportCyclicCollection(value);
            return _failedContextCollection;
          }
          return value;
        }
        if (identical(value, _omittedContextValue) ||
            identical(value, _failedContextCollection)) {
          index += 1;
          continue;
        }
        if (value is! Map && value is! List && !_retainNode(valuePath)) {
          return _failedContextCollection;
        }
        normalized.add(value);
        index += 1;
      }
      final result = List<Object?>.unmodifiable(normalized);
      completed = true;
      return result;
    } finally {
      _activeContainers.remove(raw);
      if (!completed) _retainedNodes = retainedNodesBefore;
    }
  }

  Object? _normalizeValue(Object? raw, String path, int depth) {
    if (raw == null) {
      return _omittedContextValue;
    }
    if (raw is String || raw is int || raw is bool) {
      return raw;
    }
    if (raw is double) {
      if (!raw.isFinite) {
        _reportInvalidNonFiniteDouble(path);
        return _omittedContextValue;
      }
      return raw == 0.0 ? 0.0 : raw;
    }
    if (raw is Map<Object?, Object?>) {
      return _normalizeMap(raw, path, depth + 1);
    }
    if (raw is List<Object?>) {
      return _normalizeList(raw, path, depth + 1);
    }
    _reportInvalidContextValue(path, raw);
    return _omittedContextValue;
  }

  String _mapValuePath(String path, String key) {
    if (_policy.throwOnViolation) return '$path.$key';
    return '$path.<map value>';
  }

  bool _acceptDepth(String path, int depth) {
    if (depth > _maxContextNestingDepth) {
      _reportInvalidContextMessage(
        'Invalid render-context value at $path: nesting exceeds '
        '$_maxContextNestingDepth levels.',
      );
      return false;
    }
    return true;
  }

  void _reportCyclicCollection(_ContextCycleFailure failure) {
    if (_reportedCyclicContainers.add(failure.collection)) {
      _reportInvalidContextMessage(
        'Invalid render-context value at ${failure.path}: cyclic collections are not '
        'supported.',
      );
    }
  }

  bool _retainNode(String path) {
    if (_retainedNodes < _maxContextNodes) {
      _retainedNodes += 1;
      return true;
    }
    if (!_nodeLimitReported) {
      _nodeLimitReported = true;
      _reportInvalidContextMessage(
        'Invalid render-context value at $path: context exceeds '
        '$_maxContextNodes retained normalized nodes.',
      );
    }
    return false;
  }

  bool _inspectEntry(String path) {
    if (_inspectedEntries < _maxContextInspectedEntries) {
      _inspectedEntries += 1;
      return true;
    }
    if (!_inspectionLimitReported) {
      _inspectionLimitReported = true;
      _reportInvalidContextMessage(
        'Invalid render-context collection at $path: context exceeds '
        '$_maxContextInspectedEntries inspected map entries or list elements.',
      );
    }
    return false;
  }

  Object _omitUnreadableCollection(String path) {
    _reportInvalidContextMessage(
      'Invalid render-context collection at $path: the collection could not '
      'be read.',
    );
    return _failedContextCollection;
  }

  void _reportInvalidContextKey(String path, Object? key) {
    _reportInvalidContextMessage(
      'Invalid render-context key at $path: keys must be String, but found '
      '${_typeNameOf(key)}.',
    );
  }

  void _reportInvalidContextValue(String path, Object? value) {
    _reportInvalidContextMessage(
      'Invalid render-context value at $path: ${_typeNameOf(value)} is not '
      'supported. Supported types: String, int, double, bool, List, and '
      'Map with String keys.',
    );
  }

  void _reportInvalidNonFiniteDouble(String path) {
    _reportInvalidContextMessage(
      'Invalid render-context value at $path: non-finite doubles are not '
      'supported.',
    );
  }

  void _reportInvalidContextMessage(String message) {
    if (_policy.throwOnViolation) {
      throw ArgumentError(message);
    }
    _policy.reportError(
      FlutterErrorDetails(
        exception: message,
        library: 'restage',
      ),
    );
  }
}

String _typeNameOf(Object? value) {
  if (value == null) return 'Null';
  if (value is String) return 'String';
  if (value is int) return 'int';
  if (value is double) return 'double';
  if (value is bool) return 'bool';
  if (value is List<Object?>) return 'List';
  if (value is Map<Object?, Object?>) return 'Map';
  if (value is Function) return 'Function';
  return 'Object';
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return _scalarEquals(left, right);
}

bool _scalarEquals(Object? left, Object? right) {
  if (left == null || right == null) {
    return left == right;
  }
  if (left.runtimeType != right.runtimeType) {
    return false;
  }
  if (left is double && right is double) {
    return left.compareTo(right) == 0;
  }
  return left == right;
}

int _deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(_deepHash(entry.key), _deepHash(entry.value)),
      ),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return _scalarHash(value);
}

int _scalarHash(Object? value) {
  if (value == null) {
    return Object.hash(Null, null);
  }
  return Object.hash(value.runtimeType, value.hashCode);
}
