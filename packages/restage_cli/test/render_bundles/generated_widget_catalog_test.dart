import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('generated_catalog_test_');
    await File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsString('name: demo_app\n');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> seedCatalog(String contents) async {
    final file = File(generatedWidgetCatalogPath(root, 'demo_app'));
    await file.create(recursive: true);
    await file.writeAsString(contents);
  }

  test('generates first, then reads what the generator wrote', () async {
    await seedCatalog('{"generated":true}');
    String? executable;
    List<String>? arguments;
    final catalog = await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: true,
      dartExecutable: '/toolchain/bin/dart',
      processRunner: (exe, args, {String? workingDirectory}) async {
        executable = exe;
        arguments = args;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(executable, '/toolchain/bin/dart');
    expect(arguments, generatedWidgetCatalogCommand);
    expect(catalog.json, '{"generated":true}');
    expect(catalog.registersWidgets, isTrue);
  });

  test('runs the generator in the project root', () async {
    await seedCatalog('{}');
    String? seen;
    await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: true,
      dartExecutable: '/toolchain/bin/dart',
      processRunner: (exe, args, {String? workingDirectory}) async {
        seen = workingDirectory;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(seen, root.path);
  });

  test(
    'an app registering no widgets builds an empty custom library',
    () async {
      final catalog = await readGeneratedWidgetCatalog(
        projectRoot: root,
        generate: true,
        dartExecutable: '/toolchain/bin/dart',
        processRunner: (exe, args, {String? workingDirectory}) async =>
            ProcessResult(0, 0, '', ''),
      );
      expect(catalog.registersWidgets, isFalse);
      final decoded = decodeCatalog(catalog.json);
      expect(decoded.schemaVersion, kSupportedSchemaVersion);
      expect(decoded.libraries, isEmpty);
      expect(decoded.widgets, isEmpty);
    },
  );

  test('a failing generator refuses', () async {
    await expectLater(
      readGeneratedWidgetCatalog(
        projectRoot: root,
        generate: true,
        dartExecutable: '/toolchain/bin/dart',
        processRunner: (exe, args, {String? workingDirectory}) async =>
            ProcessResult(0, 1, '', 'sensitive generator output'),
      ),
      throwsA(
        isA<GeneratedCatalogException>().having(
          (error) => error.reason,
          'reason',
          'generate_failed',
        ),
      ),
    );
  });

  test('skipping generation requires the produced catalog', () async {
    await expectLater(
      readGeneratedWidgetCatalog(projectRoot: root, generate: false),
      throwsA(
        isA<GeneratedCatalogException>().having(
          (error) => error.reason,
          'reason',
          'catalog_missing',
        ),
      ),
    );
    await seedCatalog('{"produced":true}');
    final catalog = await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: false,
    );
    expect(catalog.json, '{"produced":true}');
  });

  test('a project without a readable name refuses', () async {
    await File(p.join(root.path, 'pubspec.yaml')).delete();
    await expectLater(
      readGeneratedWidgetCatalog(projectRoot: root, generate: false),
      throwsA(
        isA<GeneratedCatalogException>().having(
          (error) => error.reason,
          'reason',
          'project_identity',
        ),
      ),
    );
  });

  test('the generated path sits under the build cache', () {
    expect(
      generatedWidgetCatalogPath(root, 'demo_app'),
      p.join(
        root.path,
        '.dart_tool',
        'build',
        'generated',
        'demo_app',
        'lib',
        'src',
        'widget_catalog',
        'catalog.json',
      ),
    );
  });
}
