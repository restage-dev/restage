import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_widgetbook_example/onboarding/screens/get_started_screen.dart';

void main() {
  test(
    'native sibling authoring leaves the canonical Screen RFW baseline exact',
    () {
      // Pin the generated descriptor and canonical delivery bytes together.
      expect(
        sha256
            .convert(
              File(
                'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
              ).readAsBytesSync(),
            )
            .toString(),
        '88d33a47453596cc7e1a8a1b2cd624e40fbf7dde0a3c2f0e23a7850561f4a185',
        reason:
            'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
      );

      const delivery = <String, String>{
        'assets/onboarding/screens/opaque_screen_proof.rfwtxt':
            '566db8996c86df38e03a8f68d7aef5f8edffcd42e42d8354270be54905c5a6a7',
        'assets/onboarding/screens/opaque_screen_proof.rfw':
            '8cc8b91acac4f019533b9b6f5d38c8aed5fbb1e23edb9a1b23fe2883269aa71b',
        'assets/onboarding/screens/opaque_screen_proof.capability.json':
            '4d6d51b9ffb9050f4dd471ba0c198eda72adc62dffad4c043a43a9c98e17cbf1',
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
      'onPressed: event "continue" {value: "preview"}, child: '
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
      '{"blobSha256":'
      '"sha256:8cc8b91acac4f019533b9b6f5d38c8aed5fbb1e23edb9a1b23fe2883269aa71b",'
      '"manifest":{"builtInFloor":1,"requiredLibraries":[]}}',
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
