import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_widgetbook_example/onboarding/screens/get_started_screen.dart';

void main() {
  test('Widgetbook and A2UI example needs no runtime bundle', () {
    expect(getStartedScreenRef.provenance.bundle, isNull);
  });

  test(
    'native sibling authoring leaves the canonical Screen RFW baseline exact',
    () {
      // Pin the generated handle separately from its unchanged RFW payload.
      expect(
        sha256
            .convert(
              File(
                'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
              ).readAsBytesSync(),
            )
            .toString(),
        '5d4186249463919d49d9cbafaf8f53b19403a7f389d9e3a5a6e27bf744858994',
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

/// Reads logical RFW artifacts from generated build output.
Map<String, List<int>> _packagedArtifacts() {
  final entries = <String, List<int>>{};
  final bundles = Directory('.restage/build/bundles');
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
