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

  test('tools/list exposes both slot tools; upsert names both stores '
      'required', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };

    expect(tools, contains('restage_list_product_slots'));
    expect(tools, contains('restage_upsert_product_slot'));

    // Full-replace footgun-guard: both store ids are REQUIRED inputs so the
    // agent must consciously state each store's mapping (a product id to keep
    // it, or null to unmap it) every call.
    expect(
      tools['restage_upsert_product_slot']!.inputSchema.required,
      containsAll([
        'projectSlug',
        'appSlug',
        'name',
        'entitlement',
        'iosProductId',
        'androidProductId',
      ]),
    );
  });

  test('list_product_slots hits productSlot.list', () async {
    final rec = _recorder(
      jsonEncode([
        {
          'id': 1,
          'appId': 2,
          'name': 'pro',
          'entitlement': 'pro_access',
          '__className__': 'ProductSlot',
        },
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_product_slots',
        arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/productSlot');
    expect(rec.calls.single.body['method'], 'list');
    final slots = result.structuredContent!['productSlots']! as List<dynamic>;
    expect((slots.single as Map)['name'], 'pro');
  });

  test('upsert with both ids maps both stores and wraps one slot', () async {
    final rec = _recorder(
      jsonEncode({
        'id': 5,
        'appId': 2,
        'name': 'pro',
        'entitlement': 'pro_access',
        '__className__': 'ProductSlot',
      }),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_upsert_product_slot',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'name': 'pro',
          'entitlement': 'pro_access',
          'iosProductId': 'pro_monthly_ios',
          'androidProductId': 'pro_monthly_android',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.url.toString(), 'https://api.test/productSlot');
    expect(rec.calls.single.body['method'], 'upsert');
    expect(rec.calls.single.body['name'], 'pro');
    expect(rec.calls.single.body['entitlement'], 'pro_access');
    expect(rec.calls.single.body['iosProductId'], 'pro_monthly_ios');
    expect(rec.calls.single.body['androidProductId'], 'pro_monthly_android');
    // Single object, not a list.
    final slot = result.structuredContent!['productSlot']! as Map;
    expect(slot['id'], 5);
  });

  test('upsert with an explicit null id unmaps that store (key dropped on '
      'the wire)', () async {
    final rec = _recorder(
      jsonEncode({
        'id': 5,
        'name': 'pro',
        'entitlement': 'pro_access',
        '__className__': 'ProductSlot',
      }),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_upsert_product_slot',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'name': 'pro',
          'entitlement': 'pro_access',
          'iosProductId': 'pro_monthly_ios',
          'androidProductId': null, // explicit unmap
        },
      ),
    );

    expect(result.isError, isNot(true));
    // The unmapped store id is dropped from the wire body; the backend reads a
    // missing nullable parameter as null and unmaps that store.
    expect(rec.calls.single.body['iosProductId'], 'pro_monthly_ios');
    expect(rec.calls.single.body.containsKey('androidProductId'), isFalse);
  });

  test('omitting a required store id is rejected by the framework '
      '(fails closed — no silent unmap)', () async {
    final rec = _recorder(
      jsonEncode({'id': 5, '__className__': 'ProductSlot'}),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_upsert_product_slot',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'ios',
          'name': 'pro',
          'entitlement': 'pro_access',
          'iosProductId': 'pro_monthly_ios',
          // androidProductId omitted entirely
        },
      ),
    );

    // Required-but-nullable: an omitted store id is a schema violation, so the
    // framework rejects it before the handler — no wire call, no silent unmap.
    expect(result.isError, isTrue);
    expect(rec.calls, isEmpty);
  });

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
