import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('a paywall screen is known by its file name, wherever it is placed', () {
    expect(isPaywallScreenArtifact('paywall_pro.rfw'), isTrue);
    expect(
      isPaywallScreenArtifact('measurement/5d2c559be5e2165f/paywall_pro.rfw'),
      isTrue,
    );
    expect(isPaywallScreenArtifact('welcome.rfw'), isFalse);
    expect(isPaywallScreenArtifact('paywall_dir/welcome.rfw'), isFalse);
  });
}
