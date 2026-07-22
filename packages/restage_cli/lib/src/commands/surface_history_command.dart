import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/audit_rendering.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';

/// Show server audit history for one surface in one environment.
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
  String get description => 'Show server audit history for a surface.';

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
      final rows = await SurfaceApi(api).listSurfaceHistory(
        project: ctx.project,
        app: ctx.app,
        surfaceType: surfaceType,
        surfaceSlug: slug,
        environment: ctx.environment,
        environmentTargetId: ctx.environmentTargetId,
        runtimePlane: ctx.runtimePlane,
        organizationId: ctx.organizationId,
      );
      if (argResults?['json'] as bool? ?? false) {
        writeAuditLogJson(_stdout, rows);
      } else {
        writeAuditLogTable(_stdout, rows);
      }
      return 0;
    } on RestageApiException catch (e) {
      return _renderError(e);
    } finally {
      if (_httpClient == null) api.close();
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
