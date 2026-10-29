import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'surface_artifact_store_stub.dart'
    if (dart.library.io) 'surface_artifact_store_io.dart' as implementation;
import 'placement_decision_store.dart';
import 'surface_store_key.dart';

export 'surface_store_key.dart';

/// The last accepted delivery of a surface, kept exactly as served.
@internal
@immutable
final class StoredSurface {
  /// Creates a stored surface.
  const StoredSurface({
    required this.descriptorJson,
    required this.artifactBytes,
    this.sidecar = const <String, Object?>{},
  });

  /// The artifact descriptor, exactly as served.
  final Uint8List descriptorJson;

  /// The artifact bytes, exactly as served.
  final Uint8List artifactBytes;

  /// JSON-encodable delivery facts: served version, publication binding
  /// reference, routing receipt, provenance and any assignment identity.
  final Map<String, Object?> sidecar;
}

/// Persists the last accepted delivery per [SurfaceStoreKey].
///
/// Entries are untrusted on read: callers re-run every delivery gate.
@internal
abstract interface class SurfaceArtifactStore {
  /// The entry for [key], or null when absent or unreadable.
  Future<StoredSurface?> read(SurfaceStoreKey key);

  /// Replaces the entry for [key] atomically.
  Future<void> write(SurfaceStoreKey key, StoredSurface value);

  /// Removes the entry for [key], if any.
  Future<void> remove(SurfaceStoreKey key);

  /// Every key with an entry, across scopes.
  Future<List<SurfaceStoreKey>> keys();

  /// Removes every entry.
  Future<void> clear();
}

/// The entries of one scope and some surface types, as [readStoreScope]
/// passes them.
@internal
typedef StoredScopeRows = List<(SurfaceStoreKey, StoredSurface)>;

/// A store that reads a scope in one pass away from the frame isolate.
@internal
abstract interface class SurfaceArtifactScopeReader {
  /// Whether [readScope] runs its pass away from the frame isolate.
  bool get readsOffIsolate;

  /// Reads [scope]'s entries of [surfaceTypes] and runs [process] on them in
  /// the same pass; [process] must be sendable to another isolate.
  Future<R> readScope<R>(String scope, Set<String> surfaceTypes,
      R Function(StoredScopeRows rows) process);
}

/// [store]'s entries of [surfaceTypes] in [scope], run through [process]; an
/// unreadable entry is left out.
@internal
Future<R> readStoreScope<R>(SurfaceArtifactStore store, String scope,
    Set<String> surfaceTypes, R Function(StoredScopeRows rows) process) async {
  if (store is SurfaceArtifactScopeReader) {
    return (store as SurfaceArtifactScopeReader)
        .readScope(scope, surfaceTypes, process);
  }
  final rows = <(SurfaceStoreKey, StoredSurface)>[];
  for (final key in await store.keys()) {
    if (key.scope != scope || !surfaceTypes.contains(key.surfaceType)) {
      continue;
    }
    try {
      final value = await store.read(key);
      if (value != null) rows.add((key, value));
    } on Object {
      continue;
    }
  }
  return process(rows);
}

/// The platform store: files under the application support directory on
/// `dart:io` platforms, memory elsewhere.
///
/// [directory] overrides where files go; it defaults to
/// `<application support>/restage/surfaces`. [readsOffIsolate] defaults to
/// true outside debug builds.
@internal
SurfaceArtifactStore createSurfaceArtifactStore({
  Future<String> Function()? directory,
  bool? readsOffIsolate,
}) =>
    implementation.createSurfaceArtifactStore(
        directory: directory, readsOffIsolate: readsOffIsolate);

SurfaceArtifactStore? _shared;

/// The store every built-in resolver uses unless given its own.
@internal
SurfaceArtifactStore get sharedSurfaceArtifactStore =>
    _shared ??= createSurfaceArtifactStore();

/// Replaces the shared store; null restores the platform default.
@internal
@visibleForTesting
set sharedSurfaceArtifactStore(SurfaceArtifactStore? store) => _shared = store;

/// Removes every stored surface, for reset and identity forget.
@internal
Future<void> clearSurfaceArtifactStores() async {
  final store = sharedSurfaceArtifactStore;
  try {
    // A delivery still being saved lands before the clear, never after it.
    await PlacementDecisionStore.writesSettled(store);
    await store.clear();
  } on Object {
    // Entries left behind are still re-gated on read.
  }
}

/// An in-memory store for web, tests, and platforms without a support
/// directory.
@internal
final class MemorySurfaceArtifactStore implements SurfaceArtifactStore {
  final Map<SurfaceStoreKey, StoredSurface> _entries =
      <SurfaceStoreKey, StoredSurface>{};

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) async => _entries[key];

  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) async {
    _entries[key] = value;
  }

  @override
  Future<void> remove(SurfaceStoreKey key) async => _entries.remove(key);

  @override
  Future<List<SurfaceStoreKey>> keys() async =>
      List<SurfaceStoreKey>.unmodifiable(_entries.keys);

  @override
  Future<void> clear() async => _entries.clear();
}
