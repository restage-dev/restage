import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/measurement/governed_measurement_rpc_transport.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  group('RestageGovernedMeasurementRpcTransport', () {
    test(
      'sends one exact direct carrier and decodes its closed result',
      () async {
        final requests = <http.Request>[];
        const result = MeasurementLinkChallengeOperationResultV1.failed(
          MeasurementLinkFailureV1(
            code: MeasurementLinkFailureCode.notAllowed,
          ),
        );
        final transport = RestageGovernedMeasurementRpcTransport(
          RestageRpcClient(
            baseUrl: 'https://example.com',
            apiKey: 'rs_pk_direct',
            httpClient: MockClient((request) async {
              requests.add(request);
              return http.Response(_resultBody(result.canonicalBytes), 200);
            }),
          ),
        );
        final request = _challengeRequest();

        final response = await transport.issueLinkChallenge(request);

        expect(response, isA<MeasurementLinkChallengeFailedV1>());
        expect(
          (response as MeasurementLinkChallengeFailedV1).failure.code,
          MeasurementLinkFailureCode.notAllowed,
        );
        final sent = requests.single;
        expect(sent.method, 'POST');
        expect(sent.url.path, '/sdk/v1/measurement-governed');
        expect(sent.headers['Authorization'], 'Bearer rs_pk_direct');
        expect(
          sent.body,
          '{"operation":"issueLinkChallenge","requestCanonicalBase64":"'
          '${_carrier(request.canonicalBytes)}"}',
        );
      },
    );

    test(
      'maps HTTP and malformed-result failures to closed coarse outcomes',
      () async {
        final cases = <({int status, String body}), MeasurementLinkFailureCode>{
          (status: 400, body: '{"error":"invalid_request"}'):
              MeasurementLinkFailureCode.invalidProof,
          (status: 401, body: '{"error":"unauthorized"}'):
              MeasurementLinkFailureCode.notAllowed,
          (status: 409, body: '{"error":"conflict"}'):
              MeasurementLinkFailureCode.conflict,
          (status: 503, body: '{"error":"unavailable"}'):
              MeasurementLinkFailureCode.temporarilyUnavailable,
          (status: 200, body: '{"resultCanonicalBase64":"AQ"}'):
              MeasurementLinkFailureCode.temporarilyUnavailable,
        };

        for (final entry in cases.entries) {
          final transport = RestageGovernedMeasurementRpcTransport(
            RestageRpcClient(
              baseUrl: 'https://example.com',
              apiKey: 'rs_pk_direct',
              httpClient: MockClient(
                (_) async => http.Response(entry.key.body, entry.key.status),
              ),
            ),
          );

          final response = await transport.issueLinkChallenge(
            _challengeRequest(),
          );

          expect(response, isA<MeasurementLinkChallengeFailedV1>());
          expect(
            (response as MeasurementLinkChallengeFailedV1).failure.code,
            entry.value,
            reason: '${entry.key}',
          );
        }
      },
    );

    test('keeps privacy transport failure domain-local and closed', () async {
      final request = _privacyRequest();
      final transport = RestageGovernedMeasurementRpcTransport(
        RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_direct',
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
      );

      final receipt = await transport.requestPrivacy(request);

      expect(receipt.status, RestagePrivacyCoordinatorStatus.failed);
      expect(receipt.domainResults.single, isA<RestagePrivacyDomainFailedV1>());
      expect(
        (receipt.domainResults.single as RestagePrivacyDomainFailedV1)
            .failure
            .code,
        RestagePrivacyFailureCode.temporarilyUnavailable,
      );
    });
  });
}

MeasurementLinkChallengeRequestV1 _challengeRequest() =>
    MeasurementLinkChallengeRequestV1(
      operationId: 'challenge.rpc.1',
      target: _target(),
      subjectPolicyRef: _subjectPolicy(),
      purposePolicyRef: _purposePolicy(),
      subjectKind: MeasurementSubjectKind.identifiedUser,
      action: MeasurementLinkAction.linkSubject,
      expectedSubjectGeneration: 1,
      requesterBinding: MeasurementRequesterBinding(utf8.encode('requester')),
    );

RestagePrivacyRequestV1 _privacyRequest() {
  final reset = MeasurementSubjectOperationRequestV1(
    operationId: 'reset.rpc.1',
    target: _target(),
    subjectPolicyRef: _subjectPolicy(),
    purposePolicyRef: _purposePolicy(),
    subjectKind: MeasurementSubjectKind.identifiedUser,
    action: MeasurementSubjectOperationAction.resetSubject,
    requesterBinding: MeasurementRequesterBinding(utf8.encode('requester')),
    assertionBytes: utf8.encode('assertion'),
    consentEvidence: MeasurementConsentEvidence(utf8.encode('consent')),
    regionEvidence: MeasurementRegionEvidence(utf8.encode('region')),
    expectedSubjectGeneration: 1,
  );
  return RestagePrivacyRequestV1(
    targets: RestagePrivacyTargets.measurement,
    action: RestagePrivacyAction.delete,
    authorities: [
      RestagePrivacyDomainAuthority(
        domain: RestagePrivacyDomain.measurement,
        requestCanonicalBytes: reset.canonicalBytes,
      ),
    ],
  );
}

TargetCoordinate _target() => TargetCoordinate(
      organizationId: OrganizationId(11),
      appId: ApplicationId(23),
      environmentTargetId: EnvironmentTargetId(31),
      namedEnvironmentId: NamedEnvironmentId(37),
      runtimePlane: RuntimePlane.sandbox,
    );

SubjectPolicyRefV1 _subjectPolicy() => SubjectPolicyRefV1(
      subjectPolicyId: SubjectPolicyId('subject.rpc'),
      revisionId: SubjectPolicyRevisionId('subject.rpc.v1'),
      semanticHash: CanonicalDigest('a' * 64),
    );

PurposePolicyRefV1 _purposePolicy() => PurposePolicyRefV1(
      revisionId: PurposePolicyRevisionId('purpose.rpc.v1'),
      semanticHash: CanonicalDigest('b' * 64),
    );

String _resultBody(List<int> result) =>
    '{"resultCanonicalBase64":"${_carrier(result)}"}';

String _carrier(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
