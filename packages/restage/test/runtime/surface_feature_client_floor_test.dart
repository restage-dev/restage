import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('the surface feature floor is the installed catalog version', () {
    expect(
      kSurfaceFeatureClientFloor,
      RestageBuiltInCatalogCapabilities.currentVersion,
    );
  });
}
