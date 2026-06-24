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
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_appconfig_test');
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
    'tools/list exposes both app-config tools with the right schemas',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final tools = {
        for (final t in (await connection.listTools(ListToolsRequest())).tools)
          t.name: t,
      };

      expect(tools, contains('restage_get_app_config'));
      expect(tools, contains('restage_update_app_config'));

      // get reads via listApps, which needs the org id.
      expect(
        tools['restage_get_app_config']!.inputSchema.required,
        containsAll(['organizationId', 'projectSlug', 'appSlug']),
      );
      // update only needs project + app (org id is an optional disambiguator).
      expect(
        tools['restage_update_app_config']!.inputSchema.required,
        containsAll(['projectSlug', 'appSlug']),
      );
      expect(
        tools['restage_update_app_config']!.inputSchema.required ?? const [],
        isNot(contains('organizationId')),
      );
    },
  );

  test(
    'get_app_config reads via listApps and returns the matched app',
    () async {
      final rec = _recorder(
        jsonEncode([
          {
            'id': 1,
            'slug': 'ios',
            'name': 'iOS',
            'iosBundleId': 'com.acme.ios',
          },
          {'id': 2, 'slug': 'android', 'name': 'Android'},
        ]),
      );
      final connection = await connectServer(
        store: store,
        httpClient: rec.client,
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_get_app_config',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'mobile',
            'appSlug': 'ios',
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(rec.calls.single.url.toString(), 'https://api.test/app');
      expect(rec.calls.single.body['method'], 'listApps');
      expect(rec.calls.single.body['organizationId'], 7);
      expect(rec.calls.single.body['projectSlug'], 'mobile');
      final app = result.structuredContent!['app']! as Map;
      expect(app['slug'], 'ios');
      expect(app['iosBundleId'], 'com.acme.ios');
    },
  );

  test('get_app_config returns a clean error when no app matches', () async {
    final rec = _recorder(
      jsonEncode([
        {'id': 2, 'slug': 'android', 'name': 'Android'},
      ]),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_get_app_config',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'mobile',
          'appSlug': 'ios',
        },
      ),
    );

    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, contains('ios'));
    expect(text, isNot(contains('SUPERSECRET')));
  });

  test('update_app_config omits an absent field (leave) and sends an empty '
      'string (clear)', () async {
    final rec = _recorder(
      jsonEncode({
        'id': 1,
        'slug': 'ios',
        'name': 'iOS',
        'iosBundleId': 'com.acme.new',
        'webDomain': '',
      }),
    );
    final connection = await connectServer(
      store: store,
      httpClient: rec.client,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_update_app_config',
        arguments: {
          'projectSlug': 'mobile',
          'appSlug': 'ios',
          'iosBundleId': 'com.acme.new',
          'webDomain': '', // explicit clear
          // androidPackage omitted -> leave unchanged
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(rec.calls.single.body['method'], 'updateAppConfiguration');
    expect(rec.calls.single.body['iosBundleId'], 'com.acme.new');
    // Empty string is forwarded verbatim (clear), not dropped.
    expect(rec.calls.single.body['webDomain'], '');
    // Absent field is omitted from the wire (leave unchanged).
    expect(rec.calls.single.body.containsKey('androidPackage'), isFalse);
    final app = result.structuredContent!['app']! as Map;
    expect(app['iosBundleId'], 'com.acme.new');
  });

  test(
    'a wrong-shape 200 leaks neither the secret nor a stack trace',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"unexpected": true}', // listApps expects a list
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_get_app_config',
          arguments: {
            'organizationId': 7,
            'projectSlug': 'mobile',
            'appSlug': 'ios',
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
