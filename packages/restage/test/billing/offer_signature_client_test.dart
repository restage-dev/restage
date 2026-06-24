import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  const request = OfferSignatureRequest(
    productId: 'com.example.app.pro_monthly',
    offerId: 'winback_3mo',
    appAccountToken: 'a3f1c2d4-0000-4000-8000-000000000001',
  );

  Map<String, Object?> okBody({String? scheme}) => {
        if (scheme != null) 'scheme': scheme,
        'keyIdentifier': 'KEY123',
        'nonce': 'a3f1c2d4-0000-4000-8000-000000000001',
        'timestamp': 1718312345678,
        'signature': 'MEUCIQ...base64der...==',
      };

  RestageRpcClient clientWith(MockClient mock) => RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

  group('RestageRpcClient.mintOfferSignature', () {
    test('POSTs to /sdk/v1/offer-signature with Bearer auth and the JSON body',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode(okBody()), 200);
      });

      await clientWith(mock).mintOfferSignature(request);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/offer-signature');
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), request.toJson());
    });

    test('decodes a 200 into a typed response (absent scheme -> legacy)',
        () async {
      final mock = MockClient((req) async {
        return http.Response(jsonEncode(okBody()), 200);
      });

      final response = await clientWith(mock).mintOfferSignature(request);

      expect(response, isNotNull);
      expect(response!.scheme, OfferSignatureScheme.legacy);
      expect(response.keyIdentifier, 'KEY123');
      expect(response.timestampMs, 1718312345678);
      expect(response.signatureBase64, 'MEUCIQ...base64der...==');
    });

    test('passes the scheme discriminator through', () async {
      final mock = MockClient((req) async {
        return http.Response(jsonEncode(okBody(scheme: 'jws')), 200);
      });

      final response = await clientWith(mock).mintOfferSignature(request);

      expect(response!.scheme, OfferSignatureScheme.jws);
    });

    test('returns null on a 422 (ineligible / no signature)', () async {
      final mock = MockClient(
        (req) async => http.Response(
            jsonEncode({'error': 'offer_signature_unavailable'}), 422),
      );

      expect(await clientWith(mock).mintOfferSignature(request), isNull);
    });

    test('returns null on a non-2xx status', () async {
      final mock = MockClient((req) async => http.Response('', 503));
      expect(await clientWith(mock).mintOfferSignature(request), isNull);
    });

    test('returns null on a malformed (non-object) body', () async {
      final mock =
          MockClient((req) async => http.Response('"not-an-object"', 200));
      expect(await clientWith(mock).mintOfferSignature(request), isNull);
    });

    test('returns null on a transport throw', () async {
      final mock = MockClient((req) async => throw const _NetworkDown());
      expect(await clientWith(mock).mintOfferSignature(request), isNull);
    });

    test('returns null when the 200 body is missing signature material',
        () async {
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode({'keyIdentifier': 'K', 'nonce': 'n'}),
          200,
        ),
      );
      expect(await clientWith(mock).mintOfferSignature(request), isNull);
    });
  });
}

class _NetworkDown implements Exception {
  const _NetworkDown();
}
