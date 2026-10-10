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
    tempDir = await Directory.systemTemp.createTemp('status_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('prints identity, endpoint, and active config context', () async {
    final calls = <Map<String, dynamic>>[];
    await seedCredential(store, endpoint: 'https://api.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
defaultEnvironment: staging
organization: default
endpoint: https://api.example.com/
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _statusClient(
        calls: calls,
        organizations: const <Map<String, dynamic>>[
          {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
          {'organizationId': 8, 'slug': 'sample', 'name': 'Sample'},
        ],
        workspaces: const <Map<String, dynamic>>[
          {
            'organizationId': 8,
            'provenance': 'customer',
            'hostedAccessState': 'productionEnabled',
            'productionAllowed': true,
          },
          {
            'organizationId': 7,
            'provenance': 'sample',
            'hostedAccessState': 'sandbox',
            'productionAllowed': false,
          },
        ],
      ),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 0);
    expect(calls, hasLength(1));
    final out = stdout.toString();
    expect(out, contains('signed in as dev@example.com'));
    expect(out, contains('endpoint: https://api.example.com/'));
    expect(out, contains('organization: default'));
    expect(out, contains('project: alpha'));
    expect(out, contains('app: mobile'));
    expect(out, contains('environment: staging'));
    expect(out, contains('workspace provenance: sample'));
    expect(out, contains('hosted access: sandbox'));
    expect(out, contains('production allowed: no'));
    expect(out, isNot(contains('workspace provenance: customer')));
    expect(
      out,
      contains(
        'config: project `alpha`, app `mobile` and environment `staging` exist',
      ),
    );
    expect(out, isNot(contains('config problem')));
  });

  test('names a configured project that does not exist, and the real '
      'ones', () async {
    await seedCredential(store, endpoint: 'https://api.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: examples
app: examples
organization: acme
endpoint: https://api.example.com/
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _statusClient(
        organizations: const <Map<String, dynamic>>[
          {'organizationId': 7, 'slug': 'acme', 'name': 'Acme'},
          {'organizationId': 8, 'slug': 'sample', 'name': 'Sample'},
        ],
        workspaces: const <Map<String, dynamic>>[],
        projects: const {
          7: ['default'],
        },
      ),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 0);
    expect(
      stdout.toString(),
      contains(
        'config problem: restage_config.yaml names project `examples`, '
        'which does not exist in `acme`. Projects: `default`.',
      ),
    );
  });

  test('names a configured app that does not exist, and the real '
      'ones', () async {
    await seedCredential(store, endpoint: 'https://api.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: examples
defaultEnvironment: prod
endpoint: https://api.example.com/
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _statusClient(
        organizations: const <Map<String, dynamic>>[
          {'organizationId': 7, 'slug': 'acme', 'name': 'Acme'},
          {'organizationId': 8, 'slug': 'sample', 'name': 'Sample'},
        ],
        workspaces: const <Map<String, dynamic>>[],
        projects: const {
          7: ['alpha'],
          8: ['other'],
        },
        apps: const ['default'],
        environments: const ['staging', 'dev'],
      ),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 0);
    final out = stdout.toString();
    expect(
      out,
      contains(
        'config problem: restage_config.yaml names app `examples`, which '
        'does not exist in project `alpha` of `acme`. Apps there: `default`.',
      ),
    );
    expect(
      out,
      contains(
        'config problem: restage_config.yaml names environment `prod`, '
        'which does not exist in project `alpha`. Environments there: '
        '`dev`, `staging`.',
      ),
    );
    expect(out, isNot(contains('You belong to')));
  });

  test(
    'reports an absent workspace projection without inventing state',
    () async {
      await seedCredential(store, endpoint: 'https://api.example.com/');
      await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
organization: default
endpoint: https://api.example.com/
''');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _statusClient(
          organizations: const <Map<String, dynamic>>[
            {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
          ],
          workspaces: const <Map<String, dynamic>>[],
        ),
      ).run(['status', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('workspace: unavailable'));
      expect(stdout.toString(), isNot(contains('workspace provenance:')));
      expect(stdout.toString(), isNot(contains('production allowed:')));
    },
  );

  test(
    'reports ambiguous workspace state when config omits organization',
    () async {
      await seedCredential(store, endpoint: 'https://api.example.com/');
      await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
endpoint: https://api.example.com/
''');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _statusClient(
          organizations: const <Map<String, dynamic>>[
            {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
            {'organizationId': 8, 'slug': 'sample', 'name': 'Sample'},
          ],
          workspaces: const <Map<String, dynamic>>[
            {
              'organizationId': 7,
              'provenance': 'sample',
              'hostedAccessState': 'sandbox',
              'productionAllowed': false,
            },
            {
              'organizationId': 8,
              'provenance': 'customer',
              'hostedAccessState': 'productionEnabled',
              'productionAllowed': true,
            },
          ],
        ),
      ).run(['status', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains(
          'config problem: You belong to 2 organizations: default (id 7), '
          'sample (id 8). Set `organization: <slug>` in restage_config.yaml, '
          'or pass --organization <slug> on each call.',
        ),
      );
      expect(stdout.toString(), isNot(contains('workspace provenance:')));
      expect(stdout.toString(), isNot(contains('production allowed:')));
    },
  );

  test('not signed in exits 1', () async {
    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 1);
    expect(stderr.toString(), contains('restage login'));
  });

  test(
    'fails before HTTP when config endpoint differs from credential',
    () async {
      await seedCredential(store, endpoint: 'https://safe.example.com/');
      await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
endpoint: https://evil.example.com/
''');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: mockHttpClient((request) {
          fail(
            'HTTP request should not be made before endpoint mismatch fails',
          );
        }),
      ).run(['status', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(
        stderr.toString(),
        contains('restage login --endpoint https://evil.example.com/'),
      );
      expect(stdout.toString(), isEmpty);
    },
  );

  test('fails before HTTP when config endpoint is malformed', () async {
    await seedCredential(store, endpoint: 'https://safe.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
endpoint: https://[bad
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: mockHttpClient((request) {
        fail('HTTP request should not be made with malformed config endpoint');
      }),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 1);
    expect(
      stderr.toString(),
      contains('Invalid endpoint in restage_config.yaml'),
    );
    expect(stdout.toString(), isEmpty);
  });
}

http.Client _statusClient({
  List<Map<String, dynamic>>? calls,
  List<Map<String, dynamic>> organizations = const <Map<String, dynamic>>[],
  required List<Map<String, dynamic>> workspaces,
  Map<int, List<String>> projects = const {
    7: ['alpha'],
    8: ['alpha'],
  },
  List<String> apps = const ['mobile'],
  List<String> environments = const ['staging'],
}) {
  return mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    calls?.add(body);
    expect(request.url.path, '/scope');
    expect(body['method'], 'read');
    final selectedId = body['organizationId'] as int? ?? 7;
    final selectedProjects = projects[selectedId] ?? const <String>[];
    return http.Response(
      jsonEncode({
        'organizationId': selectedId,
        'session': {
          'email': 'dev@example.com',
          'memberships': organizations,
          'workspaceExperiences': workspaces,
          'apps': [
            for (final entry in projects.entries)
              for (final project in entry.value)
                {
                  'organizationId': entry.key,
                  'projectSlug': project,
                  'appId': 5,
                  'appSlug': apps.firstOrNull ?? '',
                },
          ],
        },
        'projects': [
          for (var i = 0; i < selectedProjects.length; i++)
            {
              'id': i + 1,
              'slug': selectedProjects[i],
              'name': selectedProjects[i],
            },
        ],
        'apps': [
          for (var i = 0; i < apps.length; i++)
            {'id': i + 5, 'projectId': 1, 'slug': apps[i], 'name': apps[i]},
        ],
        'environments': [
          for (var i = 0; i < environments.length; i++)
            {'id': i + 10, 'appId': 5, 'slug': environments[i]},
        ],
        'environmentTargets': <Object>[],
        'surfaces': <Object>[],
      }),
      200,
    );
  }, withDefaultTargetDiscovery: false);
}
