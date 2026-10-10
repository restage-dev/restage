import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

const _reasonRequired =
    'A non-empty reason is required — it is recorded in the surface audit '
    'trail.';

final _reasonProperty = Schema.string(
  description: 'The reason recorded in the audit trail.',
);

/// The audit reason recorded when a caller does not supply one.
const kDefaultMcpPublishReason = 'Published from the MCP server';

/// The surface tools, bound to [ctx].
List<ToolEntry> surfaceTools(ToolContext ctx) => [
  (_listSurfacesTool, (request) => _listSurfaces(ctx, request)),
  (_listPaywallsTool, (request) => _listPaywalls(ctx, request)),
  (_surfaceStatusTool, (request) => _surfaceStatus(ctx, request)),
  (_surfaceHistoryTool, (request) => _surfaceHistory(ctx, request)),
  (_pushSurfaceTool, (request) => _pushSurface(ctx, request)),
  liveGuarded(ctx, (
    _publishSurfaceTool,
    (request) => _publishSurface(ctx, request),
  ), reason: LiveReason.onLive),
  (_rollbackPreflightTool, (request) => _rollbackPreflight(ctx, request)),
  liveGuarded(ctx, (
    _rollbackSurfaceTool,
    (request) => _rollbackSurface(ctx, request),
  ), reason: LiveReason.always),
  liveGuarded(ctx, (
    _killSurfaceTool,
    (request) => _killSurface(ctx, request),
  ), reason: LiveReason.always),
  liveGuarded(ctx, (
    _freezeSurfaceTool,
    (request) => _setLock(ctx, request, locked: true),
  ), reason: LiveReason.always),
  liveGuarded(ctx, (
    _unfreezeSurfaceTool,
    (request) => _setLock(ctx, request, locked: false),
  ), reason: LiveReason.always),
];

final _listSurfacesTool = Tool(
  name: 'restage_list_surfaces',
  description:
      'List the surfaces under a Restage project and app, of one surfaceType '
      "or of every type when it is left out. Returns each surface's type, "
      'slug, name, last-draft timestamp, and the version each environment '
      'target serves, by environment and runtime plane. Archived surfaces are left out unless includeArchived is '
      'true; each carries archivedAt.',
  inputSchema: Schema.object(
    properties: {
      ...appProperties(),
      'appId': Schema.int(description: 'The active numeric App id.'),
      'surfaceType': UntitledSingleSelectEnumSchema(
        description: 'Optional surface type. Omit to list every type.',
        values: surfaceTypeWireNames,
      ),
      'includeArchived': Schema.bool(
        description: 'Include archived surfaces. Defaults to false.',
      ),
    },
    required: appRequired,
  ),
);

final _listPaywallsTool = Tool(
  name: 'restage_list_paywalls',
  description:
      'List the paywalls under a Restage project and app. Returns each '
      "paywall's slug, name, last-draft timestamp, and the version each "
      'environment target serves, by environment and runtime plane.',
  inputSchema: Schema.object(
    properties: appProperties(),
    required: appRequired,
  ),
);

final _surfaceStatusTool = Tool(
  name: 'restage_surface_status',
  description:
      'Show the live lifecycle state of a surface in an environment: the '
      'active version, lock state, delivery shape (blob or flow), and the '
      "pushed version history. Each flow version carries its delivery mode "
      "('typed' or 'general'); a general version's flow structure can be "
      'recomposed over the air within the installed vocabulary.',
  inputSchema: Schema.object(
    properties: surfaceTargetProperties(family: true, read: true),
    required: surfaceReadRequired,
  ),
);

final _surfaceHistoryTool = Tool(
  name: 'restage_surface_history',
  description:
      'List the revisions pushed to one surface family in an environment, '
      'newest first, marking the active one, the same as `restage surface '
      'history`.',
  inputSchema: Schema.object(
    properties: surfaceTargetProperties(family: true, read: true),
    required: surfaceReadRequired,
  ),
);

