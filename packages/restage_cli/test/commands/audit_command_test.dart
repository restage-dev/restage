import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/audit_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audit_command_');
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

  test('audit log prints the server org audit stream', () async {
    Map<String, dynamic>? logBody;
    final client = scriptedHttpClient([
      _listOrganizations,
      (request) {
        logBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode([
            {
              '__className__': 'SurfaceAuditLogEntryView',
              'action': 'surfacePublished',
              'actorType': 'human',
              'actorEmail': 'owner@example.com',
              'outcome': 'success',
              'severity': 'notice',
              'occurredAt': '2026-06-29T18:17:51.000Z',
              'context': {'surfaceSlug': 'pro'},
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
    final runner = _runner(
      stdout: out,
      credentialStore: store,
      httpClient: client,
    );
    final code = await runner.run(['audit', 'log', '-C', tempDir.path]);

    expect(code, 0);
    expect(logBody, isNotNull);
    expect(logBody!['method'], 'listAuditLog');
    expect(logBody!['organizationId'], 7);
    expect(out.toString(), contains('surfacePublished'));
    expect(out.toString(), contains('owner@example.com'));
    expect(out.toString(), contains('verified'));
  });

  test('audit export emits compliance CSV rows', () async {
    final client = scriptedHttpClient([
      _listOrganizations,
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'exportComplianceAudit');
        expect(body['organizationId'], 7);
        return http.Response(
          jsonEncode([
            {
              '__className__': 'SurfaceComplianceExportRow',
              'occurredAt': '2026-06-29T18:17:51.000Z',
              'action': 'surfaceKilled',
              'surfaceSlug': 'pro',
              'surfaceType': 'paywall',
              'environmentSlug': 'production',
              'version': 2,
              'actorEmail': 'admin@example.com',
              'reason': 'incident, rollback',
              'chainState': 'pendingChain',
              'chainVerified': false,
              'entryId': 100,
            },
          ]),
          200,
        );
      },
    ]);

    final out = StringBuffer();
    final code = await _runner(
      stdout: out,
      credentialStore: store,
      httpClient: client,
    ).run(['audit', 'export', '-C', tempDir.path]);

    expect(code, 0);
    expect(out.toString(), startsWith('occurredAt,action,surfaceType'));
    expect(out.toString(), contains('surfaceKilled'));
    expect(out.toString(), contains('"incident, rollback"'));
  });

  test('audit verdict prints the chain verification verdict', () async {
    final client = scriptedHttpClient([
      _listOrganizations,
      (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'surfaceChainVerdict');
        expect(body['organizationId'], 7);
        return http.Response(
          jsonEncode({
            '__className__': 'SurfaceChainVerdict',
            'status': 'verified',
            'verifiedThroughEntryId': 99,
            'lastRunAt': '2026-06-29T18:30:00.000Z',
          }),
          200,
        );
      },
    ]);

    final out = StringBuffer();
    final code = await _runner(
      stdout: out,
      credentialStore: store,
      httpClient: client,
    ).run(['audit', 'verdict', '-C', tempDir.path]);

    expect(code, 0);
    expect(out.toString(), contains('status: verified'));
    expect(out.toString(), contains('verified through entry: 99'));
  });
}

CommandRunner<int> _runner({
  required StringBuffer stdout,
  required FileCredentialStore credentialStore,
  required http.Client httpClient,
}) {
  return CommandRunner<int>('restage', '')..addCommand(
    AuditCommand(
      stdout: stdout,
      stderr: StringBuffer(),
      credentialStore: credentialStore,
      httpClient: httpClient,
    ),
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
