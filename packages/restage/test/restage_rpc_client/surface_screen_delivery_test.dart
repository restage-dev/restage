import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/surface_delivery_evidence.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hosted_artifact_delivery.dart';

final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  group('RestageRpcClient.fetchSurfaceScreen', () {
    test('folds registration beside a strict screen descriptor', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SurfaceAssignmentCredentialStore(
        namespace: 'screen-fold',
        actor: () async => 'actor',
        identityGeneration: () => 0,
        onRetentionRollover: () {},
      );
      SurfaceAssignmentKeyProvider.install(
        key: store.resolve,
        identityGeneration: () => store.generation,
        registration: store.capture,
        confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
            store.confirm(
          attempt: attempt,
          localRequestStartMicros: start,
          credentialHandle: handle,
          expiresAtMicros: expiry,
          serverNowMicros: serverNow,
        ),
        refuseRegistration: store.refuse,
      );
      addTearDown(SurfaceAssignmentKeyProvider.clear);
      final lease = await SurfaceAssignmentKeyProvider.captureLease();
      late Map<String, dynamic> sent;
      final serverNow = DateTime.now().microsecondsSinceEpoch;
      final response = jsonDecode(
        SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(_response()),
      ) as Map<String, dynamic>;
      response.addAll({
        'credentialHandle': 'ic1.${'a' * 64}',
        'expiresAtMicros': serverNow + 30 * Duration.microsecondsPerDay,
        'serverNowMicros': serverNow,
        'assignment': CanonicalSurfaceExperimentAssignmentV1(
          experimentId: ExperimentPublicIdV1('experiment.test'),
          experimentRevisionId: ExperimentPublicRevisionIdV1('revision.test'),
          experimentEpochId: ExperimentPublicEpochIdV1('epoch.test'),
          armId: ExperimentPublicArmIdV1('arm.test'),
          outcomeLinkCarrier: 'Y2Fycmllcg',
        ).toJson(),
      });
      final client = _client((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(response), 200);
      });

      final result = await client.fetchSurfaceScreen(
        _request(),
        registrationLease: lease,
      );

      expect(result, isA<SurfaceScreenDeliveryAvailable>());
      final assigned = result as SurfaceScreenDeliveryAvailable;
      final resolved = attachMeasurementPublicationBindingReference(
        Object(),
        null,
        canonicalExperimentAssignment: assigned.canonicalExperimentAssignment,
      );
      expect(measurementRegistrationFingerprintFor(resolved),
          lease.registration!.fingerprint);
      expect(sent['registrationNonce'], lease.registration!.registrationNonce);
      expect(sent['registrationCreatedAtMicros'],
          lease.registration!.registrationCreatedAtMicros);
      expect((await store.capture())!.credentialHandle, 'ic1.${'a' * 64}');
    });

    test('reports a malformed 429 and preserves transport unavailability',
        () async {
      _delivery.artifactRequests.clear();
      final evidence = <({
        Surface surfaceType,
        String surfaceSlug,
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
            surfaceType: surfaceType,
            surfaceSlug: surfaceSlug,
            retryAfter: retryAfter,
          ));
        },
      );
      addTearDown(SurfaceDeliveryEvidence.clear);
      final client = _client(
        (_) async => http.Response(
          'not json',
          429,
          headers: {'Retry-After': '9'},
        ),
      );

      final result = await _fetch(client, _request());

      expect(result, isA<SurfaceScreenDeliveryTransportUnavailable>());
      expect(evidence, hasLength(1));
      expect(evidence.single.surfaceType, Surface.general);
      expect(evidence.single.surfaceSlug, 'feature_announcement');
      expect(evidence.single.retryAfter, const Duration(seconds: 9));
      expect(_delivery.artifactRequests, isEmpty);
    });

    test('posts the canonical request and returns the typed response',
        () async {
      late http.Request seen;
      final expected = _response();
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
      expect(available.publicationBindingReference, bindingReference);
    });

    test('forwards canonical carriers on the strict request', () async {
      final builtIns =
          base64UrlEncode(utf8.encode('screen-built-ins')).replaceAll('=', '');
      final heldAssignment =
          base64UrlEncode(utf8.encode('screen-assignment')).replaceAll('=', '');
      late Map<String, Object?> body;
      final client = _client((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
            _response(),
          ),
          200,
        );
      });

      await _fetch(
          client,
          _request(
            sdkBuiltInsCanonicalBase64: builtIns,
            assignmentCanonicalBase64: heldAssignment,
          ));

      expect(body['sdkBuiltInsCanonicalBase64'], builtIns);
      expect(body['assignmentCanonicalBase64'], heldAssignment);
    });

    test('returns the exact canonical served assignment', () async {
      final assignment = _assignment();
      final client = _client(
        (_) async => http.Response(
          jsonEncode({
            ..._response().toJson(),
            'assignment': assignment.toJson(),
          }),
          200,
        ),
      );

      final result = await _fetch(client, _request());

      final available = result as SurfaceScreenDeliveryAvailable;
      expect(available.canonicalExperimentAssignment, assignment);
      expect(available.assignmentDiagnostic, isNull);
    });

    test('returns the closed assignment diagnostic without an assignment',
        () async {
      final client = _client(
        (_) async => http.Response(
          jsonEncode({
            ..._response().toJson(),
            'assignment': {'result': 'assignmentNotPresented'},
          }),
          200,
        ),
      );

      final result = await _fetch(client, _request());

      final available = result as SurfaceScreenDeliveryAvailable;
      expect(available.canonicalExperimentAssignment, isNull);
      expect(
        available.assignmentDiagnostic,
        SurfaceAssignmentDiagnostic.assignmentNotPresented,
      );
    });

    test('rejects a malformed assignment before fetching its artifact',
        () async {
      final before = _delivery.artifactRequests.length;
      final client = _client(
        (_) async => http.Response(
          jsonEncode({
            ..._response().toJson(),
            'assignment': {
              ..._assignment().toJson(),
              'armId': 7,
            },
          }),
          200,
        ),
      );

      final result = await _fetch(client, _request());

      expect(
        result,
        isA<SurfaceScreenDeliveryInvalidResponse>().having(
          (response) => response.reason,
          'reason',
          SurfaceScreenDeliveryInvalidResponseReason.malformed,
        ),
      );
      expect(_delivery.artifactRequests, hasLength(before));
    });

    test(
        'rejects malformed and mixed assignment diagnostics before fetching an artifact',
        () async {
      for (final assignment in <Map<String, Object?>>[
        <String, Object?>{
          'result': 'assignmentNotPresented',
          'armId': 7,
        },
        <String, Object?>{
          ..._assignment().toJson(),
          'result': 'assignmentNotPresented',
        },
      ]) {
        final before = _delivery.artifactRequests.length;
        final client = _client(
          (_) async => http.Response(
            jsonEncode({
              ..._response().toJson(),
              'assignment': assignment,
            }),
            200,
          ),
        );

        final result = await _fetch(client, _request());

        expect(
          result,
          isA<SurfaceScreenDeliveryInvalidResponse>().having(
            (response) => response.reason,
            'reason',
            SurfaceScreenDeliveryInvalidResponseReason.malformed,
          ),
          reason: '$assignment',
        );
        expect(
          _delivery.artifactRequests,
          hasLength(before),
          reason: '$assignment',
        );
      }
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

    test('classifies a host data contract change as a contract mismatch',
        () async {
      final hostDataHash = SurfaceScreenHostDataContractHash.hash(
        SurfaceScreenHostDataSchema(
          const <String, SurfaceScreenHostDataShape>{
            'habits': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataScalarShapeV1(
                SurfaceScreenHostDataScalarKind.string,
              ),
            ),
          },
        ),
      );
      final served = _response(hostDataContractHash: hostDataHash);
      final client = _client(
        (_) async => http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(served),
          200,
        ),
      );

      // A build compiled before this screen required host data.
      final result = await _fetch(client, _request());

      expect(
        (result as SurfaceScreenDeliveryInvalidResponse).reason,
        SurfaceScreenDeliveryInvalidResponseReason.contractMismatch,
      );
    });

    test('accepts a build declaring the same host data contract', () async {
      final hostDataHash = SurfaceScreenHostDataContractHash.hash(
        SurfaceScreenHostDataSchema(
          const <String, SurfaceScreenHostDataShape>{
            'habits': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataScalarShapeV1(
                SurfaceScreenHostDataScalarKind.string,
              ),
            ),
          },
        ),
      );
      final served = _response(hostDataContractHash: hostDataHash);
      final client = _client(
        (_) async => http.Response(
          SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(served),
          200,
        ),
      );

      final result = await _fetch(
        client,
        _request(),
        readerHostDataContractHash: hostDataHash,
      );

      expect(result, isA<SurfaceScreenDeliveryAvailable>());
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
  SurfaceScreenDeliveryRequest request, {
  String? readerHostDataContractHash,
}) =>
    client.fetchSurfaceScreen(
      request,
      readerHostDataContractHash: readerHostDataContractHash,
    );

