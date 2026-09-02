@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated measurement references are available to importing packages',
      () async {
    final packageRoot = _packageRoot();
    final importingPackage = await Directory.systemTemp.createTemp(
      'restage-generated-reference-',
    );
    addTearDown(() => importingPackage.delete(recursive: true));
    final materialPackage = Directory(
      '${packageRoot.parent.path}/restage_material',
    );
    final materialOverride = materialPackage.existsSync()
        ? '''
dependency_overrides:
  restage_material:
    path: ${jsonEncode(materialPackage.path)}
'''
        : '';

    await File('${importingPackage.path}/pubspec.yaml').writeAsString('''
name: restage_generated_reference_check
publish_to: none
environment:
  sdk: ^3.5.0
dependencies:
  flutter:
    sdk: flutter
  restage:
    path: ${jsonEncode(packageRoot.path)}
$materialOverride
''');
    await Directory('${importingPackage.path}/lib').create();
    await File('${importingPackage.path}/lib/generated.dart').writeAsString('''
import 'package:restage/restage.dart';

void _decodeResult(Map<String, Object?> result) {}

const flowReference =
    SurfaceFlowRef<void>.generatedWithMeasurementPublicationDraftDigest(
  id: 'welcome',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeResult,
  deliveryMode: FlowDeliveryMode.typed,
  measurementPublicationDraftDigest:
      '0000000000000000000000000000000000000000000000000000000000000000',
);

const neutralFlowReference =
    NeutralFlowScreenRef.generatedWithMeasurementPublicationDraftDigest(
  id: 'welcome',
  artifactPath: 'assets/onboarding/screens/welcome.rfw',
  version: 1,
  minClient: 1,
  measurementPublicationDraftDigest:
      '0000000000000000000000000000000000000000000000000000000000000000',
);

SurfaceScreenRef<void> screenReference(
  SurfaceScreenRuntimeProvenance provenance,
  SurfaceScreenEventContract<void> eventContract,
) =>
    SurfaceScreenRef<void>
        .generatedWithMeasurementPublicationDraftDigest(
      provenance: provenance,
      eventContract: eventContract,
      measurementPublicationDraftDigest:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );
''');

    final pubGet = await Process.run(
      'flutter',
      const <String>['pub', 'get'],
      workingDirectory: importingPackage.path,
    );
    expect(pubGet.exitCode, 0, reason: _output(pubGet));

    final analyze = await Process.run(
      'dart',
      const <String>['analyze'],
      workingDirectory: importingPackage.path,
    );
    expect(analyze.exitCode, 0, reason: _output(analyze));
  });
}

Directory _packageRoot() {
  var directory = Directory.current.absolute;
  final packageName = RegExp(r'^name:\s*restage\s*$', multiLine: true);

  while (true) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        packageName.hasMatch(pubspec.readAsStringSync())) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the restage package.');
    }
    directory = parent;
  }
}

String _output(ProcessResult result) => '${result.stdout}\n${result.stderr}';
