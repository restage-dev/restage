import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

void main() {
  group('CommercePurchaserStateResponse', () {
    test('round-trips a current entitlement state', () {
      final response = CommercePurchaserStateResponse(
        status: 'current',
        entitlements: [
          EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'pro.monthly.us',
            source: 'storeNotification',
            providerEnvironment: 'production',
          ),
        ],
        retrievedAt: DateTime.utc(2026, 9, 5, 12),
      );

      expect(
        CommercePurchaserStateResponse.fromJson(response.toJson()),
        response,
      );
    });

    test('fulfillment lines round-trip without collapsing repeated products',
        () {
      final lines = [
        CommerceFulfillmentSummary(
            id: 'line-a',
            productId: 'credit.pack',
            quantity: 3,
            providerEnvironment: 'production'),
        CommerceFulfillmentSummary(
            id: 'line-b',
            productId: 'credit.pack',
            quantity: 2,
            providerEnvironment: 'sandbox'),
      ];
      final response = CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const [],
          fulfillments: lines,
          retrievedAt: DateTime.utc(2026, 10, 17));
      final decoded =
          CommercePurchaserStateResponse.fromJson(response.toJson());
      expect(decoded, response);
      expect(decoded.hashCode, response.hashCode);
      expect(decoded.fulfillments, lines);
      lines.clear();
      expect(response.fulfillments, hasLength(2));
      expect(() => decoded.fulfillments.clear(), throwsUnsupportedError);
      expect(
          CommercePurchaserStateResponse(
              status: 'current',
              entitlements: const [],
              retrievedAt: response.retrievedAt),
          isNot(response));
      final changed = response.toJson();
      (changed['fulfillments'] as List<dynamic>)[0] =
          CommerceFulfillmentSummary(
                  id: 'line-a',
                  productId: 'credit.pack',
                  quantity: 1,
                  providerEnvironment: 'production')
              .toJson();
      expect(CommercePurchaserStateResponse.fromJson(changed), isNot(response));
    });

    test('missing fulfillment list is empty and malformed lists are refused',
        () {
      final json = <String, dynamic>{
        'status': 'current',
        'entitlements': <dynamic>[],
        'retrievedAt': '2026-10-17T00:00:00.000Z'
      };
      expect(
          CommercePurchaserStateResponse.fromJson(json).fulfillments, isEmpty);
      for (final malformed in [
        null,
        'lines',
        [1]
      ]) {
        expect(
            () => CommercePurchaserStateResponse.fromJson(
                {...json, 'fulfillments': malformed}),
            throwsArgumentError);
      }
    });

    test(
        'fulfillment decoding requires a known environment and positive quantity',
        () {
      final json = <String, dynamic>{
        'id': 'line',
        'productId': 'store.product',
        'quantity': 2,
        'providerEnvironment': 'sandbox',
        'future': true
      };
      expect(CommerceFulfillmentSummary.fromJson(json).quantity, 2);
      for (final environment in [null, '', 'unknown', 'future']) {
        expect(
            () => CommerceFulfillmentSummary.fromJson(
                {...json, 'providerEnvironment': environment}),
            throwsArgumentError);
      }
      for (final quantity in [null, 0, -1, 1.5, '2']) {
        expect(
            () => CommerceFulfillmentSummary.fromJson(
                {...json, 'quantity': quantity}),
            throwsArgumentError);
      }
      for (final field in ['id', 'productId']) {
        expect(() => CommerceFulfillmentSummary.fromJson({...json, field: ''}),
            throwsArgumentError);
      }
    });

    test('normalizes an unknown state status', () {
      final response = CommercePurchaserStateResponse.fromJson(
        const <String, dynamic>{
          'status': 'delayed',
          'entitlements': <dynamic>[],
          'retrievedAt': '2026-09-05T12:00:00.000Z',
        },
      );

      expect(response.status, 'unknown');
      expect(response.hasProductionPurchaseHistory, isNull);
    });

    test('history preserves proved presence, absence and unknown', () {
      for (final history in [true, false, null]) {
        final response = CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const [],
          retrievedAt: DateTime.utc(2026, 10, 14),
          hasProductionPurchaseHistory: history,
        );
        expect(
          CommercePurchaserStateResponse.fromJson(response.toJson())
              .hasProductionPurchaseHistory,
          history,
        );
      }
      expect(
        () => CommercePurchaserStateResponse.fromJson({
          'status': 'current',
          'entitlements': <dynamic>[],
          'retrievedAt': '2026-10-14T00:00:00.000Z',
          'hasProductionPurchaseHistory': 'false',
        }),
        throwsArgumentError,
      );
    });
  });
}
