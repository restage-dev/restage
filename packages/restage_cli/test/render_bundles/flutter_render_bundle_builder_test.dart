import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:test/test.dart';

Future<String> _identityCatalogResolver(
  Directory projectRoot,
  String catalogJson,
) async => catalogJson;

Map<String, Uint8List> _archiveFiles(Uint8List archive) {
  const archivePreambleLength = 8;
  final manifestLength = ByteData.sublistView(
    archive,
  ).getUint32(archivePreambleLength);
  final manifestStart = archivePreambleLength + 4;
  final manifestEnd = manifestStart + manifestLength;
  final manifest =
      jsonDecode(utf8.decode(archive.sublist(manifestStart, manifestEnd)))
          as Map<String, dynamic>;
  final files = <String, Uint8List>{};
  var offset = manifestEnd;
  for (final entry in manifest['files']! as List<dynamic>) {
    final file = entry as Map<String, dynamic>;
    final length = file['length']! as int;
    files[file['path']! as String] = Uint8List.sublistView(
      archive,
      offset,
      offset + length,
    );
    offset += length;
  }
  return files;
}

void main() {
  const safeBootstrap = '''
window._flutter ??= {};
_flutter.buildConfig = {"engineRevision":"test","builds":[]};
_flutter.loader.load({
  config: {
    renderer: 'skwasm',
    fontFallbackBaseUrl: 'assets/fonts/fallback/',
  },
});
''';
  late Directory root;
  late Directory project;
  late Directory sdk;
  late Directory scratch;
  late File font;
  late File license;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('render_builder_test_');
    project = Directory(p.join(root.path, 'project'))..createSync();
    sdk = Directory(p.join(root.path, 'flutter'))..createSync();
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    File(p.join(project.path, 'lib', 'main_render_bundle.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
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

  Future<Uint8List> buildCompatibilityWorkerScenario({
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
    Uri? parentOrigin,
  }) async {
    final scenarioScratch = Directory(p.join(root.path, 'scenario_scratch'))
      ..createSync();
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      if (arguments case ['--version', '--machine']) {
        return ProcessResult(1, 0, '{"frameworkVersion":"3.44.8"}', '');
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
        if (includeWorker) {
          final workerPath = p.join(output.path, 'flutter_service_worker.js');
          if (workerIsLink) {
            Link(workerPath).createSync(wasm.path);
          } else {
            File(workerPath).writeAsBytesSync(workerBytes);
          }
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
    );

    try {
      return await builder.build(
        projectRoot: project,
        catalogJson: '{"libraries":{},"widgets":[]}',
        parentOrigin:
            parentOrigin ??
            Uri.parse('http://dashboard.restage.localhost:8082'),
      );
    } finally {
      expect(scenarioScratch.existsSync(), isFalse);
    }
  }

  test('rejects unapproved parent authorities before private temp', () async {
    var tempCreations = 0;
    final builder = FlutterRenderBundleBuilder(
      tempDirectoryCreator: (_) async {
        tempCreations++;
        return scratch;
      },
      catalogResolver: _identityCatalogResolver,
    );

    for (final origin in <String>[
      'http://localhost:8082',
      'http://127.0.0.1:8082',
      'http://api.restage.localhost:8082',
      'http://bundles.restage.localhost:8082',
      'http://dashboard.restage.localhost',
      'https://dashboard.restage.localhost:8082',
      'https://nested.dashboard.restage.dev',
      'https://dashboard.restage.dev:444',
      'http://dashboard.restage.dev',
      'https://user@dashboard.restage.dev',
      'https://dashboard.restage.dev/shell',
      'https://dashboard.example.test',
    ]) {
      await expectLater(
        builder.build(
          projectRoot: project,
          catalogJson: '{"libraries":{},"widgets":[]}',
          parentOrigin: Uri.parse(origin),
        ),
        throwsA(
          isA<RenderBundleBuildException>().having(
            (error) => error.reason,
            'reason',
            'parent_origin',
          ),
        ),
        reason: origin,
      );
    }
    expect(tempCreations, 0);
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
          return ProcessResult(1, 0, '{"frameworkVersion":"3.44.8"}', '');
        }
        if (arguments case ['build', 'web', ...]) {
          buildNumber++;
          expect(workingDirectory, project.path);
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
      );
      final archive = await builder.build(
        projectRoot: project,
        catalogJson: catalogJson,
        parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
      );

      expect(archive, isNotEmpty);
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
          '--target',
          'lib/main_render_bundle.dart',
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
        _archiveFiles(archive)[renderBundleCapabilityManifestPath],
        createRenderBundleCapabilityManifest(catalogJson),
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

  for (final origin in <String>[
    'http://dashboard.restage.localhost:8082',
    'https://dashboard.restage.dev',
  ]) {
    test('accepts finite parent authority $origin', () async {
      expect(
        await buildCompatibilityWorkerScenario(
          includeWorker: false,
          parentOrigin: Uri.parse(origin),
        ),
        isNotEmpty,
        reason: origin,
      );
    });
  }

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
      }) async => ProcessResult(1, 0, '{"frameworkVersion":"3.44.4"}', '');
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
        ),
        throwsA(isA<RenderBundleBuildException>()),
      );
      expect(tempCreations, 0);
    },
  );
}