final _pushSurfaceTool = Tool(
  name: 'restage_push_surface',
  description:
      'Push generated surfaces from a local Flutter project to an '
      'environment, the same as `restage surface push`: by surface id, or '
      'by the .dart file that declares it. A pushed revision is not live '
      'until restage_publish_surface publishes it. Requires an admin role or '
      'a push-scoped key. To target the environment an app is configured '
      "for, pass the app's rs_pk_ key to restage_resolve_api_key and use "
      'the organization, project, app, environment and plane it returns.',
  inputSchema: Schema.object(
    properties: {
      'surface': Schema.string(
        description: 'The surface id, or a .dart file path in the project.',
      ),
      'all': Schema.bool(
        description:
            'Push every surface the .dart file produced instead of choosing '
            'one.',
      ),
      'recordGit': Schema.bool(
        description:
            'Build from committed source and commit a release receipt naming '
            'the commit.',
      ),
      'build': Schema.bool(
        description:
            "Push the app's build to the same environment first, so the "
            'dashboard can display the widgets these surfaces use. A failed '
            'build does not stop the surfaces; retry it alone with '
            'restage_push_build.',
      ),
      'flutterRoot': flutterRootProperty,
      'declareAssets': Schema.bool(
        description:
            'Add the files the push writes into the app, such as the '
            'measurement profile, to flutter.assets in pubspec.yaml, keeping '
            'its comments. `declareAssets: true` in restage_config.yaml does '
            'the same. Otherwise pubspec.yaml is left alone and the output '
            'names the line to add.',
      ),
      ...localProjectProperties(),
      'environmentSlug': Schema.string(
        description:
            'Environment slug (overrides restage_config.yaml '
            '`defaultEnvironment`).',
      ),
      'runtimePlane': runtimePlaneProperty,
    },
    required: ['projectDirectory', 'surface'],
  ),
);

final _publishSurfaceTool = Tool(
  name: 'restage_publish_surface',
  description:
      'Publish one pushed revision of a surface family in an environment, so '
      'it serves, the same as `restage surface publish`. Without revision it '
      'publishes the latest revision pushed there. Requires an admin role. '
      'restage_resolve_api_key names the environment an app key serves.',
  inputSchema: Schema.object(
    properties: {
      ...surfaceTargetProperties(family: true),
      'revision': Schema.int(
        description:
            'The pushed revision to publish. Defaults to the latest one '
            'pushed to the environment.',
      ),
      'reason': Schema.string(
        description:
            'The reason recorded in the audit trail. Required on a live '
            'target; a sandbox publish defaults to a generic reason.',
      ),
      'recordGit': Schema.bool(
        description:
            'Commit a release receipt naming the source the revision was '
            'built from. Needs projectDirectory. Defaults to `recordGit` in '
            'its restage_config.yaml.',
      ),
      'projectDirectory': Schema.string(
        description:
            "The app's Flutter project directory. Its restage_config.yaml "
            'supplies any project, app, environment, organization, or plane '
            'left out, and a release receipt goes into its git working tree.',
      ),
    },
    required: surfaceTargetRequired,
  ),
);

final _rollbackPreflightTool = Tool(
  name: 'restage_rollback_preflight',
  description:
      'Read-only preview of how rolling a surface back to a version is '
      'expected to affect live clients: a classification (compatible / '
      'contractChange / noActiveBaseline) plus any blocking contract '
      'changes. Never mutates anything, and the rollback itself is never '
      'gated on it. Call it before restage_rollback_surface to see the '
      'expected cohort impact. Requires an admin role.',
  inputSchema: Schema.object(
    properties: {
      ...surfaceTargetProperties(family: true),
      'toVersion': Schema.int(
        description: 'The published version the rollback would target.',
      ),
    },
    required: [...surfaceTargetRequired, 'toVersion'],
  ),
);

