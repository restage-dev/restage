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
          _scopeBody([
            {
              '__className__': 'SurfaceSummary',
              'slug': 'hello',
              'name': 'Hello',
              'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
              // Both staging targets share the slug, so the slug map holds
              // the live plane's empty answer.
              'publishedVersionByEnvironment': {
                'dev': 3,
                'staging': null,
                'prod': null,
              },
              'targetPublications': [
                _publication(1, 'dev', 'sandbox', 3),
                _publication(2, 'staging', 'sandbox', 2),
                _publication(3, 'staging', 'live', null),
                _publication(4, 'prod', 'live', null),
              ],
            },
            {
              '__className__': 'SurfaceSummary',
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
      }, withDefaultTargetDiscovery: false);

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
      // Row 1: each serving target by environment and plane.
      expect(
        lines[1],
        'hello\tHello\t2026-05-01T12:34:56.000Z\t'
        'dev/sandbox v3, staging/sandbox v2',
      );
      // Row 2: starter has no published versions, prints `-`.
      expect(lines[2], 'starter\tStarter\t2026-05-01T10:00:00.000Z\t-');
    });

    test('--json emits a JSON array of summaries', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        return http.Response(
          _scopeBody([
            {
              '__className__': 'SurfaceSummary',
              'slug': 'hello',
              'name': 'Hello',
              'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
              'publishedVersionByEnvironment': {'dev': 3},
              'targetPublications': [_publication(1, 'dev', 'sandbox', 3)],
            },
          ]),
          200,
        );
      }, withDefaultTargetDiscovery: false);

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
      expect((decoded[0] as Map<String, dynamic>)['published'], [
        {
          'environmentTargetId': 1,
          'environmentSlug': 'dev',
          'runtimePlane': 'sandbox',
          'version': 3,
        },
      ]);
    });

    test('--project / --app override the config defaults', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'config-proj', 'config-app');

      late Map<String, dynamic> seenBody;
      final client = mockHttpClient((req) {
        seenBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(_scopeBody([]), 200);
      }, withDefaultTargetDiscovery: false);

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
      expect(seenBody['method'], 'read');
      expect(stdout.toString(), 'SLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED\n');
    });

    test('resolves configured organization before listing', () async {
      await seedCredential(store);
      await seedRestageConfig(
        tempDir,
        'demo',
        'mobile',
        organization: 'restage',
      );

      final calls = <Map<String, dynamic>>[];
      final client = mockHttpClient((req) {
        calls.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(_scopeBody([]), 200);
      }, withDefaultTargetDiscovery: false);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(calls, hasLength(1));
      expect(calls.single['method'], 'read');
    });

    test('asks for --project when several projects could apply', () async {
      await seedCredential(store);
      // No restage_config.yaml, no --project/--app flags.
      final client = mockHttpClient(
        (req) => http.Response(_scopeBody([], projects: ['one', 'two']), 200),
        withDefaultTargetDiscovery: false,
      );

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('Pass --project <slug>.'));
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

    test(
      'refuses a configured project absent from the admitted scope',
      () async {
        await seedCredential(store);
        await seedRestageConfig(tempDir, 'demo', 'mobile');

        final calls = <Map<String, dynamic>>[];
        final client = mockHttpClient((req) {
          calls.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(_scopeBody([], projects: ['other']), 200);
        }, withDefaultTargetDiscovery: false);

        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: client,
        ).run(['paywall', 'list', '-C', tempDir.path]);

        expect(exitCode, 1);
        expect(calls, hasLength(1));
        expect(calls.single['method'], 'read');
        expect(stderr.toString(), contains('demo'));
        expect(stderr.toString().toLowerCase(), contains('project'));
      },
    );

    test('renders an empty admitted surface list', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final calls = <Map<String, dynamic>>[];
      final client = mockHttpClient((req) {
        calls.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(_scopeBody([]), 200);
      }, withDefaultTargetDiscovery: false);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['paywall', 'list', '-C', tempDir.path]);

      expect(exitCode, 0, reason: stderr.toString());
      expect(calls, hasLength(1));
      expect(calls.single['method'], 'read');
      expect(stdout.toString(), 'SLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED\n');
    });

    test('surfaces a network error with exit code 2', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        throw const SocketException('connection refused');
      }, withDefaultTargetDiscovery: false);

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

String _scopeBody(
  List<Map<String, Object?>> surfaces, {
  List<String> projects = const ['demo', 'config-proj', 'flag-proj'],
}) => jsonEncode({
  'organizationId': 7,
  'session': {
    'memberships': [
      {
        'organizationId': 7,
        'slug': 'restage',
        'name': 'Restage',
        'role': 'owner',
      },
    ],
    'workspaceExperiences': <Object>[],
  },
  'projects': [
    for (var i = 0; i < projects.length; i++)
      {'id': i + 1, 'slug': projects[i], 'name': projects[i]},
  ],
  'apps': [
    {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
    {'id': 6, 'projectId': 2, 'slug': 'config-app', 'name': 'Config App'},
    {'id': 7, 'projectId': 3, 'slug': 'flag-app', 'name': 'Flag App'},
  ],
  'environments': <Object>[],
  'environmentTargets': <Object>[],
  'surfaces': [
    for (final surface in surfaces)
      {'appId': 5, 'surfaceType': 'paywall', ...surface},
  ],
});

Map<String, Object?> _publication(
  int targetId,
  String environmentSlug,
  String runtimePlane,
  int? version,
) => {
  'target': {
    'environmentTargetId': targetId,
    'namedEnvironmentId': targetId,
    'environmentSlug': environmentSlug,
    'runtimePlane': runtimePlane,
  },
  'experimentSurfaceReferences': <Object>[],
  'publishedVersion': ?version,
};
