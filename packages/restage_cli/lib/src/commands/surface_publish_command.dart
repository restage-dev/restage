import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/receipt_location.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_shared/restage_shared.dart';

/// The audit reason recorded when the operator does not supply one.
const String kDefaultPublishReason = 'Published from the CLI';

/// Publish one pushed revision in one exact surface family.
///
/// The revision defaults to the latest one pushed to the target environment.
/// Standalone screens require the positive manifest contract version. Flow
/// graphs and specialized paywalls use their existing non-versioned lineage.
class SurfacePublishCommand extends Command<int> {
  /// Construct a publish command.
  SurfacePublishCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    GitProcessRunner? processRunner,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _fixedType = fixedSurfaceType,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _processRunner = processRunner {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: false,
      withContractVersion: true,
      withSourceKind: true,
    );
    argParser
      ..addOption(
        'revision',
        help:
            'Pushed revision to publish. Defaults to the latest revision '
            'pushed to the target environment.',
      )
      ..addOption('pushed-revision', help: 'Alias for --revision.')
      ..addOption('version', help: 'Alias for --revision.')
      ..addOption(
        'reason',
        help: 'Audit reason for this change. Defaults to a generic reason.',
      )
      ..addFlag(
        'record-git',
        help:
            'Commit a release receipt naming the source the published '
            'revision was built from. Set `recordGit` in restage_config.yaml '
            'to make it the default for the project.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final GitProcessRunner? _processRunner;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish a pushed revision in one exact surface family; defaults to '
      'the latest pushed revision.';

  @override
  Future<int> run() async {
    final slug = resolveSingleSlug(argResults: argResults, stderr: _stderr);
    if (slug == null) return 1;

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _stderr,
      requireExplicitSourceKindForFallback: _fixedType == null,
    );
    if (identity == null) return 1;

    final explicit = _explicitRevision();
    if (!explicit.valid) return 1;

    final reasonFlag = (argResults?['reason'] as String?)?.trim();
    final reason = reasonFlag == null || reasonFlag.isEmpty
        ? kDefaultPublishReason
        : reasonFlag;

    // The repository is checked before anything reaches the server, so a
    // publication is never made with no way to record it.
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loadedConfig = await loadRestageConfig(from: directory);
    final ReleaseRecorder? recorder;
    if (_recordGit(loadedConfig?.config)) {
      recorder = await ReleaseRecorder.open(
        projectRoot: loadedConfig?.source.parent ?? directory.absolute,
        stderr: _stderr,
        processRunner: _processRunner,
      );
      if (recorder == null) return 1;
    } else {
      recorder = null;
    }

    final ctx = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    );
    if (ctx == null) return 1;

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
      var revision = explicit.revision;
      if (revision == null) {
        revision = await _latestPushedRevision(
          api: api,
          ctx: ctx,
          identity: identity,
          slug: slug,
        );
        if (revision == null) return 1;
        _stdout.writeln(
          'Latest pushed revision for "$slug" in ${ctx.environment}: '
          'r$revision.',
        );
      }

