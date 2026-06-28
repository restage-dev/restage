import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// Show the live version, lock state, delivery shape, and version history of
/// a surface in one environment.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface status` group (requires `--type`).
///   - non-null → typed-group convenience (e.g. `paywall status`; no `--type`).
class SurfaceStatusCommand extends Command<int> {
  /// Construct a status command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// requires the operator to pass `--type`.
  SurfaceStatusCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _fixedType = fixedSurfaceType,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: false,
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the live version, lock state, shape, and version history of a '
      'surface in an environment.';

  @override
  Future<int> run() async {
    final slug = resolveSingleSlug(argResults: argResults, stderr: _stderr);
    if (slug == null) return 1;

    final surfaceType = resolveSurfaceTypeArg(
      argResults: argResults,
      fixedType: _fixedType,
      stderr: _stderr,
    );
    if (surfaceType == null) return 1;

    final ctx = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
    );
    if (ctx == null) return 1;

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: Uri.parse(ctx.credential.endpoint),
        httpClient: _httpClient,
        credential: ctx.credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }
    try {
      final status = await SurfaceApi(api).surfaceStatus(
        project: ctx.project,
        app: ctx.app,
        surfaceType: surfaceType,
        surfaceSlug: slug,
        environment: ctx.environment,
      );
      _printStatus(status);
      return 0;
    } on RestageApiException catch (e) {
      return _renderError(e);
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Print a human-readable summary of [status] to stdout.
  ///
  /// Format:
  /// ```
  ///   live: vN  locked: bool  shape: blob|flow
  ///     vN (active)  ISO-8601  contentHash
  ///     vM           ISO-8601  contentHash
  /// ```
  void _printStatus(SurfaceStatusResult status) {
    final liveLabel = status.liveVersion != null
        ? 'v${status.liveVersion}'
        : '— (none)';
    _stdout.writeln(
      'live: $liveLabel  locked: ${status.locked}  shape: ${status.deliveryShape}',
    );
    for (final v in status.versions) {
      final activeMarker = v.isActive ? ' (active)' : '';
      _stdout.writeln(
        '  v${v.version}$activeMarker  ${v.publishedAt.toIso8601String()}  ${v.contentHash}',
      );
    }
  }

  /// Render a typed API error to stderr and return the appropriate exit code.
  ///
  /// Surface-specific exceptions are rendered by [decodeSurfaceTypedException];
  /// generic ones fall through to [renderGenericTypedError].
  int _renderError(RestageApiException e) {
    final surface = decodeSurfaceTypedException(e.body);
    if (surface != null) {
      _stderr.writeln(renderSurfaceException(surface));
      return 1;
    }
    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln(e.toString());
    return 1;
  }
}
