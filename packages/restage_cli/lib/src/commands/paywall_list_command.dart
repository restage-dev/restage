import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/paywall_api.dart';
import 'package:restage_cli/src/api/paywall_models.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// List paywalls in the current project and app.
///
/// Project and app slugs are resolved in priority order: explicit
/// `--project` / `--app` flags, then `restage_config.yaml` discovered by
/// walking up from the current directory. When neither is available, the
/// command exits with a user-error.
class PaywallListCommand extends Command<int> {
  /// Construct a list command.
  PaywallListCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help:
            'Directory to start the restage_config.yaml search from. '
            'Defaults to the current working directory.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON instead of the default tab-separated table.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'list';

  @override
  String get description => 'List paywalls in the current project and app.';

  @override
  Future<int> run() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }

    final loaded = await loadRestageConfig(
      from: Directory(argResults?['directory'] as String? ?? '.'),
    );
    final project =
        (argResults?['project'] as String?) ?? loaded?.config.project;
    final app = (argResults?['app'] as String?) ?? loaded?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        'No project / app context. Run `restage init` or pass '
        '--project <slug> --app <slug>.',
      );
      return 1;
    }

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: Uri.parse(credential.endpoint),
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }
    try {
      final summaries = await PaywallApi(api).list(project: project, app: app);
      if (argResults?['json'] as bool? ?? false) {
        _stdout.writeln(jsonEncode([for (final s in summaries) s.toJson()]));
      } else {
        _renderTable(summaries);
      }
      return 0;
    } on RestageApiException catch (e) {
      return _handleApiException(e);
    } on SocketException catch (e) {
      _stderr.writeln('Could not contact the backend: $e');
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  int _handleApiException(RestageApiException e) {
    // Typed exception with no shared phrasing — `paywall list` doesn't
    // expect publish-flavoured errors, so decode the typed body (generic
    // first, then the surface endpoint's own, since the list now reads via
    // `surface`) before the generic renderer turns unknown typed bodies
    // into transport-style HTTP errors.
    final typed = decodeTypedException(e.body);
    if (typed != null) {
      _stderr.writeln(typed.toString());
      return 1;
    }
    final surfaceTyped = decodeSurfaceTypedException(e.body);
    if (surfaceTyped != null) {
      _stderr.writeln(surfaceTyped.toString());
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

  void _renderTable(List<PaywallSummary> summaries) {
    _stdout.writeln('SLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
    for (final summary in summaries) {
      final draft = summary.draftUpdatedAt.toUtc().toIso8601String();
      final published = _formatPublishedColumn(
        summary.publishedVersionByEnvironment,
      );
      _stdout.writeln('${summary.slug}\t${summary.name}\t$draft\t$published');
    }
  }

  /// Render the `PUBLISHED` column.
  ///
  /// Each `env: version` pair contributes `env=version` when the version
  /// is non-null. The whole column is a single dash (`-`) when no
  /// environment has a published version yet.
  String _formatPublishedColumn(Map<String, int?> byEnv) {
    final published = <String>[
      for (final entry in byEnv.entries)
        if (entry.value != null) '${entry.key}=${entry.value}',
    ];
    if (published.isEmpty) return '-';
    return published.join(', ');
  }
}
