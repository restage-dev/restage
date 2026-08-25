import 'dart:io';

import 'package:test/test.dart';

void main() {
  final barrel = File('lib/restage_shared.dart').readAsStringSync();

  test('default barrel omits commerce exports', () {
    for (final export in _commerceExports) {
      expect(
        barrel,
        isNot(contains(export)),
        reason: '$export must not be part of the default surface',
      );
    }
  });
}

const _commerceExports = <String>[
  "export 'src/entitlements/entitlements.dart';",
  "export 'src/offers/offers.dart';",
  "export 'src/products/restage_entitlement.dart';",
  "export 'src/products/restage_product.dart';",
];
