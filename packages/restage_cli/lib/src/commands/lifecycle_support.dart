import 'dart:io';

import 'package:args/args.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// The environment that gets the extra-strict destructive-op guardrail.
/// Centralized so the production rule lives in exactly one place; a future
/// per-environment `isProduction` flag can replace this convention.
const kProductionEnvironmentSlug = 'production';

/// Resolved (credential, project, app, environment) for a lifecycle command.
class LifecycleContext {
  /// Construct a [LifecycleContext].
  const LifecycleContext({
    required this.credential,
    required this.project,
    required this.app,
    required this.environment,
  });

  /// The authenticated credential to use for API calls.
  final Credential credential;

  /// Project slug.
  final String project;

  /// App slug under [project].
  final String app;

  /// Target environment slug.
  final String environment;
}

/// Register the options every lifecycle command shares.
///
/// [withType] adds `--type` for commands that need a surface-type selector.
/// [withReason] adds `--reason` for commands that record an audit reason.
void addLifecycleOptions(
  ArgParser parser, {
  required bool withType,
  required bool withReason,
}) {
  if (withType) {
    parser.addOption(
      'type',
      help: 'Surface type (required): onboarding, message, survey, paywall.',
    );
  }
  parser
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
}

/// Resolve credential + project/app/env. Prints a precise error and returns
/// null on any gap. Resolves credential, project, app, and environment from
/// flags and the local config file, in that priority order.
Future<LifecycleContext?> loadLifecycleContext({
  required ArgResults? argResults,
  required Interactive interactive,
  required StringSink stderr,
  FileCredentialStore? credentialStore,
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

  return LifecycleContext(
    credential: credential,
    project: project,
    app: app,
    environment: environment,
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
/// On the production environment a `--yes` bypass is refused: the operator
/// must confirm interactively. Other environments honor `--yes`. In
/// non-interactive mode without `--yes` the call fails closed regardless of
/// environment. Returns whether to proceed.
Future<bool> confirmDestructive({
  required Interactive interactive,
  required StringSink stdout,
  required StringSink stderr,
  required String environment,
  required bool yesFlag,
  required String impactLine,
}) async {
  final isProd = environment == kProductionEnvironmentSlug;
  if (isProd && yesFlag) {
    stderr.writeln(
      'Refusing --yes on the production environment. Re-run without --yes and '
      'confirm interactively.',
    );
    return false;
  }
  if (yesFlag) return true; // non-prod explicit skip
  if (!interactive.isInteractive) {
    stderr.writeln(
      'This is a destructive change to `$environment` and needs confirmation. '
      'Run interactively, or pass --yes (non-production only).',
    );
    return false;
  }
  stdout.writeln(impactLine);
  return interactive.confirm('Proceed?');
}

/// Surface types every lifecycle command accepts (matches the publish set).
const _lifecycleSurfaceTypes = <SurfaceType>{
  SurfaceType.onboarding,
  SurfaceType.message,
  SurfaceType.survey,
  SurfaceType.paywall,
};

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
  final valid = _lifecycleSurfaceTypes.map((t) => t.wireName).join(', ');
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
  if (!_lifecycleSurfaceTypes.contains(type)) {
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
