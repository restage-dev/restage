import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// Show immutable revision history for one exact generated surface family.
class SurfaceHistoryCommand extends Command<int> {
  /// Construct a history command.
  SurfaceHistoryCommand({
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
      withContractVersion: true,
      withSourceKind: true,
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit JSON instead of the default tab-separated table.',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final SurfaceType? _fixedType;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'history';

  @override
  String get description => 'Show published revisions for a surface family.';

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
      final history = await SurfaceApi(api).surfaceContractHistory(
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
      if (argResults?['json'] as bool? ?? false) {
        _stdout.writeln(jsonEncode(history.toJson()));
      } else {
        _writeFamilyHistoryTable(_stdout, history);
      }
      return 0;
    } on RestageApiException catch (e) {
      return _renderError(e);
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  void _writeFamilyHistoryTable(
    StringSink stdout,
    SurfaceContractFamilyHistoryResult history,
  ) {
    final active = history.activePublishedRevision == null
        ? '— (none)'
        : 'r${history.activePublishedRevision}';
    stdout.writeln(
      'family: ${history.family.familyAddress}  '
      'active: $active  payload: ${history.payloadKind ?? '—'}',
    );
    stdout.writeln(
      'REVISION\tACTIVE\tPUBLISHED AT\tCONTENT HASH\tMIN CLIENT\tPAYLOAD',
    );
    for (final revision in history.revisions) {
      stdout.writeln(
        'r${revision.publishedRevision}\t${revision.isActive}\t'
        '${revision.publishedAt.toUtc().toIso8601String()}\t'
        '${revision.contentHash}\t${revision.minClient}\t'
        '${revision.payloadKind}',
      );
    }
  }

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
