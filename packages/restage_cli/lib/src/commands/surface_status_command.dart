import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';

/// Show the live version, lock state, delivery shape, and version history of
/// a surface in one environment.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface status` group, normally resolved from the
///     generated manifest.
///   - non-null → typed-group compatibility convenience (e.g. `paywall
///     status`; no `--type`).
class SurfaceStatusCommand extends Command<int> {
  /// Construct a status command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// normally resolves identity from the generated manifest.
  SurfaceStatusCommand({
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
      withReason: false,
      withContractVersion: true,
      withSourceKind: true,
    );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the live version, lock state, shape, and version history of a '
      'surface in an environment.';

  @override
  Future<int> run() async {
    final slug = resolveSingleSlug(argResults: argResults, stderr: _io.stderr);
    if (slug == null) return 1;

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _io.stderr,
    );
    if (identity == null) return 1;

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final target = ctx.target!;
      final status = await SurfaceApi(ctx.api).surfaceStatus(
        project: target.project,
        app: target.app,
        surfaceType: identity.surface,
        surfaceSlug: slug,
        environment: target.environment,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
        contractVersion: identity.contractVersion,
        sourceKind: identity.sourceKind,
      );
      _printStatus(status);
      return 0;
    });
  }

  /// Print a human-readable summary of [status] to stdout.
  ///
  /// Format (`mode` segments appear only when the wire carries a flow
  /// delivery mode — flow versions on a current server):
  /// ```
  ///   live: vN  locked: bool  shape: blob|flow  mode: typed|general
  ///     vN (active)  ISO-8601  contentHash  typed|general
  ///     vM           ISO-8601  contentHash  typed|general
  /// ```
  void _printStatus(SurfaceStatusResult status) {
    final liveLabel = status.liveVersion != null
        ? 'v${status.liveVersion}'
        : '— (none)';
    final activeMode = status.versions
        .where((v) => v.isActive)
        .firstOrNull
        ?.deliveryMode;
    final modeSegment = activeMode != null ? '  mode: $activeMode' : '';
    _io.stdout.writeln(
      'live: $liveLabel  locked: ${status.locked}  '
      'shape: ${status.deliveryShape}$modeSegment',
    );
    if (status.families.isNotEmpty) {
      for (final family in status.families) {
        final active = family.activeRevision == null
            ? '— (none)'
            : 'r${family.activeRevision}';
        _io.stdout.writeln('  ${family.familyAddress}  active: $active');
      }
    }
    for (final v in status.versions) {
      final activeMarker = v.isActive ? ' (active)' : '';
      final mode = v.deliveryMode != null ? '  ${v.deliveryMode}' : '';
      _io.stdout.writeln(
        '  v${v.version}$activeMarker  '
        '${v.publishedAt.toIso8601String()}  ${v.contentHash}$mode',
      );
    }
  }
}
