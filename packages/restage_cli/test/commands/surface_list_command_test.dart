import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_list_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage surface list', () {
    test('lists one requested surface type as a table', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final calls = <Map<String, dynamic>>[];
      final client = _scopeClient([_surface('onboarding', 'welcome')], calls);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['surface', 'list', '--type', 'onboarding', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(calls, hasLength(1));
      expect(calls.single['method'], 'read');

      final lines = const LineSplitter().convert(stdout.toString().trim());
      expect(lines.first, 'TYPE\tSLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
      expect(
        lines[1],
        'onboarding\twelcome\tWelcome\t2026-05-01T12:34:56.000Z\tdev/sandbox v3',
      );
    });

    test('--archived asks for archived surfaces and shows when each was '
        'archived', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final calls = <Map<String, dynamic>>[];
      final client = _scopeClient([
        _surface('paywall', 'live'),
        {
          ..._surface('paywall', 'old'),
          'archivedAt': '2026-09-01T08:00:00.000Z',
        },
      ], calls);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
          ).run([
            'surface',
            'list',
            '--type',
            'paywall',
            '--archived',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0, reason: stderr.toString());
      expect(calls, hasLength(1));
      final lines = const LineSplitter().convert(stdout.toString().trim());
      expect(lines, [
        'TYPE\tSLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED\tARCHIVED',
        'paywall\tlive\tLive\t2026-05-01T12:34:56.000Z\tdev/sandbox v3\t-',
        'paywall\told\tOld\t2026-05-01T12:34:56.000Z\tdev/sandbox v3\t'
            '2026-09-01T08:00:00.000Z',
      ]);
    });

    test('lists every known surface type when --type is left out', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final calls = <Map<String, dynamic>>[];
      final client = _scopeClient([
        for (final type in [
          'paywall',
          'onboarding',
          'message',
          'survey',
          'general',
        ])
          _surface(type, '$type-surface'),
      ], calls);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['surface', 'list', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(calls, hasLength(1));
      final out = stdout.toString();
      expect(out, contains('paywall\tpaywall-surface'));
      expect(out, contains('onboarding\tonboarding-surface'));
      expect(out, contains('message\tmessage-surface'));
      expect(out, contains('survey\tsurvey-surface'));
      expect(out, contains('general\tgeneral-surface'));
    });

    test('--json emits typed surface summaries', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = _scopeClient([_surface('survey', 'nps')], []);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
          ).run([
            'surface',
            'list',
            '--type',
            'survey',
            '--json',
            '-C',
            tempDir.path,
          ]);

      expect(exitCode, 0);
      final decoded = jsonDecode(stdout.toString()) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect(decoded.single, containsPair('surfaceType', 'survey'));
      expect(decoded.single, containsPair('slug', 'nps'));
    });

    test('rejects invalid surface type', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['surface', 'list', '--type', 'banner', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('Invalid --type "banner"'));
    });
  });
}

http.Client _scopeClient(
  List<Map<String, dynamic>> surfaces,
  List<Map<String, dynamic>> calls,
) => mockHttpClient((request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  calls.add(body);
  expect(request.url.path, '/scope');
  expect(body['method'], 'read');
  return http.Response(
    jsonEncode({
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
        {'id': 1, 'slug': 'demo', 'name': 'Demo'},
      ],
      'apps': [
        {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
      ],
      'environments': <Object>[],
      'environmentTargets': <Object>[],
      'surfaces': [
        for (final surface in surfaces) {'appId': 5, ...surface},
      ],
    }),
    200,
  );
}, withDefaultTargetDiscovery: false);

Map<String, dynamic> _surface(String type, String slug) => {
  '__className__': 'SurfaceSummary',
  'surfaceType': type,
  'slug': slug,
  'name': _title(slug),
  'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
  'publishedVersionByEnvironment': {'dev': 3, 'prod': null},
  'targetPublications': [
    {
      'target': {
        'environmentTargetId': 1,
        'namedEnvironmentId': 1,
        'environmentSlug': 'dev',
        'runtimePlane': 'sandbox',
      },
      'experimentSurfaceReferences': <Object>[],
      'publishedVersion': 3,
    },
  ],
};

String _title(String slug) => slug
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
