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
      // The generated descriptor is ordinary source and is read as a file.
      // Its bytes moved with the generated-Dart changes
      // (collection-directory part URI, the category-neutral ref, and the
      // additive runtime provenance); the DELIVERY bytes below did not move at
      // all, which is the property this baseline exists to hold.
      expect(
        sha256
            .convert(
              File(
                'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
              ).readAsBytesSync(),
            )
            .toString(),
        'ee10783392d13df3bf53e21d7e70c882e10c44789188ff0081ea524667e5cf82',
        reason:
            'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
      );

      const delivery = <String, String>{
        'assets/onboarding/screens/get_started_screen.rfwtxt':
            '12f5157042be9f5670451f4b338a9cb1404f7ea70b24412845e383e64261d670',
        'assets/onboarding/screens/get_started_screen.rfw':
            '6de6f52ac71212a2a79391f6871f1eccf5645066bb6d7e6798aacbac29b3d355',
        'assets/onboarding/screens/get_started_screen.capability.json':
            '7640f8efacf15a352bc9da2b4d2cfb77ccf99d463956a37df63d3d9fdcca0e30',
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
            'get_started_screen.rfwtxt']!,
      ),
      'import restage.core;\n'
      'import restage.material;\n'
      'import restage.cupertino;\n'
      '\n'
      'widget OnboardingScreen = Center(child: ElevatedButton('
      'onPressed: event "continue" {value: "preview"}, child: '
      'Text(text: "Get started")));\n',
    );
    // A categorized `@Screen(surface:)` is standalone, so its handle is the
    // typed `SurfaceScreenRef` — it carries no `artifactPath`/`minClient`,
    // which belonged to the in-flow neutral reference this screen no longer
    // generates. The packaged `.rfw` path those two stood for is asserted by
    // exact digest in the delivery-map test above, not weakened here.
    expect(getStartedScreenRef.id, 'get_started_screen');
    expect(getStartedScreenRef.version, 1);
    expect(getStartedScreenRef.capabilities.builtInFloor, 1);
    expect(getStartedScreenRef.surface, Surface.onboarding);
    expect(
      utf8.decode(
        _packagedArtifacts()['assets/onboarding/screens/'
            'get_started_screen.capability.json']!,
      ),
      '{"blobSha256":'
      '"sha256:6de6f52ac71212a2a79391f6871f1eccf5645066bb6d7e6798aacbac29b3d355",'
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
