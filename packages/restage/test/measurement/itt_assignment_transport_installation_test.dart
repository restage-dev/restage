import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_assignment_diagnostics.dart';
import 'package:restage/src/measurement/measurement_assignment_transport.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/restage_runtime_test_support.dart';

void main() {
  installRestageRuntimeTestSupport();

  group('ITT assignment transport installation', () {
    test(
      'installs an adapter for a configured authenticated RPC client',
      () async {
        Restage.configure(
          apiKey: 'rs_pk_itt_install',
          baseUrl: 'https://itt-install.example.com',
        );

        expect(Restage.debugRestageRpcClient, isNotNull);

        final diagnostic =
            (await _transport().deliver(_invalidRequest())).diagnostic;

        expect(
          diagnostic,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.malformedResponse,
          ),
        );
      },
    );

    test(
      'delegates exact ITT carrier bytes through the installed RPC adapter',
      () async {
        final assignmentRequests = <http.Request>[];
        final client = RestageRpcClient(
          baseUrl: 'https://itt-replacement.example.com',
          apiKey: 'rs_pk_itt_replacement',
          httpClient: MockClient((request) async {
            if (request.url.path == '/sdk/v1/measurement-assignment') {
              assignmentRequests.add(request);
              return http.Response(
                '{"result":"assigned","candidateDelivery":"rendered","assignment":{"schemaVersion":1,"experimentId":"experiment.checkout","experimentRevisionId":"revision.checkout.1","experimentEpochId":"epoch.checkout.1","armId":"arm.treatment","outcomeLinkCarrier":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}',
                200,
              );
            }
            return http.Response('', 404);
          }),
        );
        const request = IttAssignmentRpcRequest(
          acceptedReceiptCanonicalBase64: 'AQ',
          credentialHandle: 'handle.itt.0001',
          sdkBuiltInsCanonicalBase64: 'Ag',
          assignmentContextCanonicalBase64: 'Aw',
        );

        Restage.configure(
          apiKey: 'rs_pk_itt_initial',
          baseUrl: 'https://itt-initial.example.com',
        );
        Restage.debugRestageRpcClient = client;

        final diagnostic = (await _transport().deliver(request)).diagnostic;

        expect(assignmentRequests, hasLength(1));
        final seen = assignmentRequests.single;
        expect(seen.method, 'POST');
        expect(
          seen.url,
          Uri.parse(
            'https://itt-replacement.example.com/sdk/v1/measurement-assignment',
          ),
        );
        expect(seen.url.query, isEmpty);
        expect(seen.headers['Authorization'], 'Bearer rs_pk_itt_replacement');
        expect(seen.headers['Content-Type'], contains('application/json'));
        expect(seen.body, request.canonicalJson);
        expect(
          diagnostic,
          isA<MeasurementAssignmentDeliveryAssigned>().having(
            (value) => value.candidateDelivery,
            'candidate delivery',
            MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
          ),
        );
      },
    );

    test('reconfigure replaces a stale assignment adapter', () async {
      final stale = _StaleAdapter();
      MeasurementAssignmentTransportRegistry.debugInstall(stale);

      expect(
        (await _transport().deliver(_request())).diagnostic,
        isA<MeasurementAssignmentDeliveryAssigned>(),
      );
      expect(stale.calls, 1);

      Restage.configure(
        apiKey: 'rs_pk_itt_second',
        baseUrl: 'https://itt-second.example.com',
      );

      final diagnostic =
          (await _transport().deliver(_invalidRequest())).diagnostic;

      expect(stale.calls, 1);
      expect(
        diagnostic,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.malformedResponse,
        ),
      );
    });

    test(
      'base-url-off reconfiguration clears a stale authenticated client',
      () async {
        final assignmentRequests = <http.Request>[];
        final client = _assignmentClient(
          baseUrl: 'https://itt-before-disable.example.com',
          apiKey: 'rs_pk_itt_before_disable',
          assignmentRequests: assignmentRequests,
        );
        Restage.configure(
          apiKey: 'rs_pk_itt_before_disable',
          baseUrl: 'https://itt-before-disable.example.com',
        );
        Restage.debugRestageRpcClient = client;

        expect(
          (await _transport().deliver(_request())).diagnostic,
          isA<MeasurementAssignmentDeliveryAssigned>(),
        );
        expect(assignmentRequests, hasLength(1));

        Restage.configure(apiKey: 'rs_pk_itt_base_url_off');

        final diagnostic = (await _transport().deliver(_request())).diagnostic;

        expect(assignmentRequests, hasLength(1));
        expect(
          diagnostic,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.noAdapter,
          ),
        );
      },
    );

    test(
      'unconfigured, base-url-off, and rejected authentication stay closed',
      () async {
        final unconfigured =
            (await _transport().deliver(_request())).diagnostic;
        expect(
          unconfigured,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.noAdapter,
          ),
        );

        Restage.configure(apiKey: 'rs_pk_itt_base_url_off');
        final baseUrlOff = (await _transport().deliver(_request())).diagnostic;
        expect(
          baseUrlOff,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.noAdapter,
          ),
        );

        Restage.configure(
          apiKey: 'rs_pk_itt_auth',
          baseUrl: 'https://itt-auth.example.com',
        );
        Restage.debugRestageRpcClient = RestageRpcClient(
          baseUrl: 'https://itt-auth.example.com',
          apiKey: 'rs_pk_itt_auth',
          httpClient: MockClient((request) async {
            if (request.url.path == '/sdk/v1/measurement-assignment') {
              return http.Response('', 401);
            }
            return http.Response('', 404);
          }),
        );

        final rejectedAuthentication =
            (await _transport().deliver(_request())).diagnostic;
        expect(
          rejectedAuthentication,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.unauthenticated,
          ),
        );
      },
    );

    test(
      'debug reset removes the installed adapter without leaking calls',
      () async {
        final assignmentRequests = <http.Request>[];
        Restage.configure(
          apiKey: 'rs_pk_itt_reset',
          baseUrl: 'https://itt-reset.example.com',
        );
        Restage.debugRestageRpcClient = _assignmentClient(
          baseUrl: 'https://itt-reset.example.com',
          apiKey: 'rs_pk_itt_reset',
          assignmentRequests: assignmentRequests,
        );

        Restage.debugReset();

        final diagnostic = (await _transport().deliver(_request())).diagnostic;

        expect(assignmentRequests, isEmpty);
        expect(
          diagnostic,
          isA<MeasurementAssignmentDeliveryUnavailable>().having(
            (value) => value.reason,
            'reason',
            MeasurementAssignmentUnavailableReason.noAdapter,
          ),
        );
      },
    );
  });

  test('keeps assignment transport out of public barrels and facades', () {
    final barrel = _restageFile('lib/restage.dart').readAsStringSync();
    final measurementFacade = _restageFile(
      'lib/src/measurement/restage_measurement.dart',
    ).readAsStringSync();

    for (final token in const [
      'measurement_assignment_transport.dart',
      'MeasurementAssignmentTransport',
      'IttAssignmentRpcAdapter',
      'IttAssignmentRpcRequest',
    ]) {
      expect(barrel, isNot(contains(token)), reason: 'barrel: $token');
      expect(
        measurementFacade,
        isNot(contains(token)),
        reason: 'measurement facade: $token',
      );
    }
  });
}

