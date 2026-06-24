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
      tools['restage_list_api_keys']!.inputSchema.required,
      containsAll(['projectSlug', 'appSlug', 'environmentSlug']),
    );
    expect(
      tools['restage_revoke_api_key']!.inputSchema.required,
      containsAll(['projectSlug', 'appSlug', 'apiKeyId']),
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
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/apiKey');
    expect(rec.calls.single.body['method'], 'listKeys');
    expect(rec.calls.single.body['environmentSlug'], 'production');
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
}
