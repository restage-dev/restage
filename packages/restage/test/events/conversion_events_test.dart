import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('PurchaseInitiated toMap includes priceMicros + currency + flags', () {
    const e = PurchaseInitiated(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
      priceMicros: 9990000,
      currency: 'USD',
      offerId: 'launch_offer',
      isTrial: true,
    );
    expect(e.name, 'purchase_initiated');
    final map = e.toMap();
    expect(map['name'], 'purchase_initiated');
    expect(map['productId'], 'pro_monthly');
    expect(map['priceMicros'], 9990000);
    expect(map['currency'], 'USD');
    expect(map['offerId'], 'launch_offer');
    expect(map['isTrial'], true);
    expect(map['isIntroOffer'], false);
  });

  test('PurchaseInitiated toMap omits null priceMicros and currency', () {
    const e = PurchaseInitiated(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
    );
    final map = e.toMap();
    expect(map.containsKey('priceMicros'), isFalse);
    expect(map.containsKey('currency'), isFalse);
    expect(map['productId'], 'pro_monthly');
  });

  test('PurchaseSucceeded toMap includes productId + transactionId', () {
    const e = PurchaseSucceeded(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
      transactionId: 'txn_abc123',
      priceMicros: 9990000,
      currency: 'USD',
    );
    expect(e.name, 'purchase_succeeded');
    final map = e.toMap();
    expect(map['productId'], 'pro_monthly');
    expect(map['transactionId'], 'txn_abc123');
    expect(map['priceMicros'], 9990000);
    expect(map['currency'], 'USD');
    expect(map.containsKey('offerId'), isFalse);
  });

  test('PurchaseSucceeded carries an optional offerId only when present', () {
    const e = PurchaseSucceeded(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
      transactionId: 'txn_abc123',
      priceMicros: 9990000,
      currency: 'USD',
      offerId: 'winback_3mo',
    );
    expect(e.toMap()['offerId'], 'winback_3mo');
  });

  test('PurchasePending toMap serializes PendingReason as snake_case', () {
    const e = PurchasePending(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
      reason: PendingReason.askToBuy,
    );
    expect(e.name, 'purchase_pending');
    expect(e.toMap()['reason'], 'ask_to_buy');
  });

  test('PurchaseCancelled toMap includes productId', () {
    const e = PurchaseCancelled(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
    );
    expect(e.name, 'purchase_cancelled');
    expect(e.toMap()['productId'], 'pro_monthly');
  });

  test('PurchaseFailed toMap includes errorCode + nullable platformErrorCode',
      () {
    const e = PurchaseFailed(
      paywallId: 'pro_upgrade',
      productId: 'pro_monthly',
      errorCode: 'network_error',
      message: 'connection lost',
      platformErrorCode: 'SKErrorNetworkConnectionFailed',
    );
    expect(e.name, 'purchase_failed');
    final map = e.toMap();
    expect(map['errorCode'], 'network_error');
    expect(map['platformErrorCode'], 'SKErrorNetworkConnectionFailed');
  });

  test('RestoreInitiated toMap', () {
    const e = RestoreInitiated(paywallId: 'pro_upgrade');
    expect(e.name, 'restore_initiated');
    expect(e.toMap()['name'], 'restore_initiated');
  });

  test('RestoreSucceeded toMap includes restoredProductIds', () {
    const e = RestoreSucceeded(
      paywallId: 'pro_upgrade',
      restoredProductIds: ['pro_monthly', 'pro_yearly'],
    );
    expect(e.name, 'restore_succeeded');
    expect(
      e.toMap()['restoredProductIds'],
      ['pro_monthly', 'pro_yearly'],
    );
  });

  test('RestoreNoPurchases toMap', () {
    const e = RestoreNoPurchases(paywallId: 'pro_upgrade');
    expect(e.name, 'restore_no_purchases');
  });

  test('RestoreFailed toMap includes errorCode', () {
    const e = RestoreFailed(
      paywallId: 'pro_upgrade',
      errorCode: 'network_error',
      message: 'connection lost',
    );
    expect(e.name, 'restore_failed');
    expect(e.toMap()['errorCode'], 'network_error');
  });
}
