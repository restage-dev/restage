import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Captures the single wire call a discovery tool makes and replies with [body].
({MockClient client, List<({Uri url, Map<String, dynamic> body})> calls})
_recorder(String body) {
  final calls = <({Uri url, Map<String, dynamic> body})>[];
  final client = MockClient((request) async {
    calls.add((
      url: request.url,
      body: jsonDecode(request.body) as Map<String, dynamic>,
    ));
    return http.Response(
      body,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (client: client, calls: calls);
}

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

  test(
    'tools/list exposes legacy and target-aware discovery schemas',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final tools = {
        for (final t in (await connection.listTools(ListToolsRequest())).tools)
          t.name: t,
      };

      expect(tools, contains('restage_list_organizations'));
      expect(tools, contains('restage_list_projects'));
      expect(tools, contains('restage_list_apps'));
      expect(tools, contains('restage_list_environments'));
      expect(tools, contains('restage_list_environment_targets'));

      // list_organizations takes no inputs.
      expect(
        tools['restage_list_organizations']!.inputSchema.required ?? const [],
        isEmpty,
      );
      // list_projects requires organizationId.
      expect(
        tools['restage_list_projects']!.inputSchema.required,
        containsAll(['organizationId']),
      );
      // list_apps / list_environments require organizationId + projectSlug.
      expect(
        tools['restage_list_apps']!.inputSchema.required,
        containsAll(['organizationId', 'projectSlug']),
      );
      expect(
        tools['restage_list_environments']!.inputSchema.required,
        containsAll(['organizationId', 'projectSlug']),
      );
      expect(tools['restage_list_environment_targets']!.inputSchema.required, [
        'organizationId',
        'projectSlug',
        'appSlug',
      ]);
      expect(
        tools['restage_list_environment_targets']!.inputSchema.properties,
        contains('appId'),
      );
      expect(
        tools['restage_list_environment_targets']!.inputSchema.required,
        isNot(contains('appId')),
      );
      expect(
        tools['restage_list_environment_targets']!.inputSchema.required,
        isNot(contains('runtimePlane')),
      );
    },
  );

  test(
    'list_organizations hits organization.listMine and wraps the result',
    () async {
      final rec = _recorder(
        jsonEncode([
          {
            'organizationId': 7,
            'slug': 'acme',
            'name': 'Acme',
            'role': 'admin',
            '__className__': 'OrganizationMembershipView',
          },
        ]),
      );
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_list_organizations', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(rec.calls.single.url.toString(), 'https://api.test/organization');
      expect(rec.calls.single.body['method'], 'listMine');
      final orgs = result.structuredContent!['organizations']! as List<dynamic>;
      expect((orgs.single as Map)['organizationId'], 7);
      expect((orgs.single as Map)['slug'], 'acme');
    },
  );

  test(
    'list_projects threads organizationId to project.listProjects',
    () async {
      final rec = _recorder(
        jsonEncode([
          {
            'id': 1,
            'slug': 'mobile',
            'name': 'Mobile',
            'organizationId': 7,
            '__className__': 'Project',
          },
        ]),
      );
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_projects',
          arguments: {'organizationId': 7},
        ),
      );

      expect(result.isError, isNot(true));
      expect(rec.calls.single.url.toString(), 'https://api.test/project');
      expect(rec.calls.single.body['method'], 'listProjects');
      expect(rec.calls.single.body['organizationId'], 7);
      final projects = result.structuredContent!['projects']! as List<dynamic>;
      expect((projects.single as Map)['slug'], 'mobile');
    },
  );

  test(
    'list_apps threads organizationId + projectSlug to app.listApps',
    () async {
      final rec = _recorder(
        jsonEncode([
          {
            'id': 2,
            'projectId': 1,
            'slug': 'ios',
            'name': 'iOS',
            '__className__': 'App',
          },
        ]),
      );
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_apps',
          arguments: {'organizationId': 7, 'projectSlug': 'mobile'},
        ),
      );

      expect(result.isError, isNot(true));
      expect(rec.calls.single.url.toString(), 'https://api.test/app');
      expect(rec.calls.single.body['method'], 'listApps');
      expect(rec.calls.single.body['organizationId'], 7);
      expect(rec.calls.single.body['projectSlug'], 'mobile');
      final apps = result.structuredContent!['apps']! as List<dynamic>;
      expect((apps.single as Map)['slug'], 'ios');
    },
  );

  test('list_environments threads to environment.listEnvironments', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'id': 3,
          'appId': 2,
          'slug': 'production',
          '__className__': 'Environment',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_environments',
        arguments: {'organizationId': 7, 'projectSlug': 'mobile'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/environment');
    expect(rec.calls.single.body['method'], 'listEnvironments');
    final envs = result.structuredContent!['environments']! as List<dynamic>;
    expect((envs.single as Map)['slug'], 'production');
  });

  test('list_environment_targets threads app scope + optional plane', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'environmentTargetId': 42,
          'namedEnvironmentId': 9,
          'environmentSlug': 'production',
          'runtimePlane': 'live',
          '__className__': 'EnvironmentTargetRef',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_environment_targets',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'mobile',
          'appSlug': 'ios',
          'appId': 17,
          'runtimePlane': 'live',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(
      rec.calls.single.body,
      containsPair('method', 'listEnvironmentTargets'),
    );
    expect(rec.calls.single.body, containsPair('appSlug', 'ios'));
    expect(rec.calls.single.body, containsPair('appId', 17));
    expect(rec.calls.single.body, containsPair('runtimePlane', 'live'));
    final targets =
        result.structuredContent!['environmentTargets']! as List<dynamic>;
    expect((targets.single as Map)['environmentTargetId'], 42);
  });

  test('list_environment_targets compactly omits an absent plane', () async {
    final rec = _recorder('[]');
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_environment_targets',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'mobile',
          'appSlug': 'ios',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.body, isNot(contains('appId')));
    expect(rec.calls.single.body, isNot(contains('runtimePlane')));
  });

  test(
    'list_environment_targets preserves the six same-slug plane cells',
    () async {
      final wireTargets = <Map<String, Object>>[
        for (final coordinate in const [
          (id: 101, parentId: 11, slug: 'dev', plane: 'sandbox'),
          (id: 102, parentId: 11, slug: 'dev', plane: 'live'),
          (id: 103, parentId: 12, slug: 'staging', plane: 'sandbox'),
          (id: 104, parentId: 12, slug: 'staging', plane: 'live'),
          (id: 105, parentId: 13, slug: 'prod', plane: 'sandbox'),
          (id: 106, parentId: 13, slug: 'prod', plane: 'live'),
        ])
          {
            'environmentTargetId': coordinate.id,
            'namedEnvironmentId': coordinate.parentId,
            'environmentSlug': coordinate.slug,
            'runtimePlane': coordinate.plane,
            '__className__': 'EnvironmentTargetRef',
          },
      ];
      final rec = _recorder(jsonEncode(wireTargets));
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_environment_targets',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'default',
            'appSlug': 'default',
            'appId': 17,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(rec.calls.single.body, containsPair('appId', 17));
      expect(rec.calls.single.body, isNot(contains('runtimePlane')));
      final targets =
          result.structuredContent!['environmentTargets']! as List<dynamic>;
      expect(targets, hasLength(6));
      expect(
        targets
            .cast<Map<String, dynamic>>()
            .map(
              (target) =>
                  '${target['environmentSlug']}:${target['runtimePlane']}:'
                  '${target['environmentTargetId']}:${target['namedEnvironmentId']}',
            )
            .toSet(),
        {
          'dev:sandbox:101:11',
          'dev:live:102:11',
          'staging:sandbox:103:12',
          'staging:live:104:12',
          'prod:sandbox:105:13',
          'prod:live:106:13',
        },
      );
    },
  );

  test(
    'a wrong-shape 200 body leaks neither the secret nor a stack trace',
    () async {
      // Valid JSON, wrong shape (object, not the expected list) -> a TypeError
      // deep in the cast. The shared catch-all must keep it (and the credential
      // secret) off the channel.
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"unexpected": true}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_projects',
          arguments: {'organizationId': 7},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('SUPERSECRET')));
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
    },
  );
}
