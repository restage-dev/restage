import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
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
/// The target version must exist in the published history; the command
/// validates this and previews the cohort impact before confirming.
///
/// Requires a non-empty `--reason` for the audit trail. A destructive-op
/// confirmation step guards the live runtime plane: `--yes` is accepted for
/// sandbox targets; live targets always require interactive confirmation. The
/// `--freeze` flag additionally locks the surface against future publishes
/// after the re-point.
class SurfaceRollbackCommand extends Command<int> {
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
      withContractVersion: true,
      withSourceKind: true,
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
      'Roll a surface family back to a previous published revision.';

  @override
  Future<int> run() async {
    // Step 1: resolve slug.
    final slug = resolveSingleSlug(argResults: argResults, stderr: _stderr);
    if (slug == null) return 1;

    // Step 2: resolve the exact family from the generated manifest or an
    // approved explicit fallback.
    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _stderr,
      requireExplicitSourceKindForFallback: _fixedType == null,
    );
    if (identity == null) return 1;
    final surfaceType = identity.surface;

    // Step 3: parse --to-version (required int).
    final toVersionRaw = argResults!['to-version'] as String?;
    final toVersion = int.tryParse(toVersionRaw ?? '');
    if (toVersionRaw == null || toVersion == null) {
      _stderr.writeln('Required: --to-version <N>.');
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
        interactive: _interactive,
        stderr: _stderr,
      );
      if (reason == null) return 1;
    }

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
          environmentTargetId: ctx.environmentTargetId,
          runtimePlane: ctx.runtimePlane,
          organizationId: ctx.organizationId,
          contractVersion: identity.contractVersion,
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

      // Step 9.5: PREFLIGHT — an informational cohort-impact preview folded into
      // the confirm prompt so the operator sees the cohort risk before
      // confirming. Every surface shape rolls back now (a flow-shaped paywall
      // target reaches the hosted paywall flow active arm); the preflight
      // classifies but never blocks.
      final RollbackPreflightResult preflight;
      try {
        preflight = await SurfaceApi(api).rollbackPreflight(
          project: ctx.project,
          app: ctx.app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: ctx.environment,
          toVersion: toVersion,
          environmentTargetId: ctx.environmentTargetId,
          runtimePlane: ctx.runtimePlane,
          organizationId: ctx.organizationId,
          contractVersion: identity.contractVersion,
        );
      } on RestageApiException catch (e) {
        return _renderError(e, surfaceType);
      }

      // Step 10: print the cohort-impact note unconditionally — it is the
      // only operator-visible signal for how the rollback lands across the
      // installed cohort, and the most automatable paths (--yes, --preview,
      // no tty) must not be the least informative ones. Informational only:
      // it never gates the rollback.
      _stdout.writeln(_compatibilityNote(preflight));

      // Step 10.5: a preview stops here — nothing to confirm or mutate.
      if (preview) {
        _stdout.writeln(
          'Preview only — nothing was rolled back. Re-run without --preview '
          'to roll back.',
        );
        return 0;
      }

      final impactLine =
          'Roll back "$slug" in ${ctx.environment} '
          'from v${status.liveVersion} to v$toVersion'
          '${freeze ? ' and freeze' : ''}.';

      // Step 11: confirm the destructive operation.
      final confirmed = await confirmDestructive(
        interactive: _interactive,
        stdout: _stdout,
        stderr: _stderr,
        environment: ctx.environment,
        runtimePlane: ctx.runtimePlane,
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
          reason: reason!,
          environmentTargetId: ctx.environmentTargetId,
          runtimePlane: ctx.runtimePlane,
          organizationId: ctx.organizationId,
          contractVersion: identity.contractVersion,
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
      // The backend fails closed on an undecodable/corrupt target version (a
      // data-integrity guard) — re-pointing into it would reach no clients.
      _stderr.writeln(_undecodableTargetMessage(surfaceType));
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

  /// The server-side refusal rendered for the backend
  /// [SurfaceRollbackUnsupported] rejection. Usually the data-integrity
  /// guard — the target version's stored payload can't be decoded (corrupt),
  /// so re-pointing to it would reach no clients — but an older server that
  /// predates flow-surface rollback refuses with the same wire error, so the
  /// message must not present corruption as the only possible cause.
  String _undecodableTargetMessage(SurfaceType surfaceType) =>
      "The server refused to roll ${surfaceType.wireName} back to that "
      "version. Usually the version's stored payload can't be decoded "
      '(corrupt), so re-pointing to it would reach no clients — but an '
      'older server that predates flow-surface rollback refuses the same '
      'way. Roll back to a different version, or upgrade the server.';

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
            'never-activated) — this reactivates v${preflight.toVersion}.';
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
