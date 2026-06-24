import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('PaywallCustomEvent toMap merges name + paywallId + eventName + args',
      () {
    const e = PaywallCustomEvent(
      paywallId: 'pro_upgrade',
      eventName: 'subscribe',
      args: {'plan': 'monthly', 'priceMicros': 9990000},
    );
    expect(e.name, 'paywall_custom_event');
    final map = e.toMap();
    expect(map['name'], 'paywall_custom_event');
    expect(map['paywallId'], 'pro_upgrade');
    expect(map['eventName'], 'subscribe');
    expect(map['plan'], 'monthly');
    expect(map['priceMicros'], 9990000);
  });
}
