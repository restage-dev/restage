import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('paywallPriceFor asserts exactly one arg', () {
    expect(
        () => paywallPriceFor(slot: 'a', productId: 'b'), throwsAssertionError);
    expect(() => paywallPriceFor(), throwsAssertionError);
  });

  test('paywallPriceFor returns a placeholder string in non-codegen runtime',
      () {
    final s = paywallPriceFor(slot: 'primary');
    expect(s, isA<String>());
    expect(s, isNotEmpty);
    // Placeholder convention: "$X.XX" so layout doesn't crash but signals
    // it's a binding.
    expect(s, r'$X.XX');
  });

  test('paywallPriceFor returns the shared unbound-price const', () {
    // The Dart-authoring path and the compiled-surface placeholder injector
    // must never drift apart — both return the one shared literal.
    expect(paywallPriceFor(slot: 'primary'), kRestageUnboundPriceLabel);
    expect(
        paywallPriceFor(productId: 'pro_monthly'), kRestageUnboundPriceLabel);
  });
}
