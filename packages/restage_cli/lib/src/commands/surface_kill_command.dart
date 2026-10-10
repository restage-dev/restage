import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_measurement_review.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';

/// Deactivate a surface in one environment so the SDK falls back to its
/// bundled asset.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface kill` group, normally resolved from the
///     generated manifest.
///   - non-null → typed-group compatibility convenience (e.g. `paywall kill`;
///     no `--type`).
///
/// Requires a non-empty `--reason` for the audit trail. A destructive-op
/// confirmation step guards the live runtime plane: `--yes` is accepted for
/// sandbox targets; live targets always require interactive confirmation.
/// The `--frozen` flag additionally locks the surface against future publishes
/// after killing it.
class SurfaceKillCommand extends Command<int> implements LiveGuardedCommand {
  /// Construct a kill command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// normally resolves identity from the generated manifest.
  SurfaceKillCommand({
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
    );
    addSurfaceMeasurementReviewOptions(argParser);
    argParser
      ..addFlag(
        'frozen',
        negatable: false,
        help: 'Lock the surface against future publishes after killing it.',
      )
      ..addFlag(
        'yes',
        negatable: false,
        help: 'Skip the confirmation prompt (sandbox targets only).',
      );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;

  @override
  String get name => 'kill';

  @override
  String get description =>
      'Deactivate a surface in an environment, forcing the SDK to fall back '
      'to its bundled asset.';

  @override
  Future<int> run() async {
    // Step 1: resolve slug.
    final slug = resolveSingleSlug(argResults: argResults, stderr: _io.stderr);
    if (slug == null) return 1;

    // Step 2: resolve the current manifest identity. Kill is identity-wide;
    // it intentionally does not accept a contract-version selector.
    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _io.stderr,
    );
    if (identity == null) return 1;

    // Step 3: require a non-empty audit reason.
    final reason = await requireReason(
      argResults: argResults,
      interactive: _io.interactive,
      stderr: _io.stderr,
    );
    if (reason == null) return 1;

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final target = ctx.target!;
      final surfaces = SurfaceApi(ctx.api);
      // The status doubles as an existence check and names the live version
      // for the impact line.
      final status = await surfaces.surfaceStatus(
        project: target.project,
        app: target.app,
        surfaceType: identity.surface,
        surfaceSlug: slug,
        environment: target.environment,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
      );
      final liveLabel = status.liveVersion == null
          ? '— (none)'
          : 'v${status.liveVersion}';
      final yesFlag = argResults!['yes'] as bool;
      final frozen = argResults!['frozen'] as bool;
      final confirmed = await confirmDestructive(
        interactive: _io.interactive,
        stdout: _io.stdout,
        stderr: _io.stderr,
        environment: target.environment,
        runtimePlane: target.runtimePlane,
        yesFlag: yesFlag,
        impactLine:
            'Kill ${identity.surface.wireName} "$slug" in '
            '${target.environment} (currently serving $liveLabel).',
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
        target: target,
        identity: identity,
        operation: 'surfaceKill',
        reason: reason,
        frozen: frozen,
      );
      if (impact.exitCode case final code?) return code;
      final mutation = await surfaces.kill(
        project: target.project,
        app: target.app,
        surfaceType: identity.surface,
        surfaceSlug: slug,
        environment: target.environment,
        frozen: frozen,
        reason: reason,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
        measurementProceed: impact.proceed,
      );
      _io.stdout.writeln(
        'Killed "$slug" in ${target.environment}${frozen ? ' (frozen)' : ''}.',
      );
      if (mutation != null) writeAffectedFamilyMutation(_io.stdout, mutation);
      return 0;
    });
  }
}
