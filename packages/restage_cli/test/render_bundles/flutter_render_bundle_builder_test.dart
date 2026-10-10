import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_project.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// A Flutter version no build list names ahead of time.
const _flutterVersion = '3.99.0-0.1.pre';
const _engineRevision = 'af7e796e161ae0bb1ff0758c71a7105418bd9ded';

Future<String> _identityCatalogResolver(
  Directory projectRoot,
  String catalogJson,
) async => catalogJson;

void main() {
  // The engine script defines the loader before the build configuration, the
  // way a built output does.
  const safeBootstrap = '''
window._flutter ??= {};
window._flutter.loader ??= {load(){}};
_flutter.buildConfig = {"engineRevision":"test","builds":[{"compileTarget":"dart2wasm","renderer":"skwasm"}]};
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: 'assets/fonts/fallback/',
  },
});
''';
  // The fake build writes a small engine of its own; the set is derived from it.
  final engineJs = Uint8List.fromList(utf8.encode('canvaskit loader'));
  final engineWasm = Uint8List.fromList(utf8.encode('canvaskit runtime'));
  final engineSet = RenderBundleEngineSet(
    flutterVersion: _flutterVersion,
    engineRevision: _engineRevision,
    files: <RenderBundleEngineFile>[
      RenderBundleEngineFile(
        path: 'canvaskit.js',
        contentHash: 'sha256:${sha256.convert(engineJs)}',
        byteLength: engineJs.length,
      ),
      RenderBundleEngineFile(
        path: 'canvaskit.wasm',
        contentHash: 'sha256:${sha256.convert(engineWasm)}',
        byteLength: engineWasm.length,
      ),
    ],
  );

  late Directory root;
  late Directory project;
  late Directory sdk;
  late Directory scratch;
  late Directory generated;
  late File font;
  late File license;
  late List<({Directory projectRoot, String flutterVersion})> writes;

  Future<Directory> projectWriter({
    required Directory projectRoot,
    required String flutterVersion,
    required Uint8List fontBytes,
    required Uint8List licenseBytes,
  }) async {
    writes.add((projectRoot: projectRoot, flutterVersion: flutterVersion));
    generated.createSync(recursive: true);
    File(p.join(generated.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    return generated;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('render_builder_test_');
    project = Directory(p.join(root.path, 'project'))..createSync();
    sdk = Directory(p.join(root.path, 'flutter'))..createSync();
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    generated = Directory(
      p.join(project.path, '.restage', 'build', 'render_bundle'),
    );
    writes = [];
    font = File(
      p.join(
        sdk.path,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'Roboto-Regular.ttf',
      ),
    )..createSync(recursive: true);
    font.writeAsBytesSync(<int>[1, 2, 3, 4]);
    license = File(p.join(font.parent.path, 'Roboto_LICENSE.txt'))
      ..writeAsStringSync('Roboto test license');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<RenderBundleArtifact> buildCompatibilityWorkerScenario({
    Uri? controlOrigin,
    bool includeWorker = true,
    List<int> workerBytes = const <int>[],
    String bootstrap = safeBootstrap,
    String index =
        '<!doctype html><script src="flutter_bootstrap.js"></script>',
    bool workerIsLink = false,
    String? lastBuildId,
    String lastBuildIdPath = '.last_build_id',
    bool lastBuildIdIsDirectory = false,
    bool lastBuildIdIsLink = false,
    Map<String, String> extraFiles = const <String, String>{},
    bool symbolsIsDirectory = false,
    Uri? parentOrigin,
    bool pubFails = false,
  }) async {
    final scenarioScratch = Directory(p.join(root.path, 'scenario_scratch'))
      ..createSync();
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      if (arguments case ['--version', '--machine']) {
        return ProcessResult(
          1,
          0,
          '{"frameworkVersion":"$_flutterVersion",'
              '"engineRevision":"$_engineRevision"}',
          '',
        );
      }
      if (arguments case ['pub', 'get']) {
        return ProcessResult(4, pubFails ? 1 : 0, '', '');
      }
      if (arguments case ['build', 'web', ...]) {
        final outputIndex = arguments.indexOf('--output');
        final output = Directory(arguments[outputIndex + 1])
          ..createSync(recursive: true);
        File(p.join(output.path, 'index.html')).writeAsStringSync(index);
        File(
          p.join(output.path, 'flutter_bootstrap.js'),
        ).writeAsStringSync(bootstrap);
        final wasm = File(p.join(output.path, 'main.dart.wasm'))
          ..writeAsBytesSync(Uint8List.fromList(<int>[9, 8, 7]));
        File(p.join(output.path, 'canvaskit', 'canvaskit.js'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(engineJs);
        File(p.join(output.path, 'canvaskit', 'canvaskit.wasm'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(engineWasm);
        if (includeWorker) {
          final workerPath = p.join(output.path, 'flutter_service_worker.js');
          if (workerIsLink) {
            Link(workerPath).createSync(wasm.path);
          } else {
            File(workerPath).writeAsBytesSync(workerBytes);
          }
        }
        for (final extra in extraFiles.entries) {
          File(p.join(output.path, extra.key))
            ..createSync(recursive: true)
            ..writeAsStringSync(extra.value);
        }
        if (symbolsIsDirectory) {
          Directory(
            p.join(output.path, 'main.dart.wasm.symbols'),
          ).createSync(recursive: true);
        }
        if (lastBuildId != null ||
            lastBuildIdIsDirectory ||
            lastBuildIdIsLink) {
          final metadataPath = p.join(output.path, lastBuildIdPath);
          if (lastBuildIdIsDirectory) {
            Directory(metadataPath).createSync(recursive: true);
          } else if (lastBuildIdIsLink) {
            Link(metadataPath).createSync(wasm.path, recursive: true);
          } else {
            File(metadataPath)
              ..createSync(recursive: true)
              ..writeAsStringSync(lastBuildId!);
          }
        }
        return ProcessResult(2, 0, '', '');
      }
      if (executable.endsWith('chmod')) {
        return ProcessResult(3, 0, '', '');
      }
      throw StateError('unexpected process: $executable $arguments');
    }

    final builder = FlutterRenderBundleBuilder(
      processRunner: runner,
      tempDirectoryCreator: (_) async => scenarioScratch,
      catalogResolver: _identityCatalogResolver,
      flutterExecutable: p.join(sdk.path, 'bin', 'flutter'),
      fontAuthority: RenderBundleFontAuthority(
        fontFile: font,
        licenseFile: license,
        fontSha256: sha256.convert(font.readAsBytesSync()).toString(),
        licenseSha256: sha256.convert(license.readAsBytesSync()).toString(),
      ),
      projectWriter: projectWriter,
    );

    try {
      return await builder.build(
        projectRoot: project,
        catalogJson: '{"libraries":{},"widgets":[]}',
        parentOrigin:
            parentOrigin ??
            Uri.parse('http://dashboard.restage.localhost:8082'),
        controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
      );
    } finally {
      expect(scenarioScratch.existsSync(), isFalse);
    }
  }

  test('a build configuration without a skwasm build is refused', () async {
    await expectLater(
      buildCompatibilityWorkerScenario(
        includeWorker: false,
        bootstrap: safeBootstrap.replaceAll('"skwasm"', '"canvaskit"'),
      ),
      throwsA(
        isA<RenderBundleBuildException>().having(
          (e) => e.reason,
          'reason',
          'loader_contract',
        ),
      ),
    );
  });

  test(
    'keeps a >128 KiB catalog out of two byte-identical build arguments',
    () async {
      final catalogJson = jsonEncode(<String, Object?>{
        'libraries': <String, Object?>{
          'package:café/widgets.dart': <String, Object?>{
            'capabilityVersion': 1,
          },
        },
        'widgets': <Object?>[
          <String, Object?>{
            'library': 'package:café/widgets.dart',
            'name': 'PulseBadge',
            'wireId': 'pulse_badge',
          },
        ],
        'largeMetadata': 'x' * (129 * 1024),
      });
      expect(utf8.encode(catalogJson).length, greaterThan(128 * 1024));
      final calls = <({String executable, List<String> arguments})>[];
      final defineDocuments = <Map<String, dynamic>>[];
      final defineFileLengths = <int>[];
      var buildNumber = 0;
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        calls.add((executable: executable, arguments: List.of(arguments)));
        if (arguments case ['--version', '--machine']) {
          return ProcessResult(
            1,
            0,
            '{"frameworkVersion":"$_flutterVersion",'
                '"engineRevision":"$_engineRevision"}',
            '',
          );
        }
        if (arguments case ['pub', 'get']) {
          expect(workingDirectory, generated.path);
          return ProcessResult(4, 0, '', '');
        }
        if (arguments case ['build', 'web', ...]) {
          buildNumber++;
          expect(workingDirectory, generated.path);
          final outputIndex = arguments.indexOf('--output');
          expect(outputIndex, isNonNegative);
          final defineArgument = arguments.singleWhere(
            (argument) => argument.startsWith('--dart-define-from-file='),
          );
          final output = Directory(arguments[outputIndex + 1])
            ..createSync(recursive: true);
          final defineFile = File(
            defineArgument.substring('--dart-define-from-file='.length),
          );
          defineFileLengths.add(defineFile.lengthSync());
          defineDocuments.add(
            jsonDecode(defineFile.readAsStringSync()) as Map<String, dynamic>,
          );
          File(p.join(output.path, 'index.html')).writeAsStringSync(
            '<!doctype html><script src="flutter_bootstrap.js"></script>',
          );
          File(
            p.join(output.path, 'flutter_bootstrap.js'),
          ).writeAsStringSync(safeBootstrap);
          File(
            p.join(output.path, 'flutter_service_worker.js'),
          ).writeAsBytesSync(Uint8List(0));
          File(p.join(output.path, '.last_build_id')).writeAsStringSync(
            buildNumber.isOdd
                ? '0123456789abcdef0123456789abcdef'
                : 'fedcba9876543210fedcba9876543210',
          );
          File(
            p.join(output.path, 'main.dart.wasm'),
          ).writeAsBytesSync(Uint8List.fromList(<int>[9, 8, 7]));
          File(p.join(output.path, 'canvaskit', 'canvaskit.js'))
            ..createSync(recursive: true)
            ..writeAsBytesSync(engineJs);
          File(p.join(output.path, 'canvaskit', 'canvaskit.wasm'))
            ..createSync(recursive: true)
            ..writeAsBytesSync(engineWasm);
          return ProcessResult(2, 0, 'ignored stdout $buildNumber', '');
        }
        if (executable.endsWith('chmod')) {
          return ProcessResult(3, 0, '', '');
        }
        throw StateError('unexpected process: $executable $arguments');
      }

      final builder = FlutterRenderBundleBuilder(
        processRunner: runner,
        tempDirectoryCreator: (_) async => scratch,
        catalogResolver: _identityCatalogResolver,
        flutterExecutable: p.join(sdk.path, 'bin', 'flutter'),
        fontAuthority: RenderBundleFontAuthority(
          fontFile: font,
          licenseFile: license,
          fontSha256: sha256.convert(font.readAsBytesSync()).toString(),
          licenseSha256: sha256.convert(license.readAsBytesSync()).toString(),
        ),
        projectWriter: projectWriter,
      );
      final artifact = await builder.build(
        projectRoot: project,
        catalogJson: catalogJson,
        parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
        controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
      );

      expect(artifact.appFiles, isNotEmpty);
      final buildCalls = calls
          .where((call) => call.arguments.take(2).join(' ') == 'build web')
          .toList();
      expect(buildCalls, hasLength(2));
      for (final call in buildCalls) {
        expect(call.executable, p.join(sdk.path, 'bin', 'flutter'));
        expect(
          call.arguments.map(utf8.encode).map((bytes) => bytes.length),
          everyElement(lessThan(4096)),
        );
        final stableArguments = List<String>.of(call.arguments);
        final outputIndex = stableArguments.indexOf('--output');
        stableArguments.removeRange(outputIndex, outputIndex + 2);
        stableArguments.removeWhere(
          (argument) => argument.startsWith('--dart-define-from-file='),
        );
        expect(stableArguments, <String>[
          'build',
          'web',
          '--release',
          '--wasm',
          '--csp',
          '--no-web-resources-cdn',
          '--pwa-strategy=none',
          '--no-tree-shake-icons',
          '--no-pub',
          '--target',
          renderBundleEntrypoint,
        ]);
      }
      expect(defineDocuments, hasLength(2));
      expect(defineFileLengths, everyElement(lessThan(1024)));
      for (final document in defineDocuments) {
        expect(document.keys, <String>{'RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN'});
        expect(
          document['RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN'],
          'http://dashboard.restage.localhost:8082',
        );
      }
      expect(
        artifact.appFiles[renderBundleCapabilityManifestPath],
        createRenderBundleCapabilityManifest(catalogJson),
      );
      expect(writes, hasLength(1));
      expect(writes.single.projectRoot.path, project.path);
      expect(writes.single.flutterVersion, _flutterVersion);
      // The engine set comes from what this SDK's build wrote.
      expect(artifact.engineSetId, engineSet.id);
      expect(artifact.flutterVersion, _flutterVersion);
      expect(artifact.engineSet.files.map((file) => file.path), <String>[
        'canvaskit.js',
        'canvaskit.wasm',
      ]);
      expect(
        utf8.decode(artifact.appFiles['flutter_bootstrap.js']!),
        contains('/render-bundles/v1/engine/${engineSet.id}/'),
      );
      expect(
        calls.where((call) => call.arguments.join(' ') == 'pub get'),
        hasLength(1),
      );
      expect(scratch.existsSync(), isFalse);
    },
  );

  test('rejects nonempty or linked compatibility service workers', () async {
    await expectLater(
      buildCompatibilityWorkerScenario(workerBytes: <int>[1]),
      throwsA(isA<RenderBundleBuildException>()),
    );
    if (!Platform.isWindows) {
      await expectLater(
        buildCompatibilityWorkerScenario(workerIsLink: true),
        throwsA(isA<RenderBundleBuildException>()),
      );
    }
  });

  test('rejects active compatibility service-worker dependencies', () async {
    await expectLater(
      buildCompatibilityWorkerScenario(
        bootstrap: safeBootstrap.replaceFirst(
          '_flutter.loader.load({',
          "_flutter.loader.load({\n  serviceWorkerSettings: {"
              "serviceWorkerUrl: 'flutter_service_worker.js'},",
        ),
      ),
      throwsA(isA<RenderBundleBuildException>()),
    );
    await expectLater(
      buildCompatibilityWorkerScenario(
        index:
            '<!doctype html><script>'
            "navigator.serviceWorker.register('flutter_service_worker.js');"
            '</script>',
      ),
      throwsA(isA<RenderBundleBuildException>()),
    );
  });

  test(
    'a project already resolved against its pubspec skips pub get',
    () async {
      File(p.join(generated.path, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File(
        p.join(generated.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: x\n');
      await markRenderBundleProjectResolved(generated, flutterRoot: sdk);

      // A pub get would fail here, so the build shows it never ran.
      final artifact = await buildCompatibilityWorkerScenario(
        includeWorker: false,
        pubFails: true,
      );
      expect(artifact.appFiles, isNotEmpty);
    },
  );

  test('rejects malformed or nonregular last-build metadata', () async {
    for (final lastBuildId in <String>[
      '0123456789abcdef0123456789abcde',
      '0123456789abcdef0123456789abcdeF',
    ]) {
      await expectLater(
        buildCompatibilityWorkerScenario(lastBuildId: lastBuildId),
        throwsA(isA<RenderBundleBuildException>()),
      );
    }
    await expectLater(
      buildCompatibilityWorkerScenario(lastBuildIdIsDirectory: true),
      throwsA(isA<RenderBundleBuildException>()),
    );
    if (!Platform.isWindows) {
      await expectLater(
        buildCompatibilityWorkerScenario(lastBuildIdIsLink: true),
        throwsA(isA<RenderBundleBuildException>()),
      );
    }
  });

  test('omits the build symbol maps and keeps everything else', () async {
    final artifact = await buildCompatibilityWorkerScenario(
      extraFiles: <String, String>{
        'main.dart.wasm.symbols': 'wasm symbol map',
        'main.dart.js.symbols': 'js symbol map',
        'nested/main.dart.wasm.symbols': 'not the build output',
        'assets/glyphs/math.symbols': 'a bundled asset',
      },
    );
    final files = artifact.appFiles;

    expect(files, isNot(contains('main.dart.wasm.symbols')));
    expect(files, isNot(contains('main.dart.js.symbols')));
    // Only the build's own root outputs go; anything else a project ships
    // under the same suffix has to survive, or it 404s at runtime.
    expect(files, contains('nested/main.dart.wasm.symbols'));
    expect(files, contains('assets/glyphs/math.symbols'));
    expect(files, contains('main.dart.wasm'));
  });

  test('refuses a symbol-map path that is not a regular file', () async {
    await expectLater(
      buildCompatibilityWorkerScenario(symbolsIsDirectory: true),
      throwsA(isA<RenderBundleBuildException>()),
    );
  });

  test('rejects nested or case-varied last-build metadata', () async {
    for (final path in <String>['nested/.last_build_id', '.LAST_BUILD_ID']) {
      await expectLater(
        buildCompatibilityWorkerScenario(
          lastBuildId: '0123456789abcdef0123456789abcdef',
          lastBuildIdPath: path,
        ),
        throwsA(isA<RenderBundleBuildException>()),
      );
    }
  });

  test(
    'fails before build on Flutter drift and still removes temp files',
    () async {
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async => ProcessResult(
        1,
        0,
        '{"frameworkVersion":"3.44.4","engineRevision":"$_engineRevision"}',
        '',
      );
      final builder = FlutterRenderBundleBuilder(
        processRunner: runner,
        tempDirectoryCreator: (_) async => scratch,
        catalogResolver: _identityCatalogResolver,
        flutterExecutable: p.join(sdk.path, 'bin', 'flutter'),
        fontAuthority: RenderBundleFontAuthority(
          fontFile: font,
          licenseFile: license,
          fontSha256: sha256.convert(font.readAsBytesSync()).toString(),
          licenseSha256: sha256.convert(license.readAsBytesSync()).toString(),
        ),
      );

      await expectLater(
        builder.build(
          projectRoot: project,
          catalogJson: '{"libraries":{},"widgets":[]}',
          parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
          controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
        ),
        throwsA(isA<RenderBundleBuildException>()),
      );
      expect(scratch.existsSync(), isFalse);
    },
  );

  test(
    'rejects credential-bearing catalog before creating private temp',
    () async {
      var tempCreations = 0;
      final builder = FlutterRenderBundleBuilder(
        tempDirectoryCreator: (_) async {
          tempCreations++;
          return scratch;
        },
        catalogResolver: _identityCatalogResolver,
        flutterExecutable: p.join(sdk.path, 'bin', 'flutter'),
        fontAuthority: RenderBundleFontAuthority(
          fontFile: font,
          licenseFile: license,
          fontSha256: sha256.convert(font.readAsBytesSync()).toString(),
          licenseSha256: sha256.convert(license.readAsBytesSync()).toString(),
        ),
      );

      await expectLater(
        builder.build(
          projectRoot: project,
          catalogJson:
              '{"libraries":{},"widgets":[],"nested":{"authCredentials":"no"}}',
          parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
          controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
        ),
        throwsA(isA<RenderBundleBuildException>()),
      );
      expect(tempCreations, 0);
    },
  );

  for (final failing in <String>['pub', 'build']) {
    test('names the generated project when `$failing` fails', () async {
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        if (arguments case ['--version', '--machine']) {
          return ProcessResult(
            1,
            0,
            '{"frameworkVersion":"$_flutterVersion",'
                '"engineRevision":"$_engineRevision"}',
            '',
          );
        }
        if (executable.endsWith('chmod')) return ProcessResult(3, 0, '', '');
        return ProcessResult(4, arguments.first == failing ? 1 : 0, '', '');
      }

      final builder = FlutterRenderBundleBuilder(
        processRunner: runner,
        tempDirectoryCreator: (_) async => scratch,
        catalogResolver: _identityCatalogResolver,
        flutterExecutable: p.join(sdk.path, 'bin', 'flutter'),
        fontAuthority: RenderBundleFontAuthority(
          fontFile: font,
          licenseFile: license,
          fontSha256: sha256.convert(font.readAsBytesSync()).toString(),
          licenseSha256: sha256.convert(license.readAsBytesSync()).toString(),
        ),
        projectWriter: projectWriter,
      );

      await expectLater(
        builder.build(
          projectRoot: project,
          catalogJson: '{"libraries":{},"widgets":[]}',
          parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
          controlOrigin: Uri.parse('http://bundles.restage.localhost:8081'),
        ),
        throwsA(
          isA<RenderBundleBuildException>()
              .having(
                (error) => error.reason,
                'reason',
                failing == 'pub'
                    ? 'dependencies_failed'
                    : 'flutter_build_failed',
              )
              .having(
                (error) => error.detail,
                'detail',
                p.join('.restage', 'build', 'render_bundle'),
              ),
        ),
      );
      expect(scratch.existsSync(), isFalse);
    });
  }
}
