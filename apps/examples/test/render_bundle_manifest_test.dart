import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/user_catalog.g.dart';
import 'package:restage_render_host/restage_render_host.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

void main() {
  test('generated catalog remains valid and credential-free as a manifest', () {
    final source = encodeCatalog(kUserCatalog);
    final manifest = RenderBundleManifest.fromCatalogJson(source);
    final catalog = jsonDecode(source) as Map<String, Object?>;

    expect(manifest.catalog, catalog);
    expect(
      (manifest.catalog['widgets']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .any((widget) => widget['name'] == 'PulseBadge'),
      isTrue,
    );
  });
}
