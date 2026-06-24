import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/demo_event_feedback.dart';
import 'package:restage/restage.dart';

void main() {
  group('demoPaywallEventLabel', () {
    test('labels a purchase with its product id', () {
      const event = PurchaseInitiated(
        paywallId: 'ascend_premium',
        productId: 'com.restage.pro.annual',
      );
      expect(
        demoPaywallEventLabel(event),
        'Starting purchase: com.restage.pro.annual',
      );
    });

    PaywallCustomEvent custom(String name) => PaywallCustomEvent(
          paywallId: 'ascend_premium',
          eventName: name,
          args: const {},
        );

    test('labels the restore action', () {
      expect(demoPaywallEventLabel(custom('restore')), 'Restore requested');
    });

    test('labels the terms link', () {
      expect(demoPaywallEventLabel(custom('terms')), contains('Terms'));
    });

    test('labels the privacy link', () {
      expect(demoPaywallEventLabel(custom('privacy')), contains('Privacy'));
    });

    // The paywalls fire these longer-form event names; the label helper must
    // map them too (rather than fall through to the raw-name fallback).
    test('labels the terms_of_service link fired by the paywalls', () {
      expect(
        demoPaywallEventLabel(custom('terms_of_service')),
        contains('Terms'),
      );
    });

    test('labels the privacy_policy link fired by the paywalls', () {
      expect(
        demoPaywallEventLabel(custom('privacy_policy')),
        contains('Privacy'),
      );
    });

    test('labels the subscription_info link fired by the paywalls', () {
      expect(
        demoPaywallEventLabel(custom('subscription_info')),
        contains('subscription'),
      );
    });

    test('falls back to the raw event name for an unmapped custom event', () {
      expect(demoPaywallEventLabel(custom('subscribe')), contains('subscribe'));
    });

    test('returns null for a load failure (handled by the errorBuilder)', () {
      const event = PaywallLoadFailed(
        paywallId: 'ascend_premium',
        errorCode: 'decode_failed',
        message: 'bad blob',
        retryable: false,
      );
      expect(demoPaywallEventLabel(event), isNull);
    });
  });
}
