import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final _catalog = encodeCatalog(
  const Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: <WidgetLibrary, LibraryInfo>{},
    widgets: <WidgetEntry>[],
  ),
);

void main() {
  late Directory root;
  late Directory project;
  late int tempCreations;
  late int processCalls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('render_bundle_identity_');
    project = Directory(p.join(root.path, 'app'))..createSync();
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: custom_project\n');
    Directory(p.join(root.path, 'sibling')).createSync();
    tempCreations = 0;
    processCalls = 0;
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  void writeAncestorConfig(String? projectRootUri) {
    File(p.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            if (projectRootUri != null)
              <String, Object?>{
                'name': 'custom_project',
                'rootUri': projectRootUri,
                'packageUri': 'lib/',
                'languageVersion': '3.8',
              },
          ],
        }),
      );
  }

  Future<void> expectRefusedBeforeWork() async {
    final builder = FlutterRenderBundleBuilder(
      processRunner:
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            processCalls++;
            return ProcessResult(1, 1, '', '');
          },
      tempDirectoryCreator: (_) async {
        tempCreations++;
        return Directory(p.join(root.path, 'scratch'))..createSync();
      },
      flutterExecutable: p.join(root.path, 'flutter'),
      fontAuthority: RenderBundleFontAuthority(
        fontFile: File(p.join(root.path, 'font')),
        licenseFile: File(p.join(root.path, 'license')),
        fontSha256: 'unused',
        licenseSha256: 'unused',
      ),
    );
    await expectLater(
      builder.build(
        projectRoot: project,
        catalogJson: _catalog,
        parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
        controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
      ),
      throwsA(
        isA<RenderBundleBuildException>().having(
          (error) => error.reason.code,
          'reason',
          'catalog_contract',
        ),
      ),
    );
    expect(tempCreations, 0);
    expect(processCalls, 0);
  }

  test(
    'an ancestor config that omits the project refuses before any work',
    () async {
      writeAncestorConfig(null);
      await expectRefusedBeforeWork();
    },
  );

  test('an ancestor config mapping the project elsewhere refuses before any '
      'work', () async {
    writeAncestorConfig('../sibling');
    await expectRefusedBeforeWork();
  });

  test('an unresolved project refuses before any work', () async {
    await expectRefusedBeforeWork();
  });
}
