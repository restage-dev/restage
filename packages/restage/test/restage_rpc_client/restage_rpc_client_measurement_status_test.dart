import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('a throttled folded registration keeps its durable tuple', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'throttled-folded-registration',
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
    final first = (await store.capture())!;
    late Map<String, dynamic> sent;
    final client = RestageRpcClient(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"error":"rate_limited"}', 429,
            headers: const {'retry-after': '5'});
      }),
    );
    final outcome = await client.fetchSurfaceScreen(
      SurfaceScreenDeliveryRequest(
        surface: Surface.general,
        slug: 'feature_announcement',
        contractVersion: 7,
      ),
      registrationLease: await SurfaceAssignmentKeyProvider.captureLease(),
    );
    expect(outcome, isA<SurfaceScreenDeliveryTransportUnavailable>());
    expect(sent['registrationNonce'], first.registrationNonce);
    expect(
        sent['registrationCreatedAtMicros'], first.registrationCreatedAtMicros);
    final retry = (await store.capture())!;
    expect(retry.tuple, first.tuple);
    expect(retry.credentialHandle, isNull);
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
