import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

const _purchaseTokenDigest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

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

    test('round-trips Google order evidence with a token digest', () {
      final response = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440001',
        evidence: const GoogleAcceptedStoreEvidence(
          submittedOrderId: 'GPA.1234-5678..3',
          acceptedOrderId: 'GPA.1234-5678..3',
          orderLineageId: 'GPA.1234-5678',
          acceptedPurchaseTokenDigest: _purchaseTokenDigest,
        ),
        attributionDisposition: AttributionDisposition.alreadyApplied,
      );

      final json = response.toJson();

      expect(json.toString(), isNot(contains('purchaseToken')));
      expect(
        (json['evidence'] as Map)['acceptedPurchaseTokenDigest'],
        _purchaseTokenDigest,
      );
      expect(ReportTransactionResponse.fromJson(json), response);
    });

    test('round-trips Google evidence without an order tuple', () {
      const evidence = GoogleAcceptedStoreEvidence(
        submittedOrderId: null,
        acceptedOrderId: null,
        orderLineageId: null,
        acceptedPurchaseTokenDigest: _purchaseTokenDigest,
      );

      final json = evidence.toJson();

      expect(json, isNot(contains('submittedOrderId')));
      expect(json, isNot(contains('acceptedOrderId')));
      expect(json, isNot(contains('orderLineageId')));
      expect(AcceptedStoreEvidence.fromJson(json), evidence);
    });

    test('rejects a partial Google order tuple', () {
      final json = const GoogleAcceptedStoreEvidence(
        submittedOrderId: 'GPA.1234-5678..3',
        acceptedOrderId: null,
        orderLineageId: null,
        acceptedPurchaseTokenDigest: _purchaseTokenDigest,
      ).toJson();

      expect(
        () => AcceptedStoreEvidence.fromJson(json),
        throwsArgumentError,
      );
    });

    test('rejects Google evidence missing its purchase-token digest', () {
      final json = const GoogleAcceptedStoreEvidence(
        submittedOrderId: null,
        acceptedOrderId: null,
        orderLineageId: null,
        acceptedPurchaseTokenDigest: _purchaseTokenDigest,
      ).toJson()
        ..remove('acceptedPurchaseTokenDigest');

      expect(
        () => AcceptedStoreEvidence.fromJson(json),
        throwsArgumentError,
      );
    });

    test('rejects Google evidence whose orders do not share one lineage', () {
      final json = ReportTransactionResponse(
        accepted: true,
        reportId: '550e8400-e29b-41d4-a716-446655440001',
        evidence: const GoogleAcceptedStoreEvidence(
          submittedOrderId: 'GPA.1234-5678..2',
          acceptedOrderId: 'GPA.9999-0000..3',
          orderLineageId: 'GPA.1234-5678',
          acceptedPurchaseTokenDigest: _purchaseTokenDigest,
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
