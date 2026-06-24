import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/event_demux.dart';

void main() {
  setUp(() => Restage.debugReset());

  test(
      'demuxRfwEvent("restage.purchase", {slot: primary}) -> PurchaseInitiated with resolved productId',
      () {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
    );
    final result = demuxRfwEvent(
      paywallId: 'pro_upgrade',
      name: 'restage.purchase',
      args: const {'slot': 'primary'},
    );
    expect(result, isA<PurchaseInitiated>());
    expect((result as PurchaseInitiated).productId, 'pro_monthly');
    expect(result.paywallId, 'pro_upgrade');
    // priceMicros / currency are populated by the billing layer once the
    // platform store lookup completes; the demux event leaves them null.
    expect(result.priceMicros, isNull);
    expect(result.currency, isNull);
  });

  test(
      'demuxRfwEvent("restage.purchase", {productId: ...}) -> PurchaseInitiated direct',
      () {
    final result = demuxRfwEvent(
      paywallId: 'pro_upgrade',
      name: 'restage.purchase',
      args: const {'productId': 'pro_yearly'},
    );
    expect(result, isA<PurchaseInitiated>());
    expect((result as PurchaseInitiated).productId, 'pro_yearly');
  });

  test('demuxRfwEvent("restage.restore") -> RestoreInitiated', () {
    final result = demuxRfwEvent(
      paywallId: 'pro_upgrade',
      name: 'restage.restore',
      args: const {},
    );
    expect(result, isA<RestoreInitiated>());
    expect(result.paywallId, 'pro_upgrade');
  });

  test('demuxRfwEvent any other name -> PaywallCustomEvent', () {
    final result = demuxRfwEvent(
      paywallId: 'pro_upgrade',
      name: 'subscribe',
      args: const {'plan': 'monthly'},
    );
    expect(result, isA<PaywallCustomEvent>());
    expect((result as PaywallCustomEvent).eventName, 'subscribe');
    expect(result.args, {'plan': 'monthly'});
  });

  test('demuxRfwEvent("restage.purchase", {offerId: ...}) carries the offerId',
      () {
    Restage.configure(apiKey: 'pk_test');
    final result = demuxRfwEvent(
      paywallId: 'pro_upgrade',
      name: 'restage.purchase',
      args: const {'productId': 'pro_monthly', 'offerId': 'winback_3mo'},
    );
    expect((result as PurchaseInitiated).offerId, 'winback_3mo');
  });
}
