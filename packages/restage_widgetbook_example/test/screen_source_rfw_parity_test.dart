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

  test('the canonical Screen RFW baseline is exact', () {
    // Pin the generated handle separately from its unchanged RFW payload.
    expect(
      sha256
          .convert(
            File(
              'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      '5710c44f504abe6a79885edd43f75cada80319c3520116b07395095c054a6e61',
      reason:
          'lib/onboarding/screens/restage.generated/get_started_screen.restage.g.dart',
    );

    const delivery = <String, String>{
      'assets/onboarding/screens/get_started_screen.rfwtxt':
          '8f43f76ea7cb03006a11c39443fe1ddee214f28908a831af4e6a07b36148b4cf',
      'assets/onboarding/screens/get_started_screen.rfw':
          'c30e041e83424425c6b6b0e11149a1914fa39db740176ebd215d43dc6860f835',
      'assets/onboarding/screens/get_started_screen.capability.json':
          '1d665af326f747af65a9cf58e090d4df9a01038835cf21ee77e1c8a66c38fe86',
    };

    final packaged = _packagedArtifacts();
    for (final entry in delivery.entries) {
      final bytes = packaged[entry.key];
      expect(bytes, isNotNull, reason: entry.key);
      expect(sha256.convert(bytes!).toString(), entry.value, reason: entry.key);
    }
  });

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
      // The button's value key reaches the design as a native binding.
      'widget OnboardingScreen = Center(child: ElevatedButton('
      'key: data.context._hb227fda92b, '
      'onPressed: event "continue" {value: "preview"}, child: '
      'Text(text: "Get started")));\n',
    );
    expect(getStartedScreenRef.id, 'get_started_screen');
    expect(getStartedScreenRef.version, 1);
    expect(getStartedScreenRef.capabilities.builtInFloor, 24);
    expect(getStartedScreenRef.surface, Surface.onboarding);
    expect(
      utf8.decode(
        _packagedArtifacts()['assets/onboarding/screens/'
            'get_started_screen.capability.json']!,
      ),
      '{"blobSha256":'
      '"sha256:c30e041e83424425c6b6b0e11149a1914fa39db740176ebd215d43dc6860f835",'
      '"manifest":{"builtInFloor":24,"requiredLibraries":[]}}',
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
