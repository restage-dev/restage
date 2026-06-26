import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_lifecycle_test');
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
    'tools/list exposes the lifecycle tools with the right schemas',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('null', 200)),
      );
      final tools = {
        for (final t in (await connection.listTools(ListToolsRequest())).tools)
          t.name: t,
      };

      expect(
        tools['restage_publish_paywall']!.inputSchema.required,
        containsAll([
          'projectSlug',
          'appSlug',
          'paywallSlug',
          'environmentSlug',
        ]),
      );
      expect(
        tools['restage_get_published_version']!.inputSchema.required,
        containsAll([
          'projectSlug',
          'appSlug',
          'paywallSlug',
          'environmentSlug',
        ]),
      );
      expect(
        tools['restage_get_paywall']!.inputSchema.required,
        containsAll(['projectSlug', 'appSlug', 'paywallSlug']),
      );
      // organizationId is optional on the paywall tools.
      expect(
        tools['restage_publish_paywall']!.inputSchema.properties,
        contains('organizationId'),
      );
      expect(
        tools['restage_publish_paywall']!.inputSchema.required,
        isNot(contains('organizationId')),
      );
    },
  );

  test(
    'publish_paywall hits paywall.publish and returns the new version',
    () async {
      Map<String, dynamic>? seen;
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((request) async {
          seen = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('4', 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
            'organizationId': 9,
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(seen!['method'], 'publish');
      expect(seen!['surfaceType'], 'paywall');
      expect(seen!['surfaceSlug'], 'pro');
      expect(seen!['environmentSlug'], 'production');
      expect(seen!['organizationId'], 9);
      expect(result.structuredContent!['version'], 4);
    },
  );

  test(
    'publish_paywall maps an admin-only rejection to a not-permitted message',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'UnauthorizedException',
              'data': {
                '__className__': 'UnauthorizedException',
                'resource': 'paywall',
              },
            }),
            403,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text.toLowerCase(), contains('not permitted'));
      expect(text, isNot(contains('#0')));
    },
  );

  test(
    'publish_paywall maps the surface not-found exception to a paywall message',
    () async {
      // Paywalls publish via the surface endpoint, so a never-saved paywall
      // surfaces as SurfaceNotFoundException — the MCP must still present a
      // legible "no paywall" message, not a bare status code.
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'SurfaceNotFoundException',
              'data': {
                '__className__': 'SurfaceNotFoundException',
                'surfaceSlug': 'pro',
              },
            }),
            400,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, contains("No paywall 'pro'"));
      expect(text, isNot(contains('status')));
      expect(text, isNot(contains('#0')));
    },
  );

  test(
    'publish_paywall maps the surface publish-conflict to a retry message',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'SurfacePublishConflictException',
              'data': {
                '__className__': 'SurfacePublishConflictException',
                'surfaceSlug': 'pro',
                'environmentSlug': 'production',
              },
            }),
            409,
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text.toLowerCase(), contains('concurrent publish'));
      expect(text, contains("paywall 'pro'"));
      expect(text, isNot(contains('#0')));
    },
  );

  test(
    'get_published_version returns the version, and null when never published',
    () async {
      // First call: a real version.
      final c1 = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('3', 200)),
      );
      final r1 = await c1.callTool(
        CallToolRequest(
          name: 'restage_get_published_version',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
          },
        ),
      );
      expect(r1.isError, isNot(true));
      expect(r1.structuredContent!['version'], 3);

      // Second call: never published -> null.
      final c2 = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('null', 200)),
      );
      final r2 = await c2.callTool(
        CallToolRequest(
          name: 'restage_get_published_version',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
            'environmentSlug': 'production',
          },
        ),
      );
      expect(r2.isError, isNot(true));
      expect(r2.structuredContent!['version'], isNull);
    },
  );

  test(
    'get_paywall returns clean base64, never the decode() wire wrapper',
    () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 250]);
      // The surface store holds the canonical BlobSurfacePayload frame; the
      // backend returns it in the ByteData wire form, and get_paywall
      // unwraps it back to the inner blob.
      final frame = BlobSurfacePayload(
        minClient: 3,
        blob: bytes,
      ).canonicalBytes;
      final wire = "decode('${base64Encode(frame)}', 'base64')";
      Map<String, dynamic>? seen;
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((request) async {
          seen = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(wire), 200);
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_get_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(seen!['method'], 'load');
      expect(seen!['surfaceType'], 'paywall');
      expect(seen!['surfaceSlug'], 'pro');
      final base64Out = result.structuredContent!['paywallBase64']! as String;
      expect(base64Decode(base64Out), equals(bytes));
      expect(result.structuredContent!['byteLength'], bytes.length);
      // The SQL-fragment wire form must never reach the agent.
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains("decode('")));
      expect(base64Out, isNot(contains("decode('")));
    },
  );

  test(
    'a wrong-shape 200 body leaks neither the secret nor a stack trace',
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
          name: 'restage_publish_paywall',
          arguments: {
            'projectSlug': 'acme',
            'appSlug': 'ios',
            'paywallSlug': 'pro',
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
