import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';

/// Reads a generated delivery artifact by its logical path.
///
/// Generated artifacts are packaged only inside `.rsbundle` containers, so a
/// test that wants to inspect one reads it out of a container rather than off
/// disk. Reading through the shared bundle codec is what keeps these tests
/// honest: they see exactly the bytes the runtime would serve.
///
/// A loose file at the same path still wins, so a hand-authored fixture is
/// read as written.
Uint8List readDeliveryArtifact(String logicalPath) {
  final loose = File(logicalPath);
  if (loose.existsSync()) return loose.readAsBytesSync();

  final bytes = _index()[logicalPath];
  if (bytes == null) {
    throw StateError(
      'No packaged bundle carries "$logicalPath". '
      'Known paths: ${_index().keys.take(5).join(', ')}…',
    );
  }
  return bytes;
}

/// Reads a generated delivery artifact as UTF-8 text.
String readDeliveryText(String logicalPath) =>
    utf8.decode(readDeliveryArtifact(logicalPath));

Map<String, Uint8List>? _cache;

Map<String, Uint8List> _index() {
  final cached = _cache;
  if (cached != null) return cached;

  final index = <String, Uint8List>{};
  final root = Directory('assets/restage/bundles');
  if (root.existsSync()) {
    final containers = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.rsbundle'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final container in containers) {
      final bundle = RestageBundleCodec.decode(container.readAsBytesSync());
      for (final entry in bundle.entries) {
        index[entry.logicalPath] ??= entry.bytes;
      }
    }
  }
  return _cache = index;
}
