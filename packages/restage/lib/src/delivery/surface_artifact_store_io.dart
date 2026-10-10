import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import 'surface_artifact_store.dart';

/// Files under [directory], or `<application support>/restage/surfaces`.
///
/// Under `flutter test` the default keeps entries in memory, so an app's own
/// widget tests never read or write the device directory.
SurfaceArtifactStore createSurfaceArtifactStore({
  Future<String> Function()? directory,
}) {
  if (directory == null && Platform.environment.containsKey('FLUTTER_TEST')) {
    return MemorySurfaceArtifactStore();
  }
  return _FileSurfaceArtifactStore(directory ?? _defaultDirectory);
}

Future<String> _defaultDirectory() async {
  final support = await path_provider.getApplicationSupportDirectory();
  return '${support.path}${Platform.pathSeparator}restage'
      '${Platform.pathSeparator}surfaces';
}

const _magic = <int>[0x52, 0x53, 0x53, 0x31]; // RSS1
const _extension = '.surface';
const _maxHeaderBytes = 1 << 20;

/// One file per key: magic, header length, JSON header, descriptor, artifact.
final class _FileSurfaceArtifactStore implements SurfaceArtifactStore {
  _FileSurfaceArtifactStore(this._resolveDirectory);

  final Future<String> Function() _resolveDirectory;
  final Random _random = Random();
  Future<Directory?>? _directory;

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

  File _fileFor(Directory root, SurfaceStoreKey key) {
    final name = sha256
        .convert(utf8.encode(jsonEncode(key.toJson())))
        .toString()
        .substring(0, 32);
    return File('${root.path}${Platform.pathSeparator}$name$_extension');
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
    } on Object {
      try {
        if (await temp.exists()) await temp.delete();
      } on Object {
        // The temp file is swept by the next clear.
      }
    }
  }

  @override
  Future<void> remove(SurfaceStoreKey key) async {
    final root = await _root();
    if (root == null) return _memory.remove(key);
    try {
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
    final keys = <SurfaceStoreKey>[];
    try {
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
    } on Object {
      return keys;
    }
    return keys;
  }

  @override
  Future<void> clear() async {
    await _memory.clear();
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
