import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// Builds and the widget catalog, bound to [ctx].
List<(Tool, ToolHandler)> buildTools(ToolContext ctx) => [
  (_listBuildsTool, (request) => _listBuilds(ctx, request)),
  (_pushBuildTool, (request) => _pushBuild(ctx, request)),
  (_pushCatalogTool, (request) => _pushCatalog(ctx, request)),
  (_buildReportTool, _buildReport),
  (_promoteTool, (request) => _promote(ctx, request)),
];

final _promoteTool = Tool(
  name: 'restage_widget_promote',
  description:
      'Move a widget that renders from the app into a widget class of the '
      "app's own, exported from the package's widget library, the same as "
      '`restage $promoteCommandName <file>:<line>`. Name the place as '
      'restage_build_report lists it. Use it only when the developer wants '
      'the code named and reusable; nothing requires it. Rebuild afterwards.',
  inputSchema: Schema.object(
    properties: {
      'projectDirectory': projectDirectoryProperty,
      'at': Schema.string(
        description: 'The place, as <file>:<line> or <file>:<line>:<column>.',
      ),
      'name': Schema.string(description: 'The new widget class name.'),
      'library': Schema.string(
        description:
            'The widget library to export it from, when the package has '
            'several.',
      ),
    },
    required: ['projectDirectory', 'at'],
  ),
);

Future<CallToolResult> _promote(
  ToolContext ctx,
  CallToolRequest request,
) => cliResult(ctx, [
  ...promoteCommandName.split(' '),
  '-C',
  request.str('projectDirectory'),
  if (request.optStr('name') case final name?) ...['--name', name],
  if (request.optStr('library') case final library?) ...['--library', library],
  request.str('at'),
]);

final _buildReportTool = Tool(
  name: 'restage_build_report',
  description:
      'Report what the last local build compiled, the same as `restage build '
      'report --json`: for each generated widget, how many widgets it '
      'delivers and how many render from the app, and each value, action and '
      'app-rendered widget with its reason and source location. `islands` '
      'groups the app-rendered widgets by widget and reason; each site lists '
      'the arguments a design can change (`properties`, `slots`) and the '
      'ones that stay in app code (`compiled`, each with a reason code and a '
      '`message` that says why and what to try). `changes` '
      'lists what renders from the app or what the generated widget keeps '
      'differently from restage_build_report.json, and is absent when there '
      'is no baseline. Keep app-rendered parts unless the developer wants to '
      'change or test what they cover; never rewrite code only to make one '
      'go away. Needs a build_runner build; reads no server.',
  inputSchema: Schema.object(
    properties: {
      'projectDirectory': projectDirectoryProperty,
      'accept': Schema.bool(
        description:
            'Record this build as the baseline in restage_build_report.json.',
      ),
    },
    required: ['projectDirectory'],
  ),
);

Future<CallToolResult> _buildReport(CallToolRequest request) async {
  try {
    return jsonResult(
      buildReportJson(
        await readBuildReport(
          Directory(request.str('projectDirectory')),
          accept: request.optBool('accept') ?? false,
        ),
      ),
    );
  } on BuildReportException catch (error) {
    return mcpError(error.message);
  }
}

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
      'when environmentSlug is given (an admin or a push-scoped key), the '
      "signed-in user's own head with personal, and otherwise the caller's "
      "default: the user's own head, or a key's environment. Runs the Flutter web build, so it "
      'can take minutes. An unchanged build uploads nothing. The build only '
      'feeds dashboard previews; devices render surfaces with the widgets '
      "compiled into the app. The build uses the app's own Flutter, whatever "
      'version it is: it is taken from flutterRoot, `flutterRoot` in '
      "restage_config.yaml, the project's FVM link or its .fvmrc or "
      '.flutter-version pin, the SDK its packages were resolved with, '
      'FLUTTER_ROOT, then PATH.',
  inputSchema: Schema.object(
    properties: {
      ...localProjectProperties(),
      'environmentSlug': Schema.string(
        description:
            "The environment head to move. Omit for the caller's default "
            'head.',
      ),
      'personal': Schema.bool(
        description:
            "Push to the signed-in user's own head, which only they can "
            'move. Not with environmentSlug, and not with a key.',
      ),
      'recordGit': Schema.bool(
        description: 'Record the push as a release receipt in the repository.',
      ),
      'flutterRoot': flutterRootProperty,
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
      "catalog push`. The catalog lists the app's own @RestageWidget widgets "
      "in the dashboard editor's palette. Devices never need it, and "
      'dashboard previews draw app widgets from restage_push_build. Run the '
      'code generator first; reports when the project has no generated '
      'catalog.',
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
      if (request.optBool('personal') ?? false) '--personal',
      if (request.optBool('recordGit') ?? false) '--record-git',
      if (request.optBool('generate') == false) '--no-generate',
      ...cliFlutterRootArgs(request),
    ]);
  });
}

Future<CallToolResult> _pushCatalog(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('pushing the widget catalog', (api) async {
    final project = cliProjectArgs(request);
    return cliResult(ctx, ['catalog', 'push', ...project]);
  });
}
