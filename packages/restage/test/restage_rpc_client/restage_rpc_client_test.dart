import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/billing/purchase_token_digest.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';

import '../support/hosted_artifact_delivery.dart';

/// The delivery this file's stub server speaks for. It both describes surfaces
/// and answers for their content, so no test here can accidentally stub half a
/// wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

/// A description of a one-screen surface carrying [blob], with its content
/// held ready to serve.
Map<String, Object?> _blobDelivery(List<int> blob) =>
    _delivery.describe(testBlobDocument(blob));

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

  group('RestageRpcClient.ingestMeasurement', () {
    test('POSTs the exact target-free request with Bearer auth', () async {
      const canonicalRequestBase64 = 'cGF5bG9hZA';
      const receiptCanonicalBase64 = 'cGF5bG9hZC1yZWNlaXB0';
      late http.Request seen;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({'receiptCanonicalBase64': receiptCanonicalBase64}),
            200,
          );
        }),
      );

      final outcome = await client.ingestMeasurement(canonicalRequestBase64);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/measurement');
      expect(seen.url.query, isEmpty);
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(
        seen.body,
        '{"canonicalRequestBase64":"$canonicalRequestBase64"}',
      );
      expect(
        outcome,
        isA<MeasurementIngestRpcAccepted>().having(
          (value) => value.receiptCanonicalBase64,
          'receiptCanonicalBase64',
          receiptCanonicalBase64,
        ),
      );
    });

    test('requires an exact response object and canonical receipt carrier',
        () async {
      const validReceipt = 'cGF5bG9hZC1yZWNlaXB0';
      final responseBodies = <String>[
        '{}',
        '{"receiptCanonicalBase64":7}',
        '{"receiptCanonicalBase64":""}',
        '{"receiptCanonicalBase64":"not a carrier"}',
        '{"receiptCanonicalBase64":"$validReceipt="}',
        '{"receiptCanonicalBase64":"$validReceipt","future":true}',
        'not-json',
        '["$validReceipt"]',
      ];

      for (final body in responseBodies) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient(
            (_) async => http.Response(body, 200),
          ),
        );

        final outcome = await client.ingestMeasurement('cGF5bG9hZA');

        expect(
          outcome,
          isA<MeasurementIngestRpcUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementIngestRpcUnavailableReason.malformedResponse,
          ),
          reason: body,
        );
      }
    });

    test('preserves every named HTTP outcome distinction', () async {
      final cases = <int, Type>{
        400: MeasurementIngestRpcRejected,
        413: MeasurementIngestRpcRejected,
        401: MeasurementIngestRpcUnauthenticated,
        409: MeasurementIngestRpcConflict,
      };

      for (final entry in cases.entries) {
        final client = _measurementClientWithResponse(
          http.Response('', entry.key),
        );

        final outcome = await client.ingestMeasurement('cGF5bG9hZA');

        expect(outcome.runtimeType, entry.value, reason: 'status ${entry.key}');
      }

      final forbidden = await _measurementClientWithResponse(
        http.Response('', 403),
      ).ingestMeasurement('cGF5bG9hZA');
      expect(
        forbidden,
        isA<MeasurementIngestRpcUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementIngestRpcUnavailableReason.forbidden,
        ),
      );

      final serviceUnavailable = await _measurementClientWithResponse(
        http.Response('', 503),
      ).ingestMeasurement('cGF5bG9hZA');
      expect(
        serviceUnavailable,
        isA<MeasurementIngestRpcUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementIngestRpcUnavailableReason.serviceUnavailable,
        ),
      );

      for (final status in <int>[204, 418, 500, 502]) {
        final outcome = await _measurementClientWithResponse(
          http.Response('', status),
        ).ingestMeasurement('cGF5bG9hZA');
        expect(
          outcome,
          isA<MeasurementIngestRpcUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementIngestRpcUnavailableReason.unexpectedStatus,
          ),
          reason: 'status $status',
        );
      }
    });

    test('maps timeout and I/O exceptions to transport unavailable', () async {
      final timeoutClient = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => throw TimeoutException('request timed out'),
        ),
      );
      final ioClient = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient(
          (_) async => throw http.ClientException('socket failed'),
        ),
      );

      for (final outcome in <MeasurementIngestRpcOutcome>[
        await timeoutClient.ingestMeasurement('cGF5bG9hZA'),
        await ioClient.ingestMeasurement('cGF5bG9hZA'),
      ]) {
        expect(
          outcome,
          isA<MeasurementIngestRpcUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementIngestRpcUnavailableReason.transportFailure,
          ),
        );
      }
    });

    test('diagnostics do not echo credentials or carriers', () async {
      final messages = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = originalDebugPrint);
      const apiKey = 'rs_pk_secret';
      const requestCarrier = 'c2Vuc2l0aXZlLXJlcXVlc3Q';

      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: apiKey,
        httpClient: MockClient((_) async => http.Response('', 503)),
      );

      await client.ingestMeasurement(requestCarrier);

      final diagnostics = messages.whereType<String>().join('\n');
      expect(diagnostics, isNot(contains(apiKey)));
      expect(diagnostics, isNot(contains(requestCarrier)));
    });
  });

  group('RestageRpcClient.createPurchaseIntent', () {
    test('POSTs the immutable tuple and returns the correlated commit',
        () async {
      late http.Request seen;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: _delivery.client((request) async {
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
        httpClient: _delivery.client(
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
        httpClient: _delivery.client((_) async {
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
        httpClient: _delivery.client((request) async {
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
        httpClient: _delivery.client((_) async {
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
        httpClient: _delivery.client((_) async {
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
      final mock = _delivery.client((req) async {
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
      final mock = _delivery.client((req) async {
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
      final mock = _delivery.client((req) async {
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
          httpClient: _delivery.client(
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
        httpClient: _delivery.client(
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
        httpClient: _delivery.client(
          (req) async => http.Response(jsonEncode(body), 200),
        ),
      );

      expect(await client.reportTransaction(_request), isNull);
    });

    test('Google promotion acceptance requires the exact token digest',
        () async {
      for (final acceptedToken in <String>[
        _googleRequest.storeVerificationData,
        'different-purchase-token',
      ]) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: _delivery.client(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'accepted': true,
                'reportId': _googleRequest.reportId,
                'evidence': <String, Object?>{
                  'store': 'playStore',
                  'acceptedPurchaseTokenDigest':
                      googlePurchaseTokenDigest(acceptedToken),
                },
                'attributionDisposition': 'notProvided',
                'entitlements': <Object?>[],
              }),
              200,
            ),
          ),
        );

        final response = await client.reportTransaction(_googleRequest);

        expect(
          response,
          acceptedToken == _googleRequest.storeVerificationData
              ? isNotNull
              : isNull,
          reason: 'accepted token: $acceptedToken',
        );
      }
    });

    test('returns null on 4xx (distinguishing transport failure from empty)',
        () async {
      final mock = _delivery.client((req) async => http.Response('', 401));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null on 5xx', () async {
      final mock = _delivery.client((req) async => http.Response('', 503));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

      final summaries = await client.reportTransaction(_request);

      expect(summaries, isNull);
    });

    test('returns null when the transport throws', () async {
      final mock = _delivery.client(
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
        httpClient: _delivery.client(
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
      final mock = _delivery.client(
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
      final mock = _delivery.client(
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
      final mock = _delivery.client(
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
      final mock = _delivery.client((req) async {
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
      final mock = _delivery.client((req) async => http.Response('', 503));
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
      final mock = _delivery.client((req) async => http.Response(
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
      'flow contract identity and retry bytes use the exact independent wire',
      () async {
        final requests = <http.Request>[];
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: _delivery.client((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                requests.length == 1
                    ? {
                        ..._blobDelivery([1, 2, 3]),
                        'contractRequired': true,
                        'flowContractRequired': false,
                      }
                    : {
                        ..._blobDelivery([1, 2, 3]),
                        'contractRequired': false,
                        'flowContractRequired': true,
                      },
              ),
              200,
            );
          }),
        );
        const hash = 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef'
            '0123456789abcdef';
        final callerOwnedBytes = <int>[251, 255];
        final retryRequest = FlowContractFetchRequest.retry(
          hash,
          callerOwnedBytes,
        );
        callerOwnedBytes
          ..[0] = 0
          ..add(1);
        expect(retryRequest.canonicalBytes, [251, 255]);
        expect(
          () => retryRequest.canonicalBytes![0] = 0,
          throwsUnsupportedError,
        );

        final hashOnly = await client.fetchSurface(
          surfaceType: 'onboarding',
          surfaceSlug: 'first_run',
          flowContract: const FlowContractFetchRequest.hashOnly(hash),
        );
        final retry = await client.fetchSurface(
          surfaceType: 'onboarding',
          surfaceSlug: 'first_run',
          flowContract: retryRequest,
        );

        expect(jsonDecode(requests[0].body), {
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first_run',
          'flowContractKind': 'flow',
          'flowContractVersion': 1,
          'flowContractHash': hash,
        });
        expect(jsonDecode(requests[1].body), {
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first_run',
          'flowContractKind': 'flow',
          'flowContractVersion': 1,
          'flowContractHash': hash,
          'flowContractBytes': '-_8',
        });
        expect(hashOnly!.contractRequired, isTrue);
        expect(hashOnly.flowContractRequired, isFalse);
        expect(retry!.contractRequired, isFalse);
        expect(retry.flowContractRequired, isTrue);
      },
    );

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
            httpClient: _delivery.client((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode({
                  ..._blobDelivery([requests.length]),
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
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
      expect(result.experimentId, 'exp_paywall_copy');
      expect(result.variantId, 'variant_a');
      expect(result.experimentEpoch, 3);
    });

    test('retains the exact binding header beside a generic artifact payload',
        () async {
      final reference = _bindingReference('a');
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: _delivery.client(
          (_) async => http.Response(
            jsonEncode({
              ..._blobDelivery([1, 2, 3]),
              'experimentId': 'exp_paywall_copy',
              'variantId': 'variant_a',
              'experimentEpoch': 3,
            }),
            200,
            headers: {
              // HTTP field names are case-insensitive.
              'restage-measurement-publication-binding-v1':
                  _bindingHeader(reference),
            },
          ),
        ),
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
      expect(result.experimentId, 'exp_paywall_copy');
      expect(result.variantId, 'variant_a');
      expect(result.experimentEpoch, 3);
      expect(result.publicationBindingReference, reference);
    });

    test(
      'missing, malformed, future, and coalesced binding headers leave generic artifact delivery intact',
      () async {
        final valid = _bindingHeader(_bindingReference('b'));
        for (final header in <String?>[
          null,
          'not/base64url',
          '$valid=',
          '$valid,$valid',
          'a' * 4097,
          base64UrlEncode(const [0xff]).replaceAll('=', ''),
        ]) {
          final client = RestageRpcClient(
            baseUrl: 'https://example.com',
            apiKey: 'rs_pk_test',
            httpClient: _delivery.client(
              (_) async => http.Response(
                jsonEncode({
                  ..._blobDelivery([1, 2, 3]),
                  'experimentId': 'exp_paywall_copy',
                  'variantId': 'variant_a',
                  'experimentEpoch': 3,
                }),
                200,
                headers: {
                  if (header != null)
                    'Restage-Measurement-Publication-Binding-V1': header,
                },
              ),
            ),
          );

          final result = await client.fetchSurface(
            surfaceType: 'paywall',
            surfaceSlug: 'pro_upgrade',
          );

          expect(result, isNotNull, reason: 'header: $header');
          expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
          expect(result.experimentId, 'exp_paywall_copy');
          expect(result.variantId, 'variant_a');
          expect(result.experimentEpoch, 3);
          expect(result.publicationBindingReference, isNull);
        }
      },
    );

    test(
        'case-only duplicate binding headers leave generic artifact delivery intact',
        () async {
      final header = _bindingHeader(_bindingReference('d'));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: _delivery.client(
          (_) async => http.Response(
            jsonEncode({
              ..._blobDelivery([1, 2, 3]),
            }),
            200,
            headers: {
              'Restage-Measurement-Publication-Binding-V1': header,
              'restage-measurement-publication-binding-v1': header,
            },
          ),
        ),
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(result, isNotNull);
      expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
      expect(result.publicationBindingReference, isNull);
    });

    test('parses the serve decision when present', () async {
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      expect(assembledBlob(result.artifact), orderedEquals([1, 2, 3]));
    });

    test(
        'degrades gracefully on an UNRECOGNISED decision string: it is '
        'carried as an opaque value and never throws (forward-compat with a '
        'newer server)', () async {
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
      expect(result.decision, 'someFutureDecisionValue');
    });

    test('ignores a non-string decision without failing the fetch', () async {
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      expect(assembledBlob(result.artifact), orderedEquals([1, 2, 3]));
    });

    test('treats null assignment metadata as no assignment metadata', () async {
      final mock = _delivery.client((req) async {
        return http.Response(
          jsonEncode({
            ..._blobDelivery([1, 2, 3]),
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
      expect(assembledBlob(result!.artifact), orderedEquals([1, 2, 3]));
      expect(result.experimentId, isNull);
      expect(result.variantId, isNull);
      expect(result.experimentEpoch, isNull);
    });

    test('fails closed on malformed assignment metadata', () async {
      final cases = <Map<String, Object?>>[
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp'
        },
        {
          ..._blobDelivery([1]),
          'variantId': 'variant_a'
        },
        {
          ..._blobDelivery([1]),
          'experimentId': '',
          'variantId': 'variant_a',
          'experimentEpoch': 3,
        },
        {
          ..._blobDelivery([1]),
          'experimentId': ' exp ',
          'variantId': 'variant_a',
          'experimentEpoch': 3,
        },
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp',
          'variantId': 'variant\u0000a',
          'experimentEpoch': 3,
        },
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp',
          'variantId': 1,
          'experimentEpoch': 3,
        },
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
        },
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
          'experimentEpoch': 0,
        },
        {
          ..._blobDelivery([1]),
          'experimentId': 'exp',
          'variantId': 'variant_a',
          'experimentEpoch': '3',
        },
      ];

      for (final body in cases) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: _delivery.client(
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
      final mock = _delivery.client((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              ..._blobDelivery([1, 2]),
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
      final mock = _delivery.client((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              ..._blobDelivery([1, 2]),
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
      final mock = _delivery.client((req) async {
        seenBodies.add((jsonDecode(req.body) as Map).cast());
        return http.Response(
            jsonEncode({
              ..._blobDelivery([1, 2]),
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

  group('RestageRpcClient artifact holding', () {
    test('a second resolve of the same artifact does not fetch it again',
        () async {
      // An artifact is content-addressed: naming the same one twice names bytes
      // this client already has and already verified.
      final stub = _deliveringClient(testBlobDocument(const [7, 7, 7]));
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: stub.client,
      );

      final first = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );
      final second = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(assembledBlob(first!.artifact), orderedEquals(const [7, 7, 7]));
      expect(assembledBlob(second!.artifact), orderedEquals(const [7, 7, 7]));
      expect(stub.posts, hasLength(2), reason: 'both resolves still happen');
      expect(
        stub.delivery.artifactRequests,
        hasLength(1),
        reason: 'the content is fetched once',
      );
      // The pass goes with the fetch. Nothing else in the suite would notice if
      // it stopped: every real store answers 403 without it, and none of them
      // are here.
      expect(
        stub.delivery.artifactRequests.single
            .headers[surfaceArtifactPassHeader],
        testArtifactPass,
      );
      expect(
        stub.delivery.artifactRequests.single.followRedirects,
        isFalse,
        reason: 'a redirect would re-send the pass to whatever host it named',
      );
    });

    test('holding is bounded by size, not by how many artifacts there are',
        () async {
      // Eight entries sounds small and is eighty megabytes at the publish
      // ceiling. Two artifacts, each over half the bound, cannot both be held —
      // and the older one is what goes.
      final delivery = HostedArtifactFixture();
      final big = List<int>.filled(5 * 1024 * 1024, 7);
      final other = List<int>.filled(5 * 1024 * 1024, 9);
      final bodies = <Map<String, Object?>>[
        delivery.describe(testBlobDocument(big)),
        delivery.describe(testBlobDocument(other)),
        delivery.describe(testBlobDocument(big)),
      ];
      var next = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: delivery.client(
          (_) async => http.Response(jsonEncode(bodies[next++]), 200),
        ),
      );

      for (var i = 0; i != bodies.length; i += 1) {
        await client.fetchSurface(
          surfaceType: 'paywall',
          surfaceSlug: 'pro_upgrade',
        );
      }

      expect(
        delivery.artifactRequests,
        hasLength(3),
        reason: 'the first artifact was evicted to make room for the second, '
            'so re-resolving it fetches again',
      );
    });

    test(
        'the same bytes under a different payload format are not the same '
        'artifact', () async {
      // The hash alone would make these one entry, and the first fetched would
      // answer for the other — a different frame shape read by a different
      // decoder, from a different place. Harmless with one format; silently
      // wrong with two.
      final delivery = HostedArtifactFixture();
      final document = testBlobDocument(const [7, 7, 7]);
      final bodies = <Map<String, Object?>>[
        delivery.describe(document),
        delivery.describeRaw(
          surfaceType: document.surfaceType,
          surfaceSlug: document.surfaceSlug,
          version: document.version,
          publishedAt: document.publishedAt,
          content: document.payload.canonicalBytes,
          payloadFormatVersion: kSurfaceArtifactPayloadFormatVersion + 1,
        ),
      ];
      var next = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: delivery.client(
          (_) async => http.Response(jsonEncode(bodies[next++]), 200),
        ),
      );

      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );
      final second = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      // The second delivery names a format this build cannot read. The version
      // gate lives in the description's own codec, so it is refused before the
      // seam is reached and before a byte is fetched — which is also the proof
      // that the entry held from the first resolve was not silently reused for
      // an artifact that merely shares its hash.
      expect(second, isNull);
      expect(
        delivery.artifactRequests,
        hasLength(1),
        reason: 'the unreadable delivery costs no request',
      );
    });

    test('content that failed its checks is not held', () async {
      // Holding it would hand the next resolve a refusal it had already earned,
      // without the fetch that might now succeed.
      final delivery = HostedArtifactFixture();
      final document = testBlobDocument(const [7, 7, 7]);
      final body = delivery.describe(document);
      delivery.substituteContent(
        (body['artifact']! as Map<String, Object?>)['artifactUrl']! as String,
        const <int>[0, 0, 0],
      );
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: delivery.client(
          (_) async => http.Response(jsonEncode(body), 200),
        ),
      );

      final first = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );
      final second = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(first!.artifact, isA<SurfaceArtifactUnavailable>());
      expect(second!.artifact, isA<SurfaceArtifactUnavailable>());
      expect(delivery.artifactRequests, hasLength(2));
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
      expect(assembledBlob(result!.artifact), isNotEmpty);
      expect(_captured.single.containsKey('meteringKey'), isFalse);
    });
  });
}

final _captured = <Map<String, dynamic>>[];

MockClient _bodies() {
  _captured.clear();
  return _delivery.client((req) async {
    _captured.add((jsonDecode(req.body) as Map).cast());
    return http.Response(
      jsonEncode({
        ..._blobDelivery([1, 2]),
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

RestageRpcClient _measurementClientWithResponse(http.Response response) =>
    RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) async => response),
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

const ReportTransactionRequest _googleRequest = ReportTransactionRequest(
  reportId: '550e8400-e29b-41d4-a716-446655440001',
  store: 'playStore',
  storeVerificationData: 'promotional-purchase-token',
  storeProductId: 'pro_monthly',
  storeTransactionId: null,
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

/// A delivery of [document] with its content held ready, on its own fixture so
/// the held-content assertions are not disturbed by the file-wide one.
({MockClient client, HostedArtifactFixture delivery, List<http.Request> posts})
    _deliveringClient(SurfaceDocument document) {
  final delivery = HostedArtifactFixture();
  final posts = <http.Request>[];
  final body = delivery.describe(document);
  return (
    client: delivery.client((request) async {
      posts.add(request);
      return http.Response(jsonEncode(body), 200);
    }),
    delivery: delivery,
    posts: posts,
  );
}

String _bindingHeader(MeasurementPublicationBindingReferenceV1 reference) =>
    base64UrlEncode(reference.canonicalBytes).replaceAll('=', '');

MeasurementPublicationBindingReferenceV1 _bindingReference(String seed) {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest(seed * 64),
    selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId('authority.rpc.$seed'),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}
