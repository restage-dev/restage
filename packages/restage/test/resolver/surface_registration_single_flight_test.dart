import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hour = Duration.microsecondsPerHour;
const _day = Duration.microsecondsPerDay;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var now = _day;
  var rollovers = 0;
  SurfaceAssignmentCredentialStore launch() => SurfaceAssignmentCredentialStore(
        namespace: 'single-flight',
        actor: () async => 'actor',
        identityGeneration: () => 0,
        nowMicros: () => now,
        onRetentionRollover: () => rollovers++,
      );

  setUp(() {
    now = _day;
    rollovers = 0;
  });

  test('concurrent first sends and late first origin handoff reuse tuple',
      () async {
    final store = launch();
    final first = await Future.wait([store.capture(), store.capture()]);
    expect(first[0]!.registrationNonce, first[1]!.registrationNonce);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), hasLength(1));
    now += 12 * _hour;
    final restarted = launch();
    final late = (await restarted.capture())!;
    expect(late.registrationNonce, first[0]!.registrationNonce);
    expect(late.registrationCreatedAtMicros,
        first[0]!.registrationCreatedAtMicros);
    await restarted.confirm(
      attempt: late,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    expect((await restarted.capture())!.credentialHandle, isNotNull);
  });

  test('lost response and restart reuse tuple and server remaining lifetime',
      () async {
    final first = (await launch().capture())!;
    now += 4 * _hour;
    final retryStore = launch();
    final retry = (await retryStore.capture())!;
    expect(retry.registrationNonce, first.registrationNonce);
    await retryStore.confirm(
      attempt: retry,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day + 4 * _hour,
    );
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(prefs.getKeys().single)!);
    expect(persisted['localExpiresAtMicros'], 31 * _day);
  });

  test('concurrent stale refusals replace once and obsolete reply cannot reset',
      () async {
    final store = launch();
    final old = (await store.capture())!;
    await Future.wait([store.refuse(old), store.refuse(old)]);
    final renewed = (await store.capture())!;
    expect(renewed.registrationNonce, isNot(old.registrationNonce));
    expect(rollovers, 1);
    await store.confirm(
      attempt: old,
      localRequestStartMicros: now,
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 31 * _day,
      serverNowMicros: _day,
    );
    expect((await store.capture())!.credentialHandle, isNull);
    expect((await launch().capture())!.registrationNonce,
        renewed.registrationNonce);
  });

  test('durable frame fingerprint retires only its exact registered tuple',
      () async {
    final firstStore = launch();
    final first = (await firstStore.capture())!;
    expect(
        await firstStore.confirm(
          attempt: first,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 31 * _day,
          serverNowMicros: _day,
        ),
        isTrue);
    final oldFingerprint = (await firstStore.capture())!.fingerprint;

    final restarted = launch();
    expect(await restarted.refuseFingerprint(oldFingerprint), isTrue);
    final replacement = (await restarted.capture())!;
    expect(replacement.registrationNonce, isNot(first.registrationNonce));
    expect(replacement.credentialHandle, isNull);
    expect(rollovers, 1);
    expect(
        await restarted.confirm(
          attempt: replacement,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'b' * 64}',
          expiresAtMicros: 31 * _day,
          serverNowMicros: _day,
        ),
        isTrue);
    final renewed = (await restarted.capture())!;
    expect(await restarted.refuseFingerprint(oldFingerprint), isFalse);
    expect((await launch().capture())!.fingerprint, renewed.fingerprint);
    expect(
        (await launch().capture())!.credentialHandle, renewed.credentialHandle);
    expect(rollovers, 1);
  });

  test('the same persisted tuple is distinct in another SDK namespace',
      () async {
    final first = (await launch().capture())!;
    final prefs = await SharedPreferences.getInstance();
    final firstKey = prefs.getKeys().single;
    final saved = prefs.getString(firstKey)!;
    SurfaceAssignmentCredentialStore otherStore() =>
        SurfaceAssignmentCredentialStore(
          namespace: 'another-namespace',
          actor: () async => 'actor',
          identityGeneration: () => 0,
          nowMicros: () => now,
          onRetentionRollover: () => rollovers++,
        );
    await otherStore().capture();
    final otherKey = prefs.getKeys().singleWhere((key) => key != firstKey);
    await prefs.setString(otherKey, saved);
    final sameTupleElsewhere = (await otherStore().capture())!;
    expect(sameTupleElsewhere.registrationNonce, first.registrationNonce);
    expect(sameTupleElsewhere.fingerprint, isNot(first.fingerprint));
  });
}
