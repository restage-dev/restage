import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'auth.dart';

/// Runs the `restage` CLI in process with [args].
typedef CliRunner =
    Future<int> Function(
      List<String> args, {
      required StringSink stdout,
      required StringSink stderr,
    });

/// A tool handler bound to the shared credential, client and CLI runner.
typedef ToolHandler = Future<CallToolResult> Function(CallToolRequest request);

/// One tool and its handler.
typedef ToolEntry = (Tool, ToolHandler);

/// What every tool handler shares for the server's lifetime.
class ToolContext {
  /// Construct a context.
  ToolContext({
    required this.store,
    required this.httpClient,
    required CliRunner runCli,
  }) : _runCli = runCli;

  /// The shared credential store.
  final FileCredentialStore store;

  /// The server's HTTP client.
  final http.Client httpClient;

  final CliRunner _runCli;

  /// Run [body] against the backend the stored credential names, mapping
  /// every failure to a clean result.
  Future<CallToolResult> authed(
    String action,
    Future<CallToolResult> Function(RestageApi api) body,
  ) => guardErrors(action, () async => body(await api()));

  /// The backend the stored credential names.
  Future<RestageApi> api() async {
    final credential = await store.read();
    if (credential == null) throw const NotSignedInException();
    return RestageApi(
      endpoint: Uri.parse(credential.endpoint),
      credential: credential,
      httpClient: httpClient,
    );
  }
}

/// Run the CLI with [args] and report its output: a result on exit 0, an
/// error carrying the output otherwise.
Future<CallToolResult> cliResult(ToolContext ctx, List<String> args) async {
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final exitCode = await ctx._runCli(args, stdout: stdout, stderr: stderr);
  final output = [
    stdout.toString().trim(),
    stderr.toString().trim(),
  ].where((text) => text.isNotEmpty).join('\n');
  if (exitCode != 0) return mcpError(output);
  return jsonResult(<String, Object?>{'exitCode': exitCode, 'output': output});
}

/// Surface types as wire names.
final surfaceTypeWireNames = [for (final type in Surface.values) type.wireName];

/// The `surfaceType` property.
final surfaceTypeProperty = UntitledSingleSelectEnumSchema(
  description:
      'The surface type: one of '
      '${surfaceTypeWireNames.map((n) => '"$n"').join(', ')}.',
  values: surfaceTypeWireNames,
);

/// The optional `surfaceType` property of a read, looked up by slug when left
/// out.
final surfaceReadTypeProperty = UntitledSingleSelectEnumSchema(
  description:
      'Optional surface type: one of '
      '${surfaceTypeWireNames.map((n) => '"$n"').join(', ')}. Omit to look '
      'it up by slug.',
  values: surfaceTypeWireNames,
);

/// The `surfaceSlug` property.
final surfaceSlugProperty = Schema.string(description: 'The surface slug.');

/// The optional `organizationId` property.
final organizationIdProperty = Schema.int(
  description:
      'Optional organization id (from restage_list_organizations). Required '
      'when you belong to more than one organization.',
);

/// The optional `environmentTargetId` property.
final environmentTargetIdProperty = Schema.int(
  description:
      'Optional exact environment target id, from '
      'restage_list_environment_targets.',
);

/// Runtime planes as wire names.
final runtimePlaneWireNames = [
  for (final plane in RuntimePlane.values) plane.wireName,
];

/// The optional `runtimePlane` property.
final runtimePlaneProperty = UntitledSingleSelectEnumSchema(
  description:
      'Runtime plane: sandbox or live. Required when the environment exists '
      'on both planes.',
  values: runtimePlaneWireNames,
);

/// The optional `sourceKind` property of an exact family selector.
final sourceKindProperty = UntitledSingleSelectEnumSchema(
  description:
      'Optional authored source kind: screen, flowGraph, or paywall. Omit to '
      'let the server resolve the current family.',
  values: [for (final kind in kLifecycleSourceKinds) kind.wireName],
);

/// The optional `contractVersion` property of an exact family selector.
final contractVersionProperty = Schema.int(
  description:
      'Optional positive standalone-screen contract version. Omit for the '
      'non-versioned flow or paywall lineage.',
);

/// The properties that name one app.
Map<String, Schema> appProperties() => {
  'projectDirectory': projectDirectoryProperty,
  'projectSlug': Schema.string(description: 'The project slug.'),
  'appSlug': Schema.string(description: 'The app slug.'),
  'organizationId': organizationIdProperty,
};

