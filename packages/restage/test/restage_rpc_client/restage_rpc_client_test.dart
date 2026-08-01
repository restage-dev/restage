import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('RestageRpcClient.createPurchaseIntent', () {
    test('POSTs the immutable tuple and returns the correlated commit',
        () async {
      late http.Request seen;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'purchaseIntentId': _intentRequest.purchaseIntentId,
              'created': true,
            }),
            200,
          );
        }),
      );

      final response = await client.createPurchaseIntent(_intentRequest);

      expect(seen.url.path, '/sdk/v1/purchase-intent');
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(jsonDecode(seen.body), _intentRequest.toJson());
      expect(response?.purchaseIntentId, _intentRequest.purchaseIntentId);
      expect(response?.created, isTrue);
    });

    test('fails closed when the response echoes a different intent', () async {
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'purchaseIntentId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'created': true,
            }),
            200,
          ),
        ),
      );

      expect(await client.createPurchaseIntent(_intentRequest), isNull);
    });
  });

  group('RestageRpcClient.reportTransaction', () {
    test('compile-time debug outage follows the assertion-gated define',
        () async {
      const outageRequested = bool.fromEnvironment(
        'RESTAGE_DEBUG_FAIL_TRANSACTION_REPORTS',
      );
      var requests = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) async {
          requests += 1;
          return http.Response(jsonEncode(_acceptedResponse()), 200);
        }),
      );

      final response = await client.reportTransaction(_request);

      expect(response, outageRequested ? isNull : isNotNull);
      expect(requests, outageRequested ? 0 : 1);
    });

    test('debug outage intercepts only transaction reports', () async {
      final paths = <String>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        debugFailTransactionReports: true,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode(<String, Object?>{
              'purchaseIntentId': _intentRequest.purchaseIntentId,
              'created': true,
            }),
            200,
          );
        }),
      );

      expect(await client.reportTransaction(_request), isNull);
      expect(await client.createPurchaseIntent(_intentRequest), isNotNull);
      expect(paths, <String>['/sdk/v1/purchase-intent']);
    });

    test('debug outage is inert when explicitly disabled', () async {
      var requests = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        debugFailTransactionReports: false,
        httpClient: MockClient((_) async {
          requests += 1;
          return http.Response(jsonEncode(_acceptedResponse()), 200);
        }),
      );

      expect(await client.reportTransaction(_request), isNotNull);
      expect(requests, 1);
    });

    test('debug outage diagnostics contain no transaction evidence', () async {
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = originalDebugPrint);
      var requests = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        debugFailTransactionReports: true,
        httpClient: MockClient((_) async {
          requests += 1;
          return http.Response(jsonEncode(_acceptedResponse()), 200);
        }),
      );

      expect(await client.reportTransaction(_request), isNull);
      expect(requests, 0);
      final diagnostics = messages.whereType<String>().join('\n');
      expect(diagnostics, contains('local debug outage injection'));
      expect(diagnostics, isNot(contains(_request.storeVerificationData)));
      expect(diagnostics, isNot(contains(_request.storeTransactionId)));
      expect(diagnostics, isNot(contains(_request.storeProductId)));
      expect(diagnostics, isNot(contains(_request.reportId)));
    });

    test('POSTs to /sdk/v1/reportTransaction with Bearer auth and JSON body',
        () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode(_acceptedResponse()),
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

    test('returns explicit acceptance with no entitlements', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode(_acceptedResponse()),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final response = await client.reportTransaction(_request);

      expect(response, isNotNull);
      expect(response!.accepted, isTrue);
      expect(response.reportId, _request.reportId);
      expect(response.entitlements, isEmpty);
    });

    test('returns parsed evidence, disposition, and entitlements', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode(_acceptedResponse(entitled: true)),
          200,
        );
      });
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final response = await client.reportTransaction(_request);

      expect(response, isNotNull);
      expect(response!.evidence, isA<AppleAcceptedStoreEvidence>());
      expect(
        response.attributionDisposition,
        AttributionDisposition.applied,
      );
      expect(response.entitlements, hasLength(1));
      expect(response.entitlements.single.entitlementId, 'pro');
      expect(response.entitlements.single.status, 'active');
      expect(response.entitlements.single.isEntitled, isTrue);
    });

    test('fails closed when accepted is missing or false', () async {
      for (final body in <Map<String, Object?>>[
        _acceptedResponse()..remove('accepted'),
        _acceptedResponse()..['accepted'] = false,
      ]) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient(
            (req) async => http.Response(jsonEncode(body), 200),
          ),
        );

        expect(await client.reportTransaction(_request), isNull);
      }
    });

    test('fails closed when reportId does not correlate', () async {
      final body = _acceptedResponse()
        ..['reportId'] = '550e8400-e29b-41d4-a716-446655440099';
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (req) async => http.Response(jsonEncode(body), 200),
        ),
      );

      expect(await client.reportTransaction(_request), isNull);
    });

    test('fails closed when accepted evidence is malformed', () async {
      final body = _acceptedResponse()..['evidence'] = <String, Object?>{};
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (req) async => http.Response(jsonEncode(body), 200),
        ),
      );

      expect(await client.reportTransaction(_request), isNull);
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

    test('transport diagnostics never echo store verification evidence',
        () async {
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = originalDebugPrint);
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => throw StateError(_request.storeVerificationData),
        ),
      );

      expect(await client.reportTransaction(_request), isNull);
      expect(
        messages.whereType<String>().join('\n'),
        isNot(contains(_request.storeVerificationData)),
      );
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
            ..._acceptedResponse(),
            'entitlements': <Object?>[
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
    test(
      'six opaque API keys remain the only exact-target SDK authority',
      () async {
        final keys = <String>[
          'rs_pk_dev_sandbox',
          'rs_pk_dev_live',
          'rs_pk_staging_sandbox',
          'rs_pk_staging_live',
          'rs_pk_prod_sandbox',
          'rs_pk_prod_live',
        ];
        final requests = <http.Request>[];

        for (final key in keys) {
          final client = RestageRpcClient(
            baseUrl: 'https://example.com',
            apiKey: key,
            httpClient: MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode({
                  'envelope': base64Encode([requests.length]),
                }),
                200,
              );
            }),
          );

          final result = await client.fetchSurface(
            surfaceType: 'paywall',
            surfaceSlug: 'shared',
          );
          expect(result, isNotNull, reason: key);
        }

        expect(requests, hasLength(6));
        expect(requests.map((request) => request.headers['Authorization']), [
          for (final key in keys) 'Bearer $key',
        ]);
        for (final request in requests) {
          expect(jsonDecode(request.body), {
            'surfaceType': 'paywall',
            'surfaceSlug': 'shared',
          });
        }
      },
    );

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

  group('RestageRpcClient.fetchSurface metering key', () {
    setUp(SurfaceMeteringKeyProvider.clear);
    tearDown(SurfaceMeteringKeyProvider.clear);

    test('omits meteringKey when no provider is installed', () async {
      final client = _clientCapturing(_bodies());

      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(_captured.single.containsKey('meteringKey'), isFalse);
    });

    test('threads the installed key into the request body', () async {
      const token = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
      SurfaceMeteringKeyProvider.install(
        store: MeteringTokenStore(
          prefsProvider: () => _prefsWith(token),
        ),
      );
      final client = _clientCapturing(_bodies());

      await client.fetchSurface(
        surfaceType: 'onboarding',
        surfaceSlug: 'first_run',
      );

      expect(_captured.single['meteringKey'], token);
    });

    test(
        'a failing key store leaves the surface fetch working — the body '
        'simply carries no key', () async {
      // The key is resolved WHILE the request body is being built, so a storage
      // fault that escaped would break delivery, not just counting. Delivery
      // must be strictly independent of it.
      SurfaceMeteringKeyProvider.install(
        store: MeteringTokenStore(
          prefsProvider: () async => throw StateError('storage unavailable'),
        ),
      );
      final client = _clientCapturing(_bodies());

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(
        result,
        isNotNull,
        reason: 'the surface still resolves without a metering key',
      );
      expect(result!.envelopeBytes, isNotEmpty);
      expect(_captured.single.containsKey('meteringKey'), isFalse);
    });
  });
}

