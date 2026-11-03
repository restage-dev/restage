import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/runtime/native_facts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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

  group('a pair the platform made', () {
    const nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const created = 1700000000000000;
    final reissued = '${'A' * 42}Q';

    setUp(() {
      NativeFacts.reset();
      NativeFacts.debugFacts = {
        'registrationNonce': nonce,
        'registrationCreatedAtMicros': created,
      };
      NativeFacts.debugResetRegistration =
          () => (nonce: reissued, createdAtMicros: created + 1);
    });
    tearDown(() {
      NativeFacts.debugFacts = null;
      NativeFacts.debugResetRegistration = null;
      NativeFacts.reset();
    });

    test('is sent without waiting for the local copy to be written', () async {
      final storage = _CountingPreferences()..hold = Completer<void>();
      addTearDown(() {
        if (!storage.hold!.isCompleted) storage.hold!.complete();
      });
      SharedPreferencesStorePlatform.instance = storage;
      final attempt = await launch()
          .capture()
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      expect(attempt?.registrationNonce, nonce);
      expect(attempt?.registrationCreatedAtMicros, created);
    });

    test('a failed local copy leaves the next launch on the same pair',
        () async {
      final storage = _CountingPreferences()..failNext = true;
      SharedPreferencesStorePlatform.instance = storage;
      final first = (await launch().capture())!;
      await pumpEventQueue();
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _CountingPreferences();
      NativeFacts.reset();
      NativeFacts.debugFacts = {
        'registrationNonce': nonce,
        'registrationCreatedAtMicros': created,
      };
      final second = (await launch().capture())!;
      expect(second.registrationNonce, first.registrationNonce);
      expect(second.registrationCreatedAtMicros, created);
    });

    test('a refusal takes the platform\'s new pair and keeps it', () async {
      final store = launch();
      final attempt = (await store.capture())!;
      await store.refuse(attempt);
      final renewed = (await store.capture())!;
      expect(renewed.registrationNonce, reissued);
      expect(renewed.generation, isNot(attempt.generation));
      expect((await launch().capture())!.registrationNonce, reissued);
      // Without a local copy the platform's current pair is the one used.
      SharedPreferencesStorePlatform.instance = _CountingPreferences();
      SharedPreferences.setMockInitialValues({});
      expect((await launch().capture())!.registrationNonce, reissued);
      expect(
        await store.confirm(
          attempt: attempt,
          localRequestStartMicros: now,
          credentialHandle: 'ic1.${'a' * 64}',
          expiresAtMicros: 31 * _day,
          serverNowMicros: _day,
        ),
        isFalse,
      );
    });

    test('a pair made here still waits for its write', () async {
      NativeFacts.debugFacts = {};
      NativeFacts.reset();
      NativeFacts.debugFacts = {};
      final storage = _CountingPreferences()..failNext = true;
      SharedPreferencesStorePlatform.instance = storage;
      expect(await launch().capture(), isNull);
    });
  });

  test('a relaunch reads its registration without writing it again', () async {
    final storage = _CountingPreferences();
    SharedPreferencesStorePlatform.instance = storage;
    final first = (await launch().capture())!;
    expect(storage.writes, 1);
    final again = (await launch().capture())!;
    expect(again.registrationNonce, first.registrationNonce);
    expect(storage.writes, 1);
  });

  test('a registration whose write failed is written again', () async {
    final storage = _CountingPreferences()..failNext = true;
    SharedPreferencesStorePlatform.instance = storage;
    await launch().capture();
    expect(storage.writes, 1);
    await launch().capture();
    expect(storage.writes, 2);
    await launch().capture();
    expect(storage.writes, 2);
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

final class _CountingPreferences extends InMemorySharedPreferencesStore {
  _CountingPreferences() : super.empty();
  int writes = 0;
  bool failNext = false;
  Completer<void>? hold;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    await hold?.future;
    if (failNext) {
      failNext = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
