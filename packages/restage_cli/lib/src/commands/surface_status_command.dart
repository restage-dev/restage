import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/surface_reach.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';

/// How often `--watch` reads the reach again.
const Duration surfaceReachWatchInterval = Duration(seconds: 30);

/// How long `--watch` keeps reading.
const Duration surfaceReachWatchSpan = Duration(minutes: 60);

/// The reads one `--watch` makes, the first included.
final int surfaceReachWatchPolls =
    surfaceReachWatchSpan.inSeconds ~/ surfaceReachWatchInterval.inSeconds + 1;

/// Show the live version, lock state, delivery shape, and version history of
/// a surface in one environment, and how far the live version reached
/// devices.
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
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed,
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
      withReason: false,
      withContractVersion: true,
      withSourceKind: true,
    );
    argParser.addFlag(
      'watch',
      negatable: false,
      help:
          'Read how far the live version reached devices again every '
          '${surfaceReachWatchInterval.inSeconds} seconds, for up to '
          '${surfaceReachWatchSpan.inMinutes} minutes.',
    );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;
  final Future<void> Function(Duration) _sleep;

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

    final selection = await resolveSurfaceReadSelection(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _io.stderr,
    );
    if (selection == null) return 1;

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final target = ctx.target!;
      final identity = await selection.resolve(
        api: ctx.api,
        project: target.project,
        app: target.app,
        organizationId: target.organizationId,
        appId: target.appId,
      );
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
      final routing = SurfaceRoutingApi(ctx.api);
      Future<SurfaceReach> read() => routing.readSurfaceReach(
        projectSlug: target.project,
        appSlug: target.app,
        surfaceType: identity.surface.wireName,
        surfaceSlug: slug,
        environmentId: target.environmentTargetId,
        organizationId: target.organizationId,
      );
      final watch = argResults?['watch'] == true;
      for (var poll = 0; ; poll++) {
        final SurfaceReach reach;
        try {
          reach = await read();
        } on RestageApiException {
          _io.stdout.writeln('  reach: unavailable');
          return 0;
        } on FormatException {
          _io.stdout.writeln('  reach: unavailable');
          return 0;
        }
        final lines = renderSurfaceReach(reach);
        final at = reach.asOf.toIso8601String().substring(11, 19);
        _io.stdout.writeln(
          poll == 0 ? '  reach: ${lines.first}' : '$at UTC  ${lines.first}',
        );
        for (final line in lines.skip(1)) {
          _io.stdout.writeln('  $line');
        }
        if (!watch || poll + 1 >= surfaceReachWatchPolls) break;
        await _sleep(surfaceReachWatchInterval);
      }
      return 0;
    });
  }

  /// Print a human-readable summary of [status] to stdout.
  ///
  /// Format (`mode` segments appear only when the wire carries a flow
  /// delivery mode — flow versions on a current server):
  /// ```
  ///   live: vN  locked: bool  shape: blob|flow  mode: typed|general
  ///   in your app: <Name>Surface(...)
  ///   draft: code|editor
  ///   Edited after publishing from code   (only when true)
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
    if (mountLine(status) case final line?) {
      _io.stdout.writeln('  in your app: $line');
    }
    _io.stdout.writeln('  draft: ${status.draftOrigin}');
    if (status.editedAfterCode) {
      _io.stdout.writeln('  $editedAfterCodeLabel');
    }
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
