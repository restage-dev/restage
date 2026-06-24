import 'package:restage_shared/src/offers/offers.dart';
import 'package:test/test.dart';

void main() {
  group('OfferSignatureRequest', () {
    test('toJson carries exactly the three contract fields', () {
      const request = OfferSignatureRequest(
        productId: 'com.example.app.pro_monthly',
        offerId: 'winback_3mo',
        appAccountToken: 'a3f1c2d4-0000-4000-8000-000000000001',
      );

      expect(request.toJson(), {
        'productId': 'com.example.app.pro_monthly',
        'offerId': 'winback_3mo',
        'appAccountToken': 'a3f1c2d4-0000-4000-8000-000000000001',
      });
    });

    test('value equality and hashCode', () {
      const a = OfferSignatureRequest(
        productId: 'p',
        offerId: 'o',
        appAccountToken: 't',
      );
      const b = OfferSignatureRequest(
        productId: 'p',
        offerId: 'o',
        appAccountToken: 't',
      );
      const different = OfferSignatureRequest(
        productId: 'p',
        offerId: 'o',
        appAccountToken: 'OTHER',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
    });

    test('rejects an empty contract field', () {
      expect(
        () => OfferSignatureRequest(
          productId: '',
          offerId: 'o',
          appAccountToken: 't',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
