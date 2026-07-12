import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

void main() {
  group('RestageRpcClient.fetchSurfaceStamp', () {
    test('returns a version with no watch channel', () async {
      final client = _clientReturning({'version': 7});

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp?.version, 7);
      expect(stamp?.watchChannel, isNull);
    });

    test('tolerates a watch channel', () async {
      final client = _clientReturning({
        'version': 7,
        'watchChannel': 'tok',
      });

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp?.version, 7);
      expect(stamp?.watchChannel, 'tok');
    });

    test('keeps the version but drops a non-string watch channel', () async {
      final client = _clientReturning({
        'version': 7,
        'watchChannel': 123,
      });

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      // A malformed watchChannel must not discard the otherwise-valid stamp.
      expect(stamp?.version, 7);
      expect(stamp?.watchChannel, isNull);
    });

    test('returns null for a non-integer version', () async {
      final client = _clientReturning({'version': '7'});

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isNull);
    });

    test('returns null for a non-success response', () async {
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) async => http.Response('not found', 404)),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isNull);
    });

    test('returns null when the transport throws', () async {
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (request) async => throw http.ClientException('boom', request.url),
        ),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isNull);
    });

    test('POSTs the surface identity with Bearer auth', () async {
      late http.Request seen;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'version': 7}), 200);
        }),
      );

      await client.fetchSurfaceStamp(
        surfaceType: 'onboarding',
        surfaceSlug: 'first_run',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/surface-stamp');
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {
        'surfaceType': 'onboarding',
        'surfaceSlug': 'first_run',
      });
    });
  });
}

RestageRpcClient _clientReturning(Map<String, Object?> body) =>
    RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(body), 200),
      ),
    );
