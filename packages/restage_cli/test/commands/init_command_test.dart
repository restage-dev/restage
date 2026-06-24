import 'dart:io';

import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _starterPubspec = '''
name: my_app
description: A sample app.

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
''';

Future<void> _writePubspec(
  Directory dir, [
  String content = _starterPubspec,
]) async {
  await File(p.join(dir.path, 'pubspec.yaml')).writeAsString(content);
}

void main() {
  late Directory tempDir;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('init_cmd_');
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage init', () {
    test(
      '--non-interactive with all flags writes the three artifacts',
      () async {
        await _writePubspec(tempDir);

        final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run([
          '--non-interactive',
          'init',
          '--directory',
          tempDir.path,
          '--project',
          'my-project',
          '--app',
          'my-app',
          '--env',
          'dev',
        ]);

        expect(exitCode, 0);

        // restage_config.yaml exists and parses.
        final config = await loadRestageConfig(from: tempDir);
        expect(config, isNotNull);
        expect(config!.config.project, 'my-project');
        expect(config.config.app, 'my-app');
        expect(config.config.defaultEnvironment, 'dev');

        // Starter paywall written.
        final starter = File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        );
        expect(starter.existsSync(), isTrue);
        expect(
          await starter.readAsString(),
          contains("@PaywallSource(id: 'starter')"),
        );

        // Pubspec edits applied.
        final pubspecContent = await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsString();
        expect(pubspecContent, contains('restage'));
        expect(pubspecContent, contains('restage_codegen'));
        expect(pubspecContent, contains('build_runner'));
      },
    );

    test('--dry-run prints the planned changes without writing', () async {
      await _writePubspec(tempDir);

      final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run([
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
        '--dry-run',
      ]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('restage_config.yaml'));
      expect(stdout.toString(), contains('restage'));

      // Verify the filesystem was untouched.
      expect(
        File(p.join(tempDir.path, 'restage_config.yaml')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        ).existsSync(),
        isFalse,
      );
      final pubspecContent = await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspecContent, _starterPubspec);
    });

    test('missing pubspec exits 1 with a clear message', () async {
      // No pubspec.yaml in tempDir.

      final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run([
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
      ]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('pubspec.yaml'));
    });

    for (final (:flag, :args) in const [
      (flag: '--project', args: ['--app', 'a', '--env', 'dev']),
      (flag: '--app', args: ['--project', 'p', '--env', 'dev']),
      (flag: '--env', args: ['--project', 'p', '--app', 'a']),
    ]) {
      test(
        '--non-interactive without $flag exits 1 with a usage hint',
        () async {
          await _writePubspec(tempDir);

          final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run(
            ['--non-interactive', 'init', '--directory', tempDir.path, ...args],
          );

          expect(exitCode, 1);
          expect(stderr.toString(), contains(flag));
        },
      );
    }

    test('re-run is idempotent: existing config + deps kept; exit 0', () async {
      await _writePubspec(tempDir);

      final args = [
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
      ];

      var exitCode = await RestageCli(stdout: stdout, stderr: stderr).run(args);
      expect(exitCode, 0);
      stdout.clear();
      stderr.clear();

      exitCode = await RestageCli(stdout: stdout, stderr: stderr).run(args);
      expect(exitCode, 0);
      // Either explicit `kept` reporting in stdout or simply a clean
      // exit is acceptable; the load-bearing assertion is that the
      // second run does not blow up on existing artifacts.
      final config = await loadRestageConfig(from: tempDir);
      expect(config, isNotNull);
    });

    test('skips the starter paywall when --no-starter is passed', () async {
      await _writePubspec(tempDir);

      final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run([
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
        '--no-starter',
      ]);

      expect(exitCode, 0);
      expect(
        File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        ).existsSync(),
        isFalse,
      );
    });

    test('skips pubspec edits when --no-wire-deps is passed', () async {
      await _writePubspec(tempDir);

      final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run([
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
        '--no-wire-deps',
      ]);

      expect(exitCode, 0);
      final pubspecContent = await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspecContent, isNot(contains('restage')));
    });
  });
}
