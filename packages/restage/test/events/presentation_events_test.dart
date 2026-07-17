import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('PaywallLoadStarted has name + paywallId in toMap', () {
    const e = PaywallLoadStarted(paywallId: 'pro_upgrade');
    expect(e.name, 'paywall_load_started');
    expect(e.toMap()['name'], 'paywall_load_started');
    expect(e.toMap()['paywallId'], 'pro_upgrade');
  });

  test('PaywallLoadCompleted carries loadDuration + cacheHit', () {
    const e = PaywallLoadCompleted(
      paywallId: 'pro_upgrade',
      loadDuration: Duration(milliseconds: 142),
      cacheHit: true,
    );
    expect(e.name, 'paywall_load_completed');
    final map = e.toMap();
    expect(map['loadDurationMs'], 142);
    expect(map['cacheHit'], true);
  });

  test('PaywallLoadFailed carries errorCode + retryable', () {
    const e = PaywallLoadFailed(
      paywallId: 'pro_upgrade',
      errorCode: 'decode_failed',
      message: 'corrupt blob',
      retryable: false,
    );
    expect(e.toMap()['errorCode'], 'decode_failed');
    expect(e.toMap()['retryable'], false);
  });

  test('PaywallViewed includes assignment metadata when present', () {
    const e = PaywallViewed(
      paywallId: 'pro_upgrade',
      productIds: ['pro_monthly', 'pro_yearly'],
      variantId: 'variant-b',
      experimentId: 'exp1',
      experimentEpoch: 3,
    );
    expect(e.toMap()['productIds'], ['pro_monthly', 'pro_yearly']);
    expect(e.toMap()['variantId'], 'variant-b');
    expect(e.toMap()['experimentId'], 'exp1');
    expect(e.toMap()['experimentEpoch'], 3);

    const withoutAssignment = PaywallViewed(
      paywallId: 'pro_upgrade',
      productIds: [],
    );
    expect(withoutAssignment.toMap().containsKey('experimentEpoch'), isFalse);
  });

  test('PaywallViewed carries publishedVersion when set; omits it when null',
      () {
    const withVersion = PaywallViewed(
      paywallId: 'pro_upgrade',
      productIds: ['pro_monthly'],
      publishedVersion: 5,
    );
    expect(withVersion.publishedVersion, 5);
    expect(withVersion.toMap()['publishedVersion'], 5);

    const withoutVersion = PaywallViewed(
      paywallId: 'pro_upgrade',
      productIds: ['pro_monthly'],
    );
    expect(withoutVersion.publishedVersion, isNull);
    expect(withoutVersion.toMap().containsKey('publishedVersion'), isFalse);
  });

  test('PaywallDismissed includes reason + timeOnPaywall', () {
    const e = PaywallDismissed(
      paywallId: 'pro_upgrade',
      reason: DismissReason.userClose,
      timeOnPaywall: Duration(seconds: 8),
    );
    expect(e.toMap()['reason'], 'user_close');
    expect(e.toMap()['timeOnPaywallMs'], 8000);
  });
}
