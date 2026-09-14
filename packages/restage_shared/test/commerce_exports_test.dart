import 'dart:io';

import 'package:restage_shared/commerce.dart' as commerce;
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

  test('commerce barrel exposes the wire contract', () {
    final request = commerce.CommercePurchaserStateRequest(
      appAnonymousToken: '550e8400-e29b-41d4-a716-446655440001',
    );

    expect(request.knownStoreTransactionIds, isEmpty);
  });
}

const _commerceExports = <String>[
  "export 'src/entitlements/entitlements.dart';",
  "export 'src/offers/offers.dart';",
  "export 'src/products/restage_entitlement.dart';",
  "export 'src/products/restage_product.dart';",
];
