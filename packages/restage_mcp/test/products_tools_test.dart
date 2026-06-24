import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Captures the single wire call a tool makes and replies with [body].
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
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_products_test');
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
    'tools/list exposes both product tools with the right schemas',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final tools = {
        for (final t in (await connection.listTools(ListToolsRequest())).tools)
          t.name: t,
      };

      expect(tools, contains('restage_list_products'));
      expect(tools, contains('restage_import_products'));

      // list_products requires only the project + app; store is an optional
      // filter.
      expect(
        tools['restage_list_products']!.inputSchema.required,
        containsAll(['projectSlug', 'appSlug']),
      );
      expect(
        tools['restage_list_products']!.inputSchema.required ?? const [],
        isNot(contains('store')),
      );
      // import_products requires the store (which catalog to pull).
      expect(
        tools['restage_import_products']!.inputSchema.required,
        containsAll(['projectSlug', 'appSlug', 'store']),
      );
    },
  );

  test('list_products without a store filter hits product.list', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'id': 1,
          'appId': 2,
          'store': 'appStore',
          'storeProductId': 'pro_monthly',
          'displayName': 'Pro Monthly',
          '__className__': 'Product',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_products',
        arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/product');
    expect(rec.calls.single.body['method'], 'list');
    expect(rec.calls.single.body['projectSlug'], 'acme');
    expect(rec.calls.single.body['appSlug'], 'ios');
    // No store filter -> the key is omitted from the wire call.
    expect(rec.calls.single.body.containsKey('store'), isFalse);
    final products = result.structuredContent!['products']! as List<dynamic>;
    expect((products.single as Map)['storeProductId'], 'pro_monthly');
  });

  test('list_products forwards the store filter by name', () async {
    final rec = _recorder(jsonEncode(<dynamic>[]));
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_products',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'store': 'appStore',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.body['store'], 'appStore');
  });

  test('import_products requires + forwards the store', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'id': 9,
          'store': 'playStore',
          'storeProductId': 'sub_yearly',
          'displayName': 'Yearly',
          '__className__': 'Product',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_import_products',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'android',
          'store': 'playStore',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/product');
    expect(rec.calls.single.body['method'], 'importProducts');
    expect(rec.calls.single.body['store'], 'playStore');
    final products = result.structuredContent!['products']! as List<dynamic>;
    expect((products.single as Map)['storeProductId'], 'sub_yearly');
  });

  test('an invalid store value is rejected by the framework', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_import_products',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'store': 'macAppStore', // not a StoreVendor value
        },
      ),
    );

    expect(result.isError, isTrue);
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
          name: 'restage_list_products',
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
