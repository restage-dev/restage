import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_discovery_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:SUPERSECRET',
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('discovery tools keep their existing selector schemas', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in [
      'restage_list_organizations',
      'restage_list_projects',
      'restage_list_apps',
      'restage_list_environments',
      'restage_list_environment_targets',
    ]) {
      expect(tools, contains(name));
    }
    expect(tools['restage_list_organizations']!.inputSchema.required, isEmpty);
    expect(
      tools['restage_list_environment_targets']!.inputSchema.properties,
      contains('runtimePlane'),
    );
  });

  test(
    'organization and nested lists each use one admitted scope read',
    () async {
      for (final (name, arguments, resultKey, expectedSlug) in [
        (
          'restage_list_organizations',
          <String, Object?>{},
          'organizations',
          'acme',
        ),
        (
          'restage_list_projects',
          <String, Object?>{'organizationId': 7},
          'projects',
          'mobile',
        ),
        (
          'restage_list_apps',
          <String, Object?>{'organizationId': 7, 'projectSlug': 'mobile'},
          'apps',
          'ios',
        ),
        (
          'restage_list_environments',
          <String, Object?>{'organizationId': 7, 'projectSlug': 'mobile'},
          'environments',
          'production',
        ),
      ]) {
        final calls = <Map<String, dynamic>>[];
        final connection = await connectServer(
          store: store,
          httpClient: _scopeClient(calls),
        );
        final result = await connection.callTool(
          CallToolRequest(name: name, arguments: arguments),
        );
        expect(result.isError, isNot(true), reason: name);
        expect(calls, hasLength(1), reason: name);
        expect(calls.single['method'], 'read');
        expect(calls.single['organizationId'], arguments['organizationId']);
        final rows = result.structuredContent![resultKey]! as List<dynamic>;
        expect((rows.single as Map)['slug'], expectedSlug);
      }
    },
  );

  test(
    'target list keeps distinct same-slug planes and filters locally',
    () async {
      final calls = <Map<String, dynamic>>[];
      final connection = await connectServer(
        store: store,
        httpClient: _scopeClient(calls),
      );
      final all = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_environment_targets',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'mobile',
            'appSlug': 'ios',
            'appId': 17,
          },
        ),
      );
      expect(all.isError, isNot(true));
      expect(calls, hasLength(1));
      final targets = all.structuredContent!['environmentTargets']! as List;
      expect(targets, hasLength(2));
      expect(targets.map((target) => (target as Map)['runtimePlane']).toSet(), {
        'sandbox',
        'live',
      });

      final live = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_environment_targets',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'mobile',
            'appSlug': 'ios',
            'runtimePlane': 'live',
          },
        ),
      );
      expect(calls, hasLength(2));
      final liveTargets =
          live.structuredContent!['environmentTargets']! as List;
      expect(liveTargets, hasLength(1));
      expect((liveTargets.single as Map)['environmentTargetId'], 42);
    },
  );

  test('wrong-shape response leaks neither secret nor stack', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_projects',
        arguments: {'organizationId': 7},
      ),
    );
    expect(result.isError, isTrue);
    final message = (result.content.single as TextContent).text;
    expect(message, isNot(contains('SUPERSECRET')));
    expect(message, isNot(contains('#0')));
  });
}

http.Client _scopeClient(List<Map<String, dynamic>> calls) => MockClient((
  request,
) async {
  expect(request.url.path, '/scope');
  calls.add(jsonDecode(request.body) as Map<String, dynamic>);
  return http.Response(
    jsonEncode({
      'organizationId': 7,
      'session': {
        'memberships': [
          {
            'organizationId': 7,
            'slug': 'acme',
            'name': 'Acme',
            'role': 'admin',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'mobile', 'name': 'Mobile'},
      ],
      'apps': [
        {'id': 17, 'projectId': 1, 'slug': 'ios', 'name': 'iOS'},
      ],
      'environments': [
        {'id': 41, 'appId': 17, 'namedEnvironmentId': 9, 'slug': 'production'},
        {'id': 42, 'appId': 17, 'namedEnvironmentId': 9, 'slug': 'production'},
      ],
      'environmentTargets': [
        {
          'environmentTargetId': 41,
          'namedEnvironmentId': 9,
          'environmentSlug': 'production',
          'runtimePlane': 'sandbox',
        },
        {
          'environmentTargetId': 42,
          'namedEnvironmentId': 9,
          'environmentSlug': 'production',
          'runtimePlane': 'live',
        },
      ],
      'surfaces': <Object>[],
    }),
    200,
  );
});
