import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:test/test.dart';

void main() {
  test('entitlement keys preserve exact one-to-200-scalar identity', () {
    expect(commerceMetadataMaxBytes, 65536);
    expect(commerceEntitlementKeyMaxCodePoints, 200);
    expect(commerceSlotEntitlementKeyMaxCount, 64);
    for (final (key, valid) in [
      ('a', true),
      ('a' * 200, true),
      ('\u{1f680}' * 200, true),
      (' ', true),
      (' Pro.access ', true),
      ('pro,/"\\', true),
      ('pro\naccess', true),
      ('é', true),
      ('e\u0301', true),
      ('會員', true),
      ('', false),
      ('a' * 201, false),
      ('\u{1f680}' * 201, false),
      ('pro\u0000', false),
      ('\ud800', false),
      ('\udc00', false),
    ]) {
      expect(isCanonicalCommerceEntitlementKey(key), valid, reason: key);
      if (valid) {
        expect(normalizeCommerceEntitlementKey(key), key);
      } else {
        expect(() => normalizeCommerceEntitlementKey(key), throwsArgumentError);
      }
    }
    expect(normalizeCommerceEntitlementKey('é'),
        isNot(normalizeCommerceEntitlementKey('e\u0301')));
  });
}
