import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_widgetbook_example/onboarding/screens/opaque_screen_proof.dart';

void main() {
  test(
    'native sibling authoring leaves the ScreenSource RFW baseline exact',
    () {
      const expected = <String, String>{
        'lib/onboarding/screens/opaque_screen_proof.rsscreen.g.dart':
            'ffd6d68ec5bc27c072d0bba996e8fd4f97f0abb8b752c3fabf3686f1a6741c9a',
        'assets/onboarding/screens/opaque_screen_proof.rfwtxt':
            '5c173d7ce6d0a76ae96ed06113f1c22e76b311460788358d4a5f9fc68c722198',
        'assets/onboarding/screens/opaque_screen_proof.rfw':
            '52a780c74fe59fd5f8d61b8e8e9039ad031fe99529416ed4c4d5746bb3a074bd',
        'assets/onboarding/screens/opaque_screen_proof.capability.json':
            'f470665b7fa83785910bb6a81165146ef3f65ffbb88d3f1cbd0698b74304a969',
      };

      for (final entry in expected.entries) {
        expect(
          sha256.convert(File(entry.key).readAsBytesSync()).toString(),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('RFW text, capability, and flow-facing descriptor stay exact', () {
    expect(
      File(
        'assets/onboarding/screens/opaque_screen_proof.rfwtxt',
      ).readAsStringSync(),
      'import restage.core;\n'
      'import restage.material;\n'
      'import restage.cupertino;\n'
      '\n'
      'widget OnboardingScreen = Center(child: ElevatedButton('
      'onPressed: event "continue" { value: "preview" }, child: '
      'Text(text: "Opaque screen proof")));\n',
    );
    expect(OpaqueScreenProofDescriptor.ref.id, 'opaque_screen_proof');
    expect(
      OpaqueScreenProofDescriptor.ref.artifactPath,
      'opaque_screen_proof.rfw',
    );
    expect(OpaqueScreenProofDescriptor.ref.version, 1);
    expect(OpaqueScreenProofDescriptor.ref.minClient, 1);
    expect(
      File(
        'assets/onboarding/screens/opaque_screen_proof.capability.json',
      ).readAsStringSync(),
      '{\n'
      '  "blobSha256": '
      '"sha256:52a780c74fe59fd5f8d61b8e8e9039ad031fe99529416ed4c4d5746bb3a074bd",\n'
      '  "manifest": {\n'
      '    "builtInFloor": 1,\n'
      '    "requiredLibraries": []\n'
      '  }\n'
      '}',
    );
  });
}
