import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

const _docsOrigin =
    'Reads the docs of the backend named in the restage_config.yaml of '
    'projectDirectory, else of the backend you are signed in to; '
    '$defaultDocsOrigin for Restage Cloud.';

final _docsProjectDirectory = Schema.string(
  description:
      "The app's Flutter project directory; its restage_config.yaml names "
      'the backend whose docs to read.',
);

/// Searches the published docs, the same as `restage docs search`.
final docsSearchTool = Tool(
  name: 'restage_docs_search',
  description:
      'Search the Restage documentation. Returns ranked sections with their '
      'page title, heading, URL, Markdown URL and a snippet. Read a result '
      'with restage_docs_read. $_docsOrigin',
  annotations: ToolAnnotations(readOnlyHint: true, openWorldHint: true),
  inputSchema: Schema.object(
    properties: {
      'query': Schema.string(description: 'Words to search for.'),
      'projectDirectory': _docsProjectDirectory,
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
      'read one section. $_docsOrigin',
  annotations: ToolAnnotations(readOnlyHint: true, openWorldHint: true),
  inputSchema: Schema.object(
    properties: {
      'path': Schema.string(
        description: 'Page path or URL, optionally with #anchor.',
      ),
      'projectDirectory': _docsProjectDirectory,
    },
    required: ['path'],
  ),
);

/// The docs tools, reading the docs of the configured backend through
/// [httpClient].
List<ToolEntry> docsTools(
  http.Client httpClient, {
  FileCredentialStore? credentialStore,
  Map<String, String> environment = const {},
}) {
  Future<DocsClient> client(CallToolRequest request) async {
    final directory = request.optStr('projectDirectory');
    final config = directory == null
        ? null
        : (await loadRestageConfig(from: Directory(directory)))?.config;
    return DocsClient.forBackend(
      await configuredBackend(
        config: config,
        credentialStore: credentialStore,
        environment: environment,
      ),
      httpClient: httpClient,
    );
  }

  return [
    (
      docsSearchTool,
      (request) async {
        final limit = request.optInt('limit') ?? 8;
        if (limit < 1) return mcpError('limit must be 1 or more.');
        try {
          final hits = await (await client(
            request,
          )).search(request.str('query'), limit: limit);
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
          final markdown = await (await client(
            request,
          )).read(request.str('path'));
          return CallToolResult(content: [TextContent(text: markdown)]);
        } on DocsException catch (error) {
          return mcpError(error.message);
        }
      },
    ),
  ];
}
