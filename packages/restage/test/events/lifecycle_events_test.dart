import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('EntitlementGranted is app-wide (paywallId null) and serializes source',
      () {
    const e = EntitlementGranted(
      entitlementId: 'pro',
      productId: 'pro_monthly',
      source: EntitlementSource.purchase,
      expiresAtMs: 1800000000000,
    );
    expect(e.name, 'entitlement_granted');
    expect(e.paywallId, isNull);
    final map = e.toMap();
    expect(map['name'], 'entitlement_granted');
    expect(map['entitlementId'], 'pro');
    expect(map['productId'], 'pro_monthly');
    expect(map['source'], 'purchase');
    expect(map['expiresAtMs'], 1800000000000);
  });

  test('EntitlementRevoked serializes RevokeReason as enum name', () {
    const e = EntitlementRevoked(
      entitlementId: 'pro',
      reason: RevokeReason.refunded,
    );
    expect(e.name, 'entitlement_revoked');
    expect(e.paywallId, isNull);
    final map = e.toMap();
    expect(map['entitlementId'], 'pro');
    expect(map['reason'], 'refunded');
  });

  test('SubscriptionRenewed exists as a reserved type', () {
    const e = SubscriptionRenewed(
      entitlementId: 'pro',
      productId: 'pro_monthly',
    );
    expect(e.name, 'subscription_renewed');
    expect(e.paywallId, isNull);
    final map = e.toMap();
    expect(map['entitlementId'], 'pro');
    expect(map['productId'], 'pro_monthly');
  });

  test('SubscriptionLapsed exists as a reserved type', () {
    const e = SubscriptionLapsed(
      entitlementId: 'pro',
      productId: 'pro_monthly',
    );
    expect(e.name, 'subscription_lapsed');
    expect(e.paywallId, isNull);
    final map = e.toMap();
    expect(map['entitlementId'], 'pro');
    expect(map['productId'], 'pro_monthly');
  });
}
