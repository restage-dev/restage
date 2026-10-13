import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

final _index = jsonEncode({
  'version': 1,
  'origin': 'https://docs.restage.dev',
  'pages': <Object>[],
  'chunks': [
    {
      'page': '/delivery/live-refresh',
      'title': 'Live refresh',
      'headings': ['Bring your own update channel'],
      'anchor': 'bring-your-own-update-channel',
      'url':
          'https://docs.restage.dev/delivery/live-refresh#bring-your-own-update-channel',
      'markdownUrl': 'https://docs.restage.dev/delivery/live-refresh.md',
      'markdown':
          '## Bring your own update channel\n\nImplement `SurfaceUpdateChannel`.',
      'hash': '0000000000000000',
    },
  ],
});

void main() {
  late ServerConnection connection;
  final requested = <String>[];

  setUp(() async {
    requested.clear();
    final directory = await Directory.systemTemp.createTemp('docs-tools-');
    addTearDown(() => directory.delete(recursive: true));
    connection = await connectServer(
      store: FileCredentialStore('${directory.path}/credentials'),
      httpClient: MockClient((request) async {
        requested.add(request.url.toString());
        return switch (request.url.path) {
          '/docs-index.json' => http.Response(_index, 200),
          '/delivery/live-refresh.md' => http.Response('# Live refresh\n', 200),
          _ => http.Response('not found', 404),
        };
      }),
    );
  });

  String text(CallToolResult result) =>
      (result.content.single as TextContent).text;

  test('restage_docs_search returns ranked sections with URLs', () async {
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_docs_search',
        arguments: {'query': 'update channel'},
      ),
    );
    expect(result.isError, isNot(true));
    final hit =
        ((jsonDecode(text(result)) as Map)['results'] as List).single as Map;
    expect(hit['section'], 'Bring your own update channel');
    expect(hit['url'], endsWith('#bring-your-own-update-channel'));
    expect(hit['snippet'], contains('`SurfaceUpdateChannel`'));
    expect(requested, ['https://docs.restage.dev/docs-index.json']);
  });

  test('restage_docs_read returns the page Markdown', () async {
    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_docs_read',
        arguments: {'path': 'https://docs.restage.dev/delivery/live-refresh'},
      ),
    );
    expect(text(result), '# Live refresh\n');
  });

  test('restage_docs_read names a missing page', () async {
    final result = await connection.callTool(
      CallToolRequest(name: 'restage_docs_read', arguments: {'path': '/nope'}),
    );
    expect(result.isError, isTrue);
    expect(text(result), contains('No docs page at /nope'));
  });
}
