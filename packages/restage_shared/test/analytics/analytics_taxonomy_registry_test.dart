import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('the registered taxonomy', () {
    test('every existing Tier-1 SDK event resolves to tier1', () {
      const tier1Names = <String>[
        'paywall_load_started',
        'paywall_load_completed',
        'paywall_load_failed',
        'paywall_viewed',
        'paywall_dismissed',
        'paywall_custom_event',
        'purchase_initiated',
        'purchase_succeeded',
        'purchase_pending',
        'purchase_cancelled',
        'purchase_failed',
        'restore_initiated',
        'restore_succeeded',
        'restore_no_purchases',
        'restore_failed',
        'entitlement_granted',
        'entitlement_revoked',
        'subscription_renewed',
        'subscription_lapsed',
        'flow_started',
        'flow_completed',
        'flow_unavailable',
        'flow_custom_event',
      ];
      for (final name in tier1Names) {
        expect(isRegisteredAnalyticsEvent(name), isTrue, reason: name);
        expect(tierForEvent(name), AnalyticsTier.tier1, reason: name);
      }
    });

    test('the funnel terminator + survey event are registered Tier 1', () {
      expect(tierForEvent('paywall_load_aborted'), AnalyticsTier.tier1);
      expect(tierForEvent('paywall_survey_responded'), AnalyticsTier.tier1);
    });

    test('the blessed onboarding events carry their required properties', () {
      expect(
        lookupAnalyticsEvent('onboarding_step_viewed').requiredProperties,
        containsAll(<String>['screenId', 'stepIndex']),
      );
      expect(
        lookupAnalyticsEvent('onboarding_skipped').requiredProperties,
        containsAll(<String>['atScreenId', 'stepIndex']),
      );
      expect(
        lookupAnalyticsEvent('onboarding_permission_response')
            .requiredProperties,
        containsAll(<String>['permission', 'granted']),
      );
      expect(tierForEvent('onboarding_step_viewed'), AnalyticsTier.tier1);
    });

    test('paywall_session_summary is the sole Tier-2 event', () {
      expect(tierForEvent('paywall_session_summary'), AnalyticsTier.tier2);
    });
  });

  group('soft-allow unknown names (never reject)', () {
    test('an unknown name resolves to tier1 and is flagged unregistered', () {
      expect(isRegisteredAnalyticsEvent('totally_made_up'), isFalse);
      expect(tierForEvent('totally_made_up'), AnalyticsTier.tier1);
      expect(
        lookupAnalyticsEvent('totally_made_up').requiredProperties,
        isEmpty,
      );
    });
  });

  group('AnalyticsEventSpec value semantics', () {
    test('equality + hashCode', () {
      expect(
        AnalyticsEventSpec(tier: AnalyticsTier.tier1),
        AnalyticsEventSpec(tier: AnalyticsTier.tier1),
      );
      expect(
        AnalyticsEventSpec(tier: AnalyticsTier.tier1),
        isNot(AnalyticsEventSpec(tier: AnalyticsTier.tier2)),
      );
    });

    test('requiredProperties is defensively unmodifiable', () {
      // Mutable input so the test proves the constructor wraps it.
      final mutableProps = <String>{'a'};
      final spec = AnalyticsEventSpec(
        tier: AnalyticsTier.tier1,
        requiredProperties: mutableProps,
      );
      expect(() => spec.requiredProperties.add('b'), throwsUnsupportedError);
    });
  });
}
