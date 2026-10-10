import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_asset_declaration.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'measurement_target_profile_asset_declaration_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('adds the one fixed profile asset declaration idempotently', () async {
    final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
    await pubspec.writeAsString('name: fixture\n');

    await ensureMeasurementBundledTargetProfileAssetDeclaration(
      packageRoot: tempDir,
    );
    final once = await pubspec.readAsString();
    await ensureMeasurementBundledTargetProfileAssetDeclaration(
      packageRoot: tempDir,
    );

    expect(once, contains(kMeasurementBundledTargetProfileAssetPath));
    expect(await pubspec.readAsString(), once);
  });

  test('accepts an existing direct parent asset declaration', () async {
    final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
    const source = '''
name: fixture
flutter:
  assets:
    - assets/restage/measurement/
''';
    await pubspec.writeAsString(source);

    await ensureMeasurementBundledTargetProfileAssetDeclaration(
      packageRoot: tempDir,
    );

    expect(await pubspec.readAsString(), source);
  });

  test('does not overwrite a malformed flutter assets declaration', () async {
    final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
    const source = '''
name: fixture
flutter:
  assets: not-a-list
''';
    await pubspec.writeAsString(source);

    await expectLater(
      ensureMeasurementBundledTargetProfileAssetDeclaration(
        packageRoot: tempDir,
      ),
      throwsA(isA<MeasurementBundledTargetProfileAssetDeclarationException>()),
    );

    expect(await pubspec.readAsString(), source);
  });

  test('keeps the comments and entries of an existing asset list', () async {
    final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
    const source = '''
name: fixture
flutter:
  assets:
    # Demo blobs.
    - assets/paywalls/
    # Generated bundles.
    - assets/restage/bundles/lib/paywalls/
''';
    await pubspec.writeAsString(source);

    final changed = await ensureMeasurementBundledTargetProfileAssetDeclaration(
      packageRoot: tempDir,
    );

    final updated = await pubspec.readAsString();
    expect(changed, isTrue);
    expect(updated, startsWith(source));
    expect(
      updated.substring(source.length).trim(),
      '- $kMeasurementBundledTargetProfileAssetPath',
    );
  });

  test('reports whether the profile is declared without editing', () async {
    final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
    const source = 'name: fixture\nflutter:\n  assets:\n    - a/\n';
    await pubspec.writeAsString(source);

    expect(
      await isMeasurementBundledTargetProfileAssetDeclared(
        packageRoot: tempDir,
      ),
      isFalse,
    );
    await ensureMeasurementBundledTargetProfileAssetDeclaration(
      packageRoot: tempDir,
    );
    expect(
      await isMeasurementBundledTargetProfileAssetDeclared(
        packageRoot: tempDir,
      ),
      isTrue,
    );
  });
}
