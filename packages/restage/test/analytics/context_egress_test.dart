import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/events/restage_event.dart';
import 'package:restage_shared/legacy_analytics.dart';

const _appContext = AnalyticsAppContext(
  platform: 'ios',
  locale: 'en_US',
  sdkVersion: '2.0.0',
);

const _hostContext = <String, Object?>{
  'trial': <String, Object?>{
    'daysRemaining': 2,
    'usedFeatureIds': <Object?>['export', 'templates'],
  },
  'usage': <String, Object?>{'exportsThisMonth': 3},
};

AnalyticsEvent _map(Map<String, Object?> args) => mapRestageEventToEnvelope(
      PaywallCustomEvent(
        paywallId: 'upgrade',
        eventName: 'continue',
        args: args,
      ),
      eventId: 'event-1',
      anonymousId: 'install-1',
      sessionId: 'session-1',
      appContext: _appContext,
      now: DateTime.utc(2026, 8, 27),
    );

void main() {
  test('nested host context is absent from mapped analytics properties', () {
    final envelope = _map(<String, Object?>{
      'context': _hostContext,
      'safe': 'retained',
    });
    final encoded = jsonEncode(envelope.properties);

    expect(envelope.properties, <String, Object?>{
      'eventName': 'continue',
      'safe': 'retained',
    });
    expect(encoded, isNot(contains('templates')));
    expect(encoded, isNot(contains('exportsThisMonth')));
  });

  test('data and flattened context namespaces are absent', () {
    final envelope = _map(<String, Object?>{
      'data': <String, Object?>{'context': _hostContext},
      'context.trial.daysRemaining': 2,
      'safe': 'retained',
    });

    expect(envelope.properties, <String, Object?>{
      'eventName': 'continue',
      'safe': 'retained',
    });
  });

  test('benign namespace look-alikes remain available', () {
    final envelope = _map(const <String, Object?>{
      'contextual': 'kept-contextual',
      'database': 'kept-database',
      'metadata': 'kept-metadata',
    });

    expect(envelope.properties, <String, Object?>{
      'eventName': 'continue',
      'contextual': 'kept-contextual',
      'database': 'kept-database',
      'metadata': 'kept-metadata',
    });
  });

  test('casing and whitespace cannot bypass reserved namespaces', () {
    final envelope = _map(<String, Object?>{
      'Context': _hostContext,
      ' data': _hostContext,
      'CONTEXT.x': 'hidden',
      'safe': 'retained',
    });

    expect(envelope.properties, <String, Object?>{
      'eventName': 'continue',
      'safe': 'retained',
    });
  });
}
