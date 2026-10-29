import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:path_provider/path_provider.dart' as path_provider;

import 'surface_artifact_store.dart';

/// Files under [directory], or `<application support>/restage/surfaces`.
///
/// Under `flutter test` the default keeps entries in memory, so an app's own
/// widget tests never read or write the device directory.
SurfaceArtifactStore createSurfaceArtifactStore({
  Future<String> Function()? directory,
  bool? readsOffIsolate,
}) {
  if (directory == null && Platform.environment.containsKey('FLUTTER_TEST')) {
    return MemorySurfaceArtifactStore();
  }
  return _FileSurfaceArtifactStore(directory ?? _defaultDirectory,
      readsOffIsolate: readsOffIsolate ?? !kDebugMode);
}

/// The name of the isolate a scope read runs in.
@visibleForTesting
const surfaceReadAheadIsolateName = 'restage read ahead';

Future<String> _defaultDirectory() async {
  final support = await path_provider.getApplicationSupportDirectory();
  return '${support.path}${Platform.pathSeparator}restage'
      '${Platform.pathSeparator}surfaces';
}

const _magic = <int>[0x52, 0x53, 0x53, 0x31]; // RSS1
const _extension = '.surface';
const _maxHeaderBytes = 1 << 20;

/// One file per key: magic, header length, JSON header, descriptor, artifact.
final class _FileSurfaceArtifactStore
    implements SurfaceArtifactStore, SurfaceArtifactScopeReader {
  _FileSurfaceArtifactStore(this._resolveDirectory,
      {required bool readsOffIsolate})
      : _readsOffIsolate = readsOffIsolate;

  final Future<String> Function() _resolveDirectory;

  // Debug builds read in place: a test's fake clock never delivers an
  // isolate's result.
  final bool _readsOffIsolate;

  @override
  bool get readsOffIsolate => _readsOffIsolate;
  final Random _random = Random();
  Future<Directory?>? _directory;

  // The directory is scanned once; this process's writes keep the index.
  Future<Set<SurfaceStoreKey>>? _index;

  // Without a usable directory the store keeps entries for this process only.
  final MemorySurfaceArtifactStore _memory = MemorySurfaceArtifactStore();

  Future<Directory?> _root() => _directory ??= () async {
        try {
          final directory = Directory(await _resolveDirectory());
          await directory.create(recursive: true);
          return directory;
        } on Object {
          return null;
        }
      }();

  File _fileFor(Directory root, SurfaceStoreKey key) =>
      File(_pathFor(root.path, key));

  @override
  Future<R> readScope<R>(String scope, Set<String> surfaceTypes,
      R Function(StoredScopeRows rows) process) async {
    final root = await _root();
    if (root == null) {
      return readStoreScope(_memory, scope, surfaceTypes, process);
    }
    final path = root.path;
    // One pass lists, reads and processes off the frame isolate; its listing
    // becomes the index when no scan has started.
    final pass = _readsOffIsolate
        ? Isolate.run(() => _readScopeHere(path, scope, surfaceTypes, process),
            debugName: surfaceReadAheadIsolateName)
        : Future.sync(() => _readScopeHere(path, scope, surfaceTypes, process));
    _index ??= pass.then((result) => result.$1);
    return (await pass).$2;
  }

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) async {
    final root = await _root();
    if (root == null) return _memory.read(key);
    final file = _fileFor(root, key);
    try {
      if (!await file.exists()) return null;
      final entry = _decode(await file.readAsBytes());
      if (entry == null || entry.key != key) return null;
      return entry.value;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) async {
    final root = await _root();
    if (root == null) return _memory.write(key, value);
    final target = _fileFor(root, key);
    final temp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}'
      '-${_random.nextInt(1 << 32)}.tmp',
    );
    try {
      final handle = await temp.open(mode: FileMode.write);
      try {
        await handle.writeFrom(_encode(key, value));
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temp.rename(target.path);
      await _index?.then<void>((index) => index.add(key),
          onError: (Object _) {});
    } on Object {
      try {
        if (await temp.exists()) await temp.delete();
      } on Object {
        // The temp file is swept by the next clear.
      }
      // The caller learns the entry was not kept.
      rethrow;
    }
  }

  @override
  Future<void> remove(SurfaceStoreKey key) async {
    final root = await _root();
    if (root == null) return _memory.remove(key);
    try {
      await _index?.then<void>((index) => index.remove(key),
          onError: (Object _) {});
      final file = _fileFor(root, key);
      if (await file.exists()) await file.delete();
    } on Object {
      // A leftover entry is still re-gated on read.
    }
  }

  @override
  Future<List<SurfaceStoreKey>> keys() async {
    final root = await _root();
    if (root == null) return _memory.keys();
    final scan = _index ??= _scan(root);
    try {
      return (await scan).toList();
    } on Object {
      if (identical(_index, scan)) _index = null;
      return [];
    }
  }

  // A listing that fails throws, so a partial scan is never kept.
  Future<Set<SurfaceStoreKey>> _scan(Directory root) async {
    final keys = <SurfaceStoreKey>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith(_extension)) continue;
      try {
        final key = await _readKey(entity);
        if (key != null && _fileFor(root, key).path == entity.path) {
          keys.add(key);
        }
      } on Object {
        continue;
      }
    }
    return keys;
  }

  @override
  Future<void> clear() async {
    await _memory.clear();
    _index = null;
    final root = await _root();
    if (root == null) return;
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File) await entity.delete();
      }
    } on Object {
      // Anything left is re-gated on read.
    }
  }
}

