import 'dart:typed_data';

import 'package:flutter/services.dart' show StandardMessageCodec;
import 'package:restage_shared/restage_shared.dart';

/// Encodes the binary asset manifest Flutter's `AssetManifest` reads.
///
/// A test that packages artifacts inside containers has to declare them the
/// way a real build does, because the SDK reads this manifest both to find the
/// containers and to know that a logical path was never packaged loose. The
/// wire format is Flutter's, so it lives in one place rather than in each
/// fixture that needs it.
Uint8List encodeAssetManifest(Iterable<String> assets) {
  final data = <String, Object?>{
    for (final asset in assets)
      asset: <Object?>[
        <String, Object?>{'asset': asset},
      ],
  };
  final encoded = const StandardMessageCodec().encodeMessage(data)!;
  return encoded.buffer
      .asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
}

/// Encodes one packaged container carrying [entries] at their logical paths.
Uint8List encodeRestageContainer(
  Map<String, Uint8List> entries, {
  String packageName = 'example_app',
  String authoredLibraryPath = 'lib/surfaces.dart',
}) =>
    RestageBundleCodec.encode(
      RestageBundle(
        packageName: packageName,
        authoredLibraryPath: authoredLibraryPath,
        entries: <RestageBundleEntry>[
          for (final entry in entries.entries)
            RestageBundleEntry(
              logicalPath: entry.key,
              role: RestageBundleEntryRole.screenBlob,
              bytes: entry.value,
            ),
        ],
      ),
    );
