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
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_slots_test');
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
    'slot schema requires a key set without full-store replacement',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
      final schema = tools['restage_upsert_product_slot']!.inputSchema;
      expect(schema.required, containsAll(['name', 'entitlementKeys']));
      expect(schema.properties, isNot(contains('iosProductId')));
      expect(schema.properties, isNot(contains('androidProductId')));
      expect(tools, contains('restage_read_commerce_catalog'));
      expect(tools, contains('restage_save_commerce_offering'));
    },
  );

  test('offering tools expose patch retirement and explicit revival', () async {
    final rec = _recorder('{"id":4}');
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    final save = tools['restage_save_commerce_offering']!.inputSchema;
    expect(save.properties, contains('retiredPackageIds'));
    expect(save.required, isNot(contains('retiredPackageIds')));
    expect(
      tools['restage_retire_commerce_offering']!.inputSchema.properties,
      contains('revive'),
    );
    for (final ids in [null, '[17,19]']) {
      rec.calls.clear();
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_save_commerce_offering',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'appId': 5,
            'offering': '{"id":4,"offerId":"default"}',
            'packages': '[]',
            if (ids != null) 'retiredPackageIds': ids,
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(rec.calls.single.body['method'], 'saveOffering');
      expect(
        rec.calls.single.body['retiredPackageIds'],
        ids == null ? <int>[] : [17, 19],
      );
      expect(rec.calls.single.body['packages'], isEmpty);
    }
    for (final revive in [false, true]) {
      rec.calls.clear();
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_retire_commerce_offering',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'offeringId': 4,
            'revive': revive,
          },
        ),
      );
      expect(result.isError, isNot(true));
      expect(rec.calls.single.body['retired'], !revive);
    }
  });

  test('slot tool shares the CLI key-set decoder', () async {
    final rec = _recorder(
      '{"id":3,"name":"pro","entitlementKeys":["premium","pro"]}',
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_upsert_product_slot',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'name': 'pro',
          'slotId': 3,
          'entitlementKeys': '["premium","pro"]',
        },
      ),
    );
    expect(result.isError, isNot(true));
    expect(rec.calls.single.body['method'], 'saveSlot');
    expect(rec.calls.single.body['entitlementKeys'], ['premium', 'pro']);
    expect(rec.calls.single.body['slotId'], 3);
  });

  test('catalog tool uses supplied existing IDs in one request', () async {
    final rec = _recorder(
      '{"currentOfferingId":4,"catalogRevision":2,"nextCursor":null}',
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_read_commerce_catalog',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'appId': 5,
          'environmentSlug': 'staging',
          'runtimePlane': 'sandbox',
          'environmentTargetId': 12,
        },
      ),
    );
    expect(result.isError, isNot(true));
    expect(rec.calls.single.body, {
      'method': 'readCatalog',
      'organizationId': 7,
      'appId': 5,
      'environmentId': 12,
      'limit': 100,
      'section': 'offerings',
    });
  });

  test('catalog section and cursor remain one explicit page request', () async {
    final rec = _recorder('{"catalogRevision":2,"nextCursor":"next"}');
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_read_commerce_catalog',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'appId': 5,
          'environmentSlug': 'staging',
          'environmentTargetId': 12,
          'section': 'products',
          'cursor': 'previous',
        },
      ),
    );
    expect(result.isError, isNot(true));
    expect(rec.calls.single.body['section'], 'products');
    expect(rec.calls.single.body['cursor'], 'previous');
  });

  test('slot tool maps products as a patch at a catalog revision', () async {
    final rec = _recorder('{"id":3,"name":"pro","entitlementKeys":["pro"]}');
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_upsert_product_slot',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'name': 'pro',
          'slotId': 3,
          'entitlementKeys': '["pro"]',
          'catalogRevision': 4,
          'add': '[{"productId":9,"basePlanId":"annual"}]',
          'move': '[{"productId":11}]',
        },
      ),
    );
    expect(result.isError, isNot(true));
    expect(rec.calls.single.body, {
      'method': 'saveSlot',
      'organizationId': 7,
      'projectSlug': 'acme',
      'appSlug': 'ios',
      'name': 'pro',
      'entitlementKeys': ['pro'],
      'retired': false,
      'slotId': 3,
      'expectedCatalogRevision': 4,
      'add': [
        {'productId': 9, 'basePlanId': 'annual'},
      ],
      'remove': <Object?>[],
      'move': [
        {'productId': 11, 'basePlanId': null},
      ],
    });
    final tools = await connection.listTools(ListToolsRequest());
    expect(
      tools.tools.map((t) => t.name),
      isNot(contains('restage_set_product_slot')),
    );
  });

  test(
    'invalid key JSON refuses before a mutation and leaks no secret',
    () async {
      final rec = _recorder('{}');
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_upsert_product_slot',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'name': 'pro',
            'entitlementKeys': '{}',
          },
        ),
      );
      expect(result.isError, isTrue);
      expect(rec.calls, isEmpty);
      expect(
        (result.content.single as TextContent).text,
        isNot(contains('SUPERSECRET')),
      );
    },
  );

  test(
    'a wrong-shape 200 leaks neither the secret nor a stack trace',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"unexpected": true}', // an object where a list is expected
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_product_slots',
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
