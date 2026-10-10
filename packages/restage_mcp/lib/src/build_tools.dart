import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// Builds and the widget catalog, bound to [ctx].
List<(Tool, ToolHandler)> buildTools(ToolContext ctx) => [
  (_listBuildsTool, (request) => _listBuilds(ctx, request)),
  (_pushBuildTool, (request) => _pushBuild(ctx, request)),
  (_pushCatalogTool, (request) => _pushCatalog(ctx, request)),
];

final _listBuildsTool = Tool(
  name: 'restage_list_builds',
  description:
      "List an app's builds, the same as `restage build list`: one head per "
      'environment plus one per user, each with the version it points at, '
      'the commit it was built from, and the app widget libraries that '
      'version registers. A surface that uses app widgets displays in the '
      'dashboard only through a build that registers them.',
  inputSchema: Schema.object(
    properties: appProperties(),
    required: appRequired,
  ),
);

final _pushBuildTool = Tool(
  name: 'restage_push_build',
  description:
      "Build the app's registered widgets and push the build as a render "
      'bundle, the same as `restage build push`. Moves an environment head '
      'when environmentSlug is given (an admin or a push-scoped key), or '
      "the signed-in user's own head. Runs the Flutter web build, so it "
      'can take minutes. An unchanged build uploads nothing.',
  inputSchema: Schema.object(
    properties: {
      ...localProjectProperties(),
      'environmentSlug': Schema.string(
        description:
            'The environment head to move. Omit to push to your own head.',
      ),
      'recordGit': Schema.bool(
        description: 'Record the push as a release receipt in the repository.',
      ),
      'generate': Schema.bool(
        description:
            'Run the code generator first (default true). Pass false to build '
            'against the catalog a previous run produced.',
      ),
    },
    required: ['projectDirectory'],
  ),
);

final _pushCatalogTool = Tool(
  name: 'restage_push_catalog',
  description:
      "Upload the app's generated widget catalog, the same as `restage "
      'catalog push`. Reports when the project has no generated catalog.',
  inputSchema: Schema.object(
    properties: localProjectProperties(),
    required: ['projectDirectory'],
  ),
);

Future<CallToolResult> _listBuilds(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('listing the builds', (api) async {
    final heads = await RenderBundleApi(rpc: api, uploadClient: ctx.httpClient)
        .listHeads(
          project: request.str('projectSlug'),
          app: request.str('appSlug'),
          organizationId: request.optInt('organizationId'),
        );
    return jsonResult(<String, Object?>{
      'heads': [for (final head in heads) head.toJson()],
    });
  });
}

Future<CallToolResult> _pushBuild(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('pushing the build', (api) async {
    final project = cliProjectArgs(request);
    return cliResult(ctx, [
      'build',
      'push',
      ...project,
      if (request.optStr('environmentSlug') case final environment?) ...[
        '--env',
        environment,
      ],
      if (request.optBool('recordGit') ?? false) '--record-git',
      if (request.optBool('generate') == false) '--no-generate',
    ]);
  });
}

Future<CallToolResult> _pushCatalog(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('pushing the widget catalog', (api) async {
    final project = cliProjectArgs(request);
    return cliResult(ctx, ['catalog', 'push', ...project]);
  });
}
