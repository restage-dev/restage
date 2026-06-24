import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  const full = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
    appVersion: '2.3.1',
    appBuild: '42',
  );

  test('value equality across the field graph', () {
    expect(
      full,
      const AnalyticsAppContext(
        platform: 'ios',
        locale: 'en_US',
        sdkVersion: '1.0.0',
        appVersion: '2.3.1',
        appBuild: '42',
      ),
    );
    const differentPlatform = AnalyticsAppContext(
      platform: 'android',
      locale: 'en_US',
      sdkVersion: '1.0.0',
      appVersion: '2.3.1',
      appBuild: '42',
    );
    expect(full, isNot(differentPlatform));
    expect(full.hashCode, isNot(0));
  });

  test('toJson/fromJson round-trips (incl. optional nulls)', () {
    expect(AnalyticsAppContext.fromJson(full.toJson()), full);
    const minimal = AnalyticsAppContext(
      platform: 'web',
      locale: 'fr',
      sdkVersion: '1.0.0',
    );
    expect(AnalyticsAppContext.fromJson(minimal.toJson()), minimal);
    expect(minimal.toJson().containsKey('appVersion'), isFalse);
  });

  test('fromJson fails loud on a missing required field', () {
    expect(
      () => AnalyticsAppContext.fromJson(
        const {'locale': 'en', 'sdkVersion': '1'},
      ),
      throwsFormatException,
    );
    expect(
      () => AnalyticsAppContext.fromJson(
        const {'platform': 'ios', 'sdkVersion': '1'},
      ),
      throwsFormatException,
    );
  });
}
