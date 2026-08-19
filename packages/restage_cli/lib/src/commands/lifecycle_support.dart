import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// The stable line prefix of the rollback cohort-impact note. Shared between
/// the rollback command (which writes the note) and consumers that pick it
/// out of command output (the interactive console), so a rewording cannot
/// silently blank a consumer's display.
const kCohortImpactNotePrefix = 'Cohort impact';

/// Resolved (credential, project, app, environment) for a lifecycle command.
class LifecycleContext {
  /// Construct a [LifecycleContext].
  const LifecycleContext({
    required this.credential,
    required this.apiEndpoint,
    required this.project,
    required this.app,
    required this.environment,
    required this.organizationId,
    required this.environmentTargetId,
    required this.runtimePlane,
  });

  /// The authenticated credential to use for API calls.
  final Credential credential;

  /// Backend endpoint that may receive [credential].
  final Uri apiEndpoint;

  /// Project slug.
  final String project;

  /// App slug under [project].
  final String app;

  /// Target environment slug.
  final String environment;

  /// Authorized backend organization id.
  final int organizationId;

  /// Exact numeric environment target id.
  final int environmentTargetId;

  /// Canonical runtime plane for the selected target.
  final RuntimePlane runtimePlane;
}

/// Register the options every lifecycle command shares.
///
/// [withType] adds `--type` for commands that need a surface-type selector.
/// [withReason] adds `--reason` for commands that record an audit reason.
/// [withSourceKind] adds the typed source-kind selector used by exact family
/// lifecycle commands. It is intentionally separate from the surface category.
void addLifecycleOptions(
  ArgParser parser, {
  required bool withType,
  required bool withReason,
  bool withContractVersion = false,
  bool withSourceKind = false,
}) {
  if (withType) {
    parser.addOption(
      'type',
      help:
          'Deprecated validation/disambiguation selector only; omit it when '
          'using a generated manifest, which is authoritative. Values: '
          'onboarding, message, survey, paywall, general.',
    );
  }
  if (withSourceKind) {
    parser.addOption(
      'source-kind',
      help:
          'Authored source kind for an explicit family selector: screen, '
          'flowGraph, or paywall. `screen` requires --contract-version; '
          'specialized `paywall` is non-versioned.',
    );
  }
  if (withContractVersion) {
    parser.addOption(
      'contract-version',
      help:
          'Positive standalone-screen contract version. Omit for the '
          'non-versioned flow/paywall lineage.',
    );
  }
  parser
    ..addOption(
      'organization',
      help: 'Organization slug (overrides restage_config.yaml).',
    )
    ..addOption(
      'project',
      help: 'Project slug (overrides restage_config.yaml).',
    )
    ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
    ..addOption(
      'env',
      help:
          'Environment slug (overrides restage_config.yaml '
          '`defaultEnvironment`).',
    )
    ..addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Directory to start the restage_config.yaml search from.',
    );
  if (withReason) {
    parser.addOption(
      'reason',
      help: 'Audit reason for this change (required).',
    );
  }
  addRuntimePlaneOption(parser);
}

/// Resolve credential + project/app/env. Prints a precise error and returns
/// null on any gap. Resolves credential, project, app, and environment from
/// flags and the local config file, in that priority order.
Future<LifecycleContext?> loadLifecycleContext({
  required ArgResults? argResults,
  required Interactive interactive,
  required StringSink stderr,
  FileCredentialStore? credentialStore,
  http.Client? httpClient,
}) async {
  final store = credentialStore ?? FileCredentialStore.atDefaultLocation();
  final credential = await store.read();
  if (credential == null) {
    stderr.writeln('Not signed in. Run `restage login`.');
    return null;
  }

  final loaded = await loadRestageConfig(
    from: Directory(argResults?['directory'] as String? ?? '.'),
  );
  final Uri apiEndpoint;
  try {
    apiEndpoint = resolveApiEndpoint(
      config: loaded?.config,
      credential: credential,
    );
  } on EndpointConfigurationException catch (e) {
    stderr.writeln(e.toString());
    return null;
  }

  final project = (argResults?['project'] as String?) ?? loaded?.config.project;
  final app = (argResults?['app'] as String?) ?? loaded?.config.app;
  if (project == null || app == null) {
    stderr.writeln(
      'No project / app context. Run `restage init` or pass '
      '--project <slug> --app <slug>.',
    );
    return null;
  }

  final fromFlag = argResults?['env'] as String?;
  final environment = (fromFlag != null && fromFlag.isNotEmpty)
      ? fromFlag
      : (loaded?.config.defaultEnvironment?.isNotEmpty ?? false)
      ? loaded!.config.defaultEnvironment!
      : interactive.isInteractive
      ? await interactive.prompt('Environment slug?')
      : null;

  if (environment == null || environment.isEmpty) {
    stderr.writeln(
      'Required: --env <slug>. Set `defaultEnvironment` in '
      'restage_config.yaml or pass --env.',
    );
    return null;
  }

  final RestageApi api;
  try {
    api = RestageApi(
      endpoint: apiEndpoint,
      httpClient: httpClient,
      credential: credential,
    );
  } on InsecureEndpointException catch (e) {
    stderr.writeln(e.toString());
    return null;
  }
  final ResolvedEnvironmentTargetContext? resolvedTarget;
  try {
    resolvedTarget = await resolveEnvironmentTargetContext(
      api: api,
      interactive: interactive,
      stderr: stderr,
      projectSlug: project,
      appSlug: app,
      environmentSlug: environment,
      preferredOrganizationSlug:
          (argResults?['organization'] as String?) ??
          loaded?.config.organization,
      runtimePlane: runtimePlaneFromArgs(argResults),
    );
  } finally {
    if (httpClient == null) api.close();
  }
  if (resolvedTarget == null) return null;

  return LifecycleContext(
    credential: credential,
    apiEndpoint: apiEndpoint,
    project: project,
    app: app,
    environment: environment,
    organizationId: resolvedTarget.organizationId,
    environmentTargetId: resolvedTarget.target.environmentTargetId,
    runtimePlane: resolvedTarget.target.runtimePlane,
  );
}

