import 'dart:io';

import 'package:restage_shared/legacy_analytics.dart';
import 'package:test/test.dart';

void main() {
  const ctx = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
  );
  final occurred = DateTime.utc(2026, 6, 13, 12, 30);

  AnalyticsEvent clientEvent() => AnalyticsEvent(
        eventId: 'e-1',
        name: 'paywall_viewed',
        occurredAt: occurred,
        surfaceId: 'pw-1',
        anonymousId: 'anon-1',
        sessionId: 'sess-1',
        surfaceSessionId: 'surf-1',
        appContext: ctx,
        properties: const {'plan': 'pro'},
      );

  group('value semantics', () {
    test('value equality across the field graph', () {
      expect(clientEvent(), clientEvent());
      expect(
        clientEvent(),
        isNot(
          AnalyticsEvent(
            eventId: 'e-2',
            name: 'paywall_viewed',
            occurredAt: occurred,
            anonymousId: 'anon-1',
            sessionId: 'sess-1',
            appContext: ctx,
          ),
        ),
      );
      expect(clientEvent().hashCode, clientEvent().hashCode);
    });
  });

  group('toJson/fromJson', () {
    test('client event round-trips', () {
      final event = clientEvent();
      final json = event.toJson();
      expect(
        AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        event,
      );
    });

    test('property scrubbing survives construction, decoding, and round-trip',
        () {
      const properties = <String, Object?>{
        'data': 'top-level',
        'context': 'top-level',
        'result': <String, Object?>{
          'data': <String, Object?>{'context': 'local'},
          'context': 'nested',
          'data.context.locale': 'en_US',
          'ExPeRiMeNtId': 'exp-1',
          'items': <Object?>[
            <String, Object?>{
              'vArIaNtId': 'variant-a',
              'value': 42,
            },
            <String, Object?>{
              'nested': <String, Object?>{
                'eXpErImEnTePoCh': 7,
                'Context': 'preserve',
              },
            },
          ],
        },
      };
      const expectedProperties = <String, Object?>{
        'result': <String, Object?>{
          'data': <String, Object?>{'context': 'local'},
          'context': 'nested',
          'data.context.locale': 'en_US',
          'items': <Object?>[
            <String, Object?>{'value': 42},
            <String, Object?>{
              'nested': <String, Object?>{'Context': 'preserve'},
            },
          ],
        },
      };

      final constructed = AnalyticsEvent(
        eventId: 'e-properties',
        name: 'paywall_viewed',
        occurredAt: occurred,
        anonymousId: 'a',
        sessionId: 's',
        appContext: ctx,
        properties: properties,
      );
      final decoded = AnalyticsEvent.fromJson(
        <String, Object?>{
          ...clientEvent().toJson(),
          'properties': properties,
        },
        source: AnalyticsSource.client,
      );
      final roundTripped = AnalyticsEvent.fromJson(
        decoded.toJson(),
        source: AnalyticsSource.client,
      );

      expect(constructed.properties, expectedProperties);
      expect(constructed.toJson()['properties'], expectedProperties);
      expect(decoded.properties, expectedProperties);
      expect(roundTripped.toJson()['properties'], expectedProperties);
    });

    test('schemaVersion defaults to 1 and survives the round-trip', () {
      expect(clientEvent().schemaVersion, 1);
      final json = clientEvent().toJson();
      expect(json['schemaVersion'], 1);
    });

    test('an unknown surface/platform string is preserved (not rejected)', () {
      final event = AnalyticsEvent(
        eventId: 'e-9',
        name: 'future_event',
        occurredAt: occurred,
        surface: 'hologram',
        anonymousId: 'a',
        sessionId: 's',
        appContext: const AnalyticsAppContext(
          platform: 'visionos',
          locale: 'en',
          sdkVersion: '1',
        ),
      );
      final decoded = AnalyticsEvent.fromJson(
        event.toJson(),
        source: AnalyticsSource.client,
      );
      expect(decoded.surface, 'hologram');
      expect(decoded.appContext!.platform, 'visionos');
    });
  });

  group('source-conditional required fields (forward-compat)', () {
    test(
        'source=client fails loud when appContext/sessionId/anonymousId absent',
        () {
      final missingCtx = {
        'eventId': 'e',
        'name': 'paywall_viewed',
        'occurredAt': occurred.toIso8601String(),
        'anonymousId': 'a',
        'sessionId': 's',
      };
      expect(
        () =>
            AnalyticsEvent.fromJson(missingCtx, source: AnalyticsSource.client),
        throwsFormatException,
      );
      final missingSession = {
        'eventId': 'e',
        'name': 'paywall_viewed',
        'occurredAt': occurred.toIso8601String(),
        'anonymousId': 'a',
        'appContext': ctx.toJson(),
      };
      expect(
        () => AnalyticsEvent.fromJson(
          missingSession,
          source: AnalyticsSource.client,
        ),
        throwsFormatException,
      );
    });

    test('source=server allows identity/context absent and surface=null', () {
      final serverJson = {
        'eventId': 'srv-1',
        'name': 'subscription_renewed',
        'occurredAt': occurred.toIso8601String(),
        // no surface, no appContext, no sessionId/anonymousId
      };
      final decoded =
          AnalyticsEvent.fromJson(serverJson, source: AnalyticsSource.server);
      expect(decoded.surface, isNull);
      expect(decoded.appContext, isNull);
      expect(decoded.anonymousId, isNull);
    });
  });

  group('immutability', () {
    test('properties is defensively unmodifiable', () {
      final event = clientEvent();
      expect(() => event.properties['injected'] = 1, throwsUnsupportedError);
    });

    test('mutating the source map after construction does not leak in', () {
      final mutable = <String, Object?>{'plan': 'pro'};
      final event = AnalyticsEvent(
        eventId: 'e',
        name: 'paywall_viewed',
        occurredAt: occurred,
        anonymousId: 'a',
        sessionId: 's',
        appContext: ctx,
        properties: mutable,
      );
      mutable['leaked'] = true;
      expect(event.properties.containsKey('leaked'), isFalse);
    });

    test('properties is deeply unmodifiable (nested maps/lists frozen too)',
        () {
      // Mutable input (held in a variable, not a const literal) so the test
      // proves the constructor performs the deep freeze.
      final mutableProps = <String, Object?>{
        'nested': <String, Object?>{'k': 'v'},
        'list': <Object?>[1, 2],
      };
      final event = AnalyticsEvent(
        eventId: 'e',
        name: 'paywall_viewed',
        occurredAt: occurred,
        anonymousId: 'a',
        sessionId: 's',
        appContext: ctx,
        properties: mutableProps,
      );
      expect(
        () => (event.properties['nested']! as Map)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(
        () => (event.properties['list']! as List).add(3),
        throwsUnsupportedError,
      );
    });
  });

  group('client identity must be non-empty (not just non-null)', () {
    Map<String, Object?> base() => {
          'eventId': 'e',
          'name': 'paywall_viewed',
          'occurredAt': occurred.toIso8601String(),
          'anonymousId': 'a',
          'sessionId': 's',
          'appContext': ctx.toJson(),
        };

    test('empty sessionId → FormatException', () {
      final json = base()..['sessionId'] = '';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });

    test('whitespace anonymousId → FormatException', () {
      final json = base()..['anonymousId'] = '   ';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });

    test('empty eventId → FormatException (the idempotency key)', () {
      final json = base()..['eventId'] = '';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });
  });

  group('decode robustness — fail loud, never an uncaught cast error', () {
    Map<String, Object?> base() => {
          'eventId': 'e',
          'name': 'paywall_viewed',
          'occurredAt': occurred.toIso8601String(),
          'anonymousId': 'a',
          'sessionId': 's',
          'appContext': ctx.toJson(),
        };

    test('appContext present but not a map → FormatException', () {
      final json = base()..['appContext'] = 'not-a-map';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });

    test('properties present but not a map → FormatException', () {
      final json = base()..['properties'] = 'not-a-map';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });

    test('schemaVersion present but not an int → FormatException', () {
      final json = base()..['schemaVersion'] = 'one';
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });

    test('retired assignment fields are rejected by presence', () {
      for (final field in const [
        'variantId',
        'experimentId',
        'experimentEpoch',
      ]) {
        for (final value in <Object?>[null, 'legacy', 3]) {
          final json = base()..[field] = value;
          expect(
            () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
            throwsFormatException,
            reason: '$field with value $value was accepted',
          );
        }
      }
    });

    test('unrelated additive fields remain ignored', () {
      final json = base()..['futureEnvelopeField'] = 'preserved-by-reader';
      expect(
        AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        isA<AnalyticsEvent>(),
      );
    });

    test('occurredAt a non-string → FormatException', () {
      final json = base()..['occurredAt'] = 12345;
      expect(
        () => AnalyticsEvent.fromJson(json, source: AnalyticsSource.client),
        throwsFormatException,
      );
    });
  });

  group('tier/source are NOT envelope fields (the spoof boundary)', () {
    test('a client JSON carrying tier/source does not populate the envelope',
        () {
      final spoof = {
        'eventId': 'e',
        'name': 'paywall_viewed',
        'occurredAt': occurred.toIso8601String(),
        'anonymousId': 'a',
        'sessionId': 's',
        'appContext': ctx.toJson(),
        // Spoof attempt — these are server-stamped, never envelope fields.
        'tier': 'tier1',
        'source': 'server',
      };
      final decoded =
          AnalyticsEvent.fromJson(spoof, source: AnalyticsSource.client);
      // The re-encoded envelope must not echo tier/source back.
      expect(decoded.toJson().containsKey('tier'), isFalse);
      expect(decoded.toJson().containsKey('source'), isFalse);
    });
  });

  test('properties documentation states the reserved-key contract', () {
    final source = File(
      'lib/src/legacy_analytics/analytics_event.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('`data` and `context` are reserved top-level keys'),
    );
    expect(
      source,
      contains('reservation is the top-level namespace only'),
    );
    expect(
      source,
      contains('Retired property keys are removed at every\n  /// map depth'),
    );
  });
}
