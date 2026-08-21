import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  group('RestageRpcClient.fetchSurfaceScreen', () {
    test('posts the canonical request and returns the typed response',
        () async {
      late http.Request seen;
      final expected = _response(
        assignment: SurfaceExperimentAssignment(
          experimentId: 'exp_1',
          variantId: 'treatment',
          experimentEpoch: 3,
        ),
      );
      final bindingReference = _bindingReference('a');
      final request = _request(
        assignmentKey: 'actor',
        meteringKey: 'd9428888-122b-4b0b-8b7f-3e23441121e8',
      );
      final client = _client((http.Request request) async {
        seen = request;
        return http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(expected),
          200,
          headers: {
            'Restage-Measurement-Publication-Binding-V1':
                _bindingHeader(bindingReference),
          },
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
      final available = result as SurfaceScreenDeliveryAvailable;
      final response = available.response;
      expect(response.document.surfaceType, Surface.general);
      expect(response.document.surfaceSlug, 'feature_announcement');
      expect(response.contractVersion, 7);
      expect(response.publishedRevision, 12);
      expect(response.assignment!.variantId, 'treatment');
      expect(available.publicationBindingReference, bindingReference);
    });

    test(
      'missing, malformed, future, and coalesced binding headers do not invalidate a strict publication response',
      () async {
        final expected = _response();
        final valid = _bindingHeader(_bindingReference('b'));
        for (final header in <String?>[
          null,
          'not/base64url',
          '$valid=',
          '$valid,$valid',
          'a' * 4097,
          base64UrlEncode(const [0xff]).replaceAll('=', ''),
        ]) {
          final client = _client(
            (_) async => http.Response(
              SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
                expected,
              ),
              200,
              headers: {
                if (header != null)
                  'Restage-Measurement-Publication-Binding-V1': header,
              },
            ),
          );

          final result = await _fetch(client, _request());

          expect(result, isA<SurfaceScreenDeliveryAvailable>());
          final available = result as SurfaceScreenDeliveryAvailable;
          expect(
              available.response.document.surfaceSlug, 'feature_announcement');
          expect(available.response.publishedRevision, 12);
          expect(available.publicationBindingReference, isNull);
        }
      },
    );

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
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              _response()),
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
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
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
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
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
  SurfaceScreenDeliveryRequest request,
) =>
    client.fetchSurfaceScreen(request);

RestageRpcClient _client(
        Future<http.Response> Function(http.Request) handler) =>
    RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: _delivery.client(handler),
    );

SurfaceScreenDeliveryRequest _request({
  String? assignmentKey,
  String? meteringKey,
}) =>
    SurfaceScreenDeliveryRequest(
      surface: Surface.general,
      slug: 'feature_announcement',
      contractVersion: 7,
      assignmentKey: assignmentKey,
      meteringKey: meteringKey,
    );

SurfaceScreenDeliveryDescriptor _response({
  String slug = 'feature_announcement',
  int contractVersion = 7,
  SurfaceExperimentAssignment? assignment,
}) {
  final capabilities = CapabilityManifest(
    builtInFloor: 1,
    requiredLibraries: const <LibraryRequirement>[],
  );
  final eventContractHash = SurfaceScreenEventContractHash.hash(
    SurfaceScreenEventSchema(events: const <SurfaceScreenEvent>[]),
  );
  final contractFingerprint = SurfaceScreenContractFingerprint.hash(
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
  return _delivery.describeScreen(
    document: document,
    contractVersion: contractVersion,
    contractFingerprint: contractFingerprint,
    eventContractHash: eventContractHash,
    assignment: assignment,
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
      authorityId: MeasurementPublicationAuthorityId(
        'authority.screen.$seed',
      ),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}
