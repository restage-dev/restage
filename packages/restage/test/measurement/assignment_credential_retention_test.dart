import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only retained server expiry rolls the nonce and identity lease',
      () async {
    var now = 1000000;
    var rollovers = 0;
    final requests = <Map<String, dynamic>>[];
    final client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_retention',
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (requests.length == 2) return http.Response('{}', 503);
        return http.Response(
            jsonEncode({
              'credentialHandle': requests.length == 1
                  ? 'credential.first'
                  : 'credential.second',
              'expiresAtMicros': now + 100,
            }),
            200);
      }),
    );
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'configured-target',
      actor: () async => 'local-actor',
      identityGeneration: () => 1,
      client: () => client,
      nowMicros: () => now,
      onRetentionRollover: () => rollovers++,
    );
    final firstGeneration = store.generation;
    expect(await store.resolve(), 'credential.first');
    now += 50;
    expect(await store.resolve(), 'credential.first');
    expect(requests, hasLength(1));
    now += 51;
    expect(await store.resolve(), isNull);
    expect(rollovers, 1);
    expect(store.generation, greaterThan(firstGeneration));
    expect(requests[1]['registrationNonce'],
        isNot(requests[0]['registrationNonce']));
    expect(requests[1].containsKey('credentialHandle'), isFalse);
    now++;
    expect(await store.resolve(), 'credential.second');
    expect(requests[2], requests[1],
        reason: 'pending retry keeps nonce and creation time');
    expect(rollovers, 1);
    final prefs = await SharedPreferences.getInstance();
    final retained = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(retained['credentialHandle'], 'credential.second');
    expect(retained['expiresAtMicros'], now + 100);
  });

  for (final failedWrite in [1, 2]) {
    test(
        'credential persistence write $failedWrite recovers without changing attempt',
        () async {
      final storage = _FailingPreferenceStore(failedWrite);
      SharedPreferencesStorePlatform.instance = storage;
      final requests = <Map<String, dynamic>>[];
      final client = RestageRpcClient(
        baseUrl: 'https://surfaces.example.com',
        apiKey: 'rs_pk_persistence',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final durable = await storage.getAll();
          final saved = jsonDecode(durable.values.single as String);
          expect(saved['registrationNonce'], body['registrationNonce']);
          expect(saved['registrationCreatedAtMicros'],
              body['registrationCreatedAtMicros']);
          requests.add(body);
          return http.Response(
              jsonEncode({
                'credentialHandle': 'credential.durable',
                'expiresAtMicros': 2000
              }),
              200);
        }),
      );
      final store = SurfaceAssignmentCredentialStore(
        namespace: 'persistence',
        actor: () async => 'actor',
        identityGeneration: () => 0,
        client: () => client,
        onRetentionRollover: () => fail('no retention rollover'),
        nowMicros: () => 1000,
      );
      expect(await store.resolve(), isNull);
      expect(requests, hasLength(failedWrite == 1 ? 0 : 1));
      final prefs = await SharedPreferences.getInstance();
      final failedAttempt =
          jsonDecode(prefs.getString(prefs.getKeys().single)!);
      expect(await store.resolve(), 'credential.durable');
      expect(requests.last['registrationNonce'],
          failedAttempt['registrationNonce']);
      expect(requests.last['registrationCreatedAtMicros'],
          failedAttempt['registrationCreatedAtMicros']);
      if (failedWrite == 2) {
        expect(requests.last['credentialHandle'], 'credential.durable');
      }
      final durable =
          jsonDecode((await storage.getAll()).values.single as String);
      expect(durable['credentialHandle'], 'credential.durable');
      expect(durable['expiresAtMicros'], 2000);
    });
  }

  test(
      'stale configuration cannot trigger retention rollover after awaited identity',
      () async {
    var now = 1000;
    var rollovers = 0;
    final pendingIdentity = Completer<String>();
    var waitForIdentity = false;
    RestageRpcClient? client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_old_config',
      httpClient: MockClient((_) async => http.Response(
          jsonEncode(
              {'credentialHandle': 'credential.old', 'expiresAtMicros': 1100}),
          200)),
    );
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'old-config',
      actor: () =>
          waitForIdentity ? pendingIdentity.future : Future.value('actor'),
      identityGeneration: () => 0,
      client: () => client,
      onRetentionRollover: () => rollovers++,
      nowMicros: () => now,
    );
    expect(await store.resolve(), 'credential.old');
    now = 1200;
    waitForIdentity = true;
    final staleResolve = store.resolve();
    client = null;
    pendingIdentity.complete('actor');
    expect(await staleResolve, isNull);
    expect(rollovers, 0,
        reason: 'old config must not clear newer held assignments');
  });

  test('malformed expiry responses cannot authorize retention rollover',
      () async {
    for (final response in <Map<String, Object?>>[
      {'credentialHandle': 'credential.only'},
      {'credentialHandle': 'credential.bad', 'expiresAtMicros': -1},
      {'credentialHandle': 'credential.bad', 'expiresAtMicros': 'later'},
      {
        'credentialHandle': 'credential.bad',
        'expiresAtMicros': 100,
        'extra': true
      },
    ]) {
      var now = 1000;
      final requests = <Map<String, dynamic>>[];
      var rollovers = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://surfaces.example.com',
        apiKey: 'rs_pk_refused',
        httpClient: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(response), 200);
        }),
      );
      final store = SurfaceAssignmentCredentialStore(
        namespace: 'target.${response.toString()}',
        actor: () async => 'local',
        identityGeneration: () => 1,
        client: () => client,
        nowMicros: () => now,
        onRetentionRollover: () => rollovers++,
      );
      expect(await store.resolve(), isNull);
      now += 1000000000;
      expect(await store.resolve(), isNull);
      expect(requests[1], requests[0]);
      expect(rollovers, 0);
    }
  });
}

class _FailingPreferenceStore extends InMemorySharedPreferencesStore {
  _FailingPreferenceStore(this.failedWrite) : super.empty();
  final int failedWrite;
  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (++writes == failedWrite) return false;
    return super.setValue(valueType, key, value);
  }
}
