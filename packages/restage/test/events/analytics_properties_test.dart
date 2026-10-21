import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  const assignment = SurfaceAssignment(
    experimentId: 'experiment.checkout',
    experimentRevisionId: 'revision.checkout.1',
    experimentEpochId: 'epoch.checkout.1',
    variantId: 'arm.treatment',
  );
  const attribution = SurfaceEventAttribution(
    surfaceId: 'checkout',
    surfaceType: Surface.paywall,
    surfaceVersion: '42',
    assignment: assignment,
  );

  final events = <RestageEvent>[
    const PaywallLoadStarted(attribution: attribution, paywallId: 'checkout'),
    const PaywallLoadCompleted(
      attribution: attribution,
      paywallId: 'checkout',
      loadDuration: Duration(milliseconds: 12),
      cacheHit: true,
    ),
    const PaywallLoadFailed(
      attribution: attribution,
      paywallId: 'checkout',
      errorCode: 'unavailable',
      message: 'private diagnostic',
      retryable: false,
    ),
    const PaywallViewed(
        attribution: attribution, paywallId: 'checkout', publishedVersion: 42),
    const PaywallDismissed(
      attribution: attribution,
      paywallId: 'checkout',
      reason: DismissReason.userClose,
      timeOnPaywall: Duration(seconds: 3),
    ),
    const SurfaceDeliveryRateLimited(
      attribution: attribution,
      surface: Surface.paywall,
      surfaceId: 'checkout',
      retryAfter: Duration(seconds: 7),
    ),
    PagerPageChanged(attribution: attribution, pageIndex: 1, pageCount: 3),
    const SurfacePointPresented(
      attribution: attribution,
      occurrenceId: 'a canonical occurrence',
      lineageId: 'lineage.checkout',
    ),
    const SurfacePointInteracted(
      attribution: attribution,
      occurrenceId: 'a canonical occurrence',
      lineageId: 'lineage.checkout',
    ),
    SurveyQuestionResponded(
        attribution: attribution, questionId: 'intent', questionIndex: 2),
    const PaywallCustomEvent(
      attribution: attribution,
      paywallId: 'checkout',
      eventName: 'selected',
      args: {
        'google_bad_key': 'secret',
        'nested': {'value': true}
      },
    ),
    const FlowUnavailable(
      attribution: attribution,
      flowId: 'welcome',
      flowVersion: 1,
      reason: 'unavailable',
      message: 'private diagnostic',
    ),
    const FlowCustomEvent(
      attribution: attribution,
      flowId: 'welcome',
      flowVersion: 1,
      eventName: 'continued',
      fields: {'firebase_bad_key': 'secret'},
    ),
    const FlowStarted(
        attribution: attribution, flowId: 'welcome', flowVersion: 1),
    const FlowCompleted(
        attribution: attribution, flowId: 'welcome', flowVersion: 1),
    const FlowDismissed(
        attribution: attribution, flowId: 'welcome', flowVersion: 1),
    const OnboardingStepViewed(
      attribution: attribution,
      flowId: 'welcome',
      flowVersion: 1,
      screenId: 'intro',
      stepIndex: 0,
      stepCount: 3,
    ),
    const OnboardingSkipped(
      attribution: attribution,
      flowId: 'welcome',
      flowVersion: 1,
      atScreenId: 'intro',
      stepIndex: 0,
    ),
    const OnboardingPermissionResponse(
      attribution: attribution,
      flowId: 'welcome',
      flowVersion: 1,
      permission: 'notifications',
      granted: true,
    ),
  ];

  test('every concrete event has a vendor-safe name and property shape', () {
    for (final event in events) {
      expect(
        event.name,
        matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')),
        reason: event.runtimeType.toString(),
      );
      expect(_hasReservedPrefix(event.name), isFalse);
      final properties = event.analyticsProperties;
      expect(properties.length, lessThanOrEqualTo(25));
      for (final entry in properties.entries) {
        expect(entry.key, startsWith('restage_'), reason: event.name);
        expect(entry.key, matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')));
        expect(_hasReservedPrefix(entry.key), isFalse);
        expect(entry.value is String || entry.value is num, isTrue);
        if (entry.value case final String value) {
          expect(value.length, lessThanOrEqualTo(100));
          expect(String.fromCharCodes(value.runes), value);
        }
        if (entry.value case final num value) {
          expect(value.isFinite, isTrue);
        }
      }
    }
  });

  test('allowlist excludes authored maps, diagnostics, and session identity',
      () {
    final custom = PaywallCustomEvent(
      paywallId: 'checkout',
      eventName: 'x' * 150,
      args: const {'google_bad_key': 'secret'},
      attribution: attribution,
    );
    final unavailable = FlowUnavailable(
      flowId: 'welcome',
      flowVersion: 1,
      reason: 'r' * 150,
      message: 'do not forward',
      attribution: attribution,
    );
    const started = FlowStarted(
      flowId: 'welcome',
      flowVersion: 1,
      flowSessionId: 'private-session',
      parentFlowSessionId: 'private-parent',
      attribution: attribution,
    );
    const dismissed = FlowDismissed(
      flowId: 'welcome',
      flowVersion: 1,
      flowSessionId: 'private-dismissed-session',
      attribution: attribution,
    );

    expect(custom.analyticsProperties, isNot(contains('google_bad_key')));
    expect(custom.analyticsProperties['restage_event_name'], hasLength(100));
    expect(unavailable.analyticsProperties,
        isNot(containsValue('do not forward')));
    expect(unavailable.analyticsProperties['restage_reason'], hasLength(100));
    expect(started.analyticsProperties.keys,
        isNot(contains(anyOf('flow_session_id', 'restage_flow_session_id'))));
    expect(
      started.analyticsProperties.keys,
      isNot(contains(
          anyOf('parent_flow_session_id', 'restage_parent_flow_session_id'))),
    );
    expect(
      dismissed.analyticsProperties.keys,
      isNot(contains(anyOf('flow_session_id', 'restage_flow_session_id'))),
    );
  });

  test('string truncation stops before splitting a supplementary scalar', () {
    final event = PaywallCustomEvent(
      paywallId: 'checkout',
      eventName: '${'a' * 99}🚀tail',
      args: const {},
      attribution: attribution,
    );

    expect(event.analyticsProperties['restage_event_name'], 'a' * 99);
  });

  test('string projection replaces an unpaired UTF-16 surrogate', () {
    final event = PaywallCustomEvent(
      paywallId: 'checkout',
      eventName: 'a${String.fromCharCode(0xd800)}b',
      args: const {},
      attribution: attribution,
    );

    final projected =
        event.analyticsProperties['restage_event_name']! as String;
    expect(projected, 'a\uFFFDb');
    expect(projected.length, lessThanOrEqualTo(100));
    expect(String.fromCharCodes(projected.runes), projected);
  });

  test('boolean values are integers and null optional values are omitted', () {
    const event = PaywallLoadCompleted(
      paywallId: 'checkout',
      loadDuration: Duration(milliseconds: 4),
      cacheHit: false,
      attribution: attribution,
    );

    expect(event.analyticsProperties['restage_cache_hit'], 0);
    expect(event.analyticsProperties,
        isNot(contains('restage_published_version')));
  });
}

bool _hasReservedPrefix(String value) =>
    value.startsWith('firebase_') ||
    value.startsWith('google_') ||
    value.startsWith('ga_');
