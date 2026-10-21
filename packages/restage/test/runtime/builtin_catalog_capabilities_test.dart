import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Internal: the generated installed-catalog-version constant the resolvers read.
// ignore: implementation_imports
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart'
    show Catalog, decodeCatalog, kBaselineCatalogVersion;

/// Keeps installed capabilities aligned with committed built-in catalogs.
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

  Catalog committedCatalog(String package) =>
      decodeCatalog(catalogFile(package).readAsStringSync());

  int committedContentVersion(String package) =>
      committedCatalog(package).contentVersion;

  const builtInPackages = [
    'restage_core',
    'restage_material',
    'restage_cupertino',
  ];

  test('currentVersion == max content version over the committed catalogs', () {
    final core = committedContentVersion('restage_core');
    final material = committedContentVersion('restage_material');
    final cupertino = committedContentVersion('restage_cupertino');
    final expected =
        [core, material, cupertino].reduce((a, b) => a > b ? a : b);

    expect(RestageBuiltInCatalogCapabilities.currentVersion, expected);
  });

  test('native transforms raise the generated global ceiling to 14', () {
    expect(RestageBuiltInCatalogCapabilities.currentVersion, 14);
    final core = committedCatalog('restage_core');
    for (final (name, version) in [
      ('TransformTranslate', 13),
      ('TransformScale', 14),
    ]) {
      expect(
        core.widgets.singleWhere((widget) => widget.name == name).sinceVersion,
        version,
        reason: name,
      );
    }
  });

  test('currentVersion is at least the baseline content version', () {
    expect(
      RestageBuiltInCatalogCapabilities.currentVersion,
      greaterThanOrEqualTo(1),
    );
  });

  group('the content-version line is ONE line across the built-in libraries',
      () {
    // Built-in libraries share one version line. Updating a widget may retire
    // the last current entry carrying an older version, so gaps are valid.

    /// Every above-baseline content version in use, mapped to the built-in
    /// packages that stamp a widget with it.
    Map<int, Set<String>> versionOwners() {
      final owners = <int, Set<String>>{};
      for (final package in builtInPackages) {
        for (final widget in committedCatalog(package).widgets) {
          if (widget.sinceVersion == kBaselineCatalogVersion) continue;
          owners
              .putIfAbsent(widget.sinceVersion, () => <String>{})
              .add(package);
        }
      }
      return owners;
    }

    test('no content version is stamped by two libraries', () {
      final shared = {
        for (final entry in versionOwners().entries)
          if (entry.value.length > 1) entry.key: entry.value,
      };

      expect(
        shared,
        isEmpty,
        reason: 'Two built-in libraries stamp the same content version. The '
            'version line is GLOBAL: a new widget takes one above the highest '
            'sinceVersion across ALL built-in libraries, so no two landings — '
            'and no two libraries — share a version. A shared version means a '
            'widget was stamped against its own library\'s line, and the '
            'capability floor it produces is one older clients already clear: '
            'they accept a surface they cannot render. Re-stamp it at the next '
            'global version and regenerate.',
      );
    });

    test('AppBar and Scaffold require the new global capability version', () {
      final material = committedCatalog('restage_material');
      for (final name in ['AppBar', 'Scaffold']) {
        expect(
          material.widgets
              .singleWhere((widget) => widget.name == name)
              .sinceVersion,
          12,
          reason: '$name uses the system-style and native-sizing contract.',
        );
      }
    });
  });
}
