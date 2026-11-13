import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';

import 'support/fake_store.dart';

void main() {
  late FakeStoreKitStore store;

  setUp(() {
    store = FakeStoreKitStore();
    InAppPurchasePlatform.instance = store;
  });

  Future<Map<String, Object?>> row(ProductDetails product) async {
    final data = await inAppPurchaseOfferingData(
      identifier: 'pro',
      packages: {'monthly': product},
    );
    return (data['packages']! as List).single as Map<String, Object?>;
  }

  group('App Store', () {
    test('eligible free trial is present with its phase', () async {
      expect(await row(_apple(offers: [_promo, _offer(0)])), {
        'identifier': 'monthly',
        'productIdentifier': 'pro',
        'priceString': r'$9.99',
        'currencyCode': 'USD',
        'subscriptionPeriod': 'P1M',
        'freeTrial': {'priceString': r'$0.00', 'period': 'P1W', 'cycles': 1},
      });
      expect(store.eligibilityChecks, ['pro']);
    });

    test('eligible paid offer keeps the product price format', () async {
      final product = _apple(
        display: '9,99 €',
        currency: 'EUR',
        offers: [
          _offer(
            4.99,
            mode: SK2SubscriptionOfferPaymentMode.payAsYouGo,
            unit: SK2SubscriptionPeriodUnit.month,
            count: 3,
          ),
        ],
      );
      final data = await row(product);
      expect(data['introductoryPrice'], {
        'priceString': '4,99 €',
        'period': 'P1M',
        'cycles': 3,
      });
      expect(data.keys, isNot(contains('freeTrial')));
    });

    test('zero-fraction prices format with their grouping', () async {
      Future<Object?> intro(double price) async => (await row(
        _apple(
          display: '¥1,200',
          price: 1200,
          offers: [
            _offer(price, mode: SK2SubscriptionOfferPaymentMode.payUpFront),
          ],
        ),
      ))['introductoryPrice'];
      expect(await intro(600), containsPair('priceString', '¥600'));
      expect(await intro(1000), containsPair('priceString', '¥1,000'));
      expect(await intro(599.5), isNull);
    });

    test('an unreadable format keeps a free trial without its price', () async {
      final data = await row(
        _apple(display: r'2 x $4.99', price: 9.98, offers: [_offer(0)]),
      );
      expect(data['priceString'], r'2 x $4.99');
      expect(data['freeTrial'], {'period': 'P1W', 'cycles': 1});
    });

    test('an unreadable format omits a paid offer', () async {
      final data = await row(
        _apple(
          display: r'2 x $4.99',
          price: 9.98,
          offers: [
            _offer(1.99, mode: SK2SubscriptionOfferPaymentMode.payAsYouGo),
          ],
        ),
      );
      expect(data.keys, isNot(contains('introductoryPrice')));
    });

    test('only the eligible product shows its offer', () async {
      store.eligible = (id) async => id == 'pro';
      final data = await inAppPurchaseOfferingData(
        identifier: 'pro',
        packages: {
          'a': _apple(offers: [_offer(0)]),
          'b': _apple(id: 'plus', offers: [_offer(0)]),
        },
      );
      final rows = (data['packages']! as List).cast<Map<String, Object?>>();
      expect(rows[0], contains('freeTrial'));
      expect(rows[1].keys, isNot(contains('freeTrial')));
    });

    test('an eligibility check that never answers times out', () async {
      store.eligible = (_) => Completer<bool>().future;
      final data = await row(_apple(offers: [_offer(0)]));
      expect(data['priceString'], r'$9.99');
      expect(data.keys, isNot(contains('freeTrial')));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('ineligible user gets no offer keys', () async {
      store.eligible = (_) async => false;
      final data = await row(_apple(offers: [_offer(0)]));
      expect(data.keys, isNot(contains('freeTrial')));
      expect(data['subscriptionPeriod'], 'P1M');
    });

    test('a failed eligibility check omits the offer', () async {
      store.eligible = (_) async =>
          throw PlatformException(code: 'storekit2_eligibility_check_failed');
      final data = await row(_apple(offers: [_offer(0)]));
      expect(data.keys, isNot(contains('freeTrial')));
    });

    test('no introductory offer means no keys and no check', () async {
      final data = await row(_apple(offers: [_promo]));
      expect(data.keys, isNot(contains('freeTrial')));
      expect(data.keys, isNot(contains('introductoryPrice')));
      expect(store.eligibilityChecks, isEmpty);
    });

    test('shared products are checked once', () async {
      final product = _apple(offers: [_offer(0)]);
      final data = await inAppPurchaseOfferingData(
        identifier: 'pro',
        packages: {'a': product, 'b': product},
      );
      expect(store.eligibilityChecks, ['pro']);
      for (final row
          in (data['packages']! as List).cast<Map<String, Object?>>()) {
        expect(row, contains('freeTrial'));
      }
    });

    test('another platform is not asked and shows no offer', () async {
      InAppPurchasePlatform.instance = FakeStore();
      final data = await row(_apple(offers: [_offer(0)]));
      expect(data.keys, isNot(contains('freeTrial')));
    });
  });

  group('Google Play', () {
    test('multi-phase offer gives trial, intro and renewal price', () async {
      final data = await row(
        _play([
          _phase(0, 'Free', 'P1W', 1),
          _phase(1990000, r'$1.99', 'P1M', 3),
          _phase(
            9990000,
            r'$9.99',
            'P1M',
            0,
            mode: RecurrenceMode.infiniteRecurring,
          ),
        ]),
      );
      expect(data, {
        'identifier': 'monthly',
        'productIdentifier': 'pro',
        'priceString': r'$9.99',
        'currencyCode': 'USD',
        'subscriptionPeriod': 'P1M',
        'freeTrial': {'priceString': 'Free', 'period': 'P1W', 'cycles': 1},
        'introductoryPrice': {
          'priceString': r'$1.99',
          'period': 'P1M',
          'cycles': 3,
        },
      });
      expect(store.eligibilityChecks, isEmpty);
    });

    test('each offer of a product shows its own phases', () async {
      final offers = _playOffers([
        [_base],
        [_phase(0, 'Free', 'P1W', 1), _base],
      ]);
      final data = await inAppPurchaseOfferingData(
        identifier: 'pro',
        packages: {'base': offers[0], 'trial': offers[1]},
      );
      final rows = (data['packages']! as List).cast<Map<String, Object?>>();
      expect(rows[0].keys, isNot(contains('freeTrial')));
      expect(rows[1]['freeTrial'], {
        'priceString': 'Free',
        'period': 'P1W',
        'cycles': 1,
      });
    });

    test('a base plan alone has no offer keys', () async {
      final data = await row(
        _play([
          _phase(
            9990000,
            r'$9.99',
            'P1M',
            0,
            mode: RecurrenceMode.infiniteRecurring,
          ),
        ]),
      );
      expect(data.keys, isNot(contains('freeTrial')));
      expect(data.keys, isNot(contains('introductoryPrice')));
      expect(data['subscriptionPeriod'], 'P1M');
    });
  });
}

final _promo = SK2SubscriptionOffer(
  id: 'promo',
  price: 1.99,
  type: SK2SubscriptionOfferType.promotional,
  period: const SK2SubscriptionPeriod(
    value: 1,
    unit: SK2SubscriptionPeriodUnit.month,
  ),
  periodCount: 1,
  paymentMode: SK2SubscriptionOfferPaymentMode.payAsYouGo,
);

SK2SubscriptionOffer _offer(
  double price, {
  SK2SubscriptionOfferPaymentMode mode =
      SK2SubscriptionOfferPaymentMode.freeTrial,
  SK2SubscriptionPeriodUnit unit = SK2SubscriptionPeriodUnit.week,
  int count = 1,
}) => SK2SubscriptionOffer(
  price: price,
  type: SK2SubscriptionOfferType.introductory,
  period: SK2SubscriptionPeriod(value: 1, unit: unit),
  periodCount: count,
  paymentMode: mode,
);

AppStoreProduct2Details _apple({
  String id = 'pro',
  String display = r'$9.99',
  double price = 9.99,
  String currency = 'USD',
  required List<SK2SubscriptionOffer> offers,
}) => AppStoreProduct2Details.fromSK2Product(
  SK2Product(
    id: id,
    displayName: 'Pro',
    displayPrice: display,
    description: 'Pro',
    price: price,
    type: SK2ProductType.autoRenewable,
    priceLocale: SK2PriceLocale(currencyCode: currency, currencySymbol: ''),
    subscription: SK2SubscriptionInfo(
      subscriptionGroupID: 'group',
      promotionalOffers: offers,
      subscriptionPeriod: const SK2SubscriptionPeriod(
        value: 1,
        unit: SK2SubscriptionPeriodUnit.month,
      ),
    ),
  ),
);

PricingPhaseWrapper _phase(
  int micros,
  String formatted,
  String period,
  int cycles, {
  RecurrenceMode mode = RecurrenceMode.finiteRecurring,
}) => PricingPhaseWrapper(
  billingCycleCount: cycles,
  billingPeriod: period,
  formattedPrice: formatted,
  priceAmountMicros: micros,
  priceCurrencyCode: 'USD',
  recurrenceMode: mode,
);

const _base = PricingPhaseWrapper(
  billingCycleCount: 0,
  billingPeriod: 'P1M',
  formattedPrice: r'$9.99',
  priceAmountMicros: 9990000,
  priceCurrencyCode: 'USD',
  recurrenceMode: RecurrenceMode.infiniteRecurring,
);

GooglePlayProductDetails _play(List<PricingPhaseWrapper> phases) =>
    _playOffers([phases]).single;

List<GooglePlayProductDetails> _playOffers(
  List<List<PricingPhaseWrapper>> offers,
) => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: 'Pro',
    name: 'Pro',
    productId: 'pro',
    productType: ProductType.subs,
    title: 'Pro',
    subscriptionOfferDetails: [
      for (final (index, phases) in offers.indexed)
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'monthly',
          offerId: 'offer$index',
          offerTags: const [],
          offerIdToken: 'token$index',
          pricingPhases: phases,
        ),
    ],
  ),
);