/// The required keys of [appProperties].
const appRequired = ['projectSlug', 'appSlug'];

/// The properties of a tool that runs in a local project.
Map<String, Schema> localProjectProperties() => {
  'projectDirectory': projectDirectoryProperty,
  'projectSlug': Schema.string(
    description: 'Project slug (overrides restage_config.yaml).',
  ),
  'appSlug': Schema.string(
    description: 'App slug (overrides restage_config.yaml).',
  ),
  'organizationId': organizationIdProperty,
};

/// The properties that name one environment target of one app.
Map<String, Schema> targetProperties() => {
  ...appProperties(),
  'environmentSlug': Schema.string(
    description: 'The environment slug (e.g. production).',
  ),
  'runtimePlane': runtimePlaneProperty,
  'environmentTargetId': environmentTargetIdProperty,
};

/// The required keys of [targetProperties].
const targetRequired = [...appRequired, 'environmentSlug'];

/// The properties that name one surface at one environment target.
Map<String, Schema> surfaceTargetProperties({
  bool family = false,
  bool read = false,
}) => {
  ...targetProperties(),
  'surfaceType': read ? surfaceReadTypeProperty : surfaceTypeProperty,
  'surfaceSlug': surfaceSlugProperty,
  if (family) 'sourceKind': sourceKindProperty,
  if (family) 'contractVersion': contractVersionProperty,
};

/// The required keys of [surfaceTargetProperties].
const surfaceTargetRequired = [
  ...appRequired,
  'surfaceType',
  'surfaceSlug',
  'environmentSlug',
];

/// The required keys of a read's [surfaceTargetProperties].
const surfaceReadRequired = [...appRequired, 'surfaceSlug', 'environmentSlug'];

/// The runtime plane the call names, if any.
RuntimePlane? runtimePlaneOf(CallToolRequest request) {
  final value = request.optStr('runtimePlane');
  return value == null ? null : RuntimePlane.fromWireName(value);
}

/// The surface type the call names. Throws [TargetSelectionException] for an
/// unknown one.
Surface surfaceTypeOf(CallToolRequest request) {
  final raw = request.str('surfaceType');
  try {
    return Surface.fromWireName(raw);
  } on FormatException {
    throw TargetSelectionException(
      'Unknown surfaceType "$raw". Valid values: '
      '${surfaceTypeWireNames.join(', ')}.',
    );
  }
}

/// The lifecycle identity the call names: its surface, plus the optional
/// exact family selectors.
SurfaceLifecycleIdentity lifecycleIdentityOf(CallToolRequest request) {
  final (:sourceKind, :contractVersion) = _familySelectorsOf(request);
  return explicitLifecycleIdentity(
    type: surfaceTypeOf(request),
    slug: request.str('surfaceSlug'),
    sourceKind: sourceKind,
    contractVersion: contractVersion,
  );
}

/// The lifecycle identity a read names, looking its type up by slug when the
/// call leaves `surfaceType` out.
Future<SurfaceLifecycleIdentity> readIdentityOf(
  RestageApi api,
  CallToolRequest request,
) async {
  if (request.optStr('surfaceType') != null) {
    return lifecycleIdentityOf(request);
  }
  final (:sourceKind, :contractVersion) = _familySelectorsOf(request);
  return lookUpLifecycleIdentity(
    api: api,
    project: request.str('projectSlug'),
    app: request.str('appSlug'),
    slug: request.str('surfaceSlug'),
    organizationId: request.optInt('organizationId'),
    appId: request.optInt('appId'),
    sourceKind: sourceKind,
    contractVersion: contractVersion,
    syntax: SelectorSyntax.mcp,
  );
}

({SurfaceSourceKind? sourceKind, int? contractVersion}) _familySelectorsOf(
  CallToolRequest request,
) {
  final rawKind = request.optStr('sourceKind');
  final SurfaceSourceKind? sourceKind;
  try {
    sourceKind = rawKind == null
        ? null
        : SurfaceSourceKind.fromWireName(rawKind);
  } on FormatException {
    throw TargetSelectionException('Unknown sourceKind "$rawKind".');
  }
  final contractVersion = request.optInt('contractVersion');
  if (contractVersion != null && contractVersion < 1) {
    throw const TargetSelectionException(
      'contractVersion must be a positive integer.',
    );
  }
  return (sourceKind: sourceKind, contractVersion: contractVersion);
}

