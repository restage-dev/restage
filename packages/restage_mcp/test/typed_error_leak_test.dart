import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Regression: a non-200 whose body has a recognized `className` but a
/// wrong-typed `data` field makes the typed-error decoder's unchecked cast
/// throw. That throw happens inside `guardErrors`' `on RestageApiException`
/// clause; a throw in a catch clause escapes the enclosing try (its sibling
/// catch does NOT catch it), so without a guard it reaches the MCP framework's
/// catch-all and the Dart stack trace is forwarded to the client.
void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_typed_leak');
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
    'a typed error with a malformed data field leaks no stack trace',
    () async {
      // 404 with a recognized className but `appSlug` as an int, not a string —
      // the typed decoder's `data['appSlug'] as String` throws.
      final connection = await connectServer(
        store: store,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'className': 'AppNotFoundException',
              'data': {'appSlug': 12345, 'projectSlug': 'mobile'},
            }),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_products',
          arguments: {'projectSlug': 'mobile', 'appSlug': 'ios'},
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, isNot(contains('TypeError')));
      expect(text, isNot(contains('#0')));
      expect(text, isNot(contains('package:restage')));
      expect(text, isNot(contains('SUPERSECRET')));
    },
  );
}
