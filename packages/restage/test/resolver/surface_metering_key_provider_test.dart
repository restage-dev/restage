import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SurfaceMeteringKeyProvider.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(SurfaceMeteringKeyProvider.clear);

  test('currentKey returns null when nothing is installed', () async {
    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('currentKey returns the installed store token', () async {
    const token = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('restage.metering_token', token);
    final store = MeteringTokenStore(prefsProvider: () async => prefs);

    SurfaceMeteringKeyProvider.install(store: store);

    expect(await SurfaceMeteringKeyProvider.currentKey(), token);
  });

  test('clear makes currentKey return null again', () async {
    const token = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('restage.metering_token', token);
    final store = MeteringTokenStore(prefsProvider: () async => prefs);
    SurfaceMeteringKeyProvider.install(store: store);

    SurfaceMeteringKeyProvider.clear();

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('a store whose storage throws yields null instead of throwing',
      () async {
    // This is a delivery-safety property, not a metering one: currentKey is
    // awaited while building a surface-fetch request, so a thrown exception
    // here would abort the fetch and leave the surface unavailable. A storage
    // fault must degrade to "no key" — the serve still happens, it is just not
    // attributed to a distinct device.
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () async => throw StateError('storage unavailable'),
      ),
    );

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('a store whose storage fails asynchronously also yields null', () async {
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () => Future<SharedPreferences>.error(
          StateError('storage unavailable'),
        ),
      ),
    );

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('installing a second store replaces the first', () async {
    const first = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
    const second = '3f1e5b62-9c4a-4d18-9f0e-72a6c5b3d841';
    final prefsA = await _prefsWithToken(first);
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(prefsProvider: () async => prefsA),
    );
    expect(await SurfaceMeteringKeyProvider.currentKey(), first);

    final prefsB = await _prefsWithToken(second);
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(prefsProvider: () async => prefsB),
    );

    expect(await SurfaceMeteringKeyProvider.currentKey(), second);
  });
}

Future<SharedPreferences> _prefsWithToken(String token) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restage.metering_token': token,
  });
  return SharedPreferences.getInstance();
}
