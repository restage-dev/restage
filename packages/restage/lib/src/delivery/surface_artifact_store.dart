import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'surface_artifact_store_stub.dart'
    if (dart.library.io) 'surface_artifact_store_io.dart' as implementation;
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

/// The platform store: files under the application support directory on
/// `dart:io` platforms, memory elsewhere.
///
/// [directory] overrides where files go; it defaults to
/// `<application support>/restage/surfaces`.
@internal
SurfaceArtifactStore createSurfaceArtifactStore({
  Future<String> Function()? directory,
}) =>
    implementation.createSurfaceArtifactStore(directory: directory);

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
  try {
    await sharedSurfaceArtifactStore.clear();
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
