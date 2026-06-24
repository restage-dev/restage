import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/billing/signed_native_offer.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('AppleSignedOffer', () {
    AppleSignedOffer build({String offerId = 'winback_3mo'}) =>
        AppleSignedOffer(
          offerId: offerId,
          keyIdentifier: 'KEY123',
          nonce: 'a3f1c2d4-0000-4000-8000-000000000001',
          timestampMs: 1718312345678,
          signatureBase64: 'MEUCIQ...base64der...==',
        );

    test('exposes offerId through the sealed base', () {
      final SignedNativeOffer offer = build();
      expect(offer.offerId, 'winback_3mo');
    });

    test('defaults to the legacy scheme', () {
      expect(build().scheme, OfferSignatureScheme.legacy);
    });

    test('value equality and hashCode', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(build(offerId: 'other')));
    });
  });

  group('GoogleOffer', () {
    GoogleOffer build({
      String offerId = 'winback_3mo',
      String? basePlanId = 'annual',
    }) =>
        GoogleOffer(offerId: offerId, basePlanId: basePlanId);

    test('exposes offerId through the base type', () {
      final SignedNativeOffer offer = build();
      expect(offer.offerId, 'winback_3mo');
    });

    test('basePlanId is optional and defaults to null', () {
      expect(const GoogleOffer(offerId: 'x').basePlanId, isNull);
      expect(build().basePlanId, 'annual');
    });

    test('is a SignedNativeOffer but not an AppleSignedOffer', () {
      final SignedNativeOffer offer = build();
      expect(offer, isA<SignedNativeOffer>());
      expect(offer, isNot(isA<AppleSignedOffer>()));
    });

    test('value equality and hashCode incl. basePlanId', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(build(offerId: 'other')));
      expect(build(), isNot(build(basePlanId: 'monthly')));
      expect(build(), isNot(build(basePlanId: null)));
    });
  });
}