final _rollbackSurfaceTool = Tool(
  name: 'restage_rollback_surface',
  description:
      'Roll a surface back to a previous published version by re-pointing '
      'its active-version pointer. Requires an admin role and a reason for '
      'the audit trail. Call restage_rollback_preflight first to see the '
      'expected cohort impact. Set freeze to also lock the surface against '
      'future publishes after the re-point.',
  inputSchema: Schema.object(
    properties: {
      ...surfaceTargetProperties(family: true),
      'toVersion': Schema.int(
        description: 'The published version to roll back to.',
      ),
      'reason': _reasonProperty,
      'freeze': Schema.bool(
        description:
            'Also lock the surface against future publishes after '
            'rolling back (default false).',
      ),
    },
    required: [...surfaceTargetRequired, 'toVersion', 'reason'],
  ),
);

final _killSurfaceTool = Tool(
  name: 'restage_kill_surface',
  description:
      'Deactivate a surface in an environment, so the SDK falls back to its '
      'bundled asset, the same as `restage surface kill`. Requires an admin '
      'role and a reason for the audit trail. Set frozen to also lock it '
      'against future publishes.',
  inputSchema: Schema.object(
    properties: {
      ...surfaceTargetProperties(),
      'reason': _reasonProperty,
      'frozen': Schema.bool(
        description:
            'Also lock the surface against future publishes (default '
            'false).',
      ),
    },
    required: [...surfaceTargetRequired, 'reason'],
  ),
);

final _freezeSurfaceTool = Tool(
  name: 'restage_freeze_surface',
  description:
      'Freeze a surface in an environment: no version can be published until '
      'it is unfrozen. Requires an admin role and a reason for the audit '
      'trail.',
  inputSchema: Schema.object(
    properties: {...surfaceTargetProperties(), 'reason': _reasonProperty},
    required: [...surfaceTargetRequired, 'reason'],
  ),
);

final _unfreezeSurfaceTool = Tool(
  name: 'restage_unfreeze_surface',
  description:
      'Unfreeze a surface in an environment so versions can be published '
      'again. Requires an admin role and a reason for the audit trail.',
  inputSchema: Schema.object(
    properties: {...surfaceTargetProperties(), 'reason': _reasonProperty},
    required: [...surfaceTargetRequired, 'reason'],
  ),
);

Future<CallToolResult> _listSurfaces(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('listing surfaces', (api) async {
    final snapshot = await readProgrammaticScope(
      api,
      organizationId: request.optInt('organizationId'),
    );
    if (request.optInt('organizationId') == null &&
        snapshot.organizations.length != 1) {
      throw const TargetSelectionException(
        'Pass organizationId to select an organization.',
      );
    }
    final app = snapshot
        .apps(request.str('projectSlug'))
        .where((app) => app.slug == request.str('appSlug'))
        .firstOrNull;
    final requestedAppId = request.optInt('appId');
    if (app?.appId == null ||
        (requestedAppId != null && app!.appId != requestedAppId)) {
      throw const TargetSelectionException('No app matches those selectors.');
    }
    final type = request.optStr('surfaceType');
    if (type != null) surfaceTypeOf(request);
    final surfaces = [
      for (final surface in snapshot.surfaces(
        appId: app!.appId!,
        surfaceType: type,
        includeArchived: request.optBool('includeArchived') ?? false,
      ))
        surface.toJson(),
    ];
    return jsonResult(<String, Object?>{'surfaces': surfaces});
  });
}

Future<CallToolResult> _listPaywalls(ToolContext ctx, CallToolRequest request) {
  return ctx.authed('listing paywalls', (api) async {
    final snapshot = await readProgrammaticScope(
      api,
      organizationId: request.optInt('organizationId'),
    );
    if (request.optInt('organizationId') == null &&
        snapshot.organizations.length != 1) {
      throw const TargetSelectionException(
        'Pass organizationId to select an organization.',
      );
    }
    final app = snapshot
        .apps(request.str('projectSlug'))
        .where((app) => app.slug == request.str('appSlug'))
        .firstOrNull;
    if (app?.appId == null) {
      throw const TargetSelectionException('No app matches those selectors.');
    }
    final summaries = snapshot.surfaces(
      appId: app!.appId!,
      surfaceType: Surface.paywall.wireName,
    );
    return jsonResult(<String, Object?>{
      'paywalls': [for (final summary in summaries) summary.toJson()],
    });
  });
}

