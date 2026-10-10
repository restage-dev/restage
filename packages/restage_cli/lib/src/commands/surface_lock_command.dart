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

/// Freezes or unfreezes publishing for a surface in one environment.
/// [fixedSurfaceType] selects a typed command; otherwise the manifest resolves it.
/// Requires `--reason`. Live operations require confirmation or `--yes`.
class SurfaceLockCommand extends Command<int> implements LiveGuardedCommand {
  /// Construct a freeze or unfreeze command.
  ///
  /// [lock] selects the direction: true → freeze, false → unfreeze. Pass
  /// [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// normally resolves identity from the generated manifest.
  SurfaceLockCommand({
    required bool lock,
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _lock = lock,
       _io = CommandIo(
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
  }

  final bool _lock;
  final CommandIo _io;
  final SurfaceType? _fixedType;

  @override
  String get name => _lock ? 'freeze' : 'unfreeze';

  @override
  String get description => _lock
      ? 'Freeze a surface: no version can be published until you unfreeze it.'
      : 'Unfreeze a surface so versions can be published again.';

  @override
  Future<int> run() async {
    // Step 1: resolve slug.
    final slug = resolveSingleSlug(argResults: argResults, stderr: _io.stderr);
    if (slug == null) return 1;

    // Step 2: resolve the current manifest identity. Freeze and unfreeze are
    // identity-wide and deliberately have no contract-version selector.
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
      final confirmed = await confirmLiveChange(
        command: this,
        interactive: _io.interactive,
        stdout: _io.stdout,
        stderr: _io.stderr,
        runtimePlane: target.runtimePlane,
        impactLine:
            '${_lock ? 'Freeze' : 'Unfreeze'} ${identity.surface.wireName} '
            '"$slug" in ${target.environment} (live).',
      );
      if (!confirmed) return 1;
      final surfaces = SurfaceApi(ctx.api);
      final impact = await reviewSurfaceMeasurement(
        io: _io,
        arguments: argResults!,
        api: surfaces,
        target: target,
        identity: identity,
        operation: 'surfaceFreeze',
        reason: reason,
        frozen: _lock,
      );
      if (impact.exitCode case final code?) return code;
      final mutation = await surfaces.setLock(
        project: target.project,
        app: target.app,
        surfaceType: identity.surface,
        surfaceSlug: slug,
        environment: target.environment,
        locked: _lock,
        reason: reason,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
        measurementProceed: impact.proceed,
      );
      _io.stdout.writeln(
        '${_lock ? 'Froze' : 'Unfroze'} "$slug" in ${target.environment}.',
      );
      if (mutation != null) writeAffectedFamilyMutation(_io.stdout, mutation);
      return 0;
    });
  }
}
