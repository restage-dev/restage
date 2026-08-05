import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/src/events/restage_event.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  const appContext = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
  );
  final now = DateTime.utc(2026, 6, 13, 12);

  AnalyticsEvent map(
    RestageEvent event, {
    RootAnalyticsEventBinding? rootAttribution,
    String? surfaceSessionId,
    String? userId,
  }) {
    return mapRestageEventToEnvelope(
      event,
      eventId: 'evt-1',
      anonymousId: 'anon-1',
      sessionId: 'sess-1',
      surfaceSessionId: surfaceSessionId,
      userId: userId,
      appContext: appContext,
      now: now,
      rootAttribution: rootAttribution,
    );
  }

  test(
      'a paywall event maps to surface=paywall without trusting payload '
      'experiment fields', () {
    final firedAt = DateTime.utc(2026, 6, 13, 11, 59);
    final envelope = map(
      PaywallViewed(
        paywallId: 'pw-1',
        productIds: const ['p1'],
        variantId: 'variant-A',
        experimentId: 'exp-1',
        experimentEpoch: 3,
        firedAt: firedAt,
      ),
      surfaceSessionId: 'surf-9',
      userId: 'user-7',
    );
    expect(envelope.name, 'paywall_viewed');
    expect(envelope.surface, AnalyticsSurface.paywall);
    expect(envelope.surfaceId, 'pw-1');
    expect(envelope.surfaceSessionId, 'surf-9');
    expect(envelope.anonymousId, 'anon-1');
    expect(envelope.sessionId, 'sess-1');
    expect(envelope.userId, 'user-7');
    expect(envelope.appContext, appContext);
    expect(envelope.eventId, 'evt-1');
    expect(envelope.occurredAt, firedAt);
    expect(envelope.variantId, isNull);
    expect(envelope.experimentId, isNull);
    expect(envelope.experimentEpoch, isNull);
    expect(envelope.properties.containsKey('variantId'), isFalse);
    expect(envelope.properties.containsKey('experimentId'), isFalse);
    expect(envelope.properties.containsKey('experimentEpoch'), isFalse);
  });

  test('firedAt absent falls back to now', () {
    final envelope =
        map(const PaywallViewed(paywallId: 'pw-1', productIds: []));
    expect(envelope.occurredAt, now);
  });

  test('a flow event maps to surface=onboarding with flow→surface mapping', () {
    final envelope = map(
      const FlowStarted(
        flowId: 'flow-7',
        flowVersion: 3,
        flowSessionId: 'flow-sess-1',
      ),
    );
    expect(envelope.surface, AnalyticsSurface.onboarding);
    expect(envelope.surfaceId, 'flow-7');
    expect(envelope.surfaceVersion, '3');
    expect(envelope.surfaceSessionId, 'flow-sess-1');
  });

  test('PaywallViewed.publishedVersion promotes to envelope surfaceVersion',
      () {
    final envelope = map(
      const PaywallViewed(
        paywallId: 'pw-1',
        productIds: ['p1'],
        publishedVersion: 9,
      ),
    );
    expect(envelope.surfaceVersion, '9');
    // Promoted → typed field only, never duplicated into properties.
    expect(envelope.properties.containsKey('publishedVersion'), isFalse);
  });

  test('promoted conversion dims land on envelope fields, not properties', () {
    final envelope = map(
      const PurchaseSucceeded(
        paywallId: 'pw-1',
        productId: 'prod.monthly',
        transactionId: 'txn-1',
        priceMicros: 9990000,
        currency: 'USD',
      ),
    );
    expect(envelope.productId, 'prod.monthly');
    expect(envelope.properties.containsKey('productId'), isFalse);
    // The non-promoted residual fields stay in properties.
    expect(envelope.properties['transactionId'], 'txn-1');
    expect(envelope.properties['currency'], 'USD');
  });

  test('a custom event cannot smuggle render context into properties', () {
    final envelope = map(
      const PaywallCustomEvent(
        paywallId: 'pw-1',
        eventName: 'tapped_plan',
        args: {
          'plan': 'pro',
          'data': {'context': 'render-secret'},
          'context': 'leak',
        },
      ),
    );
    expect(envelope.properties.containsKey('data'), isFalse);
    expect(envelope.properties.containsKey('context'), isFalse);
    expect(envelope.properties['plan'], 'pro');
    expect(envelope.properties['eventName'], 'tapped_plan');
  });

  test('an app-wide lifecycle event maps to surface=null', () {
    final envelope = map(
      const EntitlementGranted(
        entitlementId: 'pro',
        productId: 'prod.monthly',
        source: EntitlementSource.purchase,
      ),
    );
    expect(envelope.surface, isNull);
    expect(envelope.surfaceId, isNull);
    expect(envelope.productId, 'prod.monthly');
    expect(envelope.properties['entitlementId'], 'pro');
  });

  group('onboarding events conform to the onboarding envelope', () {
    test('onboarding_step_viewed → surface=onboarding + step properties', () {
      final envelope = map(
        const OnboardingStepViewed(
          flowId: 'first_run',
          flowVersion: 2,
          flowSessionId: 'flow-sess-1',
          screenId: 'value',
          stepIndex: 1,
          stepCount: 4,
        ),
      );
      expect(envelope.name, 'onboarding_step_viewed');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceVersion, '2');
      expect(envelope.surfaceSessionId, 'flow-sess-1');
      // Per-event extras land in properties; flow identity rides the envelope.
      expect(envelope.properties, {
        'screenId': 'value',
        'stepIndex': 1,
        'stepCount': 4,
      });
      expect(envelope.properties.containsKey('flowId'), isFalse);
      expect(envelope.properties.containsKey('flowVersion'), isFalse);
      expect(envelope.properties.containsKey('flowSessionId'), isFalse);
    });

    test('onboarding_skipped → surface=onboarding + skip properties', () {
      final envelope = map(
        const OnboardingSkipped(
          flowId: 'first_run',
          flowVersion: 1,
          flowSessionId: 'flow-sess-2',
          atScreenId: 'notify',
          stepIndex: 2,
        ),
      );
      expect(envelope.name, 'onboarding_skipped');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceSessionId, 'flow-sess-2');
      expect(envelope.properties, {'atScreenId': 'notify', 'stepIndex': 2});
    });

    test(
        'onboarding_permission_response → surface=onboarding + '
        'permission/granted', () {
      final envelope = map(
        const OnboardingPermissionResponse(
          flowId: 'first_run',
          flowVersion: 1,
          flowSessionId: 'flow-sess-3',
          permission: 'requestNotifications',
          granted: false,
        ),
      );
      expect(envelope.name, 'onboarding_permission_response');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceSessionId, 'flow-sess-3');
      expect(envelope.properties, {
        'permission': 'requestNotifications',
        'granted': false,
      });
    });

    test(
        'splits contract version (envelope surfaceVersion) from resolved active '
        'version (properties.resolvedVersion)', () {
      final envelope = map(
        const FlowStarted(
          flowId: 'first_run',
          flowVersion: 1,
          resolvedVersion: 9,
          flowSessionId: 'flow-sess-4',
        ),
      );
      // flowVersion is the stable client-contract version → promoted to the
      // typed envelope surfaceVersion.
      expect(envelope.surfaceVersion, '1');
      // resolvedVersion has no typed envelope home → it rides in properties,
      // distinct from the contract version.
      expect(envelope.properties['resolvedVersion'], 9);
    });
  });

  group('production suppression (no zeroed session summary by default)', () {
    test('paywall_session_summary is suppressed; real events are not', () {
      expect(isProdSuppressedAnalyticsEvent('paywall_session_summary'), isTrue);
      expect(isProdSuppressedAnalyticsEvent('paywall_viewed'), isFalse);
      expect(isProdSuppressedAnalyticsEvent('purchase_succeeded'), isFalse);
      expect(isProdSuppressedAnalyticsEvent('flow_started'), isFalse);
    });
  });

  group('authoritative internal root attribution', () {
    test('a child flow outcome inherits the exact rendered root envelope', () {
      const root = RootAnalyticsEventContext(
        identityGeneration: 3,
        surface: 'message',
        surfaceId: 'welcome-message',
        surfaceVersion: '14',
        surfaceSessionId: 'root-session-1',
        experimentId: 'exp-message',
        variantId: 'variant-b',
        experimentEpoch: 8,
      );

      final envelope = map(
        const FlowCustomEvent(
          flowId: 'child-flow',
          flowVersion: 2,
          resolvedVersion: 6,
          eventName: 'cta_tapped',
          fields: <String, Object?>{'cta': 'continue'},
        ),
        rootAttribution: RootAnalyticsEventBinding.active(root),
      );

      expect(envelope.surface, 'message');
      expect(envelope.surfaceId, 'welcome-message');
      expect(envelope.surfaceVersion, '14');
      expect(envelope.surfaceSessionId, 'root-session-1');
      expect(envelope.experimentId, 'exp-message');
      expect(envelope.variantId, 'variant-b');
      expect(envelope.experimentEpoch, 8);
      expect(envelope.properties['eventName'], 'cta_tapped');
      expect(envelope.properties['fields'], <String, Object?>{
        'cta': 'continue',
      });
    });

    test('pre-paint and retired roots cannot trust event assignment fields',
        () {
      final envelope = map(
        const PaywallViewed(
          paywallId: 'upgrade',
          productIds: <String>[],
          publishedVersion: 4,
          experimentId: 'event-exp',
          variantId: 'event-variant',
          experimentEpoch: 99,
        ),
        surfaceSessionId: 'global-slot',
        rootAttribution: const RootAnalyticsEventBinding.anonymous(
          surface: 'paywall',
          surfaceId: 'upgrade',
        ),
      );

      expect(envelope.surface, 'paywall');
      expect(envelope.surfaceId, 'upgrade');
      expect(envelope.surfaceVersion, isNull);
      expect(envelope.surfaceSessionId, isNull);
      expect(envelope.experimentId, isNull);
      expect(envelope.variantId, isNull);
      expect(envelope.experimentEpoch, isNull);
    });

    test('one- and two-field payload triples remain assignment-null', () {
      for (final event in const <PaywallViewed>[
        PaywallViewed(
          paywallId: 'upgrade',
          productIds: <String>[],
          experimentId: 'event-exp',
        ),
        PaywallViewed(
          paywallId: 'upgrade',
          productIds: <String>[],
          variantId: 'event-variant',
          experimentEpoch: 99,
        ),
      ]) {
        final envelope = map(event);
        expect(envelope.experimentId, isNull);
        expect(envelope.variantId, isNull);
        expect(envelope.experimentEpoch, isNull);
      }
    });

    test('active root attribution wins over a conflicting payload triple', () {
      const root = RootAnalyticsEventContext(
        identityGeneration: 3,
        surface: 'paywall',
        surfaceId: 'upgrade',
        surfaceVersion: '4',
        surfaceSessionId: 'root-session-1',
        experimentId: 'root-exp',
        variantId: 'root-variant',
        experimentEpoch: 7,
      );

      final envelope = map(
        const PaywallViewed(
          paywallId: 'upgrade',
          productIds: <String>[],
          experimentId: 'event-exp',
          variantId: 'event-variant',
          experimentEpoch: 99,
        ),
        rootAttribution: RootAnalyticsEventBinding.active(root),
      );

      expect(envelope.experimentId, 'root-exp');
      expect(envelope.variantId, 'root-variant');
      expect(envelope.experimentEpoch, 7);
    });
  });
}
