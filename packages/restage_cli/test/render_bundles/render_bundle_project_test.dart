import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_project.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory root;
  late Directory app;
  final font = Uint8List.fromList(<int>[1, 2, 3]);
  final license = Uint8List.fromList(utf8.encode('license'));

  void write(String path, String contents) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  Map<String, Object?> packageEntry(String name, String rootUri) =>
      <String, Object?>{
        'name': name,
        'rootUri': rootUri,
        'packageUri': 'lib/',
        'languageVersion': '3.8',
      };

  void resolve({
    required String at,
    required Map<String, String> roots,
    Map<String, List<String>> graph = const {},
  }) {
    write(
      '$at/.dart_tool/package_config.json',
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final entry in roots.entries)
            packageEntry(entry.key, entry.value),
        ],
        'flutterRoot': Uri.directory(p.join(root.path, 'flutter')).toString(),
      }),
    );
    write(
      '$at/.dart_tool/package_graph.json',
      jsonEncode(<String, Object?>{
        'configVersion': 1,
        'packages': <Object?>[
          for (final entry in graph.entries)
            <String, Object?>{
              'name': entry.key,
              'dependencies': entry.value,
              'devDependencies': entry.key == 'habit'
                  ? <String>['build_runner']
                  : <String>[],
            },
        ],
      }),
    );
  }

  const graph = <String, List<String>>{
    'habit': ['flutter', 'restage', 'local_widgets', 'charts'],
    'flutter': ['meta'],
    'restage': ['flutter', 'meta'],
    'local_widgets': ['restage'],
    'charts': [],
    'meta': [],
    'build_runner': [],
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('render_bundle_project_test_');
    app = Directory(p.join(root.path, 'app'));
    write('app/pubspec.yaml', '''
name: habit
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  restage: ^2.0.0
  local_widgets:
    path: ../local_widgets
  charts:
    git: https://example.test/charts.git
dev_dependencies:
  build_runner: any
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - path: assets/extra.json
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter.ttf
          weight: 700
  shaders:
    - shaders/glow.frag
  licenses:
    - legal/NOTICE.txt
  default-flavor: free
''');
    write('app/lib/user_factories.g.dart', '// generated\n');
    write('app/assets/images/logo.png', 'png');
    write('app/assets/extra.json', '{}');
    write('app/fonts/Inter.ttf', 'ttf');
    write('app/shaders/glow.frag', 'frag');
    write('app/legal/NOTICE.txt', 'notice');
    write('cache/restage/pubspec.yaml', 'name: restage\nversion: 2.3.1\n');
    write('flutter/packages/flutter/pubspec.yaml', 'name: flutter\n');
    resolve(
      at: 'app',
      roots: <String, String>{
        'habit': '../',
        'restage': '../../cache/restage',
        'meta': '../../cache/meta',
        'charts': '../../cache/charts',
        'build_runner': '../../cache/build_runner',
        'local_widgets': '../../local_widgets',
        'flutter': '../../flutter/packages/flutter',
      },
      graph: graph,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<Directory> writeProject() => writeRenderBundleProject(
    projectRoot: app,
    flutterVersion: '3.47.0',
    fontBytes: font,
    licenseBytes: license,
  );

  YamlMap pubspecOf(Directory project) =>
      loadYaml(File(p.join(project.path, 'pubspec.yaml')).readAsStringSync())
          as YamlMap;

  test(
    'writes a project under .restage/build that stands in for the app',
    () async {
      final project = await writeProject();

      expect(
        project.path,
        p.join(app.path, '.restage', 'build', 'render_bundle'),
      );
      final pubspec = pubspecOf(project);
      expect(pubspec['name'], 'habit');
      expect(pubspec['environment'], <String, Object?>{'sdk': '^3.10.0'});
      expect(pubspec['dependencies'], <String, Object?>{
        'flutter': <String, Object?>{'sdk': 'flutter'},
        'restage': 'any',
        'local_widgets': 'any',
        'charts': 'any',
        'restage_render_host': '>=2.3.0 <2.4.0',
      });
      expect(
        Link(p.join(project.path, 'lib')).targetSync(),
        p.join('..', '..', '..', 'lib'),
      );
      expect(
        File(
          p.join(project.path, 'lib', 'user_factories.g.dart'),
        ).readAsStringSync(),
        '// generated\n',
      );
      expect(
        File(p.join(project.path, renderBundleEntrypoint)).readAsStringSync(),
        allOf(
          contains("import 'package:habit/user_factories.g.dart';"),
          contains(
            "import 'package:restage_render_host/restage_render_host.dart';",
          ),
          contains('registerWidgets: registerRestageWidgets'),
          contains(
            "String.fromEnvironment('RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN')",
          ),
          contains('flutterVersion: "3.47.0"'),
        ),
      );
      final bootstrap = File(
        p.join(project.path, 'web', 'flutter_bootstrap.js'),
      ).readAsStringSync();
      expect(
        bootstrap,
        contains("fontFallbackBaseUrl: 'assets/fonts/fallback/'"),
      );
      expect(bootstrap, contains("canvasKitBaseUrl: 'canvaskit/'"));
      // A named renderer would rule out the fallback build.
      expect(RegExp(r'\brenderer\s*:').hasMatch(bootstrap), isFalse);
      expect(bootstrap, isNot(contains('http')));
      expect(bootstrap, isNot(contains('serviceWorker')));
      expect(
        File(p.join(project.path, 'web', 'index.html')).readAsStringSync(),
        contains('<script src="flutter_bootstrap.js" async></script>'),
      );
      expect(
        File(
          p.join(
            project.path,
            'restage_render_bundle',
            'fonts',
            'Roboto-Regular.ttf',
          ),
        ).readAsBytesSync(),
        font,
      );
    },
  );

  test(
    'pins what the app resolved and nothing it only develops with',
    () async {
      final pubspec = pubspecOf(await writeProject());

      expect(pubspec['dependency_overrides'], <String, Object?>{
        'charts': <String, Object?>{
          'path': p.join(root.path, 'cache', 'charts'),
        },
        'local_widgets': <String, Object?>{
          'path': p.join(root.path, 'local_widgets'),
        },
        'meta': <String, Object?>{'path': p.join(root.path, 'cache', 'meta')},
        'restage': <String, Object?>{
          'path': p.join(root.path, 'cache', 'restage'),
        },
      });
    },
  );

  test('carries the app assets and fonts its widgets use', () async {
    final project = await writeProject();
    final flutter = pubspecOf(project)['flutter'] as YamlMap;

    expect(flutter['uses-material-design'], isTrue);
    expect(flutter['assets'], <Object?>[
      'restage_render_bundle/fonts/Roboto_LICENSE.txt',
      'assets/images/',
      <String, Object?>{'path': 'assets/extra.json'},
    ]);
    expect(flutter['fonts'], <Object?>[
      <String, Object?>{
        'family': 'Roboto',
        'fonts': <Object?>[
          <String, Object?>{
            'asset': 'restage_render_bundle/fonts/Roboto-Regular.ttf',
          },
        ],
      },
      <String, Object?>{
        'family': 'Inter',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'fonts/Inter.ttf', 'weight': 700},
        ],
      },
    ]);
    expect(
      File(
        p.join(project.path, 'assets', 'images', 'logo.png'),
      ).readAsStringSync(),
      'png',
    );
    expect(
      File(p.join(project.path, 'assets', 'extra.json')).readAsStringSync(),
      '{}',
    );
    expect(
      File(p.join(project.path, 'fonts', 'Inter.ttf')).readAsStringSync(),
      'ttf',
    );
  });

  test('carries the app shaders, licenses and default flavor', () async {
    final project = await writeProject();
    final flutter = pubspecOf(project)['flutter'] as YamlMap;

    expect(flutter['shaders'], <Object?>['shaders/glow.frag']);
    expect(flutter['licenses'], <Object?>['legal/NOTICE.txt']);
    expect(flutter['default-flavor'], 'free');
    expect(
      File(p.join(project.path, 'shaders', 'glow.frag')).readAsStringSync(),
      'frag',
    );
    expect(
      File(p.join(project.path, 'legal', 'NOTICE.txt')).readAsStringSync(),
      'notice',
    );
  });

  test('honors a configured output_root', () async {
    write('app/build.yaml', '''
global_options:
  restage_codegen:outputs:
    options:
      output_root: generated/restage
''');
    final project = await writeProject();

    expect(
      project.path,
      p.join(app.path, 'generated', 'restage', 'render_bundle'),
    );
    expect(
      File(p.join(project.path, 'lib', 'user_factories.g.dart')).existsSync(),
      isTrue,
    );
  });

  test(
    'a rewrite keeps the caches and unchanged files, and drops the rest',
    () async {
      final project = await writeProject();
      final pubspec = File(p.join(project.path, 'pubspec.yaml'));
      final written = DateTime.utc(2001);
      pubspec.setLastModifiedSync(written);
      write('app/.restage/build/render_bundle/.dart_tool/cache', 'kept');
      write('app/.restage/build/render_bundle/stale/file.txt', 'stale');
      File(p.join(app.path, 'assets', 'extra.json')).deleteSync();

      await writeProject();

      expect(pubspec.lastModifiedSync().toUtc(), written);
      expect(
        File(p.join(project.path, '.dart_tool', 'cache')).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(project.path, 'stale')).existsSync(), isFalse);
      expect(
        FileSystemEntity.typeSync(
          p.join(project.path, 'assets', 'extra.json'),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
      expect(
        File(p.join(app.path, 'fonts', 'Inter.ttf')).existsSync(),
        isTrue,
        reason: 'the app files a link pointed at are never touched',
      );
      expect(
        File(p.join(app.path, 'lib', 'user_factories.g.dart')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'a project resolves again only when its pubspec or SDK changes',
    () async {
      final sdk = Directory(p.join(root.path, 'flutter'));
      final project = await writeProject();
      expect(isRenderBundleProjectResolved(project, flutterRoot: sdk), isFalse);
      write(
        'app/.restage/build/render_bundle/.dart_tool/package_config.json',
        '{}',
      );
      await markRenderBundleProjectResolved(project, flutterRoot: sdk);
      expect(isRenderBundleProjectResolved(project, flutterRoot: sdk), isTrue);

      await writeProject();
      expect(isRenderBundleProjectResolved(project, flutterRoot: sdk), isTrue);
      expect(
        isRenderBundleProjectResolved(
          project,
          flutterRoot: Directory(p.join(root.path, 'other_flutter')),
        ),
        isFalse,
        reason: 'another Flutter SDK resolves again',
      );

      write('app/assets/more.json', '{}');
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(
        File(p.join(app.path, 'pubspec.yaml')).readAsStringSync().replaceFirst(
          '    - path: assets/extra.json\n',
          '    - assets/more.json\n',
        ),
      );
      await writeProject();
      expect(isRenderBundleProjectResolved(project, flutterRoot: sdk), isFalse);
    },
  );

  test('a workspace member is pinned to the path it resolved to', () async {
    // The workspace root holds the package configuration.
    Directory(p.join(app.path, '.dart_tool')).deleteSync(recursive: true);
    resolve(
      at: '.',
      roots: <String, String>{
        'workspace': '../',
        'habit': '../app',
        'restage': '../cache/restage',
        'meta': '../cache/meta',
        'charts': '../cache/charts',
        'local_widgets': '../local_widgets',
        'flutter': '../flutter/packages/flutter',
      },
      graph: <String, List<String>>{...graph, 'workspace': <String>[]},
    );

    final pubspec = pubspecOf(await writeProject());
    expect(pubspec['dependency_overrides']['restage'], <String, Object?>{
      'path': p.join(root.path, 'cache', 'restage'),
    });
    expect(
      (pubspec['dependency_overrides'] as YamlMap).containsKey('workspace'),
      isFalse,
    );
  });

  test(
    'a workspace resolution that maps the app elsewhere is refused',
    () async {
      Directory(p.join(app.path, '.dart_tool')).deleteSync(recursive: true);
      Directory(p.join(root.path, 'other')).createSync();
      resolve(
        at: '.',
        roots: <String, String>{
          'habit': '../other',
          'restage': '../cache/restage',
        },
        graph: graph,
      );
      await expectLater(
        writeProject(),
        _refusedWith('dependencies_unresolved'),
      );
    },
  );

  test('an app without generated factories is refused', () async {
    File(p.join(app.path, 'lib', 'user_factories.g.dart')).deleteSync();
    await expectLater(writeProject(), _refusedWith('factories_missing'));
    expect(Directory(p.join(app.path, '.restage')).existsSync(), isFalse);
  });

  test('an app whose dependencies were never resolved is refused', () async {
    File(p.join(app.path, '.dart_tool', 'package_graph.json')).deleteSync();
    await expectLater(writeProject(), _refusedWith('dependencies_unresolved'));
    Directory(p.join(app.path, '.dart_tool')).deleteSync(recursive: true);
    await expectLater(writeProject(), _refusedWith('dependencies_unresolved'));
  });

  test(
    'a restage checkout with the render host beside it pins that copy',
    () async {
      write(
        'cache/restage_render_host/pubspec.yaml',
        'name: restage_render_host\nversion: 2.3.1\n',
      );
      final pubspec = pubspecOf(await writeProject());

      expect(pubspec['dependencies']['restage_render_host'], 'any');
      expect(
        pubspec['dependency_overrides']['restage_render_host'],
        <String, Object?>{
          'path': p.join(root.path, 'cache', 'restage_render_host'),
        },
      );
    },
  );

  test('a sibling directory of another package is not taken', () async {
    write('cache/restage_render_host/pubspec.yaml', 'name: other\n');
    final pubspec = pubspecOf(await writeProject());

    expect(pubspec['dependencies']['restage_render_host'], '>=2.3.0 <2.4.0');
    expect(
      (pubspec['dependency_overrides'] as YamlMap).containsKey(
        'restage_render_host',
      ),
      isFalse,
    );
  });

  test('an app that resolves the render host itself keeps it', () async {
    resolve(
      at: 'app',
      roots: <String, String>{
        'habit': '../',
        'restage': '../../cache/restage',
        'restage_render_host': '../../vendor/restage_render_host',
        'meta': '../../cache/meta',
        'charts': '../../cache/charts',
        'build_runner': '../../cache/build_runner',
        'local_widgets': '../../local_widgets',
        'flutter': '../../flutter/packages/flutter',
      },
      graph: <String, List<String>>{
        ...graph,
        'habit': <String>[...graph['habit']!, 'restage_render_host'],
        'restage_render_host': <String>['restage'],
      },
    );
    final pubspec = pubspecOf(await writeProject());

    expect(pubspec['dependencies']['restage_render_host'], 'any');
    expect(
      pubspec['dependency_overrides']['restage_render_host'],
      <String, Object?>{
        'path': p.join(root.path, 'vendor', 'restage_render_host'),
      },
    );
  });

  test('a restage without a readable version is refused', () async {
    write('cache/restage/pubspec.yaml', 'name: restage\n');
    await expectLater(writeProject(), _refusedWith('render_host_missing'));
  });

  test('an app without restage is refused', () async {
    resolve(
      at: 'app',
      roots: <String, String>{
        'habit': '../',
        'meta': '../../cache/meta',
        'flutter': '../../flutter/packages/flutter',
      },
      graph: <String, List<String>>{
        'habit': <String>['flutter'],
        'flutter': <String>['meta'],
        'meta': <String>[],
        'build_runner': <String>[],
      },
    );
    await expectLater(writeProject(), _refusedWith('render_host_missing'));
  });

  test('an unreadable output_root is refused', () async {
    write('app/build.yaml', '''
global_options:
  restage_codegen:outputs:
    options:
      output_root: ../outside
''');
    await expectLater(writeProject(), _refusedWith('output_root'));
  });
}

Matcher _refusedWith(String reason) => throwsA(
  isA<RenderBundleBuildException>().having(
    (error) => error.reason.code,
    'reason',
    reason,
  ),
);