/// The target one call names, with its selectors as given; the server
/// resolves them.
typedef ToolTarget = ({
  String project,
  String app,
  String environment,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  int? organizationId,
});

/// [target] as a surface family target.
FamilyTarget familyOf(ToolTarget target) => (
  project: target.project,
  app: target.app,
  environment: target.environment,
  environmentTargetId: target.environmentTargetId,
  runtimePlane: target.runtimePlane,
  organizationId: target.organizationId,
);

/// The target selectors [request] names.
ToolTarget targetSelector(CallToolRequest request) => (
  project: request.str('projectSlug'),
  app: request.str('appSlug'),
  environment: request.str('environmentSlug'),
  environmentTargetId: request.optInt('environmentTargetId'),
  runtimePlane: runtimePlaneOf(request),
  organizationId: request.optInt('organizationId'),
);

/// The exact target [request]'s selectors resolve to on the server.
Future<ResolvedEnvironmentTargetContext> resolveToolTarget(
  RestageApi api,
  CallToolRequest request,
) {
  final target = targetSelector(request);
  return resolveTargetSelection(
    api: api,
    projectSlug: target.project,
    appSlug: target.app,
    environmentSlug: target.environment,
    runtimePlane: target.runtimePlane,
    environmentTargetId: target.environmentTargetId,
    organizationId: target.organizationId,
  );
}

/// The properties that declare one exact target.
Map<String, Schema> exactTargetProperties() => {
  'organizationId': Schema.int(description: 'The organization id.'),
  'projectSlug': Schema.string(description: 'The project slug.'),
  'appSlug': Schema.string(description: 'The app slug.'),
  'environmentSlug': Schema.string(description: 'The environment slug.'),
  'environmentTargetId': Schema.int(
    description: 'The exact environment target id.',
  ),
  'runtimePlane': UntitledSingleSelectEnumSchema(
    description: 'The target runtime plane: sandbox or live.',
    values: runtimePlaneWireNames,
  ),
};

/// The required keys of [exactTargetProperties].
const exactTargetRequired = [
  'organizationId',
  'projectSlug',
  'appSlug',
  'environmentSlug',
  'environmentTargetId',
  'runtimePlane',
];

/// The refusal for a declared target that names no single authorized one.
const exactTargetError =
    'The declared target does not resolve to one exact authorized target.';

/// The exact measurement coordinate the call's declared target names, or
/// null when it names no single authorized target.
Future<measurement.TargetCoordinate?> exactTargetCoordinate(
  RestageApi api,
  CallToolRequest request,
) async {
  final ResolvedEnvironmentTargetContext resolved;
  try {
    resolved = await resolveToolTarget(api, request);
  } on RestageApiException catch (error) {
    if (decodeGenericTypedException(error.body) is TargetSelectionRefused) {
      return null;
    }
    rethrow;
  }
  return measurement.TargetCoordinate(
    organizationId: measurement.OrganizationId(resolved.organizationId),
    appId: measurement.ApplicationId(resolved.appId),
    environmentTargetId: measurement.EnvironmentTargetId(
      resolved.target.environmentTargetId,
    ),
    namedEnvironmentId: measurement.NamedEnvironmentId(
      resolved.target.namedEnvironmentId,
    ),
    runtimePlane: switch (resolved.target.runtimePlane) {
      RuntimePlane.live => measurement.RuntimePlane.live,
      RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
    },
  );
}

/// The `projectDirectory` property of a tool that runs in a local project.
final projectDirectoryProperty = Schema.string(
  description:
      "The app's Flutter project directory; restage_config.yaml there "
      'supplies any project, app, environment, organization, or plane left '
      'out.',
);

/// The CLI flags naming the project and app a local-project call addresses.
/// restage_config.yaml in `projectDirectory` supplies anything left out.
List<String> cliProjectArgs(CallToolRequest request) => [
  '-C',
  request.str('projectDirectory'),
  if (request.optInt('organizationId') case final organizationId?) ...[
    '--organization-id',
    '$organizationId',
  ],
  if (request.optStr('projectSlug') case final project?) ...[
    '--project',
    project,
  ],
  if (request.optStr('appSlug') case final app?) ...['--app', app],
];

/// The `flutterRoot` property of a tool that builds.
final flutterRootProperty = Schema.string(
  description:
      'Absolute path of the Flutter SDK directory to build with, instead of '
      'the one found from the project. Overrides `flutterRoot` in '
      'restage_config.yaml.',
);

