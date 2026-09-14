import 'package:restage_shared/commerce.dart';
import 'package:restage_shared/src/entitlements/report_transaction_response.dart';
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

  group('AcceptedStoreEvidence', () {
    test('round-trips the shared snake-case store vocabulary', () {
      const apple = AppleAcceptedStoreEvidence(
        submittedTransactionId: 'submitted',
        acceptedTransactionId: 'accepted',
        originalTransactionId: 'original',
      );
      const google = GoogleAcceptedStoreEvidence(
        submittedOrderId: 'GPA.1..0',
        acceptedOrderId: 'GPA.1..1',
        orderLineageId: 'GPA.1',
        acceptedPurchaseTokenDigest:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      expect(apple.toJson()['store'], 'app_store');
      expect(google.toJson()['store'], 'play_store');
      expect(AcceptedStoreEvidence.fromJson(apple.toJson()), apple);
      expect(AcceptedStoreEvidence.fromJson(google.toJson()), google);
      expect(
        () => AcceptedStoreEvidence.fromJson({
          ...apple.toJson(),
          'store': 'appStore',
        }),
        throwsArgumentError,
      );
    });
  });
}
