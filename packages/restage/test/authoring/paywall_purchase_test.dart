import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('paywallPurchase asserts exactly one of slot/productId is provided', () {
    expect(
        () => paywallPurchase(slot: 'a', productId: 'b'), throwsAssertionError);
    expect(() => paywallPurchase(), throwsAssertionError);
  });

  testWidgets('paywallPurchase fires restage.purchase event via dispatcher',
      (tester) async {
    String? receivedName;
    Map<String, Object?>? receivedArgs;
    VoidCallback? captured;
    await tester.pumpWidget(RestagePaywallEventDispatcher(
      onEvent: (n, a) {
        receivedName = n;
        receivedArgs = a;
      },
      child: Builder(builder: (_) {
        // Build inside the dispatcher subtree so the active dispatcher is
        // captured at construction time.
        captured = paywallPurchase(slot: 'primary');
        return const SizedBox();
      }),
    ));
    captured!();
    expect(receivedName, 'restage.purchase');
    expect(receivedArgs, {'slot': 'primary'});
  });

  testWidgets('paywallPurchase forwards an optional offerId in the event args',
      (tester) async {
    Map<String, Object?>? receivedArgs;
    VoidCallback? captured;
    await tester.pumpWidget(RestagePaywallEventDispatcher(
      onEvent: (_, a) => receivedArgs = a,
      child: Builder(builder: (_) {
        captured = paywallPurchase(slot: 'primary', offerId: 'winback_3mo');
        return const SizedBox();
      }),
    ));
    captured!();
    expect(receivedArgs, {'slot': 'primary', 'offerId': 'winback_3mo'});
  });
}