Uint8List _encode(SurfaceStoreKey key, StoredSurface value) {
  final header = utf8.encode(
    jsonEncode(<String, Object?>{
      'key': key.toJson(),
      'descriptorLength': value.descriptorJson.length,
      'artifactLength': value.artifactBytes.length,
      'sidecar': value.sidecar,
    }),
  );
  final builder = BytesBuilder(copy: false)
    ..add(_magic)
    ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
    ..add(header)
    ..add(value.descriptorJson)
    ..add(value.artifactBytes);
  return builder.takeBytes();
}

String _pathFor(String directory, SurfaceStoreKey key) {
  final name = sha256
      .convert(utf8.encode(jsonEncode(key.toJson())))
      .toString()
      .substring(0, 32);
  return '$directory${Platform.pathSeparator}$name$_extension';
}

// Every key in [directory], from headers only, and [process] run on
// [scope]'s entries of [surfaceTypes], the only files read whole. A listing
// that fails throws, so no partial index is kept.
(Set<SurfaceStoreKey>, R) _readScopeHere<R>(String directory, String scope,
    Set<String> surfaceTypes, R Function(StoredScopeRows rows) process) {
  final keys = <SurfaceStoreKey>{};
  final rows = <(SurfaceStoreKey, StoredSurface)>[];
  for (final entity in Directory(directory).listSync(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith(_extension)) continue;
    try {
      final key = _readKeySync(entity);
      if (key == null || _pathFor(directory, key) != entity.path) continue;
      keys.add(key);
      if (key.scope != scope || !surfaceTypes.contains(key.surfaceType)) {
        continue;
      }
      final entry = _decode(entity.readAsBytesSync());
      if (entry != null && entry.key == key) rows.add((key, entry.value));
    } on Object {
      continue;
    }
  }
  return (keys, process(rows));
}

/// The key in [file]'s header, reading only the header.
SurfaceStoreKey? _readKeySync(File file) {
  final handle = file.openSync();
  try {
    final prefix = handle.readSync(8);
    if (prefix.length < 8) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (prefix[i] != _magic[i]) return null;
    }
    final headerLength = ByteData.sublistView(prefix, 4, 8).getUint32(0);
    if (headerLength > _maxHeaderBytes) return null;
    final header = handle.readSync(headerLength);
    if (header.length != headerLength) return null;
    final decoded = jsonDecode(utf8.decode(header));
    return decoded is Map<String, Object?>
        ? SurfaceStoreKey.tryFromJson(decoded['key'])
        : null;
  } on FormatException {
    return null;
  } finally {
    handle.closeSync();
  }
}

/// The key in [file]'s header, reading only the header.
Future<SurfaceStoreKey?> _readKey(File file) async {
  final handle = await file.open();
  try {
    final prefix = await handle.read(8);
    if (prefix.length < 8) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (prefix[i] != _magic[i]) return null;
    }
    final headerLength = ByteData.sublistView(prefix, 4, 8).getUint32(0);
    if (headerLength > _maxHeaderBytes) return null;
    final header = await handle.read(headerLength);
    if (header.length != headerLength) return null;
    final decoded = jsonDecode(utf8.decode(header));
    return decoded is Map<String, Object?>
        ? SurfaceStoreKey.tryFromJson(decoded['key'])
        : null;
  } on FormatException {
    return null;
  } finally {
    await handle.close();
  }
}

({SurfaceStoreKey key, StoredSurface value})? _decode(Uint8List bytes) {
  if (bytes.length < 8) return null;
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return null;
  }
  final headerLength = ByteData.sublistView(bytes, 4, 8).getUint32(0);
  if (headerLength > _maxHeaderBytes || 8 + headerLength > bytes.length) {
    return null;
  }
  final Object? header;
  try {
    header = jsonDecode(
        utf8.decode(Uint8List.sublistView(bytes, 8, 8 + headerLength)));
  } on FormatException {
    return null;
  }
  if (header is! Map<String, Object?>) return null;
  final key = SurfaceStoreKey.tryFromJson(header['key']);
  final descriptorLength = header['descriptorLength'];
  final artifactLength = header['artifactLength'];
  final sidecar = header['sidecar'];
  if (key == null ||
      descriptorLength is! int ||
      artifactLength is! int ||
      descriptorLength < 0 ||
      artifactLength < 0 ||
      sidecar is! Map<String, Object?>) {
    return null;
  }
  final descriptorStart = 8 + headerLength;
  final artifactStart = descriptorStart + descriptorLength;
  if (artifactStart + artifactLength != bytes.length) return null;
  return (
    key: key,
    value: StoredSurface(
      descriptorJson: Uint8List.fromList(
        Uint8List.sublistView(bytes, descriptorStart, artifactStart),
      ),
      artifactBytes: Uint8List.fromList(
        Uint8List.sublistView(bytes, artifactStart),
      ),
      sidecar: sidecar,
    ),
  );
}
