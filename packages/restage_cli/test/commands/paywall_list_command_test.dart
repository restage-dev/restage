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
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paywall_list_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage paywall list', () {
    test('default render is a tab-separated table with a header', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        return http.Response(
          jsonEncode([
            {
              '__className__': 'PaywallSummary',
              'slug': 'hello',
              'name': 'Hello',
              'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
              'publishedVersionByEnvironment': {
                'dev': 3,
                'staging': 2,
                'prod': null,
              },
            },
            {
              '__className__': 'PaywallSummary',
              'slug': 'starter',
              'name': 'Starter',
              'draftUpdatedAt': '2026-05-01T10:00:00.000Z',
              'publishedVersionByEnvironment': {
                'dev': null,
                'staging': null,
                'prod': null,
              },
            },
          ]),
          200,
        );
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 0);
      final out = stdout.toString();
      expect(out, contains('SLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED'));
      final lines = const LineSplitter().convert(out.trim());
      // Header + 2 paywalls.
      expect(lines.length, 3);
      // Row 1: hello with all three envs (prod null is omitted).
      expect(
        lines[1],
        'hello\tHello\t2026-05-01T12:34:56.000Z\tdev=3, staging=2',
      );
      // Row 2: starter has no published versions, prints `-`.
      expect(lines[2], 'starter\tStarter\t2026-05-01T10:00:00.000Z\t-');
    });

    test('--json emits a JSON array of summaries', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        return http.Response(
          jsonEncode([
            {
              '__className__': 'PaywallSummary',
              'slug': 'hello',
              'name': 'Hello',
              'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
              'publishedVersionByEnvironment': {'dev': 3},
            },
          ]),
          200,
        );
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '--json', '-C', tempDir.path]);

      expect(exitCode, 0);
      final decoded = jsonDecode(stdout.toString()) as List<dynamic>;
      expect(decoded.length, 1);
      expect((decoded[0] as Map<String, dynamic>)['slug'], 'hello');
      expect(
        (decoded[0] as Map<String, dynamic>)['publishedVersionByEnvironment'],
        {'dev': 3},
      );
    });

    test('--project / --app override the config defaults', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'config-proj', 'config-app');

      late Map<String, dynamic> seenBody;
      final client = mockHttpClient((req) {
        seenBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('[]', 200);
      });

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
          ).run([
            'paywall',
            'list',
            '--project',
            'flag-proj',
            '--app',
            'flag-app',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0);
      expect(seenBody['projectSlug'], 'flag-proj');
      expect(seenBody['appSlug'], 'flag-app');
    });

    test('errors when no project context is available', () async {
      await seedCredential(store);
      // No restage_config.yaml, no --project/--app flags.

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('restage init'));
      expect(stderr.toString(), contains('--project'));
    });

    test('errors when not signed in', () async {
      // No credential written.
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('restage login'));
    });

    test('surfaces a ProjectNotFound typed exception', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        return http.Response(
          jsonEncode({
            'className': 'ProjectNotFoundException',
            'data': {
              '__className__': 'ProjectNotFoundException',
              'slug': 'demo',
            },
          }),
          400,
        );
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('demo'));
      expect(stderr.toString().toLowerCase(), contains('project'));
    });

    test(
      'keeps paywall-specific typed exceptions out of generic HTTP fallback',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');

        final client = mockHttpClient((req) {
          return http.Response(
            jsonEncode({
              'className': 'PaywallNotFoundException',
              'data': {
                '__className__': 'PaywallNotFoundException',
                'paywallSlug': 'missing',
              },
            }),
            400,
          );
        });

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['paywall', 'list', '-C', tempDir.path]);

        expect(exitCode, 1);
        expect(stderr.toString(), contains('PaywallNotFound'));
        expect(stderr.toString(), contains('missing'));
        expect(stderr.toString(), isNot(contains('Could not contact')));
      },
    );

    test('surfaces a network error with exit code 2', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        throw const SocketException('connection refused');
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 2);
      expect(stderr.toString().toLowerCase(), contains('could not'));
    });
  });
}
