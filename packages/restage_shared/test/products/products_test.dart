import 'package:restage_shared/src/products/restage_entitlement.dart';
import 'package:restage_shared/src/products/restage_product.dart';
import 'package:test/test.dart';

void main() {
  test('RestageProduct stores id, slot, entitlement', () {
    const p = RestageProduct(
      id: 'pro_monthly',
      slot: 'primary',
      entitlement: 'pro',
    );
    expect(p.id, 'pro_monthly');
    expect(p.slot, 'primary');
    expect(p.entitlement, 'pro');
  });

  test('RestageProduct equality is structural', () {
    const a = RestageProduct(id: 'x', slot: 'primary', entitlement: 'pro');
    const b = RestageProduct(id: 'x', slot: 'primary', entitlement: 'pro');
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });

  test('RestageEntitlement stores id and source', () {
    const e = RestageEntitlement(id: 'pro', source: EntitlementSource.purchase);
    expect(e.id, 'pro');
    expect(e.source, EntitlementSource.purchase);
  });
}