final _captured = <Map<String, dynamic>>[];

MockClient _bodies() {
  _captured.clear();
  return MockClient((req) async {
    _captured.add((jsonDecode(req.body) as Map).cast());
    return http.Response(
      jsonEncode({
        'envelope': base64Encode([1, 2])
      }),
      200,
    );
  });
}

RestageRpcClient _clientCapturing(MockClient mock) => RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: mock,
    );

Future<SharedPreferences> _prefsWith(String token) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restage.metering_token': token,
  });
  return SharedPreferences.getInstance();
}

const ReportTransactionRequest _request = ReportTransactionRequest(
  reportId: '550e8400-e29b-41d4-a716-446655440000',
  store: 'appStore',
  storeVerificationData: 'wrapped-jws',
  storeProductId: 'pro_monthly',
  storeTransactionId: 'tx-1',
);

const CreatePurchaseIntentRequest _intentRequest = CreatePurchaseIntentRequest(
  purchaseIntentId: '11111111-2222-4333-8444-555555555555',
  store: 'playStore',
  appAnonymousToken: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
  storeProductId: 'pro_monthly',
  basePlanId: 'monthly',
  offerId: 'winback',
  paywallId: 'upgrade',
  paywallVariantSlug: 'treatment',
  paywallPublishedVersion: 7,
  experimentId: 'experiment-1',
  experimentVariantId: 'arm-b',
  experimentEpoch: 2,
);

Map<String, Object?> _acceptedResponse({bool entitled = false}) {
  return <String, Object?>{
    'accepted': true,
    'reportId': _request.reportId,
    'evidence': <String, Object?>{
      'store': 'appStore',
      'submittedTransactionId': 'tx-1',
      'acceptedTransactionId': 'tx-1',
      'originalTransactionId': 'original-1',
    },
    'attributionDisposition': 'applied',
    'entitlements': <Object?>[
      if (entitled)
        <String, Object?>{
          'entitlementId': 'pro',
          'status': 'active',
          'productId': 'monthly',
          'source': 'storeNotification',
        },
    ],
  };
}
