import 'dart:io';

import 'package:restage_cli/src/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('doctor_cmd_');
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> runDoctor() => RestageCli(
    stdout: stdout,
    stderr: stderr,
  ).run(['doctor', '--directory', tempDir.path]);

  group('restage doctor', () {
    test('runs and exits 0 on an empty project', () async {
      final exitCode = await runDoctor();
      expect(exitCode, 0);
    });

    test(
      'always prints the required flag and the tofu failure-mode explanation',
      () async {
        final exitCode = await runDoctor();
        expect(exitCode, 0);

        final out = stdout.toString();
        // The mechanical surfacing: the exact flag is named.
        expect(out, contains('--no-tree-shake-icons'));
        // The failure mode is explained in plain terms.
        expect(out, contains('tofu'));
        // The exact build commands are copy-pasteable.
        expect(out, contains('flutter build ios --no-tree-shake-icons'));
        expect(out, contains('flutter build web --wasm --no-tree-shake-icons'));
      },
    );

    test('WARNs when no build config mentions the flag', () async {
      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('WARN'));
      // The reminder block is still emitted on a WARN.
      expect(stdout.toString(), contains('--no-tree-shake-icons'));
    });

    test('PASSes when a Makefile carries the flag', () async {
      await File(
        p.join(tempDir.path, 'Makefile'),
      ).writeAsString('build:\n\tflutter build ios --no-tree-shake-icons\n');

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('PASS'));
      expect(stdout.toString(), contains('Makefile'));
    });

    test('PASSes when a CI workflow file carries the flag', () async {
      final workflows = Directory(p.join(tempDir.path, '.github', 'workflows'));
      await workflows.create(recursive: true);
      await File(p.join(workflows.path, 'release.yml')).writeAsString(
        'jobs:\n  build:\n    steps:\n'
        '      - run: flutter build appbundle --no-tree-shake-icons\n',
      );

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('PASS'));
    });

    test('PASSes when a release script carries the flag', () async {
      final scripts = Directory(p.join(tempDir.path, 'scripts'));
      await scripts.create(recursive: true);
      await File(p.join(scripts.path, 'release.sh')).writeAsString(
        '#!/usr/bin/env bash\nflutter build ios --no-tree-shake-icons\n',
      );

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('PASS'));
    });

    test('exits 1 with a clear message on a missing directory', () async {
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
      ).run(['doctor', '--directory', p.join(tempDir.path, 'does-not-exist')]);
      expect(exitCode, 1);
      expect(stderr.toString(), contains('No directory'));
    });

    test('works under the global --non-interactive flag', () async {
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
      ).run(['--non-interactive', 'doctor', '--directory', tempDir.path]);
      expect(exitCode, 0);
      expect(stdout.toString(), contains('--no-tree-shake-icons'));
    });
  });
}
