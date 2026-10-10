import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SurfaceAssignmentKeyProvider.clear);

  test('serve folds first registration and later presents its handle',
      () async {
    final requests = <Map<String, dynamic>>[];
    final store = _store();
    _install(store);
    final client = RestageRpcClient(
      baseUrl: 'https://edge.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'credentialHandle': 'ic1.${'a' * 64}',
              'expiresAtMicros': DateTime.now().microsecondsSinceEpoch +
                  30 * Duration.microsecondsPerDay,
              'serverNowMicros': DateTime.now().microsecondsSinceEpoch,
              'artifact': null,
            }),
            200);
      }),
    );
    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
    expect(requests, hasLength(2));
    expect(requests.first['registrationNonce'], isNotNull);
    expect(requests.first['registrationCreatedAtMicros'], isA<int>());
    expect(requests.first.containsKey('assignmentKey'), isFalse);
    expect(requests.last.containsKey('registrationNonce'), isFalse);
    expect(requests.last['assignmentKey'], 'ic1.${'a' * 64}');
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(persisted['localExpiresAtMicros'], isA<int>());
  });

  test('a tuple that was not persisted cannot leave on a hosted serve',
      () async {
    var sends = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => null,
      identityGeneration: () => 0,
      registration: () async => null,
    );
    final client = RestageRpcClient(
      baseUrl: 'https://edge.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        sends++;
        return http.Response('{}', 200);
      }),
    );

    expect(
        await client.fetchSurface(
            surfaceType: 'general', surfaceSlug: 'notice'),
        isNull);
    expect(sends, 0);
  });

  test('typed refusal replaces tuple once before the next serve', () async {
    final requests = <Map<String, dynamic>>[];
    final store = _store();
    _install(store);
    final client = RestageRpcClient(
      baseUrl: 'https://edge.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'assignment': {'result': 'registrationRefused'},
              'artifact': null,
            }),
            200);
      }),
    );
    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
    expect(requests, hasLength(2));
    expect(requests.last['registrationNonce'],
        isNot(requests.first['registrationNonce']));
  });

  test('lost serve response replays the persisted tuple after restart',
      () async {
    final requests = <Map<String, dynamic>>[];
    final firstStore = _store();
    _install(firstStore);
    var firstSend = true;
    final client = RestageRpcClient(
      baseUrl: 'https://edge.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (firstSend) {
          firstSend = false;
          throw http.ClientException('response lost');
        }
        final now = DateTime.now().microsecondsSinceEpoch;
        return http.Response(
            jsonEncode({
              'credentialHandle': 'ic1.${'a' * 64}',
              'expiresAtMicros': now + 30 * Duration.microsecondsPerDay,
              'serverNowMicros': now,
              'artifact': null,
            }),
            200);
      }),
    );

    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
    _install(_store());
    await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');

    expect(requests, hasLength(2));
    expect(requests.last['registrationNonce'],
        requests.first['registrationNonce']);
    expect(requests.last.containsKey('assignmentKey'), isFalse);
  });

  test('typed open-frame credential refusal clears current handle', () async {
    final store = _store();
    _install(store);
    final first = (await store.capture())!;
    final now = DateTime.now().microsecondsSinceEpoch;
    await store.confirm(
      attempt: first,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: now + 30 * Duration.microsecondsPerDay,
      serverNowMicros: now,
    );
    final client = RestageRpcClient(
      baseUrl: 'https://edge.example.test',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({'error': 'refused', 'reason': 'registrationRefused'}),
            400,
          )),
    );

    expect(await client.ingestMeasurement('frame'),
        isA<MeasurementIngestRpcRejected>());
    final renewed = (await store.capture())!;
    expect(renewed.credentialHandle, isNull);
    expect(renewed.registrationNonce, isNot(first.registrationNonce));
  });

  test('lease remains current when capture renews an expired tuple', () async {
    var now = Duration.microsecondsPerDay;
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'lease-expiry',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      nowMicros: () => now,
      onRetentionRollover: () {},
    );
    _install(store);
    final first = (await store.capture())!;
    await store.confirm(
      attempt: first,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * Duration.microsecondsPerDay,
      serverNowMicros: Duration.microsecondsPerDay,
    );
    now = 31 * Duration.microsecondsPerDay;

    final lease = await SurfaceAssignmentKeyProvider.captureLease();

    expect(lease.isCurrent, isTrue);
    expect(lease.assignmentKey, isNull);
    expect(
        lease.registration!.registrationNonce, isNot(first.registrationNonce));
  });
}

SurfaceAssignmentCredentialStore _store() => SurfaceAssignmentCredentialStore(
      namespace: 'http',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: () {},
    );

void _install(SurfaceAssignmentCredentialStore store) {
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
}
