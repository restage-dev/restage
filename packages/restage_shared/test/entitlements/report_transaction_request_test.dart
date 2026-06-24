import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

void main() {
  group('ReportTransactionRequest', () {
    test('JSON round-trips all fields', () {
      const request = ReportTransactionRequest(
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

    test('JSON round-trips nullable attribution fields', () {
      const request = ReportTransactionRequest(
        store: 'playStore',
        storeVerificationData: 'purchase-token',
        storeProductId: 'pro_monthly',
        storeTransactionId: 'GPA.1234-5678',
      );

      final json = request.toJson();

      expect(json, isNot(contains('paywallId')));
      expect(ReportTransactionRequest.fromJson(json), request);
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
