import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/src/api_runner.dart';
import 'package:restage_mcp/src/auth.dart';
import 'package:restage_mcp/src/tool_support.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late ToolContext ctx;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_auth_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
    ctx = ToolContext(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      runCli: (args, {required stdout, required stderr, target}) async => 0,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String text(CallToolResult result) =>
      (result.content.single as TextContent).text;

  Future<CallToolResult> reached() =>
      ctx.authed('testing', (_) async => jsonResult({'reached': true}));

  test('with no credential the call is refused as not signed in', () async {
    final result = await reached();

    expect(result.isError, isTrue);
    expect(text(result), const NotSignedInException().toString());
    expect(text(result), contains('restage login'));
  });

  for (final endpoint in ['https://example.test/', 'http://127.0.0.1:8080/']) {
    test('a credential for $endpoint reaches the body', () async {
      await store.write(
        Credential(
          endpoint: endpoint,
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );

      final result = await reached();

      expect(result.isError, isNot(true), reason: text(result));
      expect(result.structuredContent, {'reached': true});
    });
  }

  test(
    'a non-loopback http credential is refused without echoing it',
    () async {
      await store.write(
        const Credential(
          endpoint: 'http://evil.example/',
          kind: CredentialKind.authKey,
          authToken: 'keyId:key',
        ),
      );

      final result = await reached();

      expect(result.isError, isTrue);
      expect(text(result), contains('not a secure'));
      expect(text(result), isNot(contains('evil.example')));
    },
  );
}
