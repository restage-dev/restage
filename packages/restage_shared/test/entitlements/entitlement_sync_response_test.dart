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
    });
  });
}
