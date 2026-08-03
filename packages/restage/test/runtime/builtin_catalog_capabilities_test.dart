import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Internal: the generated installed-catalog-version constant the resolvers read.
// ignore: implementation_imports
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart'
    show Catalog, decodeCatalog, kBaselineCatalogVersion;

/// Locks the SDK's installed built-in catalog content version against the
/// committed catalog.json files — the source of truth the surface delivery
/// floor is compared against. A generation drift between the per-library
/// `registry.dart` constant and the committed catalog (e.g. a hand-edited
/// constant, or the two emitters disagreeing) fails here, not silently in the
/// field.
///
/// It also holds the shape of the content-version LINE itself, which is what
/// makes the floor mean anything. See the group below.
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

  test('currentVersion is at least the baseline content version', () {
    expect(
      RestageBuiltInCatalogCapabilities.currentVersion,
      greaterThanOrEqualTo(1),
    );
  });

  group('the content-version line is ONE line across the built-in libraries',
      () {
    // Why this group exists, and why it is not a style rule.
    //
    // A client advertises ONE installed content version: the MAXIMUM over every
    // built-in library it ships (`RestageBuiltInCatalogCapabilities`, pinned by
    // the test above). A delivered surface carries ONE floor: the maximum
    // `sinceVersion` of the entries it uses. The pre-render check compares those
    // two numbers and nothing else.
    //
    // So a new widget's `sinceVersion` must exceed the highest `sinceVersion`
    // ANYWHERE in the built-in set at the time it lands — not the highest in its
    // own library. Stamp it at its own library's next value and the floor it
    // produces is one that older clients ALREADY CLEAR on the strength of a
    // different library's version. The check passes; the widget is not there to
    // render. The floor is the only thing preventing that, and it fails open —
    // silently, on a real device, for a surface that was published as safe.
    //
    // That is not hypothetical. It is the defect this group was written after:
    // three core layout widgets were stamped at the core library's next value
    // (2) while the material library was already at 4, so every client back to
    // content version 2 would have accepted a surface using widgets it does not
    // have.
    //
    // The true rule ("above the global max AT THE TIME IT LANDED") needs history
    // to check. The two properties below are the strongest statement of it that
    // the committed state alone can carry, and both would have failed on that
    // stamp. The convention that makes them sound: EACH LANDING ALLOCATES ITS
    // OWN FRESH VERSION. If a change ever needs to add widgets to two libraries
    // at once, give each library its own version — do not share one, and do not
    // weaken these checks to allow sharing.

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

    test('the versions in use run contiguously from the baseline', () {
      final used = versionOwners().keys.toList()..sort();
      final advertised = RestageBuiltInCatalogCapabilities.currentVersion;
      final expected = [
        for (var v = kBaselineCatalogVersion + 1; v <= advertised; v++) v,
      ];

      expect(
        used,
        expected,
        reason: 'The content versions in use are not the contiguous run '
            '${kBaselineCatalogVersion + 1}..$advertised. A gap means a stamp '
            'skipped a version (harmless to the floor, but it breaks the '
            'one-version-per-landing convention the shared-version check above '
            'relies on to be sound). A version above the advertised one means '
            'a widget is floored beyond what this very SDK claims to render.',
      );
    });
  });
}
