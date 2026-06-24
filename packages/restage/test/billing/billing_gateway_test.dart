import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

class _FakeGateway implements BillingGateway {
  final List<String> calls = <String>[];

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    calls.add('purchase:$productId');
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'tx_1',
      verificationData: 'fake-verification',
      priceMicros: 9990000,
      currency: 'USD',
    );
  }

  @override
  Future<RestoreOutcome> restore() async {
    calls.add('restore');
    return RestoreOutcome.succeeded(
      restoredProductIds: const <String>['pro_monthly'],
    );
  }
}

void main() {
  test('BillingGateway abstraction contract', () async {
    final gw = _FakeGateway();

    final p = await gw.purchase('pro_monthly');
    expect(p, isA<PurchaseOutcomeSucceeded>());
    final succeeded = p as PurchaseOutcomeSucceeded;
    expect(succeeded.productId, 'pro_monthly');
    expect(succeeded.transactionId, 'tx_1');
    expect(succeeded.verificationData, 'fake-verification');
    expect(succeeded.priceMicros, 9990000);
    expect(succeeded.currency, 'USD');

    final r = await gw.restore();
    expect(r, isA<RestoreOutcomeSucceeded>());
    expect(
      (r as RestoreOutcomeSucceeded).restoredProductIds,
      const <String>['pro_monthly'],
    );

    expect(gw.calls, <String>['purchase:pro_monthly', 'restore']);
  });

  test('PurchaseOutcome factories produce matching sealed subclasses', () {
    PurchaseOutcome p;

    p = PurchaseOutcome.succeeded(
      productId: 'x',
      transactionId: 't',
      verificationData: 'v',
      priceMicros: 0,
      currency: 'USD',
    );
    expect(p, isA<PurchaseOutcomeSucceeded>());
    expect((p as PurchaseOutcomeSucceeded).verificationData, 'v');

    p = PurchaseOutcome.pending(
      productId: 'x',
      reason: PendingReason.paymentPending,
    );
    expect(p, isA<PurchaseOutcomePending>());
    expect(
      (p as PurchaseOutcomePending).reason,
      PendingReason.paymentPending,
    );

    p = PurchaseOutcome.cancelled(productId: 'x');
    expect(p, isA<PurchaseOutcomeCancelled>());

    p = PurchaseOutcome.failed(
      productId: 'x',
      errorCode: 'E1',
      message: 'boom',
      platformErrorCode: 'SK_42',
    );
    expect(p, isA<PurchaseOutcomeFailed>());
    final failed = p as PurchaseOutcomeFailed;
    expect(failed.errorCode, 'E1');
    expect(failed.platformErrorCode, 'SK_42');

    // Failed outcomes may carry a null productId (e.g. restore failures
    // lifted into the purchase shape).
    p = PurchaseOutcome.failed(
      productId: null,
      errorCode: 'E2',
      message: 'no product',
    );
    expect(p, isA<PurchaseOutcomeFailed>());
    expect((p as PurchaseOutcomeFailed).productId, isNull);
  });

  test('RestoreOutcome factories produce matching sealed subclasses', () {
    RestoreOutcome r;

    r = RestoreOutcome.succeeded(
      restoredProductIds: const <String>['a', 'b'],
    );
    expect(r, isA<RestoreOutcomeSucceeded>());
    expect(
      (r as RestoreOutcomeSucceeded).restoredProductIds,
      const <String>['a', 'b'],
    );

    r = RestoreOutcome.noPurchases();
    expect(r, isA<RestoreOutcomeNoPurchases>());

    r = RestoreOutcome.failed(errorCode: 'E', message: 'm');
    expect(r, isA<RestoreOutcomeFailed>());
    final failed = r as RestoreOutcomeFailed;
    expect(failed.errorCode, 'E');
    expect(failed.message, 'm');
  });

  test(
      'PurchaseOutcomeSucceeded.verificationData is optional (receipt-less '
      'attribution-only success)', () {
    // A gateway that delegates the purchase to an external billing provider
    // (so the raw store receipt is not surfaced to the SDK) returns a
    // receipt-less success: the transaction id is present for attribution,
    // but verificationData is null. The SDK must not treat a receipt-less
    // success as a verified one.
    final outcome = PurchaseOutcome.succeeded(
      productId: 'pro_monthly',
      transactionId: 'GPA.1234-5678-9012-34567',
      verificationData: null,
      priceMicros: 9990000,
      currency: 'USD',
    );

    expect(outcome, isA<PurchaseOutcomeSucceeded>());
    final succeeded = outcome as PurchaseOutcomeSucceeded;
    expect(succeeded.verificationData, isNull);
    expect(succeeded.transactionId, 'GPA.1234-5678-9012-34567');
    expect(succeeded.productId, 'pro_monthly');
    expect(succeeded.priceMicros, 9990000);
    expect(succeeded.currency, 'USD');
  });

  test('PurchaseOutcomePending.reason is a typed PendingReason', () {
    final p = PurchaseOutcome.pending(
      productId: 'x',
      reason: PendingReason.askToBuy,
    );
    expect((p as PurchaseOutcomePending).reason, PendingReason.askToBuy);
  });

  test('RestageBillingErrorCodes pins the stable wire codes', () {
    // Public, host-switchable codes — pin the wire strings so a rename can't
    // silently change what a host `switch (errorCode)` matches on.
    expect(RestageBillingErrorCodes.unavailable, 'unavailable');
    expect(RestageBillingErrorCodes.productNotFound, 'product_not_found');
    expect(RestageBillingErrorCodes.buyFailed, 'buy_failed');
    expect(RestageBillingErrorCodes.restoreFailed, 'restore_failed');
    expect(RestageBillingErrorCodes.offerUnavailable, 'offer_unavailable');
    expect(RestageBillingErrorCodes.basePlanSelectionRequired,
        'base_plan_selection_required');
    expect(RestageBillingErrorCodes.unknown, 'unknown');
  });
}
