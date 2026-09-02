import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fast-failing host: the analytics POST is intercepted by the injected
  // MockClient.
  const baseUrl = 'http://127.0.0.1:1';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  Future<List<Object?>> firedEvents(void Function() fire) async {
    final captured = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      captured.add(req);
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    fire();
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
    final events = <Object?>[];
    for (final request in captured) {
      expect(request.headers['Authorization'], 'Bearer rs_pk_test');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      events.addAll(body['events']! as List);
    }
    return events;
  }

  Future<List<Map<String, Object?>>> capturedEvents(
    List<http.Request> requests,
  ) async {
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
    return <Map<String, Object?>>[
      for (final request in requests)
        for (final event in (jsonDecode(request.body)
            as Map<String, Object?>)['events']! as List)
          (event! as Map).cast<String, Object?>(),
    ];
  }

  test('a fired paywall event posts a mapped envelope to ingest', () async {
    final events = await firedEvents(() {
      Restage.fireEvent(const PaywallViewed(paywallId: 'pw-1'));
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

  test('the facade serializes the drop-off property contract exactly',
      () async {
    final events = await firedEvents(() {
      Restage.fireEvent(
        const OnboardingStepViewed(
          flowId: 'first_run',
          flowVersion: 1,
          screenId: 'welcome',
          stepIndex: 0,
        ),
      );
      Restage.fireEvent(
        const OnboardingSkipped(
          flowId: 'first_run',
          flowVersion: 1,
          atScreenId: 'welcome',
          stepIndex: 0,
        ),
      );
      Restage.fireEvent(
        const FlowCustomEvent(
          flowId: 'first_run',
          flowVersion: 1,
          eventName: 'continue',
          fields: <String, Object?>{},
        ),
      );
      Restage.fireEvent(
        const PaywallCustomEvent(
          paywallId: 'upgrade',
          eventName: 'continue',
          args: <String, Object?>{},
        ),
      );
      Restage.fireEvent(PagerPageChanged(pageIndex: 1, pageCount: 3));
      Restage.fireEvent(
        SurveyQuestionResponded(questionId: 'favoriteColor', questionIndex: 0),
      );
    });
    final byName = <String, Map<String, Object?>>{
      for (final raw in events)
        (raw! as Map<String, Object?>)['name']! as String:
            raw as Map<String, Object?>,
    };

    Map<String, Object?> propertiesFor(String name) =>
        (byName[name]!['properties']! as Map).cast<String, Object?>();

    expect(propertiesFor('onboarding_step_viewed'),
        containsPair('screenId', 'welcome'));
    expect(
        propertiesFor('onboarding_step_viewed'), containsPair('stepIndex', 0));
    expect(propertiesFor('onboarding_skipped'),
        containsPair('atScreenId', 'welcome'));
    expect(propertiesFor('flow_custom_event'),
        containsPair('eventName', 'continue'));
    expect(
      propertiesFor('paywall_custom_event'),
      containsPair('eventName', 'continue'),
    );
    expect(propertiesFor('page_changed'), <String, Object?>{
      'pageIndex': 1,
      'pageCount': 3,
    });
    expect(propertiesFor('paywall_survey_responded'), <String, Object?>{
      'questionId': 'favoriteColor',
      'questionIndex': 0,
    });
  });

  test('paywall_viewed posts immediately without waiting for batch size',
      () async {
    http.Request? captured;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      captured = req;
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    Restage.fireEvent(const PaywallViewed(paywallId: 'pw-1'));
    await pumpEventQueue();

    expect(captured, isNotNull);
  });

  test(
      'onboarding_step_viewed posts immediately without waiting for batch size',
      () async {
    http.Request? captured;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      captured = req;
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    Restage.fireEvent(
      const OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        flowSessionId: 'flow-session-1',
        screenId: 'welcome',
        stepIndex: 0,
      ),
    );
    await pumpEventQueue();

    expect(captured, isNotNull);
  });

  test('transient exposure flush failure keeps the event retryable', () async {
    var calls = 0;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      calls += 1;
      return http.Response('', calls == 1 ? 500 : 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    Restage.fireEvent(const PaywallViewed(paywallId: 'pw-1'));
    await pumpEventQueue();

    expect(calls, 1);
    await Restage.debugFlushAnalytics();
    expect(calls, 2);
  });

  test('app pause flushes pending analytics below the batch size', () async {
    var calls = 0;
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      calls += 1;
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    Restage.fireEvent(
      const PaywallDismissed(
        paywallId: 'pw-1',
        reason: DismissReason.userClose,
        timeOnPaywall: Duration(seconds: 3),
      ),
    );
    await pumpEventQueue();
    expect(calls, 0);

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await pumpEventQueue();

    expect(calls, 1);
  });

  test('with no baseUrl, fireEvent is inert (no transport)', () async {
    Restage.debugAnalyticsHttpClient = MockClient((req) async {
      fail('analytics must not POST when no baseUrl is configured');
    });
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.fireEvent(const PaywallViewed(paywallId: 'pw-1'));
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
    Restage.fireEvent(const PaywallViewed(paywallId: 'pw-1'));
    await pumpEventQueue();
    await Restage.debugFlushAnalytics();
  });

  test(
      'activating a root emits canonical surface_presented immediately '
      'without entering the public event stream', () async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    final publicEvents = <RestageEvent>[];
    final subscription = Restage.events.listen(publicEvents.add);
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'welcome-message',
    )..stage(surfaceVersion: '14');

    presentation.activate();

    final events = await capturedEvents(requests);
    expect(events, hasLength(1));
    expect(events.single, containsPair('name', 'surface_presented'));
    expect(events.single, containsPair('surface', 'message'));
    expect(events.single, containsPair('surfaceId', 'welcome-message'));
    expect(events.single, containsPair('surfaceVersion', '14'));
    expect(events.single['surfaceSessionId'], isNotNull);
    expect(publicEvents, isEmpty);
    await subscription.cancel();
  });

  test('an offline canonical presentation remains retryable with its snapshot',
      () async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', requests.length == 1 ? 500 : 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'offline-message',
    )..stage(surfaceVersion: '2');

    presentation.activate();
    await pumpEventQueue();
    expect(requests, hasLength(1));

    await Restage.debugFlushAnalytics();
    expect(requests, hasLength(2));
    final retried = ((jsonDecode(requests.last.body)
            as Map<String, Object?>)['events']! as List)
        .single! as Map<String, Object?>;
    expect(retried['name'], 'surface_presented');
    expect(retried['surfaceSessionId'], isNotNull);
  });

  test('same-authority configure preserves an offline buffered canonical event',
      () async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', requests.length == 1 ? 500 : 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'buffered-message',
    )..stage(surfaceVersion: '6');

    presentation.activate();
    await pumpEventQueue();
    expect(requests, hasLength(1));

    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    await Restage.debugFlushAnalytics();

    expect(requests, hasLength(2));
    final first = ((jsonDecode(requests.first.body)
            as Map<String, Object?>)['events']! as List)
        .single! as Map<String, Object?>;
    final retried = ((jsonDecode(requests.last.body)
            as Map<String, Object?>)['events']! as List)
        .single! as Map<String, Object?>;
    expect(retried['eventId'], first['eventId']);
    expect(retried['surface'], 'message');
    expect(retried['surfaceId'], 'buffered-message');
    expect(retried['surfaceVersion'], '6');
    expect(retried['surfaceSessionId'], isNotNull);
  });

  test('reset after fire cannot rewrite that event root attribution', () async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'survey',
      surfaceId: 'activation-survey',
    )..stage(surfaceVersion: '3');
    presentation.activate();
    await pumpEventQueue();
    requests.clear();

    presentation.runWithEventContext(() {
      Restage.fireEvent(
        const FlowCustomEvent(
          flowId: 'nested-flow',
          flowVersion: 1,
          eventName: 'answer_submitted',
          fields: <String, Object?>{},
        ),
      );
    });
    Restage.reset();

    final events = await capturedEvents(requests);
    final envelope = events.singleWhere(
      (event) => event['name'] == 'flow_custom_event',
    );
    expect(envelope['surface'], 'survey');
    expect(envelope['surfaceId'], 'activation-survey');
    expect(envelope['surfaceVersion'], '3');
    expect(envelope['surfaceSessionId'], isNotNull);
  });

  test(
      'canonical event id and time are captured at paint acknowledgement '
      'before a cold anonymous-id lookup', () async {
    final requests = <http.Request>[];
    final preferences = Completer<SharedPreferences>();
    var nextId = 0;
    final paintTime = DateTime.utc(2026, 7, 29, 17, 30, 12, 345);
    var currentTime = paintTime;
    RootAnalyticsRuntime.debugIdentityFactory = () => AnalyticsIdentity(
          prefsProvider: () => preferences.future,
          newId: () => 'id-${nextId++}',
        );
    RootAnalyticsRuntime.debugClock = () => currentTime;
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'cold-start',
    )..stage(surfaceVersion: '1');

    presentation.activate();
    currentTime = paintTime.add(const Duration(hours: 4));
    Restage.reset();
    preferences.complete(await SharedPreferences.getInstance());

    final canonical = (await capturedEvents(requests)).singleWhere(
      (event) => event['name'] == 'surface_presented',
    );
    expect(canonical['eventId'], 'id-1');
    expect(canonical['occurredAt'], paintTime.toIso8601String());
    expect(canonical['surface'], 'message');
    expect(canonical['surfaceId'], 'cold-start');
    expect(canonical['surfaceVersion'], '1');
    expect(canonical['surfaceSessionId'], 'id-0');
  });

  test('reset before a deferred outcome strips root assignment', () async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(surfaceVersion: '9');
    presentation.activate();
    await pumpEventQueue();
    requests.clear();
    final deferred = presentation.captureDeferredContext();
    presentation.dispose();

    Restage.reset();
    deferred.runWithEventContext(() {
      Restage.fireEvent(
        const PaywallDismissed(
          paywallId: 'upgrade',
          reason: DismissReason.userClose,
          timeOnPaywall: Duration(seconds: 1),
        ),
      );
    });

    final events = await capturedEvents(requests);
    final envelope = events.singleWhere(
      (event) => event['name'] == 'paywall_dismissed',
    );
    expect(envelope['surface'], 'paywall');
    expect(envelope['surfaceId'], 'upgrade');
    expect(envelope['surfaceVersion'], isNull);
    expect(envelope['surfaceSessionId'], isNull);
  });

  for (final boundary in <String>[
    'api key',
    'endpoint',
    'environment',
    'analytics disable',
  ]) {
    test(
        '$boundary retirement permanently strips a deferred root after '
        're-enable', () async {
      final requests = <http.Request>[];
      Restage.debugAnalyticsHttpClient = MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      });
      Restage.configure(
        apiKey: 'rs_pk_authority_a',
        baseUrl: baseUrl,
      );
      final presentation = RootAnalyticsRuntime.createPresentation(
        surface: 'paywall',
        surfaceId: 'upgrade',
      )..stage(surfaceVersion: '9');
      presentation.activate();
      await capturedEvents(requests);
      requests.clear();
      final deferred = presentation.captureDeferredContext();
      presentation.dispose();

      switch (boundary) {
        case 'api key':
          Restage.configure(
            apiKey: 'rs_pk_authority_b',
            baseUrl: baseUrl,
          );
          break;
        case 'endpoint':
          Restage.configure(
            apiKey: 'rs_pk_authority_a',
            baseUrl: 'http://127.0.0.1:2',
          );
          break;
        case 'environment':
          Restage.configure(
            apiKey: 'rs_pk_authority_a',
            baseUrl: baseUrl,
            environment: RestageEnvironment.sandbox,
          );
          break;
        case 'analytics disable':
          Restage.configure(
            apiKey: 'rs_pk_authority_a',
            baseUrl: baseUrl,
            analyticsEnabled: false,
          );
          break;
      }
      Restage.configure(
        apiKey: 'rs_pk_authority_a',
        baseUrl: baseUrl,
      );

      deferred.runWithEventContext(() {
        Restage.fireEvent(
          const PaywallDismissed(
            paywallId: 'upgrade',
            reason: DismissReason.userClose,
            timeOnPaywall: Duration(seconds: 1),
          ),
        );
      });

      final events = await capturedEvents(requests);
      final envelope = events.singleWhere(
        (event) => event['name'] == 'paywall_dismissed',
      );
      expect(envelope['surface'], 'paywall');
      expect(envelope['surfaceId'], 'upgrade');
      expect(envelope['surfaceVersion'], isNull);
      expect(envelope['surfaceSessionId'], isNull);
    });
  }
}
