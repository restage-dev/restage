import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('the installed catalog supports the surface feature floor', () {
    expect(kSurfaceFeatureClientFloor, 9);
    expect(
      kSurfaceFeatureClientFloor,
      lessThanOrEqualTo(RestageBuiltInCatalogCapabilities.currentVersion),
    );
  });

  test('the installed catalog supports grouped widget lists', () {
    expect(kGroupedWidgetListClientFloor, 10);
    expect(
      kGroupedWidgetListClientFloor,
      lessThanOrEqualTo(RestageBuiltInCatalogCapabilities.currentVersion),
    );
  });
}
