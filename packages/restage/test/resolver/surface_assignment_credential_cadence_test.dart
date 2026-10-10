import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _day = Duration.microsecondsPerDay;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var now = 0;
  late List<Map<String, dynamic>> requests;
  late RestageRpcClient client;
  const expiresAt = 30 * _day;

  setUp(() {
    now = _day;
    requests = [];
    client = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_cadence',
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'credentialHandle': 'credential.held',
            'expiresAtMicros': expiresAt,
          }),
          200,
        );
      }),
    );
  });

  // A new store per launch, sharing the persisted registration.
  SurfaceAssignmentCredentialStore launch() => SurfaceAssignmentCredentialStore(
        namespace: 'cadence',
        actor: () async => 'actor',
        identityGeneration: () => 0,
        client: () => client,
        nowMicros: () => now,
        onRetentionRollover: () => fail('no retention rollover'),
      );

  test('a fresh registration presents once and records confirmation', () async {
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(1));
    expect(requests.single.containsKey('credentialHandle'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(stored['lastConfirmedAtMicros'], now);
  });

  test('a launch within a day of confirmation reuses the stored handle',
      () async {
    expect(await launch().resolve(), 'credential.held');
    now += _day - 1;
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(1));
  });

  test('a launch a day after confirmation re-presents the handle', () async {
    expect(await launch().resolve(), 'credential.held');
    now += _day;
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(2));
    expect(requests.last['credentialHandle'], 'credential.held');
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(stored['lastConfirmedAtMicros'], now);
    now += _day - 1;
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(2));
  });

  test('a handle expiring within a day is re-presented', () async {
    expect(await launch().resolve(), 'credential.held');
    now = expiresAt - _day;
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(2));
  });

  test('a confirmation time ahead of the clock is re-presented', () async {
    expect(await launch().resolve(), 'credential.held');
    now -= 1;
    expect(await launch().resolve(), 'credential.held');
    expect(requests, hasLength(2));
  });

  test('a running store re-presents a day after confirmation', () async {
    final store = launch();
    expect(await store.resolve(), 'credential.held');
    now += _day - 1;
    expect(await store.resolve(), 'credential.held');
    expect(requests, hasLength(1));
    now += 1;
    expect(await store.resolve(), 'credential.held');
    expect(requests, hasLength(2));
    expect(requests.last['credentialHandle'], 'credential.held');
  });
}
