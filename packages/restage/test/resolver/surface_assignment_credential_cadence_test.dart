import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _day = Duration.microsecondsPerDay;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var now = 60 * _day;
  var rollovers = 0;
  SurfaceAssignmentCredentialStore launch() => SurfaceAssignmentCredentialStore(
        namespace: 'cadence',
        actor: () async => 'actor',
        identityGeneration: () => 0,
        nowMicros: () => now,
        onRetentionRollover: () => rollovers++,
      );

  setUp(() {
    now = 60 * _day;
    rollovers = 0;
  });

  test('ahead clock uses request start and server remaining life', () async {
    final store = launch();
    final attempt = (await store.capture())!;
    expect(attempt.credentialHandle, isNull);
    final requestStart = now;
    now += 3 * Duration.microsecondsPerSecond;
    await store.confirm(
      attempt: attempt,
      localRequestStartMicros: requestStart,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    final confirmed = (await store.capture())!;
    expect(confirmed.credentialHandle, 'ic1.${'a' * 64}');
    expect(rollovers, 0);
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(persisted['localExpiresAtMicros'], requestStart + 30 * _day);
    expect(persisted['expiresAtMicros'], 31 * _day);
    now = requestStart + 29 * _day;
    expect((await launch().capture())!.credentialHandle, isNotNull);
    now = requestStart + 30 * _day;
    final renewed = (await launch().capture())!;
    expect(renewed.credentialHandle, isNull);
    expect(renewed.registrationNonce, isNot(attempt.registrationNonce));
    expect(rollovers, 1);
  });

  test('same handle cannot extend persisted local deadline', () async {
    final store = launch();
    final attempt = (await store.capture())!;
    final firstStart = now;
    await store.confirm(
      attempt: attempt,
      localRequestStartMicros: firstStart,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    now += 2 * _day;
    await store.confirm(
      attempt: attempt,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(persisted['localExpiresAtMicros'], firstStart + 30 * _day);
    expect((await launch().capture())!.credentialHandle, isNotNull);
  });

  test('same handle can shorten local deadline', () async {
    final store = launch();
    final attempt = (await store.capture())!;
    await store.confirm(
      attempt: attempt,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    now += 2 * _day;
    await store.confirm(
      attempt: attempt,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: 5 * _day,
    );
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(persisted['localExpiresAtMicros'], 88 * _day);
  });

  test('confirmed tuple refuses changed handle or server expiry', () async {
    final store = launch();
    final attempt = (await store.capture())!;
    expect(
        await store.confirm(
          attempt: attempt,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 31 * _day,
          serverNowMicros: _day,
        ),
        isTrue);
    expect(
        await store.confirm(
          attempt: attempt,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'b' * 64}',
          expiresAtMicros: 31 * _day,
          serverNowMicros: _day,
        ),
        isFalse);
    expect(
        await store.confirm(
          attempt: attempt,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 32 * _day,
          serverNowMicros: _day,
        ),
        isFalse);
  });
}