Future<CallToolResult> _surfaceStatus(
  ToolContext ctx,
  CallToolRequest request,
) => ctx.authed('reading the surface status', (api) async {
  final identity = await readIdentityOf(api, request);
  final target = targetSelector(request);
  final status = await SurfaceApi(api).surfaceStatus(
    project: target.project,
    app: target.app,
    surfaceType: identity.surface,
    surfaceSlug: identity.slug,
    environment: target.environment,
    environmentTargetId: target.environmentTargetId,
    runtimePlane: target.runtimePlane,
    organizationId: target.organizationId,
    contractVersion: identity.contractVersion,
    sourceKind: identity.sourceKind,
  );
  return jsonResult(status.toJson());
});

Future<CallToolResult> _surfaceHistory(
  ToolContext ctx,
  CallToolRequest request,
) => ctx.authed('reading the surface history', (api) async {
  final history = await familyHistory(
    api: SurfaceApi(api),
    identity: await readIdentityOf(api, request),
    at: familyOf(targetSelector(request)),
  );
  return jsonResult(history.toJson());
});

Future<CallToolResult> _pushSurface(ToolContext ctx, CallToolRequest request) =>
    ctx.authed('pushing the surface', (api) async {
      return cliResult(ctx, [
        'surface',
        'push',
        request.str('surface'),
        ...cliTargetArgs(request),
        if (request.optBool('all') ?? false) '--all',
        if (request.optBool('build') ?? false) '--build',
        ...cliFlutterRootArgs(request),
        if (request.optBool('declareAssets') ?? false) '--declare-assets',
        if (request.optBool('recordGit') case final recordGit?)
          recordGit ? '--record-git' : '--no-record-git',
      ]);
    });

Future<CallToolResult> _publishSurface(
  ToolContext ctx,
  CallToolRequest request,
) async {
  final explicitRevision = request.optInt('revision');
  if (explicitRevision != null && explicitRevision < 1) {
    return mcpError('Expected a positive integer for the revision to publish.');
  }
  final reasonArgument = request.optStr('reason')?.trim();
  final reason = reasonArgument == null || reasonArgument.isEmpty
      ? kDefaultMcpPublishReason
      : reasonArgument;

  // The repository is checked before anything reaches the server, so a
  // publication is never made with no way to record it.
  final directory = request.optStr('projectDirectory');
  final recordGit =
      request.optBool('recordGit') ??
      (directory == null
          ? false
          : (await loadRestageConfig(
                  from: Directory(directory),
                ))?.config.recordGit ??
                false);
  ReleaseRecorder? recorder;
  if (recordGit) {
    if (directory == null) {
      return mcpError(
        'recordGit needs projectDirectory, the git working tree.',
      );
    }
    try {
      recorder = await ReleaseRecorder.open(projectRoot: Directory(directory));
    } on ReleaseRecorderException catch (error) {
      return mcpError(error.message);
    }
  }

  return ctx.authed('publishing the surface', (api) async {
    final output = StringBuffer();
    final (:publication, :recorded) = await publishSurface(
      api: SurfaceApi(api),
      identity: lifecycleIdentityOf(request),
      at: familyOf(targetSelector(request)),
      revision: explicitRevision,
      reason: reason,
      record: recorder == null
          ? null
          : (recorder: recorder, target: await resolveToolTarget(api, request)),
      stdout: output,
      stderr: output,
    );
    return jsonResult(<String, Object?>{
      'publishedRevision': publication.revision,
      'latestPushed': publication.latest,
      'result': publication.result.toJson(),
      'showInApp': mountGuide(
        publication.result.sourceKind == null
            ? publication.family.sourceKind
            : SurfaceSourceKind.fromWireName(publication.result.sourceKind!),
        publication.family.slug,
        mountName: publication.result.mountName,
      ),
      if (recorded != null)
        'receipt': {'recorded': recorded, 'output': output.toString().trim()},
    });
  });
}