/// Return a non-empty audit reason, or null after printing a required-flag
/// error. Prompts when interactive and `--reason` was omitted.
Future<String?> requireReason({
  required ArgResults? argResults,
  required Interactive interactive,
  required StringSink stderr,
}) async {
  final flag = (argResults?['reason'] as String?)?.trim();
  if (flag != null && flag.isNotEmpty) return flag;
  if (interactive.isInteractive) {
    final entered = (await interactive.prompt(
      'Reason for this change?',
    )).trim();
    if (entered.isNotEmpty) return entered;
  }
  stderr.writeln('Required: --reason "<why>".');
  return null;
}

/// The extra-strict destructive-op guardrail.
///
/// On the live runtime plane a `--yes` bypass is refused: the operator must
/// confirm interactively. Sandbox targets honor `--yes`, including targets
/// whose environment slug happens to be `production`. In non-interactive mode
/// without `--yes` the call fails closed regardless of plane. Returns whether
/// to proceed.
Future<bool> confirmDestructive({
  required Interactive interactive,
  required StringSink stdout,
  required StringSink stderr,
  required String environment,
  required RuntimePlane runtimePlane,
  required bool yesFlag,
  required String impactLine,
}) async {
  final isLive = runtimePlane == RuntimePlane.live;
  if (isLive && yesFlag) {
    stderr.writeln(
      'Refusing --yes on the live runtime plane. Re-run without --yes and '
      'confirm interactively.',
    );
    return false;
  }
  if (yesFlag) return true; // sandbox explicit skip
  if (!interactive.isInteractive) {
    stderr.writeln(
      'This is a destructive change to `$environment` and needs confirmation. '
      'Run interactively, or pass --yes (sandbox only).',
    );
    return false;
  }
  stdout.writeln(impactLine);
  return interactive.confirm('Proceed?');
}

/// Exactly-one positional `<slug>`, or null after a precise error.
String? resolveSingleSlug({
  required ArgResults? argResults,
  required StringSink stderr,
}) {
  final rest = argResults?.rest ?? const <String>[];
  if (rest.isEmpty) {
    stderr.writeln('Missing positional argument: <slug>.');
    return null;
  }
  if (rest.length > 1) {
    stderr.writeln(
      'Too many positional arguments. Expected exactly one <slug>.',
    );
    return null;
  }
  return rest.first;
}

/// Returns [fixedType] when set (paywall convenience); otherwise parses
/// `--type` against the accepted set. Null after a crisp error.
SurfaceType? resolveSurfaceTypeArg({
  required ArgResults? argResults,
  required SurfaceType? fixedType,
  required StringSink stderr,
}) {
  if (fixedType != null) return fixedType;
  final raw = argResults?['type'] as String?;
  final valid = kLifecycleSurfaceTypes.map((t) => t.wireName).join(', ');
  if (raw == null || raw.isEmpty) {
    stderr.writeln('Required: --type <$valid>.');
    return null;
  }
  final SurfaceType type;
  try {
    type = SurfaceType.fromWireName(raw);
  } on FormatException {
    stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
    return null;
  }
  if (!kLifecycleSurfaceTypes.contains(type)) {
    stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
    return null;
  }
  return type;
}

/// Return a customer-facing error message for a typed [SurfaceException].
///
/// Use this instead of [SurfaceException.toString] in command error paths so
/// users see legible messages rather than internal debug representations.
String renderSurfaceException(SurfaceException e) => switch (e) {
  SurfaceNotFound(:final surfaceSlug) => "Surface '$surfaceSlug' not found.",
  SurfaceEnvironmentNotFound(:final environmentSlug) =>
    "Environment '$environmentSlug' not found.",
  SurfacePublishConflict(:final surfaceSlug, :final environmentSlug) =>
    "Concurrent publish conflict for '$surfaceSlug' in '$environmentSlug'. "
        'Retry the operation.',
  SurfaceRollbackUnsupported(:final surfaceSlug) =>
    "Rollback is not supported for '$surfaceSlug'.",
  SurfaceVersionNotFound(:final surfaceSlug, :final toVersion) =>
    "Version v$toVersion not found for '$surfaceSlug'.",
};

/// Print the complete family effect returned by an identity-wide mutation.
///
/// Identity-wide controls deliberately do not narrow this output to the
/// family selected by a manifest entry. The server response is the authority
/// for the affected set.
void writeAffectedFamilyMutation(
  StringSink stdout,
  SurfaceIdentityMutationResult result,
) {
  final type = result.surfaceType.isEmpty ? 'surface' : result.surfaceType;
  final environment = result.environmentSlug.isEmpty
      ? ''
      : ' in ${result.environmentSlug}';
  stdout.writeln(
    'Identity: $type "${result.surfaceSlug}"$environment  '
    'frozen: ${result.frozen}',
  );
  stdout.writeln('Affected families:');
  if (result.affectedFamilies.isEmpty) {
    stdout.writeln('  none');
    return;
  }
  for (final family in result.affectedFamilies) {
    stdout.writeln(
      '  ${family.familyAddress}: '
      '${_revisionLabel(family.activeRevisionBefore)} -> '
      '${_revisionLabel(family.activeRevisionAfter)}'
      '${family.publishedRevision == null ? '' : '  '
                'published r${family.publishedRevision}'}',
    );
  }
}

String _revisionLabel(int? revision) =>
    revision == null ? 'inactive' : 'r$revision';
