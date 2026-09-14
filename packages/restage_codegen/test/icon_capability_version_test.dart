import 'dart:io';

import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:test/test.dart';

void main() {
  final material = decodeCatalog(
    File(
      '../restage_material/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );

  test('expanded Icon takes the first version above the old global ceiling',
      () {
    // main 98f5026ee had core=5, Material=4 and Cupertino=1. sinceVersion
    // covers the last capability change as well as widget introduction.
    expect(
      material.widgets
          .singleWhere((entry) => entry.name == 'Icon')
          .sinceVersion,
      6,
    );
  });

  for (final properties in [
    'iconCodepoint: 62530, iconFontFamily: "CupertinoIcons"',
    'iconCodepoint: 57490, iconMatchTextDirection: true',
    'iconCodepoint: 57490, iconMatchTextDirection: false',
    'iconCodepoint: 57490',
  ]) {
    test('old global ceiling rejects and version 6 accepts Icon($properties)',
        () {
      final result = deriveCapabilityManifest(
        parseLibraryFile('''
import restage.material;
widget Paywall = Icon($properties);
'''),
        material,
      );
      expect(result.issues, isEmpty);
      final manifest = result.manifest!;
      expect(manifest.builtInFloor, 6);
      expect(
        BlobRenderCapabilityGate.evaluate(
          required: manifest,
          installed: InstalledCapability(
            builtInCatalogVersion: 5,
            installedLibraries: const [],
          ),
        ),
        isA<BlobRenderRejected>(),
      );
      expect(
        BlobRenderCapabilityGate.evaluate(
          required: manifest,
          installed: InstalledCapability(
            builtInCatalogVersion: 6,
            installedLibraries: const [],
          ),
        ),
        isA<BlobRenderAccepted>(),
      );
    });
  }
}
