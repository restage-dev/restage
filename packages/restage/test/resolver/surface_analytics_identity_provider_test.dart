import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_analytics_identity_provider.dart';

void main() {
  const identifier = '12345678-1234-4234-8234-123456789abc';

  setUp(SurfaceAnalyticsIdentityProvider.clear);
  tearDown(SurfaceAnalyticsIdentityProvider.clear);

  test('replacing the provider advances its generation', () {
    Future<String?> provider() async => identifier;
    final initial = SurfaceAnalyticsIdentityProvider.generation;
    SurfaceAnalyticsIdentityProvider.install(provider);
    final installed = SurfaceAnalyticsIdentityProvider.generation;
    expect(installed, greaterThan(initial));
    SurfaceAnalyticsIdentityProvider.install(provider);
    expect(SurfaceAnalyticsIdentityProvider.generation, installed);
    SurfaceAnalyticsIdentityProvider.install(() async => identifier);
    expect(SurfaceAnalyticsIdentityProvider.generation, greaterThan(installed));
  });

  test('every clear advances the generation even without a provider', () {
    final initial = SurfaceAnalyticsIdentityProvider.generation;
    SurfaceAnalyticsIdentityProvider.clear();
    final cleared = SurfaceAnalyticsIdentityProvider.generation;
    expect(cleared, greaterThan(initial));
    SurfaceAnalyticsIdentityProvider.clear();
    expect(SurfaceAnalyticsIdentityProvider.generation, greaterThan(cleared));
  });

  test('not installed returns null', () async {
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), isNull);
  });

  test('returns a valid lowercase identifier', () async {
    SurfaceAnalyticsIdentityProvider.install(() async => identifier);
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), identifier);
  });

  for (final value in ['not-a-uuid', '', identifier.substring(1)]) {
    test('drops malformed identifier "$value"', () async {
      SurfaceAnalyticsIdentityProvider.install(() async => value);
      expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), isNull);
    });
  }

  test('provider failure returns null', () async {
    SurfaceAnalyticsIdentityProvider.install(
        () async => throw StateError('prefs'));
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), isNull);
  });

  test('clear removes the provider', () async {
    SurfaceAnalyticsIdentityProvider.install(() async => identifier);
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), identifier);
    SurfaceAnalyticsIdentityProvider.clear();
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), isNull);
  });

  test('each read invokes the provider', () async {
    var calls = 0;
    SurfaceAnalyticsIdentityProvider.install(() async {
      calls += 1;
      return identifier;
    });
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), identifier);
    expect(await SurfaceAnalyticsIdentityProvider.anonymousId(), identifier);
    expect(calls, 2);
  });
}
