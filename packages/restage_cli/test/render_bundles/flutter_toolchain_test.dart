import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/render_bundles/flutter_toolchain.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory project;
  late Map<String, String> versions;

  /// A Flutter SDK at [root] that reports [version].
  String sdk(String root, String version) {
    final flutter = File(p.join(temp.path, root, 'bin', 'flutter'))
      ..createSync(recursive: true);
    final executable = flutter.resolveSymbolicLinksSync();
    versions[executable] = version;
    return p.join(temp.path, root);
  }

  Future<ProcessResult> runner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final version = versions[executable];
    if (version == null) return ProcessResult(1, 1, '', '');
    return ProcessResult(
      1,
      0,
      jsonEncode(<String, String>{'frameworkVersion': version}),
      '',
    );
  }

  Future<FlutterToolchain> resolve({
    String? flagRoot,
    String? configRoot,
    Map<String, String> environment = const {},
  }) => resolveBuildFlutterToolchain(
    projectRoot: project,
    flagRoot: flagRoot,
    configRoot: configRoot,
    environment: environment,
    processRunner: runner,
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('flutter_toolchain_');
    project = Directory(p.join(temp.path, 'app'))..createSync();
    versions = <String, String>{};
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('uses the first Flutter found, whatever its version', () async {
    final path = sdk('path_flutter', '3.0.0');

    final toolchain = await resolve(
      environment: {'PATH': p.join(path, 'bin'), 'HOME': temp.path},
    );

    expect(toolchain.executable, p.join(path, 'bin', 'flutter'));
    expect(toolchain.root, path);
    expect(toolchain.source, 'PATH');
    expect(toolchain.version, '3.0.0');
  });

  test('uses the FVM link of the project or a parent first', () async {
    final link = sdk(p.join('.fvm', 'flutter_sdk'), '3.49.0-1.0.pre');
    sdk('path_flutter', '3.47.7');

    final toolchain = await resolve(
      environment: {
        'PATH': p.join(temp.path, 'path_flutter', 'bin'),
        'FLUTTER_ROOT': p.join(temp.path, 'path_flutter'),
      },
    );

    expect(toolchain.executable, p.join(link, 'bin', 'flutter'));
    expect(toolchain.source, 'FVM link at ${p.join(temp.path, '.fvm')}');
    expect(toolchain.version, '3.49.0-1.0.pre');
  });

  test('finds the version .fvmrc pins in the FVM cache', () async {
    File(
      p.join(project.path, '.fvmrc'),
    ).writeAsStringSync('{"flutter": "3.44.8"}');
    final cached = sdk(p.join('cache', 'versions', '3.44.8'), '3.44.8');
    final root = sdk('flutter_root', '3.47.7');

    final toolchain = await resolve(
      environment: {
        'FVM_CACHE_PATH': p.join(temp.path, 'cache'),
        'FLUTTER_ROOT': root,
      },
    );

    expect(toolchain.executable, p.join(cached, 'bin', 'flutter'));
    expect(toolchain.source, '.fvmrc at ${project.path}');
    expect(toolchain.version, '3.44.8');
  });

  test('finds the version .flutter-version pins in the FVM cache', () async {
    File(
      p.join(project.path, '.flutter-version'),
    ).writeAsStringSync('3.41.2\n');
    final cached = sdk(p.join('fvm', 'versions', '3.41.2'), '3.41.2');

    final toolchain = await resolve(environment: {'HOME': temp.path});

    expect(toolchain.executable, p.join(cached, 'bin', 'flutter'));
    expect(toolchain.source, '.flutter-version at ${project.path}');
  });

  test('a pin that is not installed falls through to FLUTTER_ROOT', () async {
    File(p.join(project.path, '.flutter-version')).writeAsStringSync('3.41.2');
    final root = sdk('flutter_root', '3.47.7');

    final toolchain = await resolve(
      environment: {'HOME': temp.path, 'FLUTTER_ROOT': root},
    );

    expect(toolchain.executable, p.join(root, 'bin', 'flutter'));
    expect(toolchain.source, 'FLUTTER_ROOT');
  });

  test('a pin naming a path is ignored', () async {
    File(
      p.join(project.path, '.flutter-version'),
    ).writeAsStringSync('../../elsewhere');
    sdk(p.join('fvm', 'versions', '..', '..', 'elsewhere'), '1.0.0');

    await expectLater(
      resolve(environment: {'HOME': temp.path}),
      throwsA(isA<FlutterToolchainException>()),
    );
  });

  test('uses a named root at any version', () async {
    final root = sdk('pinned', '3.0.0');
    sdk('path_flutter', '3.47.7');

    final toolchain = await resolve(
      configRoot: root,
      environment: {'PATH': p.join(temp.path, 'path_flutter', 'bin')},
    );

    expect(toolchain.executable, p.join(root, 'bin', 'flutter'));
    expect(toolchain.source, 'flutterRoot in restage_config.yaml');
    expect(toolchain.version, '3.0.0');
  });

  test('a named root that reports no version is refused', () async {
    final root = sdk('broken', '3.0.0');
    versions.clear();

    await expectLater(
      resolve(flagRoot: root),
      throwsA(
        isA<FlutterToolchainException>().having(
          (e) => e.message,
          'message',
          contains(
            'The Flutter at $root (--flutter-root) did not report its version.',
          ),
        ),
      ),
    );
  });

  test('says how to point the build at a Flutter when none is found', () async {
    await expectLater(
      resolve(),
      throwsA(
        isA<FlutterToolchainException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('No Flutter SDK was found.'),
            contains('run `restage build push --flutter-root <sdk directory>`'),
            isNot(contains('Install Flutter')),
          ),
        ),
      ),
    );
  });

  test('names the MCP argument when called through the MCP', () async {
    final error = await runZoned(
      () => resolve().then<Object?>((_) => null, onError: (Object e) => e),
      zoneValues: selectorSyntaxZoneValues(SelectorSyntax.mcp),
    );

    expect(
      (error! as FlutterToolchainException).message,
      allOf(
        contains('call restage_push_build with flutterRoot: <sdk directory>'),
        isNot(contains('--flutter-root')),
      ),
    );
  });

  test('a flag root wins over the configured one', () async {
    final flag = sdk('flag', '3.47.7');
    final configured = sdk('configured', '3.44.8');

    final toolchain = await resolve(flagRoot: flag, configRoot: configured);

    expect(toolchain.executable, p.join(flag, 'bin', 'flutter'));
    expect(toolchain.source, '--flutter-root');
  });
}
