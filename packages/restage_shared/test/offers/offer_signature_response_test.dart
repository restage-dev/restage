import 'package:restage_shared/src/offers/offers.dart';
import 'package:test/test.dart';

void main() {
  group('OfferSignatureResponse.fromJson', () {
    Map<String, dynamic> wire({Object? scheme}) => {
          if (scheme != null) 'scheme': scheme,
          'keyIdentifier': 'KEY123',
          'nonce': 'a3f1c2d4-0000-4000-8000-000000000001',
          'timestamp': 1718312345678,
          'signature': 'MEUCIQ...base64der...==',
        };

    test('absent scheme defaults to legacy (matches the shipped route)', () {
      final r = OfferSignatureResponse.fromJson(wire());
      expect(r.scheme, OfferSignatureScheme.legacy);
      expect(r.keyIdentifier, 'KEY123');
      expect(r.nonce, 'a3f1c2d4-0000-4000-8000-000000000001');
      expect(r.timestampMs, 1718312345678);
      expect(r.signatureBase64, 'MEUCIQ...base64der...==');
    });

    test('"legacy" parses to legacy', () {
      expect(
        OfferSignatureResponse.fromJson(wire(scheme: 'legacy')).scheme,
        OfferSignatureScheme.legacy,
      );
    });

    test('"jws" parses to jws', () {
      expect(
        OfferSignatureResponse.fromJson(wire(scheme: 'jws')).scheme,
        OfferSignatureScheme.jws,
      );
    });

    test('an unknown scheme string is lenient -> unsupported (never a crash)',
        () {
      expect(
        OfferSignatureResponse.fromJson(wire(scheme: 'quantum')).scheme,
        OfferSignatureScheme.unsupported,
      );
    });

    test('a non-string scheme is also lenient -> unsupported', () {
      expect(
        OfferSignatureResponse.fromJson(wire(scheme: 42)).scheme,
        OfferSignatureScheme.unsupported,
      );
    });

    test('a missing required field throws (strict on the signature material)',
        () {
      expect(
        () => OfferSignatureResponse.fromJson(const {
          'keyIdentifier': 'KEY123',
          'nonce': 'n',
          // timestamp missing
          'signature': 'sig',
        }),
        throwsArgumentError,
      );
    });

    test('value equality and hashCode', () {
      final a = OfferSignatureResponse.fromJson(wire());
      final b = OfferSignatureResponse.fromJson(wire());
      final different = OfferSignatureResponse.fromJson(wire(scheme: 'jws'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
    });
  });
}
