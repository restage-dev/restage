import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// Freeze or unfreeze a surface in one environment.
///
/// When frozen, a publish snapshots a new version but does not make it live.
/// Unfreezing restores the default behaviour: the next publish activates.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface freeze`/`surface unfreeze` group (requires `--type`).
///   - non-null → typed-group convenience (e.g. `paywall freeze`; no `--type`).
///
/// Requires a non-empty `--reason` for the audit trail. Because freeze and
/// unfreeze are reversible, no destructive-op confirmation prompt is needed.
class SurfaceLockCommand extends Command<int> {
  /// Construct a freeze or unfreeze command.
  ///
  /// [lock] selects the direction: true → freeze, false → unfreeze. Pass
  /// [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// requires the operator to pass `--type`.
  SurfaceLockCommand({
    required bool lock,
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _lock = lock,
       _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _fixedType = fixedSurfaceType,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: true,
    );
  }

  final bool _lock;
  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => _lock ? 'freeze' : 'unfreeze';

  @override
  String get description => _lock
      ? 'Freeze a surface (a publish snapshots a version but does not activate it).'
      : 'Unfreeze a surface (let the next publish activate again).';

  @override
  Future<int> run() async {
    // Step 1: resolve slug.
    final slug = resolveSingleSlug(argResults: argResults, stderr: _stderr);
    if (slug == null) return 1;

    // Step 2: resolve surface type.
    final surfaceType = resolveSurfaceTypeArg(
      argResults: argResults,
      fixedType: _fixedType,
      stderr: _stderr,
    );
    if (surfaceType == null) return 1;

    // Step 3: require a non-empty audit reason.
    final reason = await requireReason(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
    );
    if (reason == null) return 1;

    // Step 4: resolve credential + project/app/env.
    final ctx = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
    );
    if (ctx == null) return 1;

    // Step 5: build the API client.
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
      // Step 6: set or clear the publish lock.
      try {
        await SurfaceApi(api).setLock(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          locked: _lock,
          reason: reason,
        );
      } on RestageApiException catch (e) {
        if (decodeGenericTypedException(e.body) is UnauthorizedAccess) {
          _stderr.writeln(
            '${_lock ? 'Freezing' : 'Unfreezing'} requires an admin role.',
          );
          return 1;
        }
        return _renderError(e);
      }

      // Step 7: confirm success.
      _stdout.writeln(
        '${_lock ? 'Froze' : 'Unfroze'} "$slug" in ${ctx.environment}.',
      );
      return 0;
    } finally {
      if (_httpClient == null) api.close();
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
