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
        storeVerificationData: GooglePlayPurchaseReceipt(
          originalJson: '{"purchaseToken":"purchase-token"}',
          signature: 'test-signature',
        ).toVerificationData(),
        storeProductId: 'pro.monthly.us',
        storeTransactionId: 'GPA.1234-5678..0',
        appAnonymousToken: _token,
        paywallId: 'launch-paywall',
        paywallVariantSlug: 'treatment',
        paywallPublishedVersion: 7,
      );

      expect(CommerceReportRequest.fromJson(request.toJson()), request);
    });

    test('app-history restore is an optional strict boolean', () {
      final ordinary = CommerceReportRequest(
          reportId: _reportId,
          store: 'app_store',
          storeVerificationData: 'signed-jws',
          storeProductId: 'pro.monthly.us',
          storeTransactionId: 'tx-1',
          appAnonymousToken: _token);
      expect(ordinary.restoreAppHistory, isFalse);
      expect(ordinary.toJson().containsKey('restoreAppHistory'), isFalse);
      expect(
          CommerceReportRequest.fromJson(ordinary.toJson()).restoreAppHistory,
          isFalse);
      final explicitFalse = CommerceReportRequest.fromJson(
          {...ordinary.toJson(), 'restoreAppHistory': false});
      expect(explicitFalse, ordinary);
      final restore = CommerceReportRequest.fromJson(
          {...ordinary.toJson(), 'restoreAppHistory': true});
      expect(restore.restoreAppHistory, isTrue);
      expect(restore.toJson()['restoreAppHistory'], isTrue);
      expect(CommerceReportRequest.fromJson(restore.toJson()), restore);
      expect(restore, isNot(ordinary));
      expect(CommerceReportRequest.fromJson(restore.toJson()).hashCode,
          restore.hashCode);
      for (final invalid in [
        null,
        0,
        1,
        'true',
        'false',
        <dynamic>[],
        <String, dynamic>{}
      ]) {
        expect(
            () => CommerceReportRequest.fromJson(
                {...ordinary.toJson(), 'restoreAppHistory': invalid}),
            throwsArgumentError);
      }
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
