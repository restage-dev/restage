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

/// Activate one exact published revision in one exact surface family.
///
/// Standalone screens require the positive manifest contract version. Flow
/// graphs and specialized paywalls use their existing non-versioned lineage.
class SurfaceActivateCommand extends Command<int> {
  /// Construct an activation command.
  SurfaceActivateCommand({
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
        'revision',
        help: 'Published revision to activate (required).',
      )
      ..addOption('published-revision', help: 'Alias for --revision.')
      ..addOption('version', help: 'Alias for --revision.');
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'activate';

  @override
  String get description =>
      'Activate one published revision in one exact surface family.';

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

    final revision = _resolveRevision();
    if (revision == null) return 1;

    final reason = await requireReason(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
    );
    if (reason == null) return 1;

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
          _stderr.writeln('Activating requires an admin role.');
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
        'Activated "$slug" at r$revision in ${ctx.environment} '
        '(${identity.familyAddress}).',
      );
      _stdout.writeln(
        'Active revision: ${result.activeRevisionAfter == null ? 'inactive' : 'r${result.activeRevisionAfter}'} '
        '  frozen: ${result.frozen}',
      );
      return 0;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  int? _resolveRevision() {
    final values = <String, String?>{
      '--revision': argResults?['revision'] as String?,
      '--published-revision': argResults?['published-revision'] as String?,
      '--version': argResults?['version'] as String?,
    };
    final provided = values.entries
        .where((entry) => entry.value != null && entry.value!.trim().isNotEmpty)
        .toList(growable: false);
    if (provided.isEmpty) {
      _stderr.writeln(
        'Required: --revision <N> (or --published-revision/--version).',
      );
      return null;
    }
    final parsed = <String, int?>{
      for (final entry in provided)
        entry.key: int.tryParse(entry.value!.trim()),
    };
    if (parsed.values.any((value) => value == null || value < 1)) {
      _stderr.writeln(
        'Expected a positive integer for the activation revision.',
      );
      return null;
    }
    final distinct = parsed.values.toSet();
    if (distinct.length != 1) {
      _stderr.writeln(
        'Activation revision flags must agree; pass only one revision.',
      );
      return null;
    }
    return distinct.single;
  }
}
