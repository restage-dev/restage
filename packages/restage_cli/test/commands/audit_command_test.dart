import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/spec_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
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
            {
              '__className__': 'SurfaceAuditLogEntryView',
              'action': 'experimentStarted',
              'actorType': 'human',
              'actorEmail': 'owner@example.com',
              'outcome': 'success',
              'severity': 'info',
              'targetType': 'experiment',
              'targetId': 'experiment.one',
              'targetName': 'Annual plan framing',
              'occurredAt': '2026-06-29T18:16:51.000Z',
              'context': {'experimentId': 'experiment.one'},
              'chainState': 'pendingChain',
              'chainVerified': false,
            },
            {
              '__className__': 'SurfaceAuditLogEntryView',
              'action': 'experimentPaused',
              'actorType': 'human',
              'outcome': 'success',
              'severity': 'info',
              'targetType': 'experiment',
              'targetId': 'experiment.gone',
              'occurredAt': '2026-06-29T18:15:51.000Z',
              'context': {'experimentId': 'experiment.gone'},
              'chainState': 'pendingChain',
              'chainVerified': false,
            },
          ]),
          200,
        );
      },
    ], withDefaultTargetDiscovery: false);

    final out = StringBuffer();
    final runner = _runner(
      stdout: out,
      credentialStore: store,
      httpClient: client,
    );
    final code = await runner.run(['audit', 'log', '-C', tempDir.path]);

    expect(code, 0);
    final lines = out.toString().split('\n');
    expect(lines.first, startsWith('WHEN\tACTION\tTARGET\tACTOR'));
    expect(lines, contains(contains('\tsurfacePublished\tpro\t')));
    expect(
      lines,
      contains(contains('\texperimentStarted\tAnnual plan framing\t')),
    );
    // An experiment deleted since keeps its id.
    expect(lines, contains(contains('\texperimentPaused\texperiment.gone\t')));
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
    ], withDefaultTargetDiscovery: false);

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
    ], withDefaultTargetDiscovery: false);

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
  final runner = CommandRunner<int>('restage', '');
  operationCommands(
    CommandIo(
      stdout: stdout,
      stderr: StringBuffer(),
      interactive: const NonInteractive(),
      credentialStore: credentialStore,
      httpClient: httpClient,
    ),
    exclude: const {'surface'},
  ).forEach(runner.addCommand);
  return runner;
}

http.Response _listOrganizations(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
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
      'projects': <Object>[],
      'apps': <Object>[],
      'environments': <Object>[],
      'environmentTargets': <Object>[],
      'surfaces': <Object>[],
    }),
    200,
  );
}
