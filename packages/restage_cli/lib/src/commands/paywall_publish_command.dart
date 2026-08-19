import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';

/// Publish one generated specialized paywall from its exact manifest closure.
class PaywallPublishCommand extends Command<int> {
  /// Construct a paywall publish command.
  PaywallPublishCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser
      ..addOption(
        'organization',
        help: 'Organization slug (overrides restage_config.yaml).',
      )
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'env',
        help:
            'Environment slug to publish to (overrides '
            'restage_config.yaml `defaultEnvironment`).',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help:
            'Directory to locate restage_config.yaml and the fixed generated '
            'publication manifest. It does not select artifacts.',
      );
    addRuntimePlaneOption(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish a generated paywall from its manifest artifact closure.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <name>. Run `restage paywall '
        'publish <name>`.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one <name>.',
      );
      return 1;
    }
    final paywallName = rest.single;

    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loadedConfig = await loadRestageConfig(from: directory);
    final projectRoot = loadedConfig?.source.parent ?? directory.absolute;
    final project =
        (argResults?['project'] as String?) ?? loadedConfig?.config.project;
    final app = (argResults?['app'] as String?) ?? loadedConfig?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        'No project / app context. Run `restage init` or pass '
        '--project <slug> --app <slug>.',
      );
      return 1;
    }

    final AssembledSurfacePublication assembled;
    try {
      final manifest = await SurfacePublicationManifestLoader().load(
        projectRoot: projectRoot,
      );
      final entry = manifest.select(slug: paywallName, type: Surface.paywall);
      if (entry.publication.sourceKind != SurfaceSourceKind.paywall) {
        throw const PublicationManifestException(
          'The generated paywall identity is not a specialized paywall '
          'source. Use `restage surface publish` for a categorized ordinary '
          'screen.',
        );
      }
      assembled = await SurfacePublicationAssembler().assemble(
        loaded: manifest,
        entry: entry,
      );
    } on PublicationException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    if (assembled.capabilityWarning != null) {
      _stderr.writeln(assembled.capabilityWarning);
    }

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }

    final Uri apiEndpoint;
    try {
      apiEndpoint = resolveApiEndpoint(
        config: loadedConfig?.config,
        credential: credential,
      );
    } on EndpointConfigurationException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }

    final environment = await _resolveEnvironment(
      argResults?['env'] as String?,
      loadedConfig?.config.defaultEnvironment,
    );
    if (environment == null) return 1;

    return _runPipeline(
      credential: credential,
      apiEndpoint: apiEndpoint,
      project: project,
      app: app,
      environment: environment,
      preferredOrganizationSlug:
          (argResults?['organization'] as String?) ??
          loadedConfig?.config.organization,
      runtimePlane: runtimePlaneFromArgs(argResults),
      assembled: assembled,
    );
  }

  Future<int> _runPipeline({
    required Credential credential,
    required Uri apiEndpoint,
    required String project,
    required String app,
    required String environment,
    required String? preferredOrganizationSlug,
    required RuntimePlane? runtimePlane,
    required AssembledSurfacePublication assembled,
  }) async {
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: apiEndpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }

    try {
      final target = await resolveEnvironmentTargetContext(
        api: api,
        interactive: _interactive,
        stderr: _stderr,
        projectSlug: project,
        appSlug: app,
        environmentSlug: environment,
        preferredOrganizationSlug: preferredOrganizationSlug,
        runtimePlane: runtimePlane,
      );
      if (target == null) return 1;

      try {
        final result = await SurfacePublicationApi(api).publish(
          project: project,
          app: app,
          environment: environment,
          request: assembled.request,
          environmentTargetId: target.target.environmentTargetId,
          runtimePlane: target.target.runtimePlane,
          organizationId: target.organizationId,
        );
        _stdout.writeln(
          'Published paywall ${assembled.entry.publication.slug} to '
          '$environment; ${result.stateDescription}',
        );
        return 0;
      } on RestageApiException catch (error) {
        return _handleApiException(error);
      } on SocketException {
        _stderr.writeln('Could not publish the generated paywall.');
        return 2;
      } on FormatException {
        _stderr.writeln('Could not decode the publication response.');
        return 2;
      }
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  int _handleApiException(RestageApiException error) {
    final outcome = renderGenericTypedError(error);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln('Could not publish the generated paywall.');
    return 1;
  }

  Future<String?> _resolveEnvironment(
    String? fromFlag,
    String? fromConfig,
  ) async {
    if (fromFlag != null && fromFlag.isNotEmpty) return fromFlag;
    if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
    if (_interactive.isInteractive) {
      return _interactive.prompt('Environment slug?');
    }
    _stderr.writeln(
      'Required: --env <slug>. Set `defaultEnvironment` in '
      'restage_config.yaml or pass --env on the command line.',
    );
    return null;
  }
}
