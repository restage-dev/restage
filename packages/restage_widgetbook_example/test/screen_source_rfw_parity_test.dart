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
        'f1b1946cab13f732674722603453858698eedc7176ec886be7957fffb50b0750',
        reason:
            'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
      );

      const delivery = <String, String>{
        'assets/onboarding/screens/get_started_screen.rfwtxt':
            '12f5157042be9f5670451f4b338a9cb1404f7ea70b24412845e383e64261d670',
        'assets/onboarding/screens/get_started_screen.rfw':
            'd8c256759a2c5e01f503bb92d90c93bd2f1b2c235886b5f197cc76faed2ad16e',
        'assets/onboarding/screens/get_started_screen.capability.json':
            '7291c40340caaf90a06d1b59a8dcc9c5eced0b8796ab706e0bb3aa249deae689',
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
      '"sha256:d8c256759a2c5e01f503bb92d90c93bd2f1b2c235886b5f197cc76faed2ad16e",'
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
