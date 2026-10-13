import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

void main() {
  test('a throttled assignment is unavailable, not an error', () async {
    final logs = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = previous);

    final outcome = await _clientAnswering(429).serveIttAssignment(_request());

    expect(outcome, isA<IttAssignmentRpcUnavailable>());
    expect(
      (outcome as IttAssignmentRpcUnavailable).reason,
      IttAssignmentRpcUnavailableReason.serviceUnavailable,
    );
    expect(logs, isEmpty);
  });

  test('a throttled collection decision is no decision', () async {
    final decision = await _clientAnswering(429)
        .readMeasurementCollectionDecisionExact(_bindingReference('a'));
    expect(decision, isNull);
  });

  test('a throttled credential registration yields no credential', () async {
    final credential = await _clientAnswering(429).registerAssignmentCredential(
      registrationNonce: 'A' * 43,
      registrationCreatedAtMicros: 100,
    );
    expect(credential, isNull);
  });
}

RestageRpcClient _clientAnswering(int status) => RestageRpcClient(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":"rate_limited"}',
          status,
          headers: const {'retry-after': '5'},
        ),
      ),
    );

IttAssignmentRpcRequest _request() => const IttAssignmentRpcRequest(
      acceptedReceiptCanonicalBase64: 'AQ',
      credentialHandle: 'handle.itt.0001',
      sdkBuiltInsCanonicalBase64: 'Ag',
      assignmentContextCanonicalBase64: 'Aw',
    );

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
      authorityId: MeasurementPublicationAuthorityId('authority.status.$seed'),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}
