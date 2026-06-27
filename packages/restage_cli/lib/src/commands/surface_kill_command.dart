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

/// Deactivate a surface in one environment so the SDK falls back to its
/// bundled asset.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface kill` group (requires `--type`).
///   - non-null → typed-group convenience (e.g. `paywall kill`; no `--type`).
///
/// Requires a non-empty `--reason` for the audit trail. A destructive-op
/// confirmation step guards production: `--yes` is accepted on non-production
/// environments; production always requires an interactive confirmation.
/// The `--frozen` flag additionally locks the surface against future publishes
/// after killing it.
class SurfaceKillCommand extends Command<int> {
  /// Construct a kill command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the `paywall`
  /// convenience group); omit it for the generic `surface` group, which
  /// requires the operator to pass `--type`.
  SurfaceKillCommand({
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
      withReason: true,
    );
    argParser
      ..addFlag(
        'frozen',
        negatable: false,
        help: 'Lock the surface against future publishes after killing it.',
      )
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Skip the confirmation prompt (non-production environments only).',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'kill';

  @override
  String get description =>
      'Deactivate a surface in an environment, forcing the SDK to fall back '
      'to its bundled asset.';

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
      // Step 6: fetch the current status — doubles as an existence check and
      // provides the live version for the human-readable impact line.
      final SurfaceStatusResult status;
      try {
        status = await SurfaceApi(api).surfaceStatus(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
        );
      } on RestageApiException catch (e) {
        return _renderError(e);
      }

      // Step 7: build the impact line.
      final liveLabel = status.liveVersion == null
          ? '— (none)'
          : 'v${status.liveVersion}';
      final impactLine =
          'Kill ${surfaceType.wireName} "$slug" in ${ctx.environment} '
          '(currently serving $liveLabel).';

      // Step 8: confirm the destructive operation.
      final yesFlag = argResults!['yes'] as bool;
      final frozen = argResults!['frozen'] as bool;

      final confirmed = await confirmDestructive(
        interactive: _interactive,
        stdout: _stdout,
        stderr: _stderr,
        environment: ctx.environment,
        yesFlag: yesFlag,
        impactLine: impactLine,
      );
      if (!confirmed) {
        // Print 'Aborted.' only for an interactive decline (where the user
        // was shown the impact line and said no). The prod-refusal and the
        // non-interactive paths already write a message to stderr.
        if (!yesFlag && _interactive.isInteractive) {
          _stdout.writeln('Aborted.');
        }
        return 1;
      }

      // Step 9: call kill.
      try {
        await SurfaceApi(api).kill(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          frozen: frozen,
          reason: reason,
        );
      } on RestageApiException catch (e) {
        if (decodeGenericTypedException(e.body) is UnauthorizedAccess) {
          _stderr.writeln('Killing requires an admin role.');
          return 1;
        }
        return _renderError(e);
      }

      _stdout.writeln(
        'Killed "$slug" in ${ctx.environment}${frozen ? ' (frozen)' : ''}.',
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
