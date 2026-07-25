import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the metering identity is wired by `Restage.configure`.
///
/// Two design statements are load-bearing here and neither is self-evident from
/// reading the call site:
///
///  1. the metering identity is minted independently of the analytics opt-out —
///     turning analytics off must not turn delivery counting off; and
///  2. the metering identity is sent ONLY to the surface-delivery endpoint, and
///     never appears in the analytics event stream.
///
/// Both are privacy-relevant promises made in the metering store's own
/// documentation, so they are pinned rather than left to code reading.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fast-failing host: the analytics POST is intercepted by the injected
  // client, and the (best-effort) entitlement sync harmlessly returns null.
  const baseUrl = 'http://127.0.0.1:1';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  test('configure installs the metering identity even with analytics disabled',
      () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );

    final key = await SurfaceMeteringKeyProvider.currentKey();
    expect(
      key,
      isNotNull,
      reason: 'delivery counting does not depend on the analytics opt-in',
    );
    expect(
      await SurfaceAssignmentKeyProvider.resolve(),
      isNull,
      reason: 'the experiment-assignment identity DOES follow the opt-out — '
          'the two are deliberately different',
    );
  });

  test('configure without a base URL installs no metering identity', () {
    Restage.configure(apiKey: 'rs_pk_test');

    expect(SurfaceMeteringKeyProvider.currentKey(), completion(isNull));
  });

  test(
      're-configuring without a base URL clears a previously installed '
      'metering identity', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    expect(await SurfaceMeteringKeyProvider.currentKey(), isNotNull);

    Restage.configure(apiKey: 'rs_pk_test');

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('the metering identity is stable across re-configuration', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final first = await SurfaceMeteringKeyProvider.currentKey();

    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    expect(
      await SurfaceMeteringKeyProvider.currentKey(),
      first,
      reason: 'a device must not be recounted just because configure re-ran',
    );
  });

  test('reset clears both the metering identity and its store', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    expect(await SurfaceMeteringKeyProvider.currentKey(), isNotNull);

    Restage.debugReset();

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('the metering identity never appears in an analytics event payload',
      () async {
    http.Request? captured;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      captured = req;
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    // Resolve the key first so it definitely exists while the event is built —
    // otherwise an absent key would make this assertion vacuous.
    final meteringKey = await SurfaceMeteringKeyProvider.currentKey();
    expect(meteringKey, isNotNull);

    Restage.fireEvent(
      const PaywallViewed(paywallId: 'pw-1', productIds: ['p1']),
    );
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();

    expect(captured, isNotNull);
    final body = captured!.body;
    expect(
      body,
      isNot(contains(meteringKey!)),
      reason: 'the delivery-metering identity must not cross into analytics',
    );
    // The analytics stream has its own separate pseudonymous id, and it must
    // NOT be the metering one — otherwise the two identities are joinable.
    final events =
        (jsonDecode(body) as Map<String, Object?>)['events']! as List;
    final envelope = events.single! as Map<String, Object?>;
    expect(envelope['anonymousId'], isNotNull);
    expect(envelope['anonymousId'], isNot(meteringKey));
  });
}
