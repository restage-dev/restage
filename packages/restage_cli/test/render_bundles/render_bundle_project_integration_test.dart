import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_project.dart';
import 'package:test/test.dart';

const _siblings = <String>[
  'restage_core',
  'restage_material',
  'restage_cupertino',
  'restage_shared',
  'restage_measurement_schema',
  'rfw_catalog_schema',
];

/// A plain app on the SDK in this checkout resolves and compiles the project
/// a build generates for it.
void main() {
  String? flutter;
  try {
    flutter = findFlutterExecutable();
  } on RenderBundleBuildException {
    flutter = null;
  }
  final packages = p.normalize(p.absolute('..'));

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('render_bundle_app_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> arguments, Directory directory) =>
      Process.run(flutter!, arguments, workingDirectory: directory.path);

  test(
    'the generated project resolves and its entrypoint compiles',
    () async {
      final app = Directory(p.join(root.path, 'sample_app'))..createSync();
      String local(String name) => '    path: ${p.join(packages, name)}\n';
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(
        'name: sample_app\n'
        'publish_to: none\n'
        'environment:\n'
        '  sdk: ^3.8.0\n'
        'dependencies:\n'
        '  flutter:\n'
        '    sdk: flutter\n'
        '  restage:\n${local('restage')}'
        'dependency_overrides:\n'
        '${_siblings.map((name) => '  $name:\n${local(name)}').join()}',
      );
      File(p.join(app.path, 'lib', 'user_factories.g.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'void registerRestageWidgets({\n'
          '  bool includeMaterial = true,\n'
          '  bool includeCupertino = true,\n'
          '}) {}\n',
        );
      final appResolved = await run(<String>['pub', 'get', '--offline'], app);
      expect(appResolved.exitCode, 0, reason: '${appResolved.stderr}');

      final project = await writeRenderBundleProject(
        projectRoot: app,
        flutterVersion: requiredRenderBundleFlutterVersion,
        fontBytes: Uint8List.fromList(<int>[0]),
        licenseBytes: Uint8List.fromList(<int>[0]),
      );
      final resolved = await run(<String>['pub', 'get', '--offline'], project);
      expect(resolved.exitCode, 0, reason: '${resolved.stderr}');
      final analyzed = await run(<String>['analyze'], project);
      expect(analyzed.exitCode, 0, reason: '${analyzed.stdout}');

      // Nothing outside the generated output lands in the app.
      expect(
        app
            .listSync()
            .map((entity) => p.basename(entity.path))
            .where((name) => !name.startsWith('.'))
            .toSet(),
        <String>{'lib', 'pubspec.yaml', 'pubspec.lock'},
      );
    },
    skip: flutter == null ? 'Flutter is not on PATH.' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
