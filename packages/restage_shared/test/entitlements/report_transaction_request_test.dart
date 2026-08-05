import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

void main() {
  group('ReportTransactionRequest', () {
    test('JSON round-trips all fields', () {
      const request = ReportTransactionRequest(
        reportId: '550e8400-e29b-41d4-a716-446655440000',
        purchaseIntentId: '11111111-2222-4333-8444-555555555555',
        store: 'appStore',
        storeVerificationData: 'long-base64-blob',
        storeProductId: 'com.example.app.pro_monthly',
        storeTransactionId: '2000000123456789',
        appAnonymousToken: 'a-uuid-v4',
        paywallId: 'pw_abc',
        paywallVariantSlug: 'control',
        paywallPublishedVersion: 7,
      );

      expect(ReportTransactionRequest.fromJson(request.toJson()), request);
    });

    test('JSON round-trips nullable correlation and attribution fields', () {
      const request = ReportTransactionRequest(
        store: 'playStore',
        storeVerificationData: 'purchase-token',
        storeProductId: 'pro_monthly',
        storeTransactionId: 'GPA.1234-5678',
      );

      final json = request.toJson();

      expect(json, isNot(contains('paywallId')));
      expect(json, isNot(contains('reportId')));
      expect(json, isNot(contains('purchaseIntentId')));
      expect(ReportTransactionRequest.fromJson(json), request);
    });

    test('playStore permits an absent storeTransactionId and omits it', () {
      final request = ReportTransactionRequest.fromJson(const {
        'store': 'playStore',
        'storeVerificationData': 'purchase-token',
        'storeProductId': 'pro_monthly',
      });

      expect(request.storeTransactionId, isNull);
      expect(request.toJson(), isNot(contains('storeTransactionId')));
      expect(
        ReportTransactionRequest.fromJson(request.toJson()),
        request,
      );
    });

    test('playStore rejects an empty storeTransactionId', () {
      expect(
        () => ReportTransactionRequest.fromJson(const {
          'store': 'playStore',
          'storeVerificationData': 'purchase-token',
          'storeProductId': 'pro_monthly',
          'storeTransactionId': '',
        }),
        throwsArgumentError,
      );
    });

    test('appStore rejects an absent storeTransactionId', () {
      expect(
        () => ReportTransactionRequest.fromJson(const {
          'store': 'appStore',
          'storeVerificationData': 'signed-transaction-info',
          'storeProductId': 'pro_monthly',
        }),
        throwsArgumentError,
      );
    });

    test('rejects a non-UUID-v4 reportId', () {
      expect(
        () => ReportTransactionRequest.fromJson(const {
          'reportId': 'not-a-uuid',
          'store': 'playStore',
          'storeVerificationData': 'purchase-token',
          'storeProductId': 'pro_monthly',
          'storeTransactionId': 'GPA.1234-5678',
        }),
        throwsArgumentError,
      );
    });

    test('rejects a non-UUID-v4 purchaseIntentId', () {
      expect(
        () => ReportTransactionRequest.fromJson(const {
          'purchaseIntentId': 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',
          'store': 'playStore',
          'storeVerificationData': 'purchase-token',
          'storeProductId': 'pro_monthly',
          'storeTransactionId': 'GPA.1234-5678',
        }),
        throwsArgumentError,
      );
    });

    test('rejects unknown store values', () {
      expect(
        () => ReportTransactionRequest.fromJson(const {
          'store': 'amazonStore',
          'storeVerificationData': 'blob',
          'storeProductId': 'pro_monthly',
          'storeTransactionId': 'tx_1',
        }),
        throwsArgumentError,
      );
    });
  });
}