/// The CLI flag for a `flutterRoot` argument, when one is given.
List<String> cliFlutterRootArgs(CallToolRequest request) => [
  if (request.optStr('flutterRoot') case final root?) ...[
    '--flutter-root',
    root,
  ],
];

/// The CLI flags naming the environment target a local-project call
/// addresses, as given; the CLI fills the rest from restage_config.yaml and
/// the server resolves them.
List<String> cliTargetArgs(CallToolRequest request) => [
  ...cliProjectArgs(request),
  if (request.optStr('environmentSlug') case final environment?) ...[
    '--env',
    environment,
  ],
  if (request.optStr('runtimePlane') case final plane?) ...['--plane', plane],
];

/// Target selectors restage_config.yaml can supply.
const _configSelectors = ['projectSlug', 'appSlug', 'environmentSlug'];

/// Lets a tool that names a project read missing selectors from the
/// restage_config.yaml in `projectDirectory`.
///
/// Applies to tools that take an optional `projectDirectory`; tools that
/// require one run the CLI there, which reads the config itself.
ToolEntry withProjectConfig(ToolContext ctx, ToolEntry entry) {
  final (tool, handler) = entry;
  final schema = tool.inputSchema;
  final properties = schema.properties ?? const <String, Schema>{};
  final required = schema.required ?? const <String>[];
  if (!properties.containsKey('projectDirectory') ||
      !properties.containsKey('projectSlug') ||
      required.contains('projectDirectory')) {
    return entry;
  }
  final fillable = [
    for (final key in _configSelectors)
      if (required.contains(key)) key,
  ];
  final adapted = _withSchema(
    tool,
    required: [
      for (final key in required)
        if (!fillable.contains(key)) key,
    ],
  );
  return (
    adapted,
    (request) => guardErrors('reading restage_config.yaml', () async {
      final CallToolRequest filled;
      try {
        filled = await _fillFromProjectConfig(
          ctx,
          request,
          properties.keys.toSet(),
        );
      } on RestageConfigFormatException catch (error) {
        return mcpError(error.message);
      }
      for (final key in fillable) {
        if (filled.optStr(key) == null) {
          return mcpError(
            'Missing $key: pass it, or pass projectDirectory with a '
            'restage_config.yaml that sets it.',
          );
        }
      }
      return handler(filled);
    }),
  );
}

Future<CallToolRequest> _fillFromProjectConfig(
  ToolContext ctx,
  CallToolRequest request,
  Set<String> accepted,
) async {
  final directory = request.optStr('projectDirectory');
  if (directory == null) return request;
  final loaded = await loadRestageConfig(from: Directory(directory));
  if (loaded == null) {
    throw TargetSelectionException(
      'No restage_config.yaml found in $directory or above it.',
    );
  }
  final config = loaded.config;
  final args = <String, Object?>{...?request.arguments};
  void fill(String key, Object? value) {
    if (value != null && accepted.contains(key) && args[key] == null) {
      args[key] = value;
    }
  }

  fill('projectSlug', config.project);
  fill('appSlug', config.app);
  if (args['environmentTargetId'] == null) {
    fill('environmentSlug', config.defaultEnvironment);
    fill('runtimePlane', config.plane?.wireName);
  }
  final organization = config.organization;
  if (organization != null &&
      accepted.contains('organizationId') &&
      args['organizationId'] == null) {
    final organizations = await DiscoveryApi(
      await ctx.api(),
    ).listOrganizations();
    args['organizationId'] = organizations
        .firstWhere(
          (candidate) => candidate.slug == organization,
          orElse: () => throw TargetSelectionException(
            'No organization found for "$organization" from '
            'restage_config.yaml.',
          ),
        )
        .organizationId;
  }
  return CallToolRequest(
    name: request.name,
    arguments: args,
    meta: request.meta,
  );
}

/// [tool] with extra input [properties] and, when given, a new [required]
/// list and a [description] suffix.
Tool _withSchema(
  Tool tool, {
  Map<String, Schema> properties = const {},
  List<String>? required,
  String? describe,
}) {
  final schema = tool.inputSchema;
  final schemaMap = schema as Map<String, Object?>;
  final toolMap = tool as Map<String, Object?>;
  return Tool.fromMap({
    ...toolMap,
    if (describe != null) 'description': '${tool.description ?? ''} $describe',
    'inputSchema': ObjectSchema.fromMap({
      ...schemaMap,
      'properties': {...?schema.properties, ...properties},
      'required': ?required ?? schema.required,
    }),
  });
}

