import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  // Pin the built-in library set. The A2UI emit adapter detects built-in
  // widgets DYNAMICALLY (via WidgetLibrary.builtInByNamespace) to compute the
  // built-in capability floor, while the runtime SDK's
  // RestageBuiltInCatalogCapabilities.currentVersion HARDCODES
  // max(kCoreCatalogContentVersion, kMaterialCatalogContentVersion,
  // kCupertinoCatalogContentVersion). The two agree only as long as the
  // built-in set is exactly {core, material, cupertino}. A fourth built-in
  // library would diverge them silently — the adapter would fold it into the
  // floor while the hardcoded-3 runtime constant would not — re-opening a
  // capability fail-open. This guard turns that silent divergence into a loud
  // failure at the moment a built-in is added.
  test('the built-in library namespace set is exactly core/material/cupertino',
      () {
    expect(
      WidgetLibrary.builtInLibraries.map((l) => l.namespace).toSet(),
      {'restage.core', 'restage.material', 'restage.cupertino'},
      reason: 'A built-in library was added or removed. Before this lands, '
          'update RestageBuiltInCatalogCapabilities.currentVersion in the '
          'runtime SDK (it hardcodes max over the three built-in content '
          'versions) so the A2UI adapter floor and the runtime constant stay '
          'in agreement — otherwise the catalog can advertise a built-in '
          'version the runtime cannot render. See the follow-up to derive the '
          'runtime constant from the canonical built-in set instead of '
          'hardcoding it.',
    );
  });
}
