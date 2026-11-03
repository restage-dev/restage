@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The packages the app resolves from this repository rather than pub.dev.
const _local = [
  'restage_shared',
  'rfw_catalog_schema',
  'restage_core',
  'restage_material',
  'restage_cupertino',
  'restage_measurement_schema',
  'restage_compiler_core',
  'restage_svg',
];

void main() {
  test('dart fix --apply renames renderDeadline to firstLaunchWait', () async {
    final packages = Directory.current.parent.path;
    // Directory.systemTemp follows TMPDIR.
    final app = Directory.systemTemp.createTempSync('restage_fix_data');
    addTearDown(() => app.deleteSync(recursive: true));
    final overrides = [
      for (final name in _local)
        if (Directory('$packages/$name').existsSync())
          '  $name:\n    path: $packages/$name\n',
    ].join();
    File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: fix_data_probe
publish_to: none
environment:
  sdk: ^3.8.0
  flutter: '>=3.0.0'
dependencies:
  flutter:
    sdk: flutter
  restage:
    path: ${Directory.current.path}
dependency_overrides:
$overrides''');
    Directory('${app.path}/lib').createSync();
    final source = File('${app.path}/lib/main.dart')..writeAsStringSync('''
import 'package:restage/restage.dart';

void main() {
  Restage.configure(renderDeadline: const Duration(milliseconds: 500));
  Restage.configureWithInstalledCatalog(
      renderDeadline: const Duration(milliseconds: 400));
}
''');

    Future<void> run(String tool, List<String> args) async {
      final result = await Process.run(tool, args, workingDirectory: app.path);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    }

    await run('flutter', ['pub', 'get', '--offline']);
    await run('dart', ['fix', '--apply']);
    final fixed = source.readAsStringSync();
    expect(fixed, isNot(contains('renderDeadline')));
    expect(fixed, contains('Restage.configure(firstLaunchWait:'));
    expect(fixed,
        contains('configureWithInstalledCatalog(\n      firstLaunchWait:'));
  });
}
