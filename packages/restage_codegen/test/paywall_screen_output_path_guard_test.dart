import 'dart:io';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('paywall codegen owns its flow-screen output directory', () {
    final buildConfig = File('build.yaml').readAsStringSync();

    expect(kPaywallScreensAssetDir, 'assets/paywalls/screens');
    expect(
      buildConfig,
      contains('assets/paywalls/screens/paywall_{{name}}.rfw'),
    );
    expect(
      buildConfig,
      contains(
        'assets/paywalls/screens/paywall_{{name}}.capability.json',
      ),
    );
    expect(
      buildConfig,
      isNot(contains('assets/onboarding/screens/paywall_')),
    );
  });
}