RestageRpcClient _client(
        Future<http.Response> Function(http.Request) handler) =>
    RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: _delivery.client(handler),
    );

SurfaceScreenDeliveryRequest _request({
  String? sdkBuiltInsCanonicalBase64,
  String? assignmentCanonicalBase64,
  String? assignmentKey,
  String? meteringKey,
}) =>
    SurfaceScreenDeliveryRequest(
      sdkBuiltInsCanonicalBase64: sdkBuiltInsCanonicalBase64,
      assignmentCanonicalBase64: assignmentCanonicalBase64,
      surface: Surface.general,
      slug: 'feature_announcement',
      contractVersion: 7,
      assignmentKey: assignmentKey,
      meteringKey: meteringKey,
    );

SurfaceScreenDeliveryDescriptor _response({
  String slug = 'feature_announcement',
  int contractVersion = 7,
  String? hostDataContractHash,
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
    hostDataContractHash: hostDataContractHash,
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
  );
}

CanonicalSurfaceExperimentAssignmentV1 _assignment() =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.screen'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.screen.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.screen.1'),
      armId: ExperimentPublicArmIdV1('arm.screen'),
      outcomeLinkCarrier:
          base64UrlEncode(utf8.encode('outcome.screen')).replaceAll('=', ''),
    );

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
