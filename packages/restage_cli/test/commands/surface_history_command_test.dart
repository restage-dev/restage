import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_history_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('surface_history_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
    await seedRestageConfig(
      tempDir,
      'alpha',
      'mobile',
      defaultEnvironment: 'staging',
      organization: 'restage',
      endpoint: 'http://localhost:8080/',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'prints server surface history and threads configured organization',
    () async {
      Map<String, dynamic>? historyBody;
      final client = scriptedHttpClient([
        _listOrganizations,
        (request) {
          historyBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode([
              {
                '__className__': 'SurfaceAuditLogEntryView',
                'action': 'surfacePublished',
                'actorType': 'human',
                'actorEmail': 'owner@example.com',
                'outcome': 'success',
                'severity': 'notice',
                'targetType': 'surface',
                'targetId': '42',
                'occurredAt': '2026-06-29T18:17:51.000Z',
                'reason': 'demo publish',
                'context': {
                  'surfaceSlug': 'pro',
                  'surfaceType': 'paywall',
                  'environmentSlug': 'staging',
                  'publishedVersion': '2',
                },
                'chainState': 'chained',
                'chainVerified': true,
                'entryId': 99,
              },
            ]),
            200,
          );
        },
      ]);

      final out = StringBuffer();
      final runner = CommandRunner<int>('restage', '')
        ..addCommand(
          SurfaceHistoryCommand(
            stdout: out,
            stderr: StringBuffer(),
            interactive: const NonInteractive(),
            fixedSurfaceType: SurfaceType.paywall,
            credentialStore: store,
            httpClient: client,
          ),
        );

      final code = await runner.run(['history', 'pro', '-C', tempDir.path]);

      expect(code, 0);
      expect(historyBody, isNotNull);
      expect(historyBody!['method'], 'listSurfaceHistory');
      expect(historyBody!['projectSlug'], 'alpha');
      expect(historyBody!['appSlug'], 'mobile');
      expect(historyBody!['environmentSlug'], 'staging');
      expect(historyBody!['surfaceType'], 'paywall');
      expect(historyBody!['surfaceSlug'], 'pro');
      expect(historyBody!['organizationId'], 7);
      expect(out.toString(), contains('surfacePublished'));
      expect(out.toString(), contains('owner@example.com'));
      expect(out.toString(), contains('demo publish'));
      expect(out.toString(), contains('verified'));
    },
  );
}

http.Response _listOrganizations(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listMine');
  return http.Response(
    jsonEncode([
      {
        'organizationId': 7,
        'slug': 'restage',
        'name': 'Restage',
        'role': 'owner',
      },
    ]),
    200,
  );
}
