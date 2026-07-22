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

      late Map<String, dynamic> seenBody;
      final client = mockHttpClient((req) {
        seenBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode([_surface('onboarding', 'welcome')]),
          200,
        );
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['surface', 'list', '--type', 'onboarding', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(seenBody['method'], 'list');
      expect(seenBody['projectSlug'], 'demo');
      expect(seenBody['appSlug'], 'mobile');
      expect(seenBody['appId'], 5);
      expect(seenBody['surfaceType'], 'onboarding');

      final lines = const LineSplitter().convert(stdout.toString().trim());
      expect(lines.first, 'TYPE\tSLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
      expect(
        lines[1],
        'onboarding\twelcome\tWelcome\t2026-05-01T12:34:56.000Z\tdev=3',
      );
    });

    test('--all lists every known surface type', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final seenTypes = <String>[];
      final client = mockHttpClient((req) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final type = body['surfaceType'] as String;
        seenTypes.add(type);
        return http.Response(
          jsonEncode([_surface(type, '$type-surface')]),
          200,
        );
      });

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run(['surface', 'list', '--all', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(seenTypes, ['paywall', 'onboarding', 'message', 'survey']);
      final out = stdout.toString();
      expect(out, contains('paywall\tpaywall-surface'));
      expect(out, contains('onboarding\tonboarding-surface'));
      expect(out, contains('message\tmessage-surface'));
      expect(out, contains('survey\tsurvey-surface'));
    });

    test('--json emits typed surface summaries', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final client = mockHttpClient((req) {
        return http.Response(jsonEncode([_surface('survey', 'nps')]), 200);
      });

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

    test('requires --type or --all', () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'demo', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['surface', 'list', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('Required: --type'));
      expect(stderr.toString(), contains('--all'));
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

Map<String, dynamic> _surface(String type, String slug) => {
  '__className__': 'SurfaceSummary',
  'surfaceType': type,
  'slug': slug,
  'name': _title(slug),
  'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
  'publishedVersionByEnvironment': {'dev': 3, 'prod': null},
};

String _title(String slug) => slug
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
