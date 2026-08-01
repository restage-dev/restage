import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

void main() {
  group('ReportTransactionResponse', () {
    test('round-trips Apple accepted evidence and entitlements', () {
      final response = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440000',
        evidence: const AppleAcceptedStoreEvidence(
          submittedTransactionId: '2000000000000001',
          acceptedTransactionId: '2000000000000002',
          originalTransactionId: '1000000000000001',
        ),
        attributionDisposition: AttributionDisposition.applied,
        entitlements: [
          EntitlementSummary(
            entitlementId: 'pro',
            status: 'active',
            productId: 'pro_monthly',
            source: 'clientReport',
          ),
        ],
      );

      expect(ReportTransactionResponse.fromJson(response.toJson()), response);
      expect(response.toJson()['entitlements'], hasLength(1));
    });

    test('round-trips Google evidence without a purchase token', () {
      final response = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440001',
        evidence: const GoogleAcceptedStoreEvidence(
          submittedOrderId: 'GPA.1234-5678..3',
          acceptedOrderId: 'GPA.1234-5678..3',
          orderLineageId: 'GPA.1234-5678',
        ),
        attributionDisposition: AttributionDisposition.alreadyApplied,
      );

      final json = response.toJson();

      expect(json.toString(), isNot(contains('purchaseToken')));
      expect(ReportTransactionResponse.fromJson(json), response);
    });

    test('rejects Google evidence whose orders do not share one lineage', () {
      final json = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440001',
        evidence: const GoogleAcceptedStoreEvidence(
          submittedOrderId: 'GPA.1234-5678..2',
          acceptedOrderId: 'GPA.9999-0000..3',
          orderLineageId: 'GPA.1234-5678',
        ),
        attributionDisposition: AttributionDisposition.alreadyApplied,
      ).toJson();

      expect(
        () => ReportTransactionResponse.fromJson(json),
        throwsArgumentError,
      );
    });

    test('rejects missing or malformed completion-safe fields', () {
      final valid = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440002',
        evidence: const AppleAcceptedStoreEvidence(
          submittedTransactionId: 'tx-1',
          acceptedTransactionId: 'tx-1',
          originalTransactionId: 'original-1',
        ),
        attributionDisposition: AttributionDisposition.notProvided,
      ).toJson();

      for (final key in <String>[
        'accepted',
        'evidence',
        'attributionDisposition',
        'entitlements',
      ]) {
        final malformed = Map<String, dynamic>.from(valid)..remove(key);
        expect(
          () => ReportTransactionResponse.fromJson(malformed),
          throwsArgumentError,
          reason: 'missing $key must fail closed',
        );
      }
    });
  });
}
