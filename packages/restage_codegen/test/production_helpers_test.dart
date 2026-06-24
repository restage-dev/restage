import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:test/test.dart';

void main() {
  // The build (`codegen_builder.dart`) and the coverage scanner
  // (`real_package_scanner.dart`'s `scanPackage` default) both obtain their
  // paywall helper registry from `productionPaywallHelperRegistry()`. They
  // therefore register the same set BY CONSTRUCTION. This test pins the other
  // half BY ASSERTION: the factory registers exactly the canonical
  // `paywallHelpers` list — no missing, no extra — so the single source of
  // truth cannot silently drift from the list it is meant to mirror.
  test('productionPaywallHelperRegistry registers exactly paywallHelpers', () {
    final registry = productionPaywallHelperRegistry();
    String key(HelperDefinition d) => '${d.name} ${d.libraryOrigin}';
    expect(
      registry.definitions.map(key).toSet(),
      paywallHelpers.map(key).toSet(),
    );
  });
}
