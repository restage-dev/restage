import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// One canned paywall as the backend's `surface.list` wire shape (paywalls
/// list via the surface substrate, so the row is a `SurfaceSummary`).
final _onePaywallBody = jsonEncode([
  {
    'surfaceType': 'paywall',
    'slug': 'pro',
    'name': 'Pro',
    'draftUpdatedAt': '2026-06-01T00:00:00.000Z',
    'publishedVersionByEnvironment': {'production': 3},
    '__className__': 'SurfaceSummary',
  },
]);

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_tool_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> writeCredential({String endpoint = 'https://api.test/'}) =>
      store.write(
        Credential(
          endpoint: endpoint,
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );

  test(
    'tools/list exposes restage_list_paywalls with the right schema',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      final result = await connection.listTools(ListToolsRequest());
      final tool = result.tools.singleWhere(
        (t) => t.name == 'restage_list_paywalls',
      );
      expect(
        tool.inputSchema.required,
        containsAll(['projectSlug', 'appSlug']),
      );
      expect(tool.inputSchema.properties, contains('projectSlug'));
      expect(tool.inputSchema.properties, contains('appSlug'));
    },
  );

  test(
    'tools/call returns the paywalls and sends the device-code auth header',
    () async {
      await writeCredential();
      Uri? seenUrl;
      String? seenMethod;
      String? seenAuth;
      Map<String, dynamic>? seenBody;
      final mock = MockClient((request) async {
        seenUrl = request.url;
        seenMethod = request.method;
        seenAuth = request.headers['authorization'];
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          _onePaywallBody,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final connection = await connectServer(store: store, httpClient: mock);
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      // Not an error.
      expect(result.isError, isNot(true));

      // Structured content carries the paywalls.
      final paywalls = result.structuredContent!['paywalls']! as List<dynamic>;
      expect(paywalls, hasLength(1));
      expect((paywalls.single as Map)['slug'], 'pro');

      // The text content is valid JSON mirroring the structured payload.
      final text = (result.content.single as TextContent).text;
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(
        (decoded['paywalls']! as List).single,
        isA<Map<String, dynamic>>(),
      );

      // The wire call hit <endpoint>/surface with method=list, surfaceType
      // paywall, and the slugs (paywalls list via the surface substrate).
      expect(seenMethod, 'POST');
      expect(seenUrl.toString(), 'https://api.test/surface');
      expect(seenBody!['method'], 'list');
      expect(seenBody!['surfaceType'], 'paywall');
      expect(seenBody!['projectSlug'], 'acme');
      expect(seenBody!['appSlug'], 'ios');

      // The load-bearing capital-`B` device-code header (no secret in output).
      expect(seenAuth, 'Basic ${base64Encode(utf8.encode('keyId:key'))}');
      expect(text, isNot(contains('keyId:key')));
    },
  );

  test(
    'tools/call without a credential returns a clean not-signed-in error',
    () async {
      final connection = await connectServer(
        store: store, // empty temp store
        httpClient: MockClient((_) async {
          fail('the backend must not be contacted when not signed in');
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, contains('restage login'));
    },
  );

  test(
    'tools/call maps a backend error cleanly without leaking a stack trace',
    () async {
      await writeCredential();
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'AppNotFoundException',
              'data': {
                '__className__': 'AppNotFoundException',
                'appSlug': 'ios',
                'projectSlug': 'acme',
              },
            }),
            404,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      // A legible, domain-specific message decoded from the typed payload —
      // not a raw status code or a Dart stack trace.
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
      expect(text, contains('ios'));
      expect(text, contains('acme'));
    },
  );

  test(
    'tools/call maps an unauthorized backend error to a not-permitted message',
    () async {
      await writeCredential();
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'UnauthorizedException',
              'data': {
                '__className__': 'UnauthorizedException',
                'resource': 'paywalls',
              },
            }),
            403,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text.toLowerCase(), contains('not permitted'));
      expect(text, isNot(contains('#0')));
    },
  );

  test('tools/call with a corrupt credential leaks neither the secret nor a '
      'stack trace', () async {
    // A malformed credentials file: jsonDecode inside the credential read
    // throws a FormatException whose message embeds the raw source text —
    // which contains the secret authToken.
    File('${tempDir.path}/credentials').writeAsStringSync(
      '{"endpoint":"https://api.test/","kind":"authKey",'
      '"authToken":"keyId:SUPERSECRET" CORRUPT}',
    );
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async {
        fail('the backend must not be contacted with a corrupt credential');
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_paywalls',
        arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
      ),
    );

    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, isNot(contains('SUPERSECRET')));
    expect(text, isNot(contains('keyId:')));
    expect(text, isNot(contains('#0')));
    expect(text, isNot(contains('package:restage')));
  });

  test(
    'tools/call with a non-JSON 200 body leaks no stack trace (API path)',
    () async {
      // A proxy/CDN can return HTTP 200 with a non-JSON body; the wire layer
      // throws a FormatException deep inside PaywallApi.list. The catch-all
      // must cover this second code path, not just the credential read.
      await writeCredential();
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            '<html>503 from a proxy</html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
      expect(text, isNot(contains('FormatException')));
    },
  );

  test(
    'tools/call with a wrong-shape 200 body leaks no stack trace (API path)',
    () async {
      // Valid JSON, wrong shape (object, not the expected list) — PaywallApi
      // throws a TypeError. Same catch-all, same no-leak guarantee.
      await writeCredential();
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
          name: 'restage_list_paywalls',
          arguments: {'projectSlug': 'acme', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
    },
  );

  test('tools/call with a missing required argument is rejected', () async {
    await writeCredential();
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async {
        fail('the backend must not be contacted when input is invalid');
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_paywalls',
        arguments: {'projectSlug': 'acme'}, // appSlug missing
      ),
    );

    expect(result.isError, isTrue);
  });
}
