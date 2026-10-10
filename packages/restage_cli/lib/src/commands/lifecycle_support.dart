import 'package:args/args.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/experiment_activation_host_transport.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

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
    required this.organizationSlug,
    required this.appId,
    required this.namedEnvironmentId,
    required this.environmentTargetId,
    required this.runtimePlane,
    this.planeIsImplicit = true,
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

  /// Slug of the organization [organizationId] names.
  final String organizationSlug;

  /// Authorized numeric app identity resolved with the target.
  final int appId;

  /// Stable named-environment identity resolved with the target.
  final int namedEnvironmentId;

  /// Exact numeric environment target id.
  final int environmentTargetId;

  /// Canonical runtime plane for the selected target.
  final RuntimePlane runtimePlane;

  /// Whether a follow-up command reaches this target without `--plane`.
  final bool planeIsImplicit;

  /// This target as a resolved selector.
  ResolvedEnvironmentTargetContext get resolved =>
      ResolvedEnvironmentTargetContext(
        projectSlug: project,
        appSlug: app,
        organizationId: organizationId,
        organizationSlug: organizationSlug,
        appId: appId,
        target: EnvironmentTargetSummary(
          environmentTargetId: environmentTargetId,
          namedEnvironmentId: namedEnvironmentId,
          environmentSlug: environment,
          runtimePlane: runtimePlane,
        ),
        planeIsImplicit: planeIsImplicit,
      );

  /// This target for a surface family operation.
  FamilyTarget get family => familyTargetOf(resolved);
}

/// Converts an exact resolved lifecycle context into an activation route
/// profile without choosing additional selectors.
extension ExperimentActivationLifecycleContext on LifecycleContext {
  /// The profile supplied by a CLI host to its activation transport.
  ExperimentActivationRouteProfile get experimentActivationRouteProfile =>
      ExperimentActivationRouteProfile(
        projectSlug: project,
        appSlug: app,
        environmentSlug: environment,
        environmentTargetId: environmentTargetId,
        runtimePlane: switch (runtimePlane) {
          RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
          RuntimePlane.live => measurement.RuntimePlane.live,
        },
        selectedOrganizationId: organizationId,
        selectedAppId: appId,
      );
}

/// Register the `--type` selector of a surface command.
void addSurfaceTypeOption(ArgParser parser) => parser.addOption(
  'type',
  help:
      'Deprecated validation/disambiguation selector only; omit it when '
      'using a generated manifest, which is authoritative. Values: '
      'onboarding, message, survey, paywall, general.',
);

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
  if (withType) addSurfaceTypeOption(parser);
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
  addScopeOptions(parser, OperationScope.target);
  if (withReason) {
    parser.addOption(
      'reason',
      help: 'Audit reason for this change (required).',
    );
  }
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

/// Exactly-one positional `<id>`, or null after a precise error.
String? resolveSingleSlug({
  required ArgResults? argResults,
  required StringSink stderr,
}) {
  final rest = argResults?.rest ?? const <String>[];
  if (rest.isEmpty) {
    stderr.writeln('Missing positional argument: <id>.');
    return null;
  }
  if (rest.length > 1) {
    stderr.writeln('Too many positional arguments. Expected exactly one <id>.');
    return null;
  }
  final slug = rest.first;
  if (!isValidSurfaceSlug(slug)) {
    stderr.writeln('Refusing the id `$slug`. $surfaceSlugRefusalMessage');
    return null;
  }
  return slug;
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
                'pushed r${family.publishedRevision}'}',
    );
  }
}

String _revisionLabel(int? revision) =>
    revision == null ? 'inactive' : 'r$revision';
