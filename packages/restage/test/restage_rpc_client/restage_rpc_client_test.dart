import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('RestageRpcClient construction', () {
    test('rejects empty baseUrl', () {
      expect(
        () => RestageRpcClient(baseUrl: '', apiKey: 'rs_pk_x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty apiKey', () {
      expect(
        () => RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a baseUrl that ends with a trailing slash', () {
      expect(
        () => RestageRpcClient(
          baseUrl: 'https://example.com/',
          apiKey: 'rs_pk_x',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RestageRpcClient.reportTransaction', () {
    test('POSTs to /sdk/v1/reportTransaction with Bearer auth and JSON body',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode(<String, Object?>{'entitlements': <Object?>[]}),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      await client.reportTransaction(_request);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/reportTransaction');
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), _request.toJson());
    });

    test('returns an empty list from a 200 response with no entitlements',
        () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode(<String, Object?>{'entitlements': <Object?>[]}),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      // Non-null: the server's explicit "nothing entitled" answer, not
      // a transport failure.
      expect(summaries, isNotNull);
      expect(summaries, isEmpty);
    });

    test('returns the parsed entitlements from a 200 response', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'entitlements': [
              {
                'entitlementId': 'pro',
                'status': 'active',
                'productId': 'monthly',
                'source': 'storeNotification',
              },
            ],
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, hasLength(1));
      expect(summaries!.single.entitlementId, 'pro');
      expect(summaries.single.status, 'active');
      expect(summaries.single.isEntitled, isTrue);
    });

    test('returns null on 4xx (distinguishing transport failure from empty)',
        () async {
      final mock = MockClient((req) async => http.Response('', 401));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null on 5xx', () async {
      final mock = MockClient((req) async => http.Response('', 503));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null when the transport throws', () async {
      final mock = MockClient(
        (req) async => throw http.ClientException('boom', req.url),
      );
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null when the response body is malformed JSON', () async {
      final mock = MockClient(
        (req) async => http.Response('not-json{', 200),
      );
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null when the response body is not a JSON object', () async {
      final mock = MockClient(
        (req) async => http.Response('["scalar-array"]', 200),
      );
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null when a 200 carries a malformed entitlement entry',
        () async {
      // A 200 whose entitlements list has a structurally-invalid entry (the
      // fail-loud EntitlementSummary.fromJson throws on it) must degrade to
      // null, not throw out of the call.
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode(<String, Object?>{
            'entitlements': [
              {'entitlementId': 'pro'}, // missing status/productId/source
            ],
          }),
          200,
        ),
      );
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });
  });

  group('RestageRpcClient.syncEntitlements', () {
    test('POSTs to /sdk/v1/syncEntitlements with the sync request body',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode(<String, Object?>{'entitlements': <Object?>[]}),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final request = EntitlementSyncRequest(
        appAnonymousToken: '11111111-2222-4333-8444-555555555555',
        knownStoreTransactionIds: ['tx-1', 'tx-2'],
      );

      await client.syncEntitlements(request);

      expect(seen.url.path, '/sdk/v1/syncEntitlements');
      expect(jsonDecode(seen.body), request.toJson());
    });

    test('returns null when the request fails', () async {
      final mock = MockClient((req) async => http.Response('', 503));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.syncEntitlements(EntitlementSyncRequest());

      expect(summaries, isNull);
    });

    test('degrades gracefully when the server returns an unknown status',
        () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'entitlements': [
                {
                  'entitlementId': 'pro',
                  'status': 'something-new-from-server',
                  'productId': 'monthly',
                  'source': 'storeNotification',
                },
              ],
            }),
            200,
          ));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.syncEntitlements(EntitlementSyncRequest());

      expect(summaries, hasLength(1));
      expect(summaries!.single.status, 'unknown');
      expect(summaries.single.isEntitled, isFalse);
    });
  });

  group('RestageRpcClient.fetchSurface version omission', () {
    test('returns envelope bytes with valid assignment metadata', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
            'experimentId': 'exp_paywall_copy',
            'variantId': 'variant_a',
            'experimentEpoch': 3,
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(result!.envelopeBytes, orderedEquals([1, 2, 3]));
      expect(result.experimentId, 'exp_paywall_copy');
      expect(result.variantId, 'variant_a');
      expect(result.experimentEpoch, 3);
    });

    test('parses the serve decision when present', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
            'decision': 'assigned',
            'experimentId': 'exp_paywall_copy',
            'variantId': 'variant_a',
            'experimentEpoch': 3,
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(result!.decision, 'assigned');
    });

    test('preserves current behaviour when the decision is absent', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(result!.decision, isNull);
      expect(result.envelopeBytes, orderedEquals([1, 2, 3]));
    });

    test(
        'degrades gracefully on an UNRECOGNISED decision string: it is '
        'carried as an opaque value and never throws (forward-compat with a '
        'newer server)', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
            // A value a future server (e.g. a later phase's clientIncompatible)
            // may emit that this client build does not recognise.
            'decision': 'someFutureDecisionValue',
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      // The surface still resolves (the unknown decision does not fail the
      // fetch); the value is carried opaquely for the caller to interpret.
      expect(result, isNotNull);
      expect(result!.envelopeBytes, orderedEquals([1, 2, 3]));
      expect(result.decision, 'someFutureDecisionValue');
    });

    test('ignores a non-string decision without failing the fetch', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
            'decision': 42,
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(result!.decision, isNull);
      expect(result.envelopeBytes, orderedEquals([1, 2, 3]));
    });

    test('treats null assignment metadata as no assignment metadata', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'envelope': base64Encode([1, 2, 3]),
            'experimentId': null,
            'variantId': null,
            'experimentEpoch': null,
          }),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(result!.envelopeBytes, orderedEquals([1, 2, 3]));
      expect(result.experimentId, isNull);
      expect(result.variantId, isNull);
      expect(result.experimentEpoch, isNull);
    });

    test('fails closed on malformed assignment metadata', () async {
      final cases = <Map<String, Object?>>[
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp'
        },
        {
          'envelope': base64Encode([1]),
          'variantId': 'variant_a'
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': '',
          'variantId': 'variant_a',
          'experimentEpoch': 3,
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': ' exp ',
          'variantId': 'variant_a',
          'experimentEpoch': 3,
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp',
          'variantId': 'variant\u0000a',
          'experimentEpoch': 3,
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp',
          'variantId': 1,
          'experimentEpoch': 3,
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
          'experimentEpoch': 0,
        },
        {
          'envelope': base64Encode([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
          'experimentEpoch': '3',
        },
      ];

      for (final body in cases) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode(body), 200),
          ),
        );

        final result = await client.fetchSurface(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        );

        expect(result, isNull);
      }
    });

    test('includes version in the body when an exact version is requested',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'envelope': base64Encode([1, 2])
            }),
            200);
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      await client.fetchSurface(
        surfaceType: 'onboarding',
        surfaceSlug: 'first_run',
        version: 1,
      );

      expect(jsonDecode(seen.body), {
        'surfaceType': 'onboarding',
        'surfaceSlug': 'first_run',
        'version': 1,
      });
    });

    test('OMITS version from the body when version is null (active arm)',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'envelope': base64Encode([1, 2])
            }),
            200);
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
        version: null,
      );

      expect(jsonDecode(seen.body), {
        'surfaceType': 'paywall',
        'surfaceSlug': 'pro_upgrade',
      });
      expect((jsonDecode(seen.body) as Map).containsKey('version'), isFalse);
    });

    test('includes assignmentKey only when the caller provides one', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final mock = MockClient((req) async {
        seenBodies.add((jsonDecode(req.body) as Map).cast());
        return http.Response(
            jsonEncode({
              'envelope': base64Encode([1, 2])
            }),
            200);
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
        assignmentKey: 'anon-123',
      );
      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(seenBodies.first, {
        'surfaceType': 'paywall',
        'surfaceSlug': 'pro_upgrade',
        'assignmentKey': 'anon-123',
      });
      expect(seenBodies.last, {
        'surfaceType': 'paywall',
        'surfaceSlug': 'pro_upgrade',
      });
    });
  });
}

const ReportTransactionRequest _request = ReportTransactionRequest(
  store: 'appStore',
  storeVerificationData: 'wrapped-jws',
  storeProductId: 'pro_monthly',
  storeTransactionId: 'tx-1',
);
