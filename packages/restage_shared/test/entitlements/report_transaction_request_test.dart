import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

const _reportId = '550e8400-e29b-41d4-a716-446655440002';
const _intentId = '550e8400-e29b-41d4-a716-446655440000';
const _token = '550e8400-e29b-41d4-a716-446655440001';

void main() {
  group('CommerceReportRequest', () {
    test('round-trips provider evidence and optional intent identity', () {
      final request = CommerceReportRequest(
        reportId: _reportId,
        intentId: _intentId,
        store: 'play_store',
        storeVerificationData: 'purchase-token',
        storeProductId: 'pro.monthly.us',
        storeTransactionId: 'GPA.1234-5678..0',
        appAnonymousToken: _token,
        paywallId: 'launch-paywall',
        paywallVariantSlug: 'treatment',
        paywallPublishedVersion: 7,
      );

      expect(CommerceReportRequest.fromJson(request.toJson()), request);
    });

    test('requires a report identity and snake-case store value', () {
      expect(
        () => CommerceReportRequest.fromJson(const <String, dynamic>{
          'store': 'app_store',
          'storeVerificationData': 'signed-jws',
          'storeProductId': 'pro.monthly.us',
          'appAnonymousToken': _token,
        }),
        throwsArgumentError,
      );
      expect(
        () => CommerceReportRequest.fromJson(const <String, dynamic>{
          'reportId': _reportId,
          'store': 'appStore',
          'storeVerificationData': 'signed-jws',
          'storeProductId': 'pro.monthly.us',
          'appAnonymousToken': _token,
        }),
        throwsArgumentError,
      );
    });

    test('requires an App Store transaction identity', () {
      expect(
        () => CommerceReportRequest.fromJson(const <String, dynamic>{
          'reportId': _reportId,
          'store': 'app_store',
          'storeVerificationData': 'signed-jws',
          'storeProductId': 'pro.monthly.us',
          'appAnonymousToken': _token,
        }),
        throwsArgumentError,
      );
    });

    test('preserves canonical-form report identity casing', () {
      final request = CommerceReportRequest(
        reportId: '550E8400-E29B-41D4-A716-446655440002',
        store: 'app_store',
        storeVerificationData: 'signed-jws',
        storeProductId: 'pro.monthly.us',
        storeTransactionId: 'tx-1',
        appAnonymousToken: _token,
      );

      expect(CommerceReportRequest.fromJson(request.toJson()), request);
    });
  });
}
