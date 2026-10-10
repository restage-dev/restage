import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

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

    test('PASSes when no build config turns off icon tree shaking', () async {
      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('PASS  Icon tree shaking'));
      expect(stdout.toString(), isNot(contains('WARN  Icon')));
    });

    group('project config', () {
      late FileCredentialStore store;

      setUp(() async {
        store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
        await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString(
          'project: examples\napp: examples\n'
          'endpoint: https://api.example.com/\n',
        );
      });

      Future<int> runDoctorWith(http.Client client) => RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['doctor', '--directory', tempDir.path]);

      test('SKIPs the server check when not signed in', () async {
        final exitCode = await runDoctorWith(
          mockHttpClient((_) => fail('no request without a credential')),
        );
        expect(exitCode, 0);
        expect(stdout.toString(), contains('SKIP  Project config'));
        expect(stdout.toString(), contains('restage login'));
      });

      test('WARNs with the real projects when the configured one does not '
          'exist', () async {
        await seedCredential(store, endpoint: 'https://api.example.com/');
        final exitCode = await runDoctorWith(
          mockHttpClient((request) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return switch (body['method']) {
              'listMine' => http.Response(
                jsonEncode([
                  {'organizationId': 7, 'slug': 'acme', 'name': 'Acme'},
                ]),
                200,
              ),
              'listProjects' => http.Response(
                jsonEncode([
                  {'slug': 'default', 'name': 'Default'},
                ]),
                200,
              ),
              final method => throw StateError('Unexpected method: $method'),
            };
          }, withDefaultTargetDiscovery: false),
        );
        expect(exitCode, 0);
        expect(stdout.toString(), contains('WARN  Project config'));
        expect(
          stdout.toString(),
          contains(
            'restage_config.yaml names project `examples`, which does not '
            'exist in `acme`. Projects: `default`.',
          ),
        );
      });
    });

    test('WARNs when a Makefile carries the flag', () async {
      await File(
        p.join(tempDir.path, 'Makefile'),
      ).writeAsString('build:\n\tflutter build ios --no-tree-shake-icons\n');

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('WARN'));
      expect(stdout.toString(), contains('Makefile'));
    });

    test('WARNs when a CI workflow file carries the flag', () async {
      final workflows = Directory(p.join(tempDir.path, '.github', 'workflows'));
      await workflows.create(recursive: true);
      await File(p.join(workflows.path, 'release.yml')).writeAsString(
        'jobs:\n  build:\n    steps:\n'
        '      - run: flutter build appbundle --no-tree-shake-icons\n',
      );

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('WARN'));
    });

    test('WARNs when a release script carries the flag', () async {
      final scripts = Directory(p.join(tempDir.path, 'scripts'));
      await scripts.create(recursive: true);
      await File(p.join(scripts.path, 'release.sh')).writeAsString(
        '#!/usr/bin/env bash\nflutter build ios --no-tree-shake-icons\n',
      );

      final exitCode = await runDoctor();
      expect(exitCode, 0);
      expect(stdout.toString(), contains('WARN'));
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
      expect(stdout.toString(), contains('Icon tree shaking'));
    });
  });
}
