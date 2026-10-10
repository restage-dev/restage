import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/restage_mcp.dart';
import 'package:test/test.dart';

import '_support/fake_backend.dart';
import '_support/harness.dart';

String _text(CallToolResult result) =>
    (result.content.single as TextContent).text;

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_cli_tools');
    store = FileCredentialStore('${tempDir.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A CLI runner that records its arguments and prints [output].
  (CliRunner, List<List<String>>) recordingCli({
    String output = 'done',
    int exitCode = 0,
  }) {
    final runs = <List<String>>[];
    return (
      (args, {required stdout, required stderr}) async {
        runs.add(args);
        (exitCode == 0 ? stdout : stderr).writeln(output);
        return exitCode;
      },
      runs,
    );
  }

  test('status, init and doctor run the CLI commands they mirror', () async {
    final (cli, runs) = recordingCli(output: 'signed in as a@b.c');
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend((_) async => http.Response('null', 200)),
      cliRunner: cli,
    );

    final status = await connection.callTool(
      CallToolRequest(
        name: 'restage_status',
        arguments: {'projectDirectory': '/work/app'},
      ),
    );
    expect(status.isError, isNot(true), reason: _text(status));
    expect(status.structuredContent!['output'], 'signed in as a@b.c');

    final init = await connection.callTool(
      CallToolRequest(
        name: 'restage_init',
        arguments: {
          'projectDirectory': '/work/app',
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'environmentSlug': 'staging',
          'organizationId': 7,
          'runtimePlane': 'live',
          'starter': false,
          'dryRun': true,
        },
      ),
    );
    expect(init.isError, isNot(true), reason: _text(init));

    final doctor = await connection.callTool(
      CallToolRequest(
        name: 'restage_doctor',
        arguments: {'projectDirectory': '/work/app'},
      ),
    );
    expect(doctor.isError, isNot(true), reason: _text(doctor));

    expect(runs, [
      ['status', '-C', '/work/app'],
      [
        'init',
        '-C',
        '/work/app',
        '--project',
        'demo',
        '--app',
        'mobile',
        '--env',
        'staging',
        '--organization',
        'acme',
        '--plane',
        'live',
        '--no-starter',
        '--dry-run',
      ],
      ['doctor', '-C', '/work/app'],
    ]);
  });

  test('catalog and build pushes pass the organization id as given', () async {
    final (cli, runs) = recordingCli();
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend((_) async => http.Response('null', 200)),
      cliRunner: cli,
    );

    final catalog = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_catalog',
        arguments: {
          'projectDirectory': '/work/app',
          'organizationId': 7,
          'appSlug': 'mobile',
        },
      ),
    );
    expect(catalog.isError, isNot(true), reason: _text(catalog));

    final build = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_build',
        arguments: {
          'projectDirectory': '/work/app',
          'environmentSlug': 'staging',
          'generate': false,
        },
      ),
    );
    expect(build.isError, isNot(true), reason: _text(build));

    expect(runs, [
      [
        'catalog',
        'push',
        '-C',
        '/work/app',
        '--organization-id',
        '7',
        '--app',
        'mobile',
      ],
      ['build', 'push', '-C', '/work/app', '--env', 'staging', '--no-generate'],
    ]);
  });

  test('the audit tools read the resolved organization', () async {
    final calls = <BackendCall>[];
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend((call) async {
        return switch (call.method) {
          'surfaceChainVerdict' => http.Response(
            jsonEncode({'status': 'verified', 'verifiedThroughEntryId': 3}),
            200,
          ),
          _ => http.Response('[]', 200),
        };
      }, calls: calls),
    );

    for (final (tool, method) in [
      ('restage_audit_log', 'listAuditLog'),
      ('restage_audit_export', 'exportComplianceAudit'),
      ('restage_audit_verdict', 'surfaceChainVerdict'),
    ]) {
      calls.clear();
      final result = await connection.callTool(
        CallToolRequest(name: tool, arguments: {}),
      );
      expect(result.isError, isNot(true), reason: _text(result));
      final read = calls.singleWhere((call) => call.method == method);
      expect(read.body['organizationId'], 7, reason: tool);
    }
  });

  test('routing tools resolve the target from environment and plane', () async {
    final calls = <BackendCall>[];
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend(
        (_) async => http.Response('null', 500),
        calls: calls,
      ),
    );

    final ambiguous = await connection.callTool(
      CallToolRequest(
        name: 'restage_read_routing',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'production',
        },
      ),
    );
    expect(ambiguous.isError, isTrue);
    expect(_text(ambiguous), contains('Pass runtimePlane: sandbox or live.'));

    await connection.callTool(
      CallToolRequest(
        name: 'restage_read_routing',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'production',
          'runtimePlane': 'live',
        },
      ),
    );
    final read = calls.last;
    expect(read.endpoint, isNot('environment'));
    expect(read.body['organizationId'], 7);
    expect(jsonEncode(read.body), contains('44'));

    final unnamed = await connection.callTool(
      CallToolRequest(
        name: 'restage_read_routing',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
        },
      ),
    );
    expect(unnamed.isError, isTrue);
    expect(
      _text(unnamed),
      contains(
        'Name environmentSlug, or an exact organizationId and '
        'environmentTargetId.',
      ),
    );
  });
}
