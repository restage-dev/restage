import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  MeteringTokenStore createStore() {
    return MeteringTokenStore(prefsProvider: () async => prefs);
  }

  test('mints and persists a valid UUIDv4 on first getOrCreate', () async {
    final store = createStore();

    final token = await store.getOrCreate();

    expect(MeteringTokenStore.isValidUuid(token), isTrue);
    expect(prefs.getString('restage.metering_token'), token);
  });

  test('returns the same cached value on subsequent calls', () async {
    final store = createStore();

    final first = await store.getOrCreate();
    await prefs.remove('restage.metering_token');
    final second = await store.getOrCreate();

    expect(second, first);
    expect(store.cached, first);
  });

  test('a fresh store over empty prefs mints a new token', () async {
    final first = await createStore().getOrCreate();
    await prefs.clear();

    final second = await createStore().getOrCreate();

    expect(second, isNot(first));
    expect(MeteringTokenStore.isValidUuid(second), isTrue);
  });

  test('returns an existing valid persisted token as-is', () async {
    const token = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
    await prefs.setString('restage.metering_token', token);

    final result = await createStore().getOrCreate();

    expect(result, token);
  });

  test('replaces a corrupt persisted value', () async {
    await prefs.setString('restage.metering_token', 'corrupt');

    final result = await createStore().getOrCreate();

    expect(result, isNot('corrupt'));
    expect(MeteringTokenStore.isValidUuid(result), isTrue);
    expect(prefs.getString('restage.metering_token'), result);
  });
}
