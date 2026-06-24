import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Security regression: a corrupt/crafted credentials file must not leak its own
/// bytes to the client. Here the stored `endpoint` embeds userinfo
/// (`<keyId>:<secret>@host`); the insecure-transport guard rejects it, and the
/// rejection message must NOT echo the endpoint (which carries the secret).
void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_cred_leak');
    store = FileCredentialStore('${tempDir.path}/credentials');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'an insecure stored endpoint with embedded userinfo leaks no secret',
    () async {
      // The endpoint is http (non-loopback) AND embeds `99:SUPERSECRET` as
      // userinfo — the insecure-transport guard throws; the message must not echo
      // it.
      await store.write(
        const Credential(
          endpoint: 'http://99:SUPERSECRET@evil.example/',
          kind: CredentialKind.authKey,
          authToken: '99:SUPERSECRET',
        ),
      );

      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
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
      expect(text, isNot(contains('evil.example')));
    },
  );

  test(
    'passthrough drops secret-named backend fields but keeps benign ones',
    () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.test/',
          kind: CredentialKind.authKey,
          // A realistic long token (production keys are high-entropy), so the
          // value funnel does not collide with benign field names here — this
          // test exercises the key-NAME redaction, not the value scrub.
          authToken: 'keyId:passthrough_session_token_value',
        ),
      );
      // A buggy/hostile 200 that mixes benign view fields with secret-named ones
      // (incl. a nested secret) — the output funnel must drop the secrets and keep
      // the benign fields, even those whose name merely CONTAINS a secret token
      // (keyPrefix contains "key"; credentialFingerprint contains "credential").
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'id': 1,
                'keyPrefix': 'rs_pk_ab',
                'credentialFingerprint': 'a1b2',
                'environmentId': 9,
                'plaintext': 'rs_sk_LEAK',
                'keyHash': 'HASHLEAK',
                'nested': {'authToken': 'TOKLEAK', 'ok': 'keep'},
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
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

      expect(result.isError, isNot(true));
      final text = (result.content.single as TextContent).text;
      // Secret-named fields dropped from the rendered text...
      expect(text, isNot(contains('rs_sk_LEAK')));
      expect(text, isNot(contains('HASHLEAK')));
      expect(text, isNot(contains('TOKLEAK')));
      // ...and benign fields kept.
      expect(text, contains('rs_pk_ab'));
      final row = (result.structuredContent!['apiKeys']! as List).single as Map;
      expect(row.containsKey('plaintext'), isFalse);
      expect(row.containsKey('keyHash'), isFalse);
      expect(row['keyPrefix'], 'rs_pk_ab');
      expect(row['credentialFingerprint'], 'a1b2');
      // Recursion: the nested secret is dropped, the nested benign field kept.
      expect((row['nested'] as Map).containsKey('authToken'), isFalse);
      expect((row['nested'] as Map)['ok'], 'keep');
    },
  );

  test(
    'the session token is scrubbed even when reflected under a benign key',
    () async {
      // Defense-in-depth: a buggy backend echoes the session token VALUE under a
      // benign field name (keyPrefix), which exact-key redaction keeps. The
      // value-scrub in the authed funnel removes the token (full `keyId:key` and
      // the bare key part) wherever it appears.
      await store.write(
        const Credential(
          endpoint: 'https://api.test/',
          kind: CredentialKind.authKey,
          authToken: 'keyId:SCRUBME',
        ),
      );
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'id': 1,
                'keyPrefix': 'keyId:SCRUBME',
                'note': 'also SCRUBME here',
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
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

      expect(result.isError, isNot(true));
      final blob =
          '${(result.content.single as TextContent).text} '
          '${jsonEncode(result.structuredContent)}';
      expect(blob, isNot(contains('SCRUBME')));
    },
  );

  test('a connection failure does not echo the endpoint host', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
    // A DNS failure: Dart embeds the host in SocketException.message.
    final connection = await connectServer(
      store: store,
      httpClient: MockClient(
        (_) async => throw const SocketException(
          "Failed host lookup: 'SECRETHOST.example'",
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
    expect(text, isNot(contains('SECRETHOST')));
  });

  test('whoami scrubs a session token aliased into the email', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:SUPERSECRET',
      ),
    );
    final connection = await connectServer(
      store: store,
      // A buggy backend whose whoami returns an email aliasing the session token.
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'id': 1, 'email': 'keyId:SUPERSECRET'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_whoami', arguments: {}),
    );

    final blob =
        '${(result.content.single as TextContent).text} '
        '${jsonEncode(result.structuredContent)}';
    expect(blob, isNot(contains('SUPERSECRET')));
  });

  test('already-signed-in login scrubs a token aliased into the email', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:SUPERSECRET',
      ),
    );
    final connection = await connectServer(
      store: store,
      // _signedInEmail -> whoami returns an aliasing email -> already_signed_in.
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'id': 1, 'email': 'leading keyId:SUPERSECRET trailing'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      loginEndpoint: Uri.parse('https://api.test/'),
      openBrowser: (_) async {},
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_login', arguments: {}),
    );

    expect(result.structuredContent!['status'], 'already_signed_in');
    final blob =
        '${(result.content.single as TextContent).text} '
        '${jsonEncode(result.structuredContent)}';
    expect(blob, isNot(contains('SUPERSECRET')));
  });

  test('the session token is scrubbed when reflected as a map KEY', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:MAPKEY_SECRET',
      ),
    );
    // A buggy backend keys a map BY the session token (full token at top level,
    // bare key nested) — the value funnel must scrub map keys, not just values.
    final connection = await connectServer(
      store: store,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'keyId:MAPKEY_SECRET': 'v1',
              'wrapper': {'MAPKEY_SECRET': 'v2'},
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
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

    expect(result.isError, isNot(true));
    final blob =
        '${(result.content.single as TextContent).text} '
        '${jsonEncode(result.structuredContent)}';
    expect(blob, isNot(contains('MAPKEY_SECRET')));
  });
}
