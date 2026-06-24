import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/analytics/analytics_transport.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  const appContext = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
  );

  AnalyticsEvent event(String id) => AnalyticsEvent(
        eventId: id,
        name: 'paywall_viewed',
        occurredAt: DateTime.utc(2026, 6, 13, 12),
        anonymousId: 'anon-1',
        sessionId: 'sess-1',
        appContext: appContext,
      );

  test('flush POSTs the buffered batch with the bearer key, then clears',
      () async {
    http.Request? captured;
    final transport = AnalyticsTransport(
      endpointUrl: 'https://api.example.com/analytics/events',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      }),
    );

    transport
      ..enqueue(event('e1'))
      ..enqueue(event('e2'));
    await transport.flush();

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(
        captured!.url.toString(), 'https://api.example.com/analytics/events');
    expect(captured!.headers['Authorization'], 'Bearer rs_pk_test');
    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final events = body['events']! as List;
    expect(events.length, 2);
    expect((events.first as Map)['eventId'], 'e1');

    // Buffer cleared on success — a second flush sends nothing.
    captured = null;
    await transport.flush();
    expect(captured, isNull);
  });

  test('a network exception never throws into the caller; batch is retained',
      () async {
    var calls = 0;
    final transport = AnalyticsTransport(
      endpointUrl: 'https://api.example.com/analytics/events',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((req) async {
        calls++;
        if (calls == 1) throw const SocketLikeException();
        return http.Response('', 200);
      }),
    );

    transport.enqueue(event('e1'));
    // Must not throw.
    await transport.flush();
    // The event is retained and resent on the next (successful) flush.
    await transport.flush();
    expect(calls, 2);
  });

  test('a 5xx retains the batch; a 4xx drops it (poison)', () async {
    var status = 500;
    var calls = 0;
    final transport = AnalyticsTransport(
      endpointUrl: 'https://api.example.com/analytics/events',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((req) async {
        calls++;
        return http.Response('', status);
      }),
    );

    transport.enqueue(event('e1'));
    await transport.flush(); // 500 → retained
    expect(calls, 1);

    status = 400;
    await transport.flush(); // 400 → dropped
    expect(calls, 2);
    await transport.flush(); // nothing left to send
    expect(calls, 2);
  });

  test('enqueue auto-flushes when the batch threshold is reached', () async {
    var calls = 0;
    final transport = AnalyticsTransport(
      endpointUrl: 'https://api.example.com/analytics/events',
      apiKey: 'rs_pk_test',
      batchSize: 2,
      httpClient: MockClient((req) async {
        calls++;
        return http.Response('', 200);
      }),
    );

    transport.enqueue(event('e1'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0); // below threshold
    transport.enqueue(event('e2'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1); // threshold reached → auto-flush
  });

  test('the buffer is bounded — oldest dropped beyond maxBufferSize', () async {
    final sent = <String>[];
    final transport = AnalyticsTransport(
      endpointUrl: 'https://api.example.com/analytics/events',
      apiKey: 'rs_pk_test',
      maxBufferSize: 2,
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        for (final e in body['events']! as List) {
          sent.add((e as Map)['eventId']! as String);
        }
        return http.Response('', 200);
      }),
    );

    transport
      ..enqueue(event('e1'))
      ..enqueue(event('e2'))
      ..enqueue(event('e3')); // e1 evicted (oldest)
    await transport.flush();
    expect(sent, ['e2', 'e3']);
  });
}

/// A stand-in throwable for a network failure.
class SocketLikeException implements Exception {
  const SocketLikeException();
}
