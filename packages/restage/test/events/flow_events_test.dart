import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('FlowUnavailable is a RestageEvent', () {
    const event = FlowUnavailable(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_descriptor',
      message: 'Flow descriptor was not found.',
    );

    expect(event, isA<RestageEvent>());
  });

  test('FlowUnavailable toMap includes flow-specific payload and firedAt', () {
    final firedAt = DateTime.utc(2026, 5, 22, 12, 30);
    final event = FlowUnavailable(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_descriptor',
      message: 'Flow descriptor was not found.',
      firedAt: firedAt,
    );

    expect(event.name, 'flow_unavailable');
    expect(event.toMap(), {
      'name': 'flow_unavailable',
      'flowId': 'first_run',
      'flowVersion': 1,
      'reason': 'missing_descriptor',
      'message': 'Flow descriptor was not found.',
      'firedAt': firedAt.toIso8601String(),
    });
  });

  test('FlowUnavailable does not reuse paywallId', () {
    const event = FlowUnavailable(
      flowId: 'first_run',
      flowVersion: 1,
      reason: 'missing_descriptor',
      message: 'Flow descriptor was not found.',
    );

    expect(event.toMap(), isNot(contains('paywallId')));
    expect(event.paywallId, isNull);
  });

  test('FlowCustomEvent toMap keeps filtered fields under flow identity', () {
    final firedAt = DateTime.utc(2026, 5, 25, 9, 30);
    final event = FlowCustomEvent(
      flowId: 'first_run',
      flowVersion: 1,
      eventName: 'analyticsTap',
      fields: const {'ctaId': 'primary'},
      firedAt: firedAt,
    );

    expect(event.name, 'flow_custom_event');
    expect(event.paywallId, isNull);
    expect(event.toMap(), {
      'name': 'flow_custom_event',
      'flowId': 'first_run',
      'flowVersion': 1,
      'eventName': 'analyticsTap',
      'fields': {'ctaId': 'primary'},
      'firedAt': firedAt.toIso8601String(),
    });
  });

  test('flow lifecycle events are SDK-authored and bounded', () {
    const started = FlowStarted(flowId: 'first_run', flowVersion: 1);
    const completed = FlowCompleted(flowId: 'first_run', flowVersion: 1);

    expect(started.name, 'flow_started');
    expect(started.paywallId, isNull);
    expect(started.toMap(), {
      'name': 'flow_started',
      'flowId': 'first_run',
      'flowVersion': 1,
    });
    expect(completed.name, 'flow_completed');
    expect(completed.paywallId, isNull);
    expect(completed.toMap(), {
      'name': 'flow_completed',
      'flowId': 'first_run',
      'flowVersion': 1,
    });
  });

  group('OnboardingStepViewed', () {
    test('is a RestageEvent with no paywallId', () {
      const event = OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        screenId: 'welcome',
        stepIndex: 0,
      );

      expect(event, isA<RestageEvent>());
      expect(event.name, 'onboarding_step_viewed');
      expect(event.paywallId, isNull);
      expect(event.toMap(), isNot(contains('paywallId')));
    });

    test('toMap carries flow identity + step properties', () {
      final firedAt = DateTime.utc(2026, 6, 14, 10);
      final event = OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 2,
        flowSessionId: 'flow-sess-1',
        screenId: 'value',
        stepIndex: 1,
        stepCount: 4,
        firedAt: firedAt,
      );

      expect(event.toMap(), {
        'name': 'onboarding_step_viewed',
        'flowId': 'first_run',
        'flowVersion': 2,
        'flowSessionId': 'flow-sess-1',
        'screenId': 'value',
        'stepIndex': 1,
        'stepCount': 4,
        'firedAt': firedAt.toIso8601String(),
      });
    });

    test('toMap omits the optional flowSessionId/stepCount/firedAt', () {
      const event = OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        screenId: 'welcome',
        stepIndex: 0,
      );

      expect(event.toMap(), {
        'name': 'onboarding_step_viewed',
        'flowId': 'first_run',
        'flowVersion': 1,
        'screenId': 'welcome',
        'stepIndex': 0,
      });
    });
  });

  group('OnboardingSkipped', () {
    test('toMap carries flow identity + skip properties', () {
      const event = OnboardingSkipped(
        flowId: 'first_run',
        flowVersion: 1,
        flowSessionId: 'flow-sess-2',
        atScreenId: 'notify',
        stepIndex: 2,
      );

      expect(event, isA<RestageEvent>());
      expect(event.name, 'onboarding_skipped');
      expect(event.paywallId, isNull);
      expect(event.toMap(), {
        'name': 'onboarding_skipped',
        'flowId': 'first_run',
        'flowVersion': 1,
        'flowSessionId': 'flow-sess-2',
        'atScreenId': 'notify',
        'stepIndex': 2,
      });
    });
  });

  group('OnboardingPermissionResponse', () {
    test('toMap carries flow identity + permission/granted (granted)', () {
      const event = OnboardingPermissionResponse(
        flowId: 'first_run',
        flowVersion: 1,
        flowSessionId: 'flow-sess-3',
        permission: 'requestNotifications',
        granted: true,
      );

      expect(event, isA<RestageEvent>());
      expect(event.name, 'onboarding_permission_response');
      expect(event.paywallId, isNull);
      expect(event.toMap(), {
        'name': 'onboarding_permission_response',
        'flowId': 'first_run',
        'flowVersion': 1,
        'flowSessionId': 'flow-sess-3',
        'permission': 'requestNotifications',
        'granted': true,
      });
    });

    test('toMap reports a declined response (granted=false)', () {
      const event = OnboardingPermissionResponse(
        flowId: 'first_run',
        flowVersion: 1,
        permission: 'requestNotifications',
        granted: false,
      );

      expect(event.toMap(), {
        'name': 'onboarding_permission_response',
        'flowId': 'first_run',
        'flowVersion': 1,
        'permission': 'requestNotifications',
        'granted': false,
      });
    });
  });
}
