import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Internal: the generated installed-catalog-version constant the resolvers read.
// ignore: implementation_imports
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart' show decodeCatalog;

/// Locks the SDK's installed built-in catalog content version against the
/// committed catalog.json files — the source of truth the surface delivery
/// floor is compared against. A generation drift between the per-library
/// `registry.dart` constant and the committed catalog (e.g. a hand-edited
/// constant, or the two emitters disagreeing) fails here, not silently in the
/// field.
void main() {
  // Resolve the committed catalog.json for each sibling built-in library,
  // tolerant of either the package dir or the workspace root as cwd.
  File catalogFile(String package) {
    final fromPackageDir =
        File('../$package/lib/src/widget_catalog/catalog.json');
    return fromPackageDir.existsSync()
        ? fromPackageDir
        : File('packages/$package/lib/src/widget_catalog/catalog.json');
  }

  int committedContentVersion(String package) =>
      decodeCatalog(catalogFile(package).readAsStringSync()).contentVersion;

  test('currentVersion == max content version over the committed catalogs', () {
    final core = committedContentVersion('restage_core');
    final material = committedContentVersion('restage_material');
    final cupertino = committedContentVersion('restage_cupertino');
    final expected =
        [core, material, cupertino].reduce((a, b) => a > b ? a : b);

    expect(RestageBuiltInCatalogCapabilities.currentVersion, expected);
  });

  test('currentVersion is at least the baseline content version', () {
    expect(
      RestageBuiltInCatalogCapabilities.currentVersion,
      greaterThanOrEqualTo(1),
    );
  });
}