MeasurementAssignmentTransport<IttAssignmentRpcRequest, IttAssignmentRpcOutcome>
    _transport() => MeasurementAssignmentTransportRegistry.transportFor<
        IttAssignmentRpcRequest, IttAssignmentRpcOutcome>();

IttAssignmentRpcRequest _request() => const IttAssignmentRpcRequest(
      acceptedReceiptCanonicalBase64: 'AQ',
      credentialHandle: 'handle.itt.0001',
      sdkBuiltInsCanonicalBase64: 'Ag',
      assignmentContextCanonicalBase64: 'Aw',
    );

IttAssignmentRpcRequest _invalidRequest() => const IttAssignmentRpcRequest(
      acceptedReceiptCanonicalBase64: '',
      credentialHandle: 'handle.itt.0001',
      sdkBuiltInsCanonicalBase64: 'Ag',
    );

RestageRpcClient _assignmentClient({
  required String baseUrl,
  required String apiKey,
  required List<http.Request> assignmentRequests,
}) =>
    RestageRpcClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient((request) async {
        if (request.url.path == '/sdk/v1/measurement-assignment') {
          assignmentRequests.add(request);
          return http.Response(
            '{"result":"assigned","candidateDelivery":"rendered","assignment":{"schemaVersion":1,"experimentId":"experiment.checkout","experimentRevisionId":"revision.checkout.1","experimentEpochId":"epoch.checkout.1","armId":"arm.treatment","outcomeLinkCarrier":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );

File _restageFile(String relativePath) {
  for (final prefix in ['', 'packages/restage/']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) return candidate;
  }
  throw StateError('Could not locate packages/restage/$relativePath');
}

final class _StaleAdapter
    implements
        MeasurementAssignmentTypedAdapter<IttAssignmentRpcRequest,
            IttAssignmentRpcOutcome> {
  var calls = 0;

  @override
  Future<IttAssignmentRpcOutcome> deliver(
    IttAssignmentRpcRequest request,
  ) async {
    calls += 1;
    return IttAssignmentRpcAssigned(
      IttAssignmentRpcCandidateDelivery.rendered,
      _testAssignment(),
    );
  }

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(
    IttAssignmentRpcOutcome result,
  ) =>
      const MeasurementAssignmentDeliveryAssigned(
        candidateDelivery:
            MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
      );

  @override
  CanonicalSurfaceExperimentAssignmentV1? assignmentFor(
    IttAssignmentRpcOutcome result,
  ) =>
      result is IttAssignmentRpcAssigned ? result.assignment : null;
}

CanonicalSurfaceExperimentAssignmentV1 _testAssignment() =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.checkout'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.checkout.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.checkout.1'),
      armId: ExperimentPublicArmIdV1('arm.treatment'),
      outcomeLinkCarrier: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
