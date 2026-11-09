import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// Local project setup and checks, bound to [ctx].
List<(Tool, ToolHandler)> projectTools(ToolContext ctx) => [
  (_statusTool, (request) => _status(ctx, request)),
  (_initTool, (request) => _init(ctx, request)),
  (_doctorTool, (request) => _doctor(ctx, request)),
];

final _statusTool = Tool(
  name: 'restage_status',
  description:
      'Report the signed-in account, the endpoint, and the organization, '
      'project, app and environment a local project is configured for, the '
      'same as `restage status`.',
  inputSchema: Schema.object(
    properties: {
      'projectDirectory': Schema.string(
        description:
            'Directory to start the restage_config.yaml search from. Omit to '
            'report the account alone.',
      ),
    },
  ),
);

final _initTool = Tool(
  name: 'restage_init',
  description:
      'Set up a Flutter project for Restage, the same as `restage init`: '
      'writes restage_config.yaml, a starter surface, pubspec dependencies, '
      'and build-output ignores. Pass dryRun to see the plan first.',
  inputSchema: Schema.object(
    properties: {
      'projectDirectory': Schema.string(
        description: 'The Flutter project root.',
      ),
      'projectSlug': Schema.string(description: 'The project slug.'),
      'appSlug': Schema.string(description: 'The app slug.'),
      'environmentSlug': Schema.string(
        description: 'The default environment slug.',
      ),
      'organizationId': organizationIdProperty,
      'runtimePlane': UntitledSingleSelectEnumSchema(
        description:
            'Default runtime plane: sandbox or live. Omit it to use the plane '
            'the environment is on, sandbox first.',
        values: runtimePlaneWireNames,
      ),
      'starter': Schema.bool(
        description: 'Write a starter surface (default true).',
      ),
      'addDependencies': Schema.bool(
        description:
            'Add restage and restage_material plus restage_codegen and '
            'build_runner to pubspec.yaml, from the main branch of the public '
            'Restage repository, with the overrides they need (default true).',
      ),
      'sdkKey': Schema.string(
        description:
            "The app's publishable key (rs_pk_...), written to build.yaml with "
            'the service URL, so Restage.configure uses them and the app sends '
            'its first request before Dart starts. Without it the app builds '
            'and runs offline.',
      ),
      'previewWrapper': Schema.string(
        description:
            'A function in lib/ that wraps push images with what the app '
            'provides above its screens, such as a theme: '
            'lib/restage_preview.dart#wrapPreview.',
      ),
      'dryRun': Schema.bool(
        description: 'Report the planned changes without writing them.',
      ),
    },
    required: ['projectDirectory', 'projectSlug', 'appSlug', 'environmentSlug'],
  ),
);

final _doctorTool = Tool(
  name: 'restage_doctor',
  description:
      'Check a Flutter project for common Restage setup issues, the same as '
      '`restage doctor`.',
  inputSchema: Schema.object(
    properties: {
      'projectDirectory': Schema.string(
        description: 'The Flutter project root.',
      ),
    },
    required: ['projectDirectory'],
  ),
);

Future<CallToolResult> _status(ToolContext ctx, CallToolRequest request) =>
    guardErrors(
      'reading the status',
      () => cliResult(ctx, [
        'status',
        if (request.optStr('projectDirectory') case final directory?) ...[
          '-C',
          directory,
        ],
      ]),
    );

Future<CallToolResult> _init(ToolContext ctx, CallToolRequest request) =>
    ctx.authed('setting up the project', (api) async {
      // The config records the organization by slug.
      final organizationId = request.optInt('organizationId');
      final organization = organizationId == null
          ? null
          : (await DiscoveryApi(api).listOrganizations()).firstWhere(
              (organization) => organization.organizationId == organizationId,
              orElse: () => throw TargetSelectionException(
                'No organization found for organizationId: $organizationId.',
              ),
            );
      return cliResult(
        ctx,
        initArguments(request, organizationSlug: organization?.slug),
      );
    });

/// The `restage init` arguments for a `restage_init` [request].
List<String> initArguments(
  CallToolRequest request, {
  String? organizationSlug,
}) => [
  'init',
  '-C',
  request.str('projectDirectory'),
  '--project',
  request.str('projectSlug'),
  '--app',
  request.str('appSlug'),
  '--env',
  request.str('environmentSlug'),
  if (organizationSlug != null) ...['--organization', organizationSlug],
  if (request.optStr('runtimePlane') case final plane?) ...['--plane', plane],
  if (request.optStr('previewWrapper') case final wrapper?) ...[
    '--preview-wrapper',
    wrapper,
  ],
  if (request.optStr('sdkKey') case final key?) ...['--sdk-key', key],
  if (request.optBool('starter') == false) '--no-starter',
  if (request.optBool('addDependencies') == false) '--no-add-deps',
  if (request.optBool('dryRun') ?? false) '--dry-run',
];

/// The `restage_init` tool's input schema.
@visibleForTesting
ObjectSchema get initToolSchema => _initTool.inputSchema;

Future<CallToolResult> _doctor(ToolContext ctx, CallToolRequest request) =>
    guardErrors(
      'checking the project',
      () => cliResult(ctx, ['doctor', '-C', request.str('projectDirectory')]),
    );
