import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/first_launch_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _key = 'restage.first_launch_utc';
const _platformKey = 'flutter.$_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an absent origin persists UTC and survives a new preferences instance',
      () async {
    final utc = DateTime.utc(2026, 10, 3, 12, 34, 56, 123, 456);
    final local =
        DateTime.fromMicrosecondsSinceEpoch(utc.microsecondsSinceEpoch);

    final first = await FirstLaunchStore().readOrCreate(local);
    expect(first, utc);
    expect(first!.isUtc, isTrue);

    SharedPreferences.resetStatic();
    final reloaded = await SharedPreferences.getInstance();
    expect(reloaded.getString(_key), utc.toIso8601String());
    expect(
      await FirstLaunchStore().readOrCreate(utc.add(const Duration(days: 10))),
      utc,
    );
  });

  test('repeated reads preserve the persisted origin without writes', () async {
    final first = DateTime.utc(2026, 10, 3, 12);
    final storage = _installStorage({_key: first.toIso8601String()});
    final store = FirstLaunchStore();

    expect(await store.readOrCreate(first.add(const Duration(days: 5))), first);
    expect(await store.readOrCreate(first.subtract(const Duration(days: 5))),
        first);
    expect(storage.writes, 0);
    expect((await storage.getAll())[_platformKey], first.toIso8601String());
  });

  for (final corrupt in <Object>[
    '',
    'unreadable',
    '2026-10-03',
    '2026-10-03T12:00:00.000',
    '2026-02-30T12:00:00.000Z',
    '2026-10-03T12:00:00.000+02:00',
    42,
  ]) {
    test('corrupt origin $corrupt remains unknown without being rewritten',
        () async {
      final storage = _installStorage({_key: corrupt});
      final store = FirstLaunchStore();
      final now = DateTime.utc(2026, 10, 3);

      expect(await store.readOrCreate(now), isNull);
      expect(
          await store.readOrCreate(now.add(const Duration(days: 1))), isNull);
      expect(storage.writes, 0);
      expect((await storage.getAll())[_platformKey], corrupt);
    });
  }

  test('a failed preferences read stays unknown and preserves the origin',
      () async {
    final first = DateTime.utc(2026, 10, 3);
    final storage = _installStorage({_key: first.toIso8601String()})
      ..failReads = true;
    final store = FirstLaunchStore();

    expect(
        await store.readOrCreate(first.add(const Duration(days: 1))), isNull);
    expect(storage.writes, 0);
    storage.failReads = false;
    expect(await store.readOrCreate(first.add(const Duration(days: 2))), first);
    expect((await storage.getAll())[_platformKey], first.toIso8601String());
  });

  test('a failed reload cannot treat cached data as a successful read',
      () async {
    final first = DateTime.utc(2026, 10, 3);
    final storage = _installStorage({_key: first.toIso8601String()});
    await SharedPreferences.getInstance();
    storage.failReads = true;

    expect(await FirstLaunchStore().readOrCreate(first), isNull);
    expect(storage.writes, 0);
    storage.failReads = false;
    expect((await storage.getAll())[_platformKey], first.toIso8601String());
  });

  for (final throws in [false, true]) {
    test(
        'a ${throws ? 'throwing' : 'failed'} write never confirms cached origin',
        () async {
      final storage = _installStorage({})
        ..failWrites = true
        ..throwOnWrite = throws;
      final store = FirstLaunchStore();
      final first = DateTime.utc(2026, 10, 3, 12);

      expect(await store.readOrCreate(first), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(_key), first.toIso8601String());
      expect((await storage.getAll()).containsKey(_platformKey), isFalse);
      expect(
          await store.readOrCreate(first.add(const Duration(days: 1))), isNull);
      expect(
        await FirstLaunchStore()
            .readOrCreate(first.add(const Duration(days: 2))),
        isNull,
      );

      storage.failWrites = false;
      final persisted = first.add(const Duration(days: 3));
      expect(await store.readOrCreate(persisted), persisted);
      expect(
          (await storage.getAll())[_platformKey], persisted.toIso8601String());
      expect(await store.readOrCreate(persisted.add(const Duration(days: 1))),
          persisted);
      expect(storage.writes, 4);
    });
  }

  test('concurrent reads share preferences acquisition and the first clock',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final ready = Completer<SharedPreferences>();
    var reads = 0;
    final store = FirstLaunchStore(preferences: () {
      reads++;
      return ready.future;
    });
    final now = DateTime.utc(2026, 10, 3, 12);

    final first = store.readOrCreate(now);
    final second = store.readOrCreate(now.add(const Duration(days: 1)));
    expect(reads, 1);
    ready.complete(preferences);
    expect(await Future.wait([first, second]), [now, now]);
    await preferences.reload();
    expect(preferences.getString(_key), now.toIso8601String());
  });

  for (final succeeds in [true, false]) {
    test(
        'independent stores share one ${succeeds ? 'successful' : 'failed'} '
        'in-flight production write', () async {
      final storage = _installStorage({})
        ..releaseWrite = Completer<void>()
        ..failWrites = !succeeds;
      final now = DateTime.utc(2026, 10, 3, 12);
      final firstStore = FirstLaunchStore();
      var completed = false;
      final first = firstStore.readOrCreate(now);
      await storage.writeEntered.future;
      final second = FirstLaunchStore()
          .readOrCreate(now.add(const Duration(days: 1)))
          .then((value) {
        completed = true;
        return value;
      });
      final third = firstStore.readOrCreate(now.add(const Duration(days: 2)));
      await Future<void>.delayed(Duration.zero);

      expect(storage.writes, 1);
      expect(completed, isFalse);
      expect((await storage.getAll()).containsKey(_platformKey), isFalse);
      storage.releaseWrite!.complete();
      final expected = succeeds ? now : null;
      expect(await Future.wait([first, second, third]),
          [expected, expected, expected]);
      expect((await storage.getAll())[_platformKey],
          succeeds ? now.toIso8601String() : null);
    });
  }

  test('explicit persistent test reset also isolates existing store instances',
      () async {
    final store = FirstLaunchStore();
    final first = DateTime.utc(2026, 10, 3);
    expect(await store.readOrCreate(first), first);

    SharedPreferences.setMockInitialValues({});
    final next = first.add(const Duration(days: 1));
    expect(await store.readOrCreate(next), next);
    expect(await FirstLaunchStore().readOrCreate(next), next);
  });

  test('install age is whole elapsed UTC days across clock boundaries', () {
    final first = DateTime.utc(2026, 10, 3, 12);
    int? age(Duration elapsed) => daysSinceInstall(
          nowUtc: first.add(elapsed),
          firstLaunchUtc: first,
        );

    expect(age(const Duration(hours: 23, minutes: 59)), 0);
    expect(age(const Duration(hours: 24)), 1);
    expect(age(const Duration(hours: 49)), 2);
    expect(age(const Duration(days: -1)), 0);
    expect(daysSinceInstall(nowUtc: first, firstLaunchUtc: null), isNull);
  });

  test('a shortened daylight-saving civil day is not an elapsed install day',
      () {
    final first = DateTime.parse('2026-03-08T00:30:00-08:00');
    final nextMidnight = DateTime.parse('2026-03-09T00:30:00-07:00');
    expect(
      daysSinceInstall(nowUtc: nextMidnight, firstLaunchUtc: first),
      0,
    );
    expect(
      daysSinceInstall(
        nowUtc: nextMidnight.add(const Duration(hours: 1)),
        firstLaunchUtc: first,
      ),
      1,
    );
    expect(
      daysSinceInstall(nowUtc: nextMidnight.toLocal(), firstLaunchUtc: first),
      0,
    );
  });
}

_ControlledPreferences _installStorage(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  final storage = _ControlledPreferences(values);
  SharedPreferencesStorePlatform.instance = storage;
  return storage;
}

final class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences(Map<String, Object> values)
      : super.withData({
          for (final entry in values.entries)
            'flutter.${entry.key}': entry.value,
        });

  bool failReads = false;
  bool failWrites = false;
  bool throwOnWrite = false;
  int writes = 0;
  final writeEntered = Completer<void>();
  Completer<void>? releaseWrite;

  @override
  Future<Map<String, Object>> getAll() {
    if (failReads) throw StateError('Preferences read failed');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    if (!writeEntered.isCompleted) writeEntered.complete();
    await releaseWrite?.future;
    if (failWrites) {
      if (throwOnWrite) throw StateError('Preferences write failed');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
