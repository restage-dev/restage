import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/onboarding/flows/lumen_onboarding.dart';
import 'package:restage_example/surfaces/lumen_trial_ending_flow.dart';
import 'package:restage_shared/restage_shared.dart';

String _bundled(String bundle, String logicalPath) => utf8.decode(
      RestageBundleCodec.decode(
        File('assets/restage/bundles/lib/$bundle').readAsBytesSync(),
      ).entries.singleWhere((entry) => entry.logicalPath == logicalPath).bytes,
    );

void main() {
  // Both flows embed the same measured welcome offer, each through its own
  // routed copy; the compiled document must name the copy the bundle ships.
  test('a compiled flow embeds the document its bundle ships', () {
    expect(
      lumenOnboardingFlowRef.compiled!.documentJson,
      _bundled(
        'onboarding/flows/lumen_onboarding.rsbundle',
        'assets/onboarding/flows/lumen_onboarding.flow.json',
      ),
    );
    expect(
      lumenTrialOfferRef.compiled!.documentJson,
      _bundled(
        'surfaces/lumen_trial_ending_flow.rsbundle',
        'assets/message/flows/lumen_trial_offer.flow.json',
      ),
    );
  });
}
