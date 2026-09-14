import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

void main() {
  group('CommerceReportResponse', () {
    test('round-trips a verified result and purchaser state', () {
      final response = CommerceReportResponse(
        outcome: 'verified',
        purchaserState: CommercePurchaserStateResponse(
          status: 'current',
          entitlements: [
            EntitlementSummary(
              entitlementId: 'pro',
              status: 'active',
              productId: 'pro.monthly.us',
              source: 'clientReport',
            ),
          ],
          retrievedAt: DateTime.utc(2026, 9, 5, 12),
        ),
      );

      expect(CommerceReportResponse.fromJson(response.toJson()), response);
    });

    test('normalizes an unknown response outcome', () {
      final response = CommerceReportResponse.fromJson(
        const <String, dynamic>{
          'outcome': 'settled_later',
          'purchaserState': <String, dynamic>{
            'status': 'current',
            'entitlements': <dynamic>[],
            'retrievedAt': '2026-09-05T12:00:00.000Z',
          },
        },
      );

      expect(response.outcome, 'unknown');
    });
  });
}
