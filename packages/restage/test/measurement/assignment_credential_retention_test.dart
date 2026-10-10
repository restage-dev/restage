import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SurfaceAssignmentKeyProvider.clear);

  test('only the confirmed server lifetime rolls the durable tuple', () async {
    var now = 1000000;
    var rollovers = 0;
    SurfaceAssignmentCredentialStore store() =>
        SurfaceAssignmentCredentialStore(
          namespace: 'configured-target',
          actor: () async => 'local-actor',
          identityGeneration: () => 1,
          nowMicros: () => now,
          onRetentionRollover: () => rollovers++,
        );
    final firstStore = store();
    final first = (await firstStore.capture())!;
    expect(
        await firstStore.confirm(
          attempt: first,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 1100,
          serverNowMicros: 1000,
        ),
        isTrue);
    now += 50;
    expect((await store().capture())!.credentialHandle, 'ic1.${'a' * 64}');
    now += 51;
    final renewed = (await store().capture())!;
    expect(renewed.registrationNonce, isNot(first.registrationNonce));
    expect(renewed.credentialHandle, isNull);
    expect(rollovers, 1);

    // A lost serve response and process restart must resend the same tuple.
    expect((await store().capture())!.tuple, renewed.tuple);
    final prefs = await SharedPreferences.getInstance();
    final retained = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(retained['registrationNonce'], renewed.registrationNonce);
    expect(retained.containsKey('credentialHandle'), isFalse);
  });

  for (final failedWrite in [1, 2]) {
    test('failed durable write $failedWrite cannot publish a false handle',
        () async {
      final previous = SharedPreferencesStorePlatform.instance;
      final storage = _FailingPreferenceStore(failedWrite);
      SharedPreferencesStorePlatform.instance = storage;
      addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
      SurfaceAssignmentCredentialStore store() =>
          SurfaceAssignmentCredentialStore(
            namespace: 'persistence',
            actor: () async => 'actor',
            identityGeneration: () => 0,
            onRetentionRollover: () => fail('no retention rollover'),
            nowMicros: () => 1000,
          );
      final firstStore = store();
      final first = await firstStore.capture();
      if (failedWrite == 1) {
        expect(first, isNull, reason: 'an unpersisted tuple cannot be sent');
        expect(await storage.getAll(), isEmpty);
        expect(await store().capture(), isNotNull);
        return;
      }

      final tuple = first!;
      expect(
          await firstStore.confirm(
            attempt: tuple,
            localRequestStartMicros: 1000,
            credentialHandle: 'ic1.${'a' * 64}',
            expiresAtMicros: 2000,
            serverNowMicros: 1000,
          ),
          isFalse);
      // SharedPreferences may update its cache even when the platform write
      // fails; a new process observes the durable platform value.
      await (await SharedPreferences.getInstance()).reload();
      final restarted = store();
      final retry = (await restarted.capture())!;
      expect(retry.tuple, tuple.tuple);
      expect(retry.credentialHandle, isNull);
      expect(
          await restarted.confirm(
            attempt: retry,
            localRequestStartMicros: 1000,
            credentialHandle: 'ic1.${'a' * 64}',
            expiresAtMicros: 2000,
            serverNowMicros: 1000,
          ),
          isTrue);
      expect((await store().capture())!.credentialHandle, 'ic1.${'a' * 64}');
    });
  }

  test('stale identity cannot roll retention after an awaited actor', () async {
    var now = 1000;
    var identityGeneration = 0;
    var rollovers = 0;
    final pendingIdentity = Completer<String>();
    var waitForIdentity = false;
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'old-config',
      actor: () =>
          waitForIdentity ? pendingIdentity.future : Future.value('actor'),
      identityGeneration: () => identityGeneration,
      onRetentionRollover: () => rollovers++,
      nowMicros: () => now,
    );
    final first = (await store.capture())!;
    expect(
        await store.confirm(
          attempt: first,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 1100,
          serverNowMicros: 1000,
        ),
        isTrue);
    now = 1200;
    waitForIdentity = true;
    final staleCapture = store.capture();
    identityGeneration++;
    pendingIdentity.complete('actor');
    expect(await staleCapture, isNull);
    expect(rollovers, 0,
        reason: 'old identity must not clear newer held assignments');
  });

  test('malformed folded metadata never confirms or rotates a tuple', () async {
    final invalidBodies = <Map<String, Object?>>[
      {'credentialHandle': 'ic1.${'a' * 64}'},
      {
        'credentialHandle': 'ic1.${'a' * 64}',
        'expiresAtMicros': -1,
        'serverNowMicros': 1000,
      },
      {
        'credentialHandle': 'ic1.${'a' * 64}',
        'expiresAtMicros': 'later',
        'serverNowMicros': 1000,
      },
      {
        'credentialHandle': 'ic1.${'a' * 64}',
        'expiresAtMicros': 2000,
        'serverNowMicros': 0,
      },
    ];
    for (var index = 0; index < invalidBodies.length; index++) {
      var rollovers = 0;
      final store = SurfaceAssignmentCredentialStore(
        namespace: 'invalid-$index',
        actor: () async => 'local',
        identityGeneration: () => 1,
        nowMicros: () => 1000,
        onRetentionRollover: () => rollovers++,
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
      final first = (await store.capture())!;
      final sent = <Map<String, dynamic>>[];
      final client = RestageRpcClient(
        baseUrl: 'https://surfaces.example.com',
        apiKey: 'rs_pk_refused',
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(invalidBodies[index]), 200);
        }),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final lease = await SurfaceAssignmentKeyProvider.captureLease();
        expect(
          await client.fetchSurfaceScreen(
            SurfaceScreenDeliveryRequest(
              surface: Surface.general,
              slug: 'feature_announcement',
              contractVersion: 7,
            ),
            registrationLease: lease,
          ),
          isA<SurfaceScreenDeliveryInvalidResponse>(),
        );
      }
      expect(sent, hasLength(2));
      expect(sent[0]['registrationNonce'], first.registrationNonce);
      expect(sent[1]['registrationNonce'], first.registrationNonce);
      expect((await store.capture())!.credentialHandle, isNull);
      expect(rollovers, 0);
      SurfaceAssignmentKeyProvider.clear();
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
