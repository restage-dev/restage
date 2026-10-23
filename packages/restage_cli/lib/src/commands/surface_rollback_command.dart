import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_measurement_review.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';

/// Roll a surface back to a previous version by re-pointing the active-version
/// pointer.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface rollback` group, normally resolved from the
///     generated manifest.
///   - non-null → typed-group compatibility convenience (e.g. `paywall
///     rollback`; no `--type`).
///
/// Works for paywalls AND flow surfaces (onboarding / message / survey /
/// general) — the re-point reaches the selected family's active-arm clients.
/// The target version must exist in the pushed history; the command
/// validates this and previews the cohort impact before confirming.
///
/// Requires a non-empty `--reason` for the audit trail. A destructive-op
/// confirmation step guards the live runtime plane: `--yes` is accepted for
/// sandbox targets; live targets always require interactive confirmation. The
/// `--freeze` flag additionally locks the surface against future publishes
/// after the re-point.
class SurfaceRollbackCommand extends Command<int>
    implements LiveGuardedCommand {
  /// Construct a rollback command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the
  /// `paywall` convenience group); omit it for the generic `surface`
  /// group, which normally resolves identity from the generated manifest.
  SurfaceRollbackCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ),
       _fixedType = fixedSurfaceType {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: true,
      withContractVersion: true,
      withSourceKind: true,
    );
    addSurfaceMeasurementReviewOptions(argParser);
    argParser
      ..addOption(
        'to-version',
        help: 'Version number to roll back to (required).',
      )
      ..addFlag(
        'freeze',
        negatable: false,
        help: 'Lock the surface against future publishes after rolling back.',
      )
      ..addFlag(
        'yes',
        negatable: false,
        help: 'Skip the confirmation prompt (sandbox targets only).',
      )
      ..addFlag(
        'preview',
        negatable: false,
        help:
            'Preview only: print how the rollback is expected to affect live '
            'clients (the cohort-impact classification) and exit without '
            'confirming or rolling back.',
      );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Roll a surface family back to a previous pushed revision.';

  @override
  Future<int> run() async {
    // Step 1: resolve slug.
    final slug = resolveSingleSlug(argResults: argResults, stderr: _io.stderr);
    if (slug == null) return 1;

    // Step 2: resolve the exact family from the generated manifest or an
    // approved explicit fallback.
    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _io.stderr,
    );
    if (identity == null) return 1;

    // Step 3: parse --to-version (required int).
    final toVersionRaw = argResults!['to-version'] as String?;
    if (toVersionRaw == null) {
      return runAuthed(
        _io,
        argResults,
        OperationScope.target,
        (ctx) =>
            _reportMissingTarget(SurfaceApi(ctx.api), ctx.target!, identity),
      );
    }
    final toVersion = int.tryParse(toVersionRaw);
    if (toVersion == null) {
      _io.stderr.writeln('Required: --to-version <N>.');
      return 1;
    }

    // Step 3.5: --preview runs only the read path (status validation +
    // preflight) — no audit reason, no confirm, no mutation.
    final preview = argResults!['preview'] as bool;

    // Step 4: require a non-empty audit reason (not for a preview — nothing
    // is mutated, so there is nothing to audit).
    String? reason;
    if (!preview) {
      reason = await requireReason(
        argResults: argResults,
        interactive: _io.interactive,
        stderr: _io.stderr,
      );
      if (reason == null) return 1;
    }

    return runAuthed(
      _io,
      argResults,
      OperationScope.target,
      (ctx) => _rollBack(
        SurfaceApi(ctx.api),
        ctx.target!,
        identity,
        toVersion: toVersion,
        preview: preview,
        reason: reason,
      ),
      command: this,
      fitQuestion: 'Roll back anyway?',
    );
  }

  /// Names the versions a rollback can target when `--to-version` is missing.
  Future<int> _reportMissingTarget(
    SurfaceApi surfaces,
    LifecycleContext ctx,
    SurfaceLifecycleIdentity identity,
  ) async {
    final status = await surfaces.surfaceStatus(
      project: ctx.project,
      app: ctx.app,
      surfaceType: identity.surface,
      surfaceSlug: identity.slug,
      environment: ctx.environment,
      environmentTargetId: ctx.environmentTargetId,
      runtimePlane: ctx.runtimePlane,
      organizationId: ctx.organizationId,
      contractVersion: identity.contractVersion,
      sourceKind: identity.sourceKind,
    );
    final versions = [...status.versions]
      ..sort((a, b) => b.version.compareTo(a.version));
    final listed = versions.isEmpty
        ? '(none)'
        : versions
              .take(10)
              .map((v) => 'v${v.version}${v.isActive ? ' (active)' : ''}')
              .join(', ');
    _io.stderr.writeln(
      'Required: --to-version <N>. Published versions: $listed.',
    );
    return 1;
  }

  Future<int> _rollBack(
    SurfaceApi surfaces,
    LifecycleContext ctx,
    SurfaceLifecycleIdentity identity, {
    required int toVersion,
    required bool preview,
    required String? reason,
  }) async {
    final slug = identity.slug;
    final surfaceType = identity.surface;
    final freeze = argResults!['freeze'] as bool;
    final yesFlag = argResults!['yes'] as bool;

    // The status names the live version and the pushed history.
    final status = await surfaces.surfaceStatus(
      project: ctx.project,
      app: ctx.app,
      surfaceType: surfaceType,
      surfaceSlug: slug,
      environment: ctx.environment,
      environmentTargetId: ctx.environmentTargetId,
      runtimePlane: ctx.runtimePlane,
      organizationId: ctx.organizationId,
      contractVersion: identity.contractVersion,
      sourceKind: identity.sourceKind,
    );
    final availableVersions = status.versions.map((v) => v.version).toList();
    if (!availableVersions.contains(toVersion)) {
      final available = availableVersions.isEmpty
          ? '(none)'
          : availableVersions.map((v) => 'v$v').join(', ');
      _io.stderr.writeln(
        'Version v$toVersion not found. Available: $available.',
      );
      return 1;
    }

    // The cohort-impact note is printed on every path and never gates.
    final preflight = await surfaces.rollbackPreflight(
      project: ctx.project,
      app: ctx.app,
      surfaceType: surfaceType,
      surfaceSlug: slug,
      environment: ctx.environment,
      toVersion: toVersion,
      environmentTargetId: ctx.environmentTargetId,
      runtimePlane: ctx.runtimePlane,
      organizationId: ctx.organizationId,
      contractVersion: status.contractVersion,
      sourceKind: identity.sourceKind,
    );
    _io.stdout.writeln(_compatibilityNote(preflight));
    if (preview) {
      _io.stdout.writeln(
        'Preview only — nothing was rolled back. Re-run without --preview '
        'to roll back.',
      );
      return 0;
    }

    final confirmed = await confirmDestructive(
      interactive: _io.interactive,
      stdout: _io.stdout,
      stderr: _io.stderr,
      environment: ctx.environment,
      runtimePlane: ctx.runtimePlane,
      yesFlag: yesFlag,
      impactLine:
          'Roll back "$slug" in ${ctx.environment} '
          'from v${status.liveVersion} to v$toVersion'
          '${freeze ? ' and freeze' : ''}.',
    );
    if (!confirmed) {
      // Only an interactive decline lacks a message of its own.
      if (!yesFlag && _io.interactive.isInteractive) {
        _io.stdout.writeln('Aborted.');
      }
      return 1;
    }

    final impact = await reviewSurfaceMeasurement(
      io: _io,
      arguments: argResults!,
      api: surfaces,
      target: ctx,
      identity: identity,
      operation: 'surfaceRollback',
      reason: reason!,
      publishedRevision: toVersion,
      contractVersion: status.contractVersion,
      frozen: freeze,
    );
    if (impact.exitCode case final code?) return code;
    await surfaces.rollback(
      project: ctx.project,
      app: ctx.app,
      surfaceType: surfaceType,
      surfaceSlug: slug,
      environment: ctx.environment,
      toVersion: toVersion,
      lockAfter: freeze,
      reason: reason,
      environmentTargetId: ctx.environmentTargetId,
      runtimePlane: ctx.runtimePlane,
      organizationId: ctx.organizationId,
      contractVersion: status.contractVersion,
      sourceKind: identity.sourceKind,
      measurementProceed: impact.proceed,
    );
    _io.stdout.writeln(
      'Rolled back "$slug" to v$toVersion${freeze ? ' (frozen)' : ''}.',
    );
    return 0;
  }

  /// A one-line cohort-impact note for the confirm prompt. Total by
  /// construction — every classification, including one this CLI does not
  /// recognize, renders at least the raw classification, so no path can
  /// print nothing. The compatibility is judged server-side against the
  /// currently-live version as a proxy; the SDK re-checks per client.
  String _compatibilityNote(RollbackPreflightResult preflight) {
    const caveat =
        '(Compatibility is judged against the currently-live version; each '
        'installed client re-checks against its own bundled copy and falls '
        'back safely.)';
    switch (preflight.classification) {
      case RollbackPreflightClassification.compatible:
        return '$kCohortImpactNotePrefix: live clients on the current contract will '
            'render v${preflight.toVersion}. $caveat';
      case RollbackPreflightClassification.contractChange:
        final changes = preflight.blockingChanges.isEmpty
            ? ''
            : ' Changes: ${preflight.blockingChanges.join('; ')}.';
        return '$kCohortImpactNotePrefix: v${preflight.toVersion} changes the flow '
            'contract vs the live version — clients on the current contract '
            'fall back to their bundled copy.$changes $caveat';
      case RollbackPreflightClassification.noActiveBaseline:
        return '$kCohortImpactNotePrefix: nothing is currently live (killed or '
            'never published) — this publishes v${preflight.toVersion}.';
      case RollbackPreflightClassification.unsupportedTargetShape:
      case RollbackPreflightClassification.unknown:
        // unsupportedTargetShape is reserved and no longer emitted by the
        // backend (flow-shaped paywall targets roll back now); unknown is
        // forward-compat. Render the raw classification the server sent so
        // even an unrecognized answer stays legible.
        return '$kCohortImpactNotePrefix: classification '
            '"${preflight.classificationWireName}".';
    }
  }
}
