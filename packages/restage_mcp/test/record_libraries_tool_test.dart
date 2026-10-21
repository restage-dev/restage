import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  late Directory package;
  late ServerConnection connection;

  setUp(() async {
    package = Directory.systemTemp.createTempSync('record_libraries_tool_');
    File('${package.path}/pubspec.yaml').writeAsStringSync('name: acme');
    connection = await connectServer(
      store: FileCredentialStore('${package.path}/credentials'),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
  });

  tearDown(() => package.deleteSync(recursive: true));

  Future<CallToolResult> record() => connection.callTool(
    CallToolRequest(
      name: 'restage_record_libraries',
      arguments: {'projectDirectory': package.path},
    ),
  );

  test('records the drafted contracts like the CLI', () async {
    File(
        '${package.path}/.restage/build/library-contracts/acme.widgets/v2.json',
      )
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'namespace': 'acme.widgets',
          'capabilityVersion': 2,
          'compatibleSince': 1,
        }),
      );

    final result = await record();

    expect(result.isError, isNot(true));
    final recorded = result.structuredContent!['recorded']! as List;
    expect(recorded.single, containsPair('namespace', 'acme.widgets'));
    expect(
      File(
        '${package.path}/.restage/library-contracts/acme.widgets/v2.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('says to build first when nothing is drafted', () async {
    final result = await record();

    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      contains('dart run build_runner build'),
    );
  });
}
