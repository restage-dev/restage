import 'package:restage_shared/commerce.dart';
import 'package:test/test.dart';

const _intentId = '550e8400-e29b-41d4-a716-446655440000';
const _token = '550e8400-e29b-41d4-a716-446655440001';

void main() {
  group('CommerceIntentRequest', () {
    test('round-trips a logical offer and surface attribution', () {
      final request = CommerceIntentRequest(
        intentId: _intentId,
        offerId: 'pro.monthly',
        store: 'app_store',
        appAnonymousToken: _token,
        surfaceId: 'upgrade',
        surfaceKind: 'paywall',
        variantSlug: 'control',
        publishedVersion: 3,
      );

      expect(CommerceIntentRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), isNot(contains('storeProductId')));
    });

    test('rejects unknown fields and non-logical offer identifiers', () {
      expect(
        () => CommerceIntentRequest.fromJson(const <String, dynamic>{
          'intentId': _intentId,
          'offerId': 'PRO MONTHLY',
          'store': 'app_store',
          'appAnonymousToken': _token,
        }),
        throwsArgumentError,
      );
      expect(
        () => CommerceIntentRequest.fromJson(const <String, dynamic>{
          'intentId': _intentId,
          'offerId': 'pro.monthly',
          'store': 'app_store',
          'appAnonymousToken': _token,
          'storeProductId': 'provider.sku',
        }),
        throwsArgumentError,
      );
    });

    test('requires a surface for variant and published-version attribution',
        () {
      expect(
        () => CommerceIntentRequest(
          intentId: _intentId,
          offerId: 'pro.monthly',
          store: 'app_store',
          appAnonymousToken: _token,
          variantSlug: 'control',
        ),
        throwsArgumentError,
      );
      expect(
        () => CommerceIntentRequest.fromJson(const <String, dynamic>{
          'intentId': _intentId,
          'offerId': 'pro.monthly',
          'store': 'app_store',
          'appAnonymousToken': _token,
          'publishedVersion': 1,
        }),
        throwsArgumentError,
      );
    });
  });

  group('CommerceIntentResponse', () {
    test('round-trips the server-resolved purchasable', () {
      final response = CommerceIntentResponse(
        intentId: _intentId,
        status: 'ready',
        resolved: CommerceResolvedPurchasable(
          storeProductId: 'pro.monthly.us',
          productKind: 'autoRenewableSubscription',
          storeOfferIdentifier: 'intro',
          appAccountToken: _token,
          offerSignature: const OfferSignatureResponse(
            scheme: OfferSignatureScheme.legacy,
            keyIdentifier: 'key-1',
            nonce: 'nonce-1',
            timestampMs: 1234,
            signatureBase64: 'c2lnbmF0dXJl',
          ),
        ),
      );

      expect(CommerceIntentResponse.fromJson(response.toJson()), response);
    });
  });
}
