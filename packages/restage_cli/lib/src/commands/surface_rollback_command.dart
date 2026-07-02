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

/// Roll a surface back to a previous version by re-pointing the active-version
/// pointer.
///
/// Usable two ways via [fixedSurfaceType]:
///   - null → generic `surface rollback` group (requires `--type`).
///   - non-null → typed-group convenience (e.g. `paywall rollback`; no
///     `--type`).
///
/// Works for paywalls AND flow surfaces (onboarding / message / survey) — the
/// re-point reaches a flow surface's active-arm clients. The one case still
/// refused is rolling a paywall back to a flow-shaped version (a lowered
/// navigation paywall), which the hosted paywall path cannot active-serve yet.
/// The target version must exist in the published history; the command
/// validates this and previews the cohort impact before confirming.
///
/// Requires a non-empty `--reason` for the audit trail. A destructive-op
/// confirmation step guards production: `--yes` is accepted on
/// non-production environments; production always requires an interactive
/// confirmation. The `--freeze` flag additionally locks the surface
/// against future publishes after the re-point.
class SurfaceRollbackCommand extends Command<int> {
  /// Construct a rollback command.
  ///
  /// Pass [fixedSurfaceType] to pin the surface type (e.g. for the
  /// `paywall` convenience group); omit it for the generic `surface`
  /// group, which requires the operator to pass `--type`.
  SurfaceRollbackCommand({
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
  String get name => 'rollback';

  @override
  String get description =>
      'Roll a surface back to a previous version (paywalls and flow surfaces). '
      'Rolling a paywall back to a flow-shaped version is not yet supported.';

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

    // Step 3: parse --to-version (required int).
    final toVersionRaw = argResults!['to-version'] as String?;
    final toVersion = int.tryParse(toVersionRaw ?? '');
    if (toVersionRaw == null || toVersion == null) {
      _stderr.writeln('Required: --to-version <N>.');
      return 1;
    }

    // Step 4: require a non-empty audit reason.
    final reason = await requireReason(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
    );
    if (reason == null) return 1;

    // Step 5: resolve credential + project/app/env.
    final ctx = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    );
    if (ctx == null) return 1;

    // Step 6: build the API client.
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: ctx.apiEndpoint,
        httpClient: _httpClient,
        credential: ctx.credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }
    try {
      final freeze = argResults!['freeze'] as bool;
      final yesFlag = argResults!['yes'] as bool;

      // Step 7: fetch the current status — provides the delivery shape,
      // version history, and the live version for the impact line.
      final SurfaceStatusResult status;
      try {
        status = await SurfaceApi(api).surfaceStatus(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          organizationId: ctx.organizationId,
        );
      } on RestageApiException catch (e) {
        return _renderError(e, surfaceType);
      }

      // Step 8 (removed): flow surfaces roll back now. The one residual — a
      // flow-shaped paywall target — is caught by the preflight below (fast,
      // before the confirm) and, defensively, by the backend gate.

      // Step 9: VERSION VALIDATION — the target version must exist in the
      // published history before confirming the operation.
      final availableVersions = status.versions.map((v) => v.version).toList();
      if (!availableVersions.contains(toVersion)) {
        final available = availableVersions.isEmpty
            ? '(none)'
            : availableVersions.map((v) => 'v$v').join(', ');
        _stderr.writeln(
          'Version v$toVersion not found. Available: $available.',
        );
        return 1;
      }

      // Step 9.5: PREFLIGHT — an informational cohort-impact preview. A
      // flow-shaped paywall target is refused here; every other classification
      // is surfaced in the impact line so the operator sees the cohort risk
      // before confirming.
      final RollbackPreflightResult preflight;
      try {
        preflight = await SurfaceApi(api).rollbackPreflight(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          toVersion: toVersion,
        );
      } on RestageApiException catch (e) {
        return _renderError(e, surfaceType);
      }
      if (preflight.classification ==
          RollbackPreflightClassification.unsupportedTargetShape) {
        _stderr.writeln(_rollbackUnsupportedMessage(surfaceType));
        return 1;
      }

      // Step 10: build the impact line + the cohort-impact note.
      final base =
          'Roll back "$slug" in ${ctx.environment} '
          'from v${status.liveVersion} to v$toVersion'
          '${freeze ? ' and freeze' : ''}.';
      final note = _compatibilityNote(preflight);
      final impactLine = note == null ? base : '$base\n$note';

      // Step 11: confirm the destructive operation.
      final confirmed = await confirmDestructive(
        interactive: _interactive,
        stdout: _stdout,
        stderr: _stderr,
        environment: ctx.environment,
        yesFlag: yesFlag,
        impactLine: impactLine,
      );
      if (!confirmed) {
        // Print 'Aborted.' only for an interactive decline (where the
        // user was shown the impact line and said no). The prod-refusal
        // and the non-interactive paths already write a message to stderr.
        if (!yesFlag && _interactive.isInteractive) {
          _stdout.writeln('Aborted.');
        }
        return 1;
      }

      // Step 12: call rollback.
      try {
        await SurfaceApi(api).rollback(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          toVersion: toVersion,
          lockAfter: freeze,
          reason: reason,
          organizationId: ctx.organizationId,
        );
      } on RestageApiException catch (e) {
        return _renderError(e, surfaceType);
      }

      // Step 13: success.
      _stdout.writeln(
        'Rolled back "$slug" to v$toVersion${freeze ? ' (frozen)' : ''}.',
      );
      return 0;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Render a typed API error to stderr and return the appropriate exit
  /// code.
  ///
  /// Surface-specific rollback exceptions are rendered with command-specific
  /// wording; the admin-role exception is intercepted before the generic
  /// renderer so it produces a rollback-specific message; everything else
  /// falls through to [renderGenericTypedError].
  int _renderError(RestageApiException e, SurfaceType surfaceType) {
    final surface = decodeSurfaceTypedException(e.body);
    if (surface is SurfaceRollbackUnsupported) {
      // Defense-in-depth: the backend refuses a flow-shaped paywall target even
      // if the preflight did not catch it first.
      _stderr.writeln(_rollbackUnsupportedMessage(surfaceType));
      return 1;
    }
    if (surface != null) {
      _stderr.writeln(renderSurfaceException(surface));
      return 1;
    }
    if (decodeGenericTypedException(e.body) is UnauthorizedAccess) {
      _stderr.writeln('Rolling back requires an admin role.');
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

  /// The honest residual message: rolling a paywall back to a flow-shaped
  /// version is not yet supported. Shared by the preflight fast-fail and the
  /// backend-rejection branch of [_renderError] so the wording stays single.
  String _rollbackUnsupportedMessage(SurfaceType surfaceType) =>
      "Rolling ${surfaceType.wireName} back to a flow-shaped version isn't "
      'supported yet: a paywall lowered to a navigation flow has no hosted '
      'active-serve path. (Flow surfaces — onboarding, message, survey — do '
      'roll back.)';

  /// A one-line cohort-impact note for the confirm prompt, or null when there
  /// is nothing useful to add. The compatibility is judged server-side against
  /// the currently-live version as a proxy; the SDK re-checks per client.
  String? _compatibilityNote(RollbackPreflightResult preflight) {
    const caveat =
        '(Compatibility is judged against the currently-live version; each '
        'installed client re-checks against its own bundled copy and falls '
        'back safely.)';
    switch (preflight.classification) {
      case RollbackPreflightClassification.compatible:
        return 'Cohort impact: live clients on the current contract will '
            'render v${preflight.toVersion}. $caveat';
      case RollbackPreflightClassification.contractChange:
        final changes = preflight.blockingChanges.isEmpty
            ? ''
            : ' Changes: ${preflight.blockingChanges.join('; ')}.';
        return 'Cohort impact: v${preflight.toVersion} changes the flow '
            'contract vs the live version — clients on the current contract '
            'fall back to their bundled copy.$changes $caveat';
      case RollbackPreflightClassification.noActiveBaseline:
        return 'Cohort impact: nothing is currently live (killed or '
            'never-activated) — this reactivates v${preflight.toVersion}.';
      case RollbackPreflightClassification.unsupportedTargetShape:
      case RollbackPreflightClassification.unknown:
        // unsupportedTargetShape is handled before the confirm; unknown adds
        // no note (forward-compatibility).
        return null;
    }
  }
}
