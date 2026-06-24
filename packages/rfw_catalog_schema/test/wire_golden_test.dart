import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Byte-exact round-trip golden over the three committed catalogs.
///
/// This is the anti-drift oracle: it asserts that the canonical codec is a
/// byte-for-byte inverse of itself over the committed source-of-truth files,
/// going through the production [encodeCatalog]/[decodeCatalog] entrypoints
/// (not a test-assembled serialization). A representation change that altered
/// the emitted JSON — key ordering, whitespace, number formatting, a dropped
/// or added field — fails here against the committed bytes.
///
/// The test cwd is the package root, so the sibling catalog packages are
/// reached relatively. Files are compared as strings with no normalization or
/// re-pretty-printing on either side.
void main() {
  const committedCatalogs = <String, String>{
    'restage_core': '../restage_core/lib/src/widget_catalog/catalog.json',
    'restage_material':
        '../restage_material/lib/src/widget_catalog/catalog.json',
    'restage_cupertino':
        '../restage_cupertino/lib/src/widget_catalog/catalog.json',
  };

  group('committed-catalog byte-golden', () {
    committedCatalogs.forEach((name, path) {
      test('$name round-trips byte-for-byte through the canonical codec', () {
        final committed = File(path).readAsStringSync();
        final reEncoded = encodeCatalog(decodeCatalog(committed));
        expect(
          reEncoded,
          committed,
          reason: 'encodeCatalog(decodeCatalog(<$name catalog.json>)) must be '
              'byte-identical to the committed file; a difference means the '
              'wire format moved.',
        );
      });
    });
  });
}
