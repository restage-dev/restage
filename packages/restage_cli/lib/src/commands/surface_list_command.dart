import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';

/// List surfaces in the current project and app.
class SurfaceListCommand extends Command<int> {
  /// Construct a generic surface list command.
  SurfaceListCommand({
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
        'type',
        help: 'Surface type: paywall, onboarding, message, survey.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'List every supported surface type.',
      )
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
  String get description => 'List surfaces in the current project and app.';

  @override
  Future<int> run() async {
    final surfaceTypes = _resolveSurfaceTypes();
    if (surfaceTypes == null) return 1;

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

    final Uri apiEndpoint;
    try {
      apiEndpoint = resolveApiEndpoint(
        config: loaded?.config,
        credential: credential,
      );
    } on EndpointConfigurationException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: apiEndpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }

    try {
      final organizationId = await resolveRequiredOrganizationId(
        api: api,
        config: loaded?.config,
        stderr: _stderr,
      );
      if (organizationId == null) return 1;
      final appId = await resolveActiveAppId(
        discovery: DiscoveryApi(api),
        stderr: _stderr,
        organizationId: organizationId,
        projectSlug: project,
        appSlug: app,
      );
      if (appId == null) return 1;

      final surfaceApi = SurfaceApi(api);
      final summaries = <SurfaceSummary>[];
      for (final surfaceType in surfaceTypes) {
        summaries.addAll(
          await surfaceApi.list(
            project: project,
            app: app,
            surfaceType: surfaceType,
            organizationId: organizationId,
            appId: appId,
          ),
        );
      }

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

  List<SurfaceType>? _resolveSurfaceTypes() {
    final all = argResults?['all'] as bool? ?? false;
    final raw = argResults?['type'] as String?;
    final valid = _listableSurfaceTypes.map((type) => type.wireName).join(', ');
    if (all && raw != null && raw.isNotEmpty) {
      _stderr.writeln('Pass either --all or --type <$valid>, not both.');
      return null;
    }
    if (all) return _listableSurfaceTypes;
    if (raw == null || raw.isEmpty) {
      _stderr.writeln('Required: --type <$valid>, or pass --all.');
      return null;
    }
    final SurfaceType type;
    try {
      type = SurfaceType.fromWireName(raw);
    } on FormatException {
      _stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
      return null;
    }
    if (!_listableSurfaceTypes.contains(type)) {
      _stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
      return null;
    }
    return [type];
  }

  int _handleApiException(RestageApiException e) {
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

  void _renderTable(List<SurfaceSummary> summaries) {
    _stdout.writeln('TYPE\tSLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
    for (final summary in summaries) {
      final draft = summary.draftUpdatedAt.toUtc().toIso8601String();
      final published = _formatPublishedColumn(
        summary.publishedVersionByEnvironment,
      );
      _stdout.writeln(
        '${summary.surfaceType}\t${summary.slug}\t${summary.name}\t$draft\t$published',
      );
    }
  }

  String _formatPublishedColumn(Map<String, int?> byEnv) {
    final published = <String>[
      for (final entry in byEnv.entries)
        if (entry.value != null) '${entry.key}=${entry.value}',
    ];
    if (published.isEmpty) return '-';
    return published.join(', ');
  }
}

const _listableSurfaceTypes = <SurfaceType>[
  SurfaceType.paywall,
  SurfaceType.onboarding,
  SurfaceType.message,
  SurfaceType.survey,
];
