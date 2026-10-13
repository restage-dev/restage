import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// Searches the published docs, the same as `restage docs search`.
final docsSearchTool = Tool(
  name: 'restage_docs_search',
  description:
      'Search the Restage documentation. Returns ranked sections with their '
      'page title, heading, URL, Markdown URL and a snippet. Read a result '
      'with restage_docs_read.',
  annotations: ToolAnnotations(readOnlyHint: true, openWorldHint: true),
  inputSchema: Schema.object(
    properties: {
      'query': Schema.string(description: 'Words to search for.'),
      'limit': Schema.int(
        description: 'The most sections to return (default 8).',
      ),
    },
    required: ['query'],
  ),
);

/// Reads a docs page or section as Markdown, the same as `restage docs read`.
final docsReadTool = Tool(
  name: 'restage_docs_read',
  description:
      'Read a Restage documentation page as Markdown. Takes a site path '
      '(/delivery/hosted-delivery), a .md path or a docs URL. Add #anchor to '
      'read one section. The index of every page is at '
      'https://docs.restage.dev/llms.txt.',
  annotations: ToolAnnotations(readOnlyHint: true, openWorldHint: true),
  inputSchema: Schema.object(
    properties: {
      'path': Schema.string(
        description: 'Page path or URL, optionally with #anchor.',
      ),
    },
    required: ['path'],
  ),
);

/// The docs tools, reading the published docs through [httpClient].
List<ToolEntry> docsTools(
  http.Client httpClient, {
  Map<String, String> environment = const {},
}) {
  DocsClient client() =>
      DocsClient.fromEnvironment(environment, httpClient: httpClient);
  return [
    (
      docsSearchTool,
      (request) async {
        final limit = request.optInt('limit') ?? 8;
        if (limit < 1) return mcpError('limit must be 1 or more.');
        try {
          final hits = await client().search(
            request.str('query'),
            limit: limit,
          );
          return jsonResult({
            'results': [for (final hit in hits) hit.toJson()],
          });
        } on DocsException catch (error) {
          return mcpError(error.message);
        }
      },
    ),
    (
      docsReadTool,
      (request) async {
        try {
          final markdown = await client().read(request.str('path'));
          return CallToolResult(content: [TextContent(text: markdown)]);
        } on DocsException catch (error) {
          return mcpError(error.message);
        }
      },
    ),
  ];
}
