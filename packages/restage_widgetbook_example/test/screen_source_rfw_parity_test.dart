import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_widgetbook_example/onboarding/screens/opaque_screen_proof.dart';

void main() {
  test(
    'native sibling authoring leaves the canonical Screen RFW baseline exact',
    () {
      // The generated descriptor is ordinary source and is read as a file.
      // Its bytes moved with the generated-Dart changes
      // (collection-directory part URI, the category-neutral ref, and the
      // additive runtime provenance); the DELIVERY bytes below did not move at
      // all, which is the property this baseline exists to hold.
      expect(
        sha256
            .convert(
              File(
                'lib/onboarding/screens/restage.generated/opaque_screen_proof.restage.g.dart',
              ).readAsBytesSync(),
            )
            .toString(),
        'a9272cac5f3e4fac613b4f1156bcd9cf5832833b5248c369a0b37cc2c340156f',
        reason:
            'lib/onboarding/screens/restage.generated/opaque_screen_proof.restage.g.dart',
      );

      const delivery = <String, String>{
        'assets/onboarding/screens/opaque_screen_proof.rfwtxt':
            '5c173d7ce6d0a76ae96ed06113f1c22e76b311460788358d4a5f9fc68c722198',
        'assets/onboarding/screens/opaque_screen_proof.rfw':
            '52a780c74fe59fd5f8d61b8e8e9039ad031fe99529416ed4c4d5746bb3a074bd',
        'assets/onboarding/screens/opaque_screen_proof.capability.json':
            'f470665b7fa83785910bb6a81165146ef3f65ffbb88d3f1cbd0698b74304a969',
      };

      final packaged = _packagedArtifacts();
      for (final entry in delivery.entries) {
        final bytes = packaged[entry.key];
        expect(bytes, isNotNull, reason: entry.key);
        expect(
          sha256.convert(bytes!).toString(),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test('RFW text, capability, and generated handle stay exact', () {
    expect(
      utf8.decode(
        _packagedArtifacts()['assets/onboarding/screens/'
            'opaque_screen_proof.rfwtxt']!,
      ),
      'import restage.core;\n'
      'import restage.material;\n'
      'import restage.cupertino;\n'
      '\n'
      'widget OnboardingScreen = Center(child: ElevatedButton('
      'onPressed: event "continue" { value: "preview" }, child: '
      'Text(text: "Opaque screen proof")));\n',
    );
    // A categorized `@Screen(surface:)` is standalone, so its handle is the
    // typed `SurfaceScreenRef` — it carries no `artifactPath`/`minClient`,
    // which belonged to the in-flow neutral reference this screen no longer
    // generates. The packaged `.rfw` path those two stood for is asserted by
    // exact digest in the delivery-map test above, not weakened here.
    expect(opaqueScreenProofRef.id, 'opaque_screen_proof');
    expect(opaqueScreenProofRef.version, 1);
    expect(opaqueScreenProofRef.capabilities.builtInFloor, 1);
    expect(opaqueScreenProofRef.surface, Surface.onboarding);
    expect(
      utf8.decode(
        _packagedArtifacts()['assets/onboarding/screens/'
            'opaque_screen_proof.capability.json']!,
      ),
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

/// Every logical delivery artifact this package ships, read out of the
/// deterministic containers it packages them into.
Map<String, List<int>> _packagedArtifacts() {
  final entries = <String, List<int>>{};
  final bundles = Directory('assets/restage/bundles');
  if (!bundles.existsSync()) return entries;
  for (final file in bundles.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.rsbundle')) continue;
    for (final entry in RestageBundleCodec.decode(
      file.readAsBytesSync(),
    ).entries) {
      entries[entry.logicalPath] = entry.bytes;
    }
  }
  return entries;
}
