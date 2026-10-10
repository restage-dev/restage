import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_app_delete');
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

  http.Response typed(String className, Map<String, Object?> data) =>
      http.Response(
        jsonEncode({
          'className': className,
          'data': {'__className__': className, ...data},
        }),
        400,
        headers: {'content-type': 'application/json'},
      );

  Future<CallToolResult> call(
    http.Response Function(Map<String, dynamic> body) respond,
  ) async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return respond(body);
      }),
    );
    return connection.callTool(
      CallToolRequest(
        name: 'restage_delete_app',
        arguments: {
          'projectSlug': 'acme',
          'appSlug': 'tour',
          'name': 'Welcome Tour',
        },
      ),
    );
  }

  test('the tool requires the app\'s exact name', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };
    final tool = tools['restage_delete_app']!;
    expect(tool.inputSchema.required, contains('name'));
    expect(
      tool.description,
      'Delete an app nothing uses. Refused while it has serving surfaces, '
      'active API keys, running experiments or delivery rules. Requires the '
      "app's exact name.",
    );
  });

  test('a delete sends the name it was given', () async {
    Map<String, dynamic>? sent;
    final result = await call((body) {
      sent = body;
      return http.Response(
        'null',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    expect(result.isError, isNot(true));
    expect(sent!['method'], 'deleteApp');
    expect(sent!['confirmationName'], 'Welcome Tour');
  });

  test('a refusal names every hold with its count', () async {
    final result = await call(
      (_) => typed('AppDeleteRefusedException', {
        'appName': 'Welcome Tour',
        'projectName': 'Fitness',
        'holds': [
          {'kind': 'servingSurface', 'count': 1},
          {'kind': 'runningExperiment', 'count': 2},
        ],
      }),
    );
    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, contains('Welcome Tour is still in use'));
    expect(text, contains('1 surface serving'));
    expect(text, contains('2 running experiments'));
  });

  test('a name that is not the app\'s names the app', () async {
    final result = await call(
      (_) =>
          typed('AppDeleteNameMismatchException', {'appName': 'Welcome Tour'}),
    );
    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, "The name doesn't match the app's name, Welcome Tour.");
  });
}
