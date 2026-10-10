import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

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
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_apikeys_test');
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

  test('tools/list exposes list + revoke and NO mint tool', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };

    expect(tools, contains('restage_list_api_keys'));
    expect(tools, contains('restage_revoke_api_key'));
    // Minting returns a one-time plaintext secret — excluded by design.
    expect(tools, isNot(contains('restage_mint_api_key')));

    expect(
      tools['restage_list_api_keys']!.inputSchema.properties!.keys,
      containsAll([
        'projectDirectory',
        'projectSlug',
        'appSlug',
        'environmentSlug',
      ]),
    );
    expect(tools['restage_revoke_api_key']!.inputSchema.required, ['apiKeyId']);
    expect(
      tools['restage_list_api_keys']!.inputSchema.required,
      isNot(contains('environmentTargetId')),
    );
    expect(
      tools['restage_list_api_keys']!.inputSchema.required,
      isNot(contains('runtimePlane')),
    );
  });

  test('list_api_keys hits apiKey.listKeys and passes the redacted view '
      'through', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'id': 3,
          'environmentId': 9,
          'environmentSlug': 'production',
          'environmentTargetId': 42,
          'runtimePlane': 'sandbox',
          'kind': 'public',
          'keyPrefix': 'rs_pk_ab',
          'createdAt': '2026-06-01T00:00:00.000Z',
          'lastUsedAt': null,
          'revokedAt': null,
          '__className__': 'ApiKeyView',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_api_keys',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'environmentSlug': 'production',
          'environmentTargetId': 42,
          'runtimePlane': 'sandbox',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/apiKey');
    expect(rec.calls.single.body['method'], 'listKeys');
    expect(rec.calls.single.body['environmentSlug'], 'production');
    expect(rec.calls.single.body['environmentTargetId'], 42);
    expect(rec.calls.single.body['runtimePlane'], 'sandbox');
    final keys = result.structuredContent!['apiKeys']! as List<dynamic>;
    final view = keys.single as Map;
    expect(view['keyPrefix'], 'rs_pk_ab');
    // The redacted view never carries the hash or plaintext.
    expect(view.containsKey('keyHash'), isFalse);
    expect(view.containsKey('plaintext'), isFalse);
  });

  test('revoke_api_key hits apiKey.revokeKey and confirms', () async {
    final rec = _recorder('');
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_revoke_api_key',
        arguments: {'projectSlug': 'acme', 'appSlug': 'ios', 'apiKeyId': 3},
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/apiKey');
    expect(rec.calls.single.body['method'], 'revokeKey');
    expect(rec.calls.single.body['apiKeyId'], 3);
    expect(result.structuredContent!['revoked'], isTrue);
    expect(result.structuredContent!['apiKeyId'], 3);
  });

  test(
    'a wrong-shape 200 leaks neither the secret nor a stack trace',
    () async {
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
          name: 'restage_list_api_keys',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'environmentSlug': 'production',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('SUPERSECRET')));
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
    },
  );
  test('resolve_api_key matches key prefixes locally and returns the '
      'target', () async {
    const key = 'rs_pk_live_prod_abcdef0123456789';
    final bodies = <String>[];
    final client = MockClient((request) async {
      bodies.add(request.body);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final Object result = switch (body['method']) {
        'listMine' => [
          {'organizationId': 3, 'slug': 'acme', 'name': 'Acme'},
        ],
        'listProjects' => [
          {'slug': 'default', 'name': 'Default'},
        ],
        'listApps' => [
          {'id': 9, 'slug': 'default', 'name': 'Default'},
        ],
        'listEnvironmentTargets' => [
          {
            'environmentTargetId': 21,
            'namedEnvironmentId': 31,
            'environmentSlug': 'prod',
            'runtimePlane': 'live',
          },
        ],
        'listKeys' => [
          {
            'id': 5,
            'kind': 'publishable',
            'keyPrefix': 'rs_pk_live_prod_abcdef...',
          },
        ],
        final method => throw StateError('unexpected $method'),
      };
      return http.Response(jsonEncode(result), 200);
    });
    final connection = await connectServer(store: store, httpClient: client);

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_resolve_api_key', arguments: {'key': key}),
    );

    expect(result.isError, isNot(true));
    expect(bodies.where((body) => body.contains('0123456789')), isEmpty);
    final match = (result.structuredContent!['matches']! as List).single as Map;
    expect(match['organizationId'], 3);
    expect(match['projectSlug'], 'default');
    expect(match['appSlug'], 'default');
    expect(match['environmentSlug'], 'prod');
    expect(match['runtimePlane'], 'live');
    expect(match['environmentTargetId'], 21);
    expect(match['keyPrefix'], 'rs_pk_live_prod_abcdef...');
    expect(jsonEncode(result.structuredContent), isNot(contains('0123456789')));
  });
}
