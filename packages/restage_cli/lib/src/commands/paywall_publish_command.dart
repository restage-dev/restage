import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/publish_selection.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_bundle_reader.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';

/// Publish one generated specialized paywall from its exact manifest closure.
///
/// This is retained as a deprecated compatibility command. New workflows use
/// `restage surface publish <slug>` so the generated manifest remains the
/// visible authority for every surface category.
class PaywallPublishCommand extends Command<int> {
  /// Construct a paywall publish command.
  PaywallPublishCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    PublicationBundleReader? bundleReader,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _bundleReader = bundleReader {
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
            'Directory to locate restage_config.yaml and generated publication '
            'metadata. It does not select artifacts.',
      );
    addPublishAllOption(argParser, noun: 'paywall');
    addRuntimePlaneOption(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final PublicationBundleReader? _bundleReader;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Deprecated compatibility publish for a specialized paywall; prefer '
      '`surface publish`.';

  @override
  String get invocation => 'restage paywall publish <name|file.dart> [options]';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <name|file.dart>. Run `restage paywall '
        'publish <name>`, or name the .dart file the paywall is declared in.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one '
        '<name|file.dart>.',
      );
      return 1;
    }
    final selector = rest.single;

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

    final List<AssembledSurfacePublication> assembled;
    try {
      final manifest = await SurfacePublicationManifestLoader().load(
        projectRoot: projectRoot,
      );
      final entries = await resolvePublicationEntries(
        manifest: manifest,
        argument: selector,
        all: argResults?['all'] as bool? ?? false,
        type: Surface.paywall,
        // Narrow rather than abort: a file that produced a specialized
        // paywall alongside an ordinary categorized screen should still
        // publish its paywalls.
        pathSourceKind: SurfaceSourceKind.paywall,
        interactive: _interactive,
        stderr: _stderr,
        commandLine: 'restage paywall publish',
      );
      if (entries == null) return 1;
      for (final entry in entries) {
        if (entry.publication.sourceKind != SurfaceSourceKind.paywall) {
          throw const PublicationManifestException(
            'The generated paywall identity is not a specialized paywall '
            'source. Use `restage surface publish` for a categorized ordinary '
            'screen.',
          );
        }
      }
      // Everything is assembled before any network work, so a broken
      // closure fails the whole invocation instead of half-publishing.
      final assembler = SurfacePublicationAssembler(
        bundleReader: _bundleReader,
      );
      assembled = <AssembledSurfacePublication>[
        for (final entry in entries)
          await assembler.assemble(loaded: manifest, entry: entry),
      ];
    } on PublicationException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    for (final publication in assembled) {
      if (publication.capabilityWarning != null) {
        _stderr.writeln(publication.capabilityWarning);
      }
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
    required List<AssembledSurfacePublication> assembled,
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

      return await runPublishRun(
        api: api,
        assembled: assembled,
        project: project,
        app: app,
        environment: environment,
        target: target,
        noun: 'paywall',
        describe: (publication) =>
            'Published paywall ${publication.entry.publication.slug}',
        onApiException: _handleApiException,
        stdout: _stdout,
        stderr: _stderr,
      );
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
