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