      late final SurfaceFamilyMutationResult result;
      try {
        result = await SurfaceApi(api).activate(
          project: ctx.project,
          app: ctx.app,
          surfaceType: identity.surface,
          surfaceSlug: slug,
          environment: ctx.environment,
          publishedRevision: revision,
          reason: reason,
          environmentTargetId: ctx.environmentTargetId,
          runtimePlane: ctx.runtimePlane,
          organizationId: ctx.organizationId,
          contractVersion: identity.contractVersion,
        );
      } on RestageApiException catch (e) {
        if (decodeGenericTypedException(e.body) is UnauthorizedAccess) {
          _stderr.writeln('Publishing requires an admin role.');
          return 1;
        }
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

      _stdout.writeln(
        'Published "$slug" at r$revision in ${ctx.environment} '
        '(${identity.familyAddress}).',
      );
      _stdout.writeln(
        'Active revision: ${result.activeRevisionAfter == null ? 'inactive' : 'r${result.activeRevisionAfter}'} '
        '  frozen: ${result.frozen}',
      );
      if (recorder == null) return 0;
      return await _record(
        recorder: recorder,
        ctx: ctx,
        identity: identity,
        result: result,
        revision: revision,
        organization:
            (argResults?['organization'] as String?) ??
            loadedConfig?.config.organization,
      );
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Whether this invocation records a release receipt.
  bool _recordGit(RestageConfig? config) {
    final results = argResults;
    if (results != null && results.wasParsed('record-git')) {
      return results['record-git'] as bool;
    }
    return config?.recordGit ?? false;
  }

  /// Record the publication, linking it to the source of the revision.
  ///
  /// Returns the exit code: 2 when the server published and the receipt did
  /// not land, so a caller never reads a pending receipt as a failed publish.
  Future<int> _record({
    required ReleaseRecorder recorder,
    required LifecycleContext ctx,
    required SurfaceLifecycleIdentity identity,
    required SurfaceFamilyMutationResult result,
    required int revision,
    required String? organization,
  }) async {
    final recordedAt = DateTime.now();
    final surfaceType = result.surfaceType;
    final surfaceId = result.surfaceSlug;
    final source = await recorder.sourceOfPushedRevision(
      organization: ctx.organizationSlug,
      project: ctx.project,
      app: ctx.app,
      surfaceType: surfaceType,
      surfaceId: surfaceId,
      environment: ctx.environment,
      revision: revision,
    );
    if (source.state == ReceiptSourceState.unknown) {
      _stdout.writeln(
        'Nothing here records where r$revision was built from, so the receipt '
        'says its source is unknown.',
      );
    }

    final written = await recorder.write(
      receipt: ReleaseReceipt(
        operation: ReceiptOperation.surfacePublish,
        recordedAt: recordedAt,
        target: ReceiptTarget(
          organization: ctx.organizationSlug,
          organizationId: ctx.organizationId,
          project: ctx.project,
          app: ctx.app,
          environment: ctx.environment,
          environmentTargetId: ctx.environmentTargetId,
          runtimePlane: ctx.runtimePlane.wireName,
        ),
        surface: ReceiptSurface(
          type: surfaceType,
          id: surfaceId,
          sourceKind: result.sourceKind ?? identity.sourceKind.wireName,
          contractVersion: result.contractVersion ?? identity.contractVersion,
        ),
        revision: ReceiptRevision(
          stored: revision,
          activeBefore: result.activeRevisionBefore,
          activeAfter: result.activeRevisionAfter,
          identityFrozen: result.frozen,
        ),
        source: source,
      ),
      relativePath: surfacePublishReceiptPath(
        organization: ctx.organizationSlug,
        project: ctx.project,
        app: ctx.app,
        surfaceType: surfaceType,
        surfaceId: surfaceId,
        environment: ctx.environment,
        revision: revision,
        at: recordedAt,
      ),
      stdout: _stdout,
      stderr: _stderr,
    );
    final committed = await recorder.commit(
      message: 'restage: publish $surfaceId r$revision to ${ctx.environment}',
      stdout: _stdout,
      stderr: _stderr,
    );
    return written && committed ? 0 : 2;
  }

  /// The revision named on the command line, if any.
  ///
  /// A null revision alongside a true [valid] means no flag was passed and
  /// the latest pushed revision should come from the family history.
  ({bool valid, int? revision}) _explicitRevision() {
    final values = <String, String?>{
      '--revision': argResults?['revision'] as String?,
      '--pushed-revision': argResults?['pushed-revision'] as String?,
      '--version': argResults?['version'] as String?,
    };
    final provided = values.entries
        .where((entry) => entry.value != null && entry.value!.trim().isNotEmpty)
        .toList(growable: false);
    if (provided.isEmpty) return (valid: true, revision: null);
    final parsed = <String, int?>{
      for (final entry in provided)
        entry.key: int.tryParse(entry.value!.trim()),
    };
    if (parsed.values.any((value) => value == null || value < 1)) {
      _stderr.writeln(
        'Expected a positive integer for the revision to publish.',
      );
      return (valid: false, revision: null);
    }
    final distinct = parsed.values.toSet();
    if (distinct.length != 1) {
      _stderr.writeln('Revision flags must agree; pass only one revision.');
      return (valid: false, revision: null);
    }
    return (valid: true, revision: distinct.single);
  }

  /// The highest revision pushed to the target environment for this family.
  ///
  /// Reads the family history rather than trusting its order, so a server
  /// that returns revisions oldest-first still selects the newest.
  Future<int?> _latestPushedRevision({
    required RestageApi api,
    required LifecycleContext ctx,
    required SurfaceLifecycleIdentity identity,
    required String slug,
  }) async {
    final SurfaceContractFamilyHistoryResult history;
    try {
      history = await SurfaceApi(api).surfaceContractHistory(
        project: ctx.project,
        app: ctx.app,
        surfaceType: identity.surface,
        surfaceSlug: slug,
        environment: ctx.environment,
        sourceKind: identity.sourceKind,
        contractVersion: identity.contractVersion,
        environmentTargetId: ctx.environmentTargetId,
        runtimePlane: ctx.runtimePlane,
        organizationId: ctx.organizationId,
      );
    } on RestageApiException catch (e) {
      _renderLookupError(e);
      return null;
    }
    if (history.revisions.isEmpty) {
      _stderr.writeln(
        'No pushed revisions for "$slug" in ${ctx.environment}. Run '
        '`restage surface push $slug` first.',
      );
      return null;
    }
    return history.revisions
        .map((revision) => revision.publishedRevision)
        .reduce((a, b) => a > b ? a : b);
  }

  void _renderLookupError(RestageApiException e) {
    final surface = decodeSurfaceTypedException(e.body);
    if (surface != null) {
      _stderr.writeln(renderSurfaceException(surface));
      return;
    }
    final outcome = renderGenericTypedError(e);
    _stderr.writeln(outcome?.message ?? e.toString());
  }
}
