import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('RestageRpcClient.fetchSurfaceScreen', () {
    test('posts the canonical request and returns the typed response',
        () async {
      late http.Request seen;
      final expected = _response(
        assignment: SurfaceExperimentAssignmentV1(
          experimentId: 'exp_1',
          variantId: 'treatment',
          experimentEpoch: 3,
        ),
      );
      final request = _request(
        assignmentKey: 'actor',
        meteringKey: 'd9428888-122b-4b0b-8b7f-3e23441121e8',
      );
      final client = _client((http.Request request) async {
        seen = request;
        return http.Response(
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(expected),
          200,
        );
      });

      final result = await _fetch(client, request);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/surface');
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(
        seen.body,
        SurfaceScreenDeliveryRequestV1Codec.encodeCanonicalJson(request),
      );
      expect(result, isA<SurfaceScreenDeliveryAvailable>());
      final response = (result as SurfaceScreenDeliveryAvailable).response;
      expect(response.document.surfaceType, Surface.general);
      expect(response.document.surfaceSlug, 'feature_announcement');
      expect(response.contractVersion, 7);
      expect(response.publishedRevision, 12);
      expect(response.assignment!.variantId, 'treatment');
    });

    test('omits malformed advisory keys through the shared request codec',
        () async {
      late http.Request seen;
      final request = _request(
        assignmentKey: ' actor ',
        meteringKey: 'not-a-uuid',
      );
      final client = _client((http.Request request) async {
        seen = request;
        return http.Response(
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(_response()),
          200,
        );
      });

      await _fetch(client, request);

      expect(
        seen.body,
        '{"schemaVersion":1,"surface":"general","slug":"feature_announcement","contractVersion":7}',
      );
    });

    test('treats the no-content and not-found outcomes as ordinary absence',
        () async {
      for (final statusCode in <int>[204, 404]) {
        final client = _client(
          (_) async => http.Response('', statusCode),
        );

        final result = await _fetch(client, _request());

        expect(
          result,
          isA<SurfaceScreenDeliveryAbsent>(),
          reason: 'status $statusCode',
        );
      }
    });

    test('treats only retryable availability statuses as transport unavailable',
        () async {
      for (final statusCode in <int>[408, 429, 500, 502, 503, 504]) {
        final client = _client(
          (_) async => http.Response('temporarily unavailable', statusCode),
        );

        final result = await _fetch(client, _request());

        expect(
          result,
          isA<SurfaceScreenDeliveryTransportUnavailable>(),
          reason: 'status $statusCode',
        );
      }
    });

    test('treats I/O and timeout failure as transport unavailable', () async {
      for (final failure in <Object>[
        http.ClientException('offline'),
        TimeoutException('delivery timed out'),
      ]) {
        final client = _client((_) async => throw failure);

        final result = await _fetch(client, _request());

        expect(result, isA<SurfaceScreenDeliveryTransportUnavailable>());
      }
    });

    test('fails closed on an unexpected local delivery failure', () async {
      final client = _client((_) async => throw StateError('bad client'));

      final result = await _fetch(client, _request());

      expect(
        result,
        isA<SurfaceScreenDeliveryInvalidResponse>().having(
          (response) => response.reason,
          'reason',
          SurfaceScreenDeliveryInvalidResponseReason.requestRejected,
        ),
      );
    });

    test('rejects deterministic HTTP failures as invalid hosted responses',
        () async {
      for (final statusCode in <int>[400, 401, 403, 409, 413, 422, 501]) {
        final client = _client(
          (_) async => http.Response('delivery rejected', statusCode),
        );

        final result = await _fetch(client, _request());

        expect(
          result,
          isA<SurfaceScreenDeliveryInvalidResponse>().having(
            (response) => response.reason,
            'reason',
            SurfaceScreenDeliveryInvalidResponseReason.requestRejected,
          ),
          reason: 'status $statusCode',
        );
      }
    });

    test('rejects a malformed present response without treating it as absent',
        () async {
      final client = _client((_) async => http.Response('{}', 200));

      final result = await _fetch(client, _request());

      expect(
        result,
        isA<SurfaceScreenDeliveryInvalidResponse>(),
      );
      expect(
        (result as SurfaceScreenDeliveryInvalidResponse).reason,
        SurfaceScreenDeliveryInvalidResponseReason.malformed,
      );
    });

    test('rejects a present response for a different identity', () async {
      final client = _client(
        (_) async => http.Response(
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(
            _response(slug: 'another_screen'),
          ),
          200,
        ),
      );

      final result = await _fetch(client, _request());

      expect(
        result,
        isA<SurfaceScreenDeliveryInvalidResponse>(),
      );
      expect(
        (result as SurfaceScreenDeliveryInvalidResponse).reason,
        SurfaceScreenDeliveryInvalidResponseReason.identityMismatch,
      );
    });

    test('rejects a present response for a different contract version',
        () async {
      final client = _client(
        (_) async => http.Response(
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(
            _response(contractVersion: 8),
          ),
          200,
        ),
      );

      final result = await _fetch(client, _request());

      expect(
        result,
        isA<SurfaceScreenDeliveryInvalidResponse>(),
      );
      expect(
        (result as SurfaceScreenDeliveryInvalidResponse).reason,
        SurfaceScreenDeliveryInvalidResponseReason.contractMismatch,
      );
    });
  });
}

Future<SurfaceScreenDeliveryResult> _fetch(
  RestageRpcClient client,
  SurfaceScreenDeliveryRequestV1 request,
) =>
    client.fetchSurfaceScreen(request);

RestageRpcClient _client(
        Future<http.Response> Function(http.Request) handler) =>
    RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient(handler),
    );

SurfaceScreenDeliveryRequestV1 _request({
  String? assignmentKey,
  String? meteringKey,
}) =>
    SurfaceScreenDeliveryRequestV1(
      surface: Surface.general,
      slug: 'feature_announcement',
      contractVersion: 7,
      assignmentKey: assignmentKey,
      meteringKey: meteringKey,
    );

SurfaceScreenDeliveryResponseV1 _response({
  String slug = 'feature_announcement',
  int contractVersion = 7,
  SurfaceExperimentAssignmentV1? assignment,
}) {
  final capabilities = CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const <LibraryRequirement>[],
  );
  final eventContractHash = SurfaceScreenEventContractHashV1.hash(
    SurfaceScreenEventSchemaV1(events: const <SurfaceScreenEventV1>[]),
  );
  final contractFingerprint = SurfaceScreenContractFingerprintV1.hash(
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    capabilities: capabilities,
    eventContractHash: eventContractHash,
  );
  final payload = BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(const <int>[1, 2, 3]),
  );
  final document = SurfaceDocument(
    surfaceType: Surface.general,
    surfaceSlug: slug,
    version: 12,
    minClient: payload.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026, 8, 11),
  );
  return SurfaceScreenDeliveryResponseV1(
    document: document,
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    contractVersion: contractVersion,
    publishedRevision: document.version,
    contractFingerprint: contractFingerprint,
    eventContractHash: eventContractHash,
    assignment: assignment,
  );
}
