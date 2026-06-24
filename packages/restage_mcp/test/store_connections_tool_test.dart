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
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_storeconn_test');
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

  test('tools/list exposes the store-connections tool', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };

    expect(tools, contains('restage_list_store_connections'));
    expect(
      tools['restage_list_store_connections']!.inputSchema.required,
      containsAll(['projectSlug', 'appSlug']),
    );
  });

  test('list_store_connections hits storeConnection.list and passes the '
      'summary through', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'store': 'appStore',
          'status': 'connected',
          'storeAppIdentifier': 'com.acme.app',
          // A non-secret 4-char display digest, not the credential bundle.
          'credentialFingerprint': 'a1b2',
          'rtdnTopic': null,
          'lastVerifiedAt': '2026-06-01T00:00:00.000Z',
          'createdAt': '2026-05-01T00:00:00.000Z',
          '__className__': 'StoreConnectionSummary',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_store_connections',
        arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/storeConnection');
    expect(rec.calls.single.body['method'], 'list');
    final connections =
        result.structuredContent!['storeConnections']! as List<dynamic>;
    final summary = connections.single as Map;
    expect(summary['status'], 'connected');
    expect(summary['credentialFingerprint'], 'a1b2');
    // The passthrough surfaces exactly the backend's summary fields; it never
    // invents a credential-bundle field.
    expect(summary.containsKey('encryptedCredential'), isFalse);
    expect(summary.containsKey('wrappedDataKey'), isFalse);
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
          name: 'restage_list_store_connections',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
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
