import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/surface_delivery_evidence.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('RestageRpcClient.fetchSurfaceStamp', () {
    test('returns a version with no watch channel', () async {
      final client = _clientReturning({'version': 7});

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStamp>());
      final available = stamp as SurfaceStamp;
      expect(available.version, 7);
      expect(available.watchChannel, isNull);
      expect(available.requiresResolution, isFalse);
    });

    test('reads a request for a fresh decision', () async {
      final client = _clientReturning({
        'version': 7,
        'requiresResolution': true,
      });

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStamp>());
      final available = stamp as SurfaceStamp;
      expect(available.version, 7);
      expect(available.requiresResolution, isTrue);
    });

    for (final value in <Object?>['true', 1, null]) {
      test('keeps the version with requiresResolution set to $value', () async {
        final client = _clientReturning({
          'version': 7,
          'requiresResolution': value,
        });

        final stamp = await client.fetchSurfaceStamp(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        );

        expect(stamp, isA<SurfaceStamp>());
        final available = stamp as SurfaceStamp;
        expect(available.version, 7);
        expect(available.requiresResolution, isFalse);
      });
    }

    for (final channel in <Object?>['tok', 123, null]) {
      test('preserves watch channel parsing with a fresh decision: $channel',
          () async {
        final client = _clientReturning({
          'version': 7,
          'watchChannel': channel,
          'requiresResolution': true,
        });

        final stamp = await client.fetchSurfaceStamp(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        );

        expect(stamp, isA<SurfaceStamp>());
        final available = stamp as SurfaceStamp;
        expect(available.version, 7);
        expect(available.watchChannel, channel is String ? channel : isNull);
        expect(available.requiresResolution, isTrue);
      });
    }

    test('tolerates a watch channel', () async {
      final client = _clientReturning({
        'version': 7,
        'watchChannel': 'tok',
      });

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStamp>());
      final available = stamp as SurfaceStamp;
      expect(available.version, 7);
      expect(available.watchChannel, 'tok');
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
      expect(stamp, isA<SurfaceStamp>());
      final available = stamp as SurfaceStamp;
      expect(available.version, 7);
      expect(available.watchChannel, isNull);
    });

    test('returns unavailable for a non-integer version', () async {
      final client = _clientReturning({'version': '7'});

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStampUnavailable>());
    });

    test('returns unavailable for a non-success response', () async {
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) async => http.Response('not found', 404)),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStampUnavailable>());
    });

    test('returns unavailable when the transport throws', () async {
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

      expect(stamp, isA<SurfaceStampUnavailable>());
    });

    test('returns unavailable for a 503 rate_limited response', () async {
      final evidence = <Duration>[];
      SurfaceDeliveryEvidence.install(
        ({
          required surfaceType,
          required surfaceSlug,
          required version,
          required reason,
        }) {},
        rateLimited: ({
          required surfaceType,
          required surfaceSlug,
          required retryAfter,
        }) {
          evidence.add(retryAfter);
        },
      );
      addTearDown(SurfaceDeliveryEvidence.clear);
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => http.Response('{"error":"rate_limited"}', 503),
        ),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStampUnavailable>());
      expect(evidence, isEmpty);
    });

    test('returns a throttled result and evidence for a malformed 429',
        () async {
      final evidence = <({
        Surface surface,
        String surfaceId,
        Duration retryAfter,
      })>[];
      SurfaceDeliveryEvidence.install(
        ({
          required surfaceType,
          required surfaceSlug,
          required version,
          required reason,
        }) {},
        rateLimited: ({
          required surfaceType,
          required surfaceSlug,
          required retryAfter,
        }) {
          evidence.add((
            surface: surfaceType,
            surfaceId: surfaceSlug,
            retryAfter: retryAfter,
          ));
        },
      );
      addTearDown(SurfaceDeliveryEvidence.clear);
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => http.Response(
            'not json',
            429,
            headers: {'Retry-After': '7'},
          ),
        ),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStampRateLimited>());
      expect(
        (stamp as SurfaceStampRateLimited).retryAfter,
        const Duration(seconds: 7),
      );
      expect(
        evidence,
        [
          (
            surface: Surface.paywall,
            surfaceId: 'pro_upgrade',
            retryAfter: const Duration(seconds: 7),
          ),
        ],
      );
    });

    test('keeps unknown-surface rate limits unavailable without evidence',
        () async {
      final evidence = <Duration>[];
      SurfaceDeliveryEvidence.install(
        ({
          required surfaceType,
          required surfaceSlug,
          required version,
          required reason,
        }) {},
        rateLimited: ({
          required surfaceType,
          required surfaceSlug,
          required retryAfter,
        }) {
          evidence.add(retryAfter);
        },
      );
      addTearDown(SurfaceDeliveryEvidence.clear);
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => http.Response('', 429, headers: {'Retry-After': '7'}),
        ),
      );

      final stamp = await client.fetchSurfaceStamp(
        surfaceType: 'future_surface',
        surfaceSlug: 'pro_upgrade',
      );

      expect(stamp, isA<SurfaceStampUnavailable>());
      expect(evidence, isEmpty);
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