Future<CallToolResult> _rollbackPreflight(
  ToolContext ctx,
  CallToolRequest request,
) => ctx.authed('previewing the rollback', (api) async {
  final identity = lifecycleIdentityOf(request);
  final target = targetSelector(request);
  final preflight = await SurfaceApi(api).rollbackPreflight(
    project: target.project,
    app: target.app,
    surfaceType: identity.surface,
    surfaceSlug: identity.slug,
    environment: target.environment,
    toVersion: request.reqInt('toVersion'),
    environmentTargetId: target.environmentTargetId,
    runtimePlane: target.runtimePlane,
    organizationId: target.organizationId,
    contractVersion: identity.contractVersion,
    sourceKind: identity.sourceKind,
  );
  return jsonResult(preflight.toJson());
});

/// The trimmed reason a mutation records, or null when it is blank.
String? _reasonOf(CallToolRequest request) {
  final reason = (request.optStr('reason') ?? '').trim();
  return reason.isEmpty ? null : reason;
}

Future<CallToolResult> _rollbackSurface(
  ToolContext ctx,
  CallToolRequest request,
) async {
  final reason = _reasonOf(request);
  if (reason == null) return mcpError(_reasonRequired);
  return ctx.authed('rolling back the surface', (api) async {
    final identity = lifecycleIdentityOf(request);
    final target = targetSelector(request);
    final toVersion = request.reqInt('toVersion');
    final freeze = request.optBool('freeze') ?? false;
    final result = await SurfaceApi(api).rollback(
      project: target.project,
      app: target.app,
      surfaceType: identity.surface,
      surfaceSlug: identity.slug,
      environment: target.environment,
      toVersion: toVersion,
      lockAfter: freeze,
      reason: reason,
      environmentTargetId: target.environmentTargetId,
      runtimePlane: target.runtimePlane,
      organizationId: target.organizationId,
      contractVersion: identity.contractVersion,
      sourceKind: identity.sourceKind,
    );
    return jsonResult(<String, Object?>{
      'rolledBackTo': toVersion,
      'frozen': freeze,
      'result': ?result?.toJson(),
    });
  });
}

Future<CallToolResult> _killSurface(
  ToolContext ctx,
  CallToolRequest request,
) async {
  final reason = _reasonOf(request);
  if (reason == null) return mcpError(_reasonRequired);
  return ctx.authed('killing the surface', (api) async {
    final target = targetSelector(request);
    final frozen = request.optBool('frozen') ?? false;
    final result = await SurfaceApi(api).kill(
      project: target.project,
      app: target.app,
      surfaceType: surfaceTypeOf(request),
      surfaceSlug: request.str('surfaceSlug'),
      environment: target.environment,
      frozen: frozen,
      reason: reason,
      environmentTargetId: target.environmentTargetId,
      runtimePlane: target.runtimePlane,
      organizationId: target.organizationId,
    );
    return jsonResult(<String, Object?>{
      'killed': true,
      'frozen': frozen,
      'result': ?result?.toJson(),
    });
  });
}

Future<CallToolResult> _setLock(
  ToolContext ctx,
  CallToolRequest request, {
  required bool locked,
}) async {
  final reason = _reasonOf(request);
  if (reason == null) return mcpError(_reasonRequired);
  return ctx.authed(
    locked ? 'freezing the surface' : 'unfreezing the surface',
    (api) async {
      final target = targetSelector(request);
      final result = await SurfaceApi(api).setLock(
        project: target.project,
        app: target.app,
        surfaceType: surfaceTypeOf(request),
        surfaceSlug: request.str('surfaceSlug'),
        environment: target.environment,
        locked: locked,
        reason: reason,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
      );
      return jsonResult(<String, Object?>{
        'frozen': locked,
        'result': ?result?.toJson(),
      });
    },
  );
}
