import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fast-failing entitlement endpoint (no DNS) — the analytics POST is
  // intercepted by the injected MockClient, so only the (best-effort, fail-safe)
  // entitlement sync touches this and harmlessly returns null.
  const baseUrl = 'http://127.0.0.1:1';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  Future<List<Object?>> firedEvents(void Function() fire) async {
    http.Request? captured;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      captured = req;
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    fire();
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
    if (captured == null) return const [];
    expect(captured!.headers['Authorization'], 'Bearer rs_pk_test');
    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    return body['events']! as List;
  }

  test('a fired paywall event posts a mapped envelope to ingest', () async {
    final events = await firedEvents(() {
      Restage.fireEvent(
        const PaywallViewed(paywallId: 'pw-1', productIds: ['p1']),
      );
    });
    expect(events, hasLength(1));
    final envelope = events.single! as Map<String, Object?>;
    expect(envelope['name'], 'paywall_viewed');
    expect(envelope['surface'], 'paywall');
    expect(envelope['surfaceId'], 'pw-1');
    expect(envelope['anonymousId'], isNotNull);
    expect(envelope['sessionId'], isNotNull);
    // Server-stamped fields are never on the client wire.
    expect(envelope.containsKey('tier'), isFalse);
    expect(envelope.containsKey('source'), isFalse);
  });

  test('track posts a custom event with reserved keys scrubbed', () async {
    final events = await firedEvents(() {
      Restage.track('button_clicked', args: {
        'label': 'upgrade',
        'data': {'context': 'render-secret'},
      });
    });
    expect(events, hasLength(1));
    final envelope = events.single! as Map<String, Object?>;
    expect(envelope['name'], 'button_clicked');
    final properties = envelope['properties']! as Map<String, Object?>;
    expect(properties['label'], 'upgrade');
    expect(properties.containsKey('data'), isFalse);
  });

  test('with no baseUrl, track/fireEvent are inert (no transport)', () async {
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      fail('analytics must not POST when no baseUrl is configured');
    });
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.track('button_clicked');
    Restage.fireEvent(
      const PaywallViewed(paywallId: 'pw-1', productIds: []),
    );
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
  });

  test('analyticsEnabled:false stays inert with a baseUrl', () async {
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      fail('analytics must not POST when analyticsEnabled is false');
    });
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );
    Restage.track('button_clicked');
    Restage.fireEvent(
      const PaywallViewed(paywallId: 'pw-1', productIds: []),
    );
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
  });
}
