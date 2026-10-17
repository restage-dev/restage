import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

String _catalog(Map<WidgetLibrary, String> widgets) => encodeCatalog(
  Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      for (final library in widgets.keys)
        library: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [
      for (final MapEntry(key: library, value: name) in widgets.entries)
        WidgetEntry(
          wireId: WireId('w0001'),
          name: name,
          library: library,
          category: WidgetCategory.layout,
          description: '$name fixture.',
          flutterType: 'package:fixture/fixture.dart#$name',
          childrenSlot: ChildrenSlot.none,
          properties: const [],
        ),
    ],
  ),
);

const _app = WidgetLibrary.custom('demo.widgets');
const _kit = WidgetLibrary.custom('kit.widgets');

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

  Future<void> seed(String path, String contents) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> seedCatalog(String contents) =>
      seed(generatedWidgetCatalogPath(root, 'demo_app'), contents);

  Future<void> seedRenderCatalog(String contents) =>
      seed(generatedRenderCatalogPath(root, 'demo_app'), contents);

  Future<ProcessResult> succeed(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async => ProcessResult(0, 0, '', '');

  test('generates first, then reads what the generator wrote', () async {
    final merged = _catalog({
      WidgetLibrary.core: 'CoreBox',
      _app: 'AppBadge',
      _kit: 'KitBadge',
    });
    await seedCatalog(_catalog({_app: 'AppBadge'}));
    await seedRenderCatalog(merged);
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
    expect(catalog.renderJson, merged);
    expect(catalog.registersWidgets, isTrue);
    expect(decodeCatalog(catalog.json).widgets.map((widget) => widget.name), [
      'AppBadge',
      'KitBadge',
    ]);
  });

  test('runs the generator in the project root', () async {
    await seedRenderCatalog(_catalog({}));
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

  test('an app and dependencies registering no widgets', () async {
    await seedRenderCatalog(_catalog({WidgetLibrary.core: 'CoreBox'}));
    final catalog = await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: true,
      dartExecutable: '/toolchain/bin/dart',
      processRunner: succeed,
    );
    expect(catalog.registersWidgets, isFalse);
    final decoded = decodeCatalog(catalog.json);
    expect(decoded.schemaVersion, kSupportedSchemaVersion);
    expect(decoded.libraries, isEmpty);
    expect(decoded.widgets, isEmpty);
  });

  test('a generator without the merged catalog leaves it null', () async {
    final own = _catalog({_app: 'AppBadge'});
    await seedCatalog(own);
    final catalog = await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: true,
      dartExecutable: '/toolchain/bin/dart',
      processRunner: succeed,
    );
    expect(catalog.renderJson, isNull);
    expect(catalog.json, own);
    expect(catalog.registersWidgets, isTrue);
  });

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

  test('skipping generation requires a produced catalog', () async {
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
    await seedRenderCatalog(_catalog({_app: 'AppBadge'}));
    final catalog = await readGeneratedWidgetCatalog(
      projectRoot: root,
      generate: false,
    );
    expect(catalog.registersWidgets, isTrue);
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

  test('the generated paths sit under the build cache', () {
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
    expect(
      generatedRenderCatalogPath(root, 'demo_app'),
      p.join(
        p.dirname(generatedWidgetCatalogPath(root, 'demo_app')),
        'render_catalog.json',
      ),
    );
  });
}