/// When a live-plane change must carry a caller-written reason.
enum LiveReason {
  /// The tool records no reason.
  none,

  /// A reason is required on every plane.
  always,

  /// A reason is required on the live plane; sandbox takes a default.
  onLive,
}

/// The refusal for a live-plane change the user has not approved.
const liveChangeRefusal =
    'This changes what a live target serves. Ask the user to approve the '
    'change, then call again with confirmLive: true.';

const _unprovenPlaneRefusal =
    'Could not confirm the target is on the sandbox plane. Name its '
    'environment, or ask the user to approve a live change and call again '
    'with confirmLive: true.';

const _liveReasonRequired =
    'A live change needs a reason: pass reason, written from what the user '
    'said.';

/// The `confirmLive` property of a tool that changes a live target.
final confirmLiveProperty = Schema.bool(
  description:
      'Set true only after the user approved this change to a live target. '
      'Without it a live target is refused; sandbox targets never need it.',
);

/// Guards a tool that changes what a target serves: on the live plane it
/// runs only with `confirmLive: true`, and with a reason when [reason] asks.
///
/// [changesLive] classifies one call; a call it rejects, such as a read, is
/// never guarded. [planeOf] reads the plane from the call when the tool
/// declares it itself; by default the target's plane is resolved.
ToolEntry liveGuarded(
  ToolContext ctx,
  ToolEntry entry, {
  LiveReason reason = LiveReason.none,
  bool Function(CallToolRequest request)? changesLive,
  FutureOr<RuntimePlane?> Function(CallToolRequest request)? planeOf,
}) {
  final (tool, handler) = entry;
  return (
    _withSchema(
      tool,
      properties: {'confirmLive': confirmLiveProperty},
      describe:
          'On a live target it needs confirmLive: true, set only after the '
          'user approves.',
    ),
    (request) => guardErrors('checking the target plane', () async {
      if (changesLive != null && !changesLive(request)) return handler(request);
      final hasReason = (request.optStr('reason') ?? '').trim().isNotEmpty;
      if (reason == LiveReason.always && !hasReason) {
        return mcpError(_liveReasonRequired);
      }
      final confirmed = request.optBool('confirmLive') ?? false;
      if (confirmed && (reason != LiveReason.onLive || hasReason)) {
        return handler(request);
      }
      final RuntimePlane? plane;
      try {
        plane = planeOf == null
            ? await _planeOf(ctx, request)
            : await planeOf(request);
      } on FormatException {
        // The tool reports its own malformed input.
        return handler(request);
      }
      if (plane == null) return mcpError(_unprovenPlaneRefusal);
      if (plane == RuntimePlane.live) {
        if (!confirmed) return mcpError(liveChangeRefusal);
        return mcpError(_liveReasonRequired);
      }
      return handler(request);
    }),
  );
}

/// The plane [request]'s target is on, or null when it names no one target.
Future<RuntimePlane?> _planeOf(ToolContext ctx, CallToolRequest request) async {
  final explicit = runtimePlaneOf(request);
  final targetId = request.optInt('environmentTargetId');
  if (explicit != null && targetId == null) return explicit;
  final environment = request.optStr('environmentSlug');
  final organizationId = request.optInt('organizationId');
  final discovery = DiscoveryApi(await ctx.api());
  if (environment == null) {
    if (targetId == null || organizationId == null) return null;
    final targets = await discovery.listEnvironmentTargets(
      organizationId: organizationId,
      projectSlug: request.str('projectSlug'),
      appSlug: request.str('appSlug'),
    );
    for (final target in targets) {
      if (target.environmentTargetId == targetId) return target.runtimePlane;
    }
    return null;
  }
  final selection = await discovery.resolveTarget(
    projectSlug: request.str('projectSlug'),
    appSlug: request.str('appSlug'),
    environmentSlug: environment,
    runtimePlane: explicit,
    environmentTargetId: targetId,
    organizationId: organizationId,
  );
  return selection.target?.runtimePlane;
}

/// The plane an exact-target tool declares; the tool checks the declaration
/// against the target before it acts.
RuntimePlane declaredPlane(CallToolRequest request) =>
    RuntimePlane.fromWireName(request.str('runtimePlane'));
