import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// List projects the signed-in account can access.
class ProjectsCommand extends Command<int> {
  /// Construct a projects command.
  ProjectsCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _delegate = _DiscoveryCommandDelegate(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ) {
    _addSharedOptions(argParser);
  }

  final _DiscoveryCommandDelegate _delegate;

  @override
  String get name => 'projects';

  @override
  String get description => 'List projects available to the signed-in account.';

  @override
  Future<int> run() => _delegate.run(argResults, (ctx) async {
    final projects = await ctx.discovery.listProjects(ctx.organizationId);
    for (final project in projects) {
      ctx.stdout.writeln('${project.slug}\t${project.name}');
    }
    return 0;
  });
}

/// List apps under a project.
class AppsCommand extends Command<int> {
  /// Construct an apps command.
  AppsCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _delegate = _DiscoveryCommandDelegate(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ) {
    _addSharedOptions(argParser);
    argParser.addOption(
      'project',
      help: 'Project slug (overrides restage_config.yaml).',
    );
  }

  final _DiscoveryCommandDelegate _delegate;

  @override
  String get name => 'apps';

  @override
  String get description => 'List apps in a project.';

  @override
  Future<int> run() => _delegate.run(argResults, (ctx) async {
    final projectSlug = await ctx.resolveProjectSlug(argResults);
    if (projectSlug == null) return 1;
    final apps = await ctx.discovery.listApps(
      organizationId: ctx.organizationId,
      projectSlug: projectSlug,
    );
    for (final app in apps) {
      ctx.stdout.writeln('${app.slug}\t${app.name}');
    }
    return 0;
  });
}

/// List environments under a project.
class EnvsCommand extends Command<int> {
  /// Construct an envs command.
  EnvsCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _delegate = _DiscoveryCommandDelegate(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ) {
    _addSharedOptions(argParser);
    argParser.addOption(
      'project',
      help: 'Project slug (overrides restage_config.yaml).',
    );
  }

  final _DiscoveryCommandDelegate _delegate;

  @override
  String get name => 'envs';

  @override
  String get description => 'List environments in a project.';

  @override
  Future<int> run() => _delegate.run(argResults, (ctx) async {
    final projectSlug = await ctx.resolveProjectSlug(argResults);
    if (projectSlug == null) return 1;
    final environments = await ctx.discovery.listEnvironments(
      organizationId: ctx.organizationId,
      projectSlug: projectSlug,
    );
    for (final environment in environments) {
      ctx.stdout.writeln(environment.slug);
    }
    return 0;
  });
}

void _addSharedOptions(ArgParser parser) {
  parser
    ..addOption(
      'organization',
      help: 'Organization slug (overrides restage_config.yaml).',
    )
    ..addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Directory to start the restage_config.yaml search from.',
    );
}

typedef _DiscoveryBody = Future<int> Function(_DiscoveryContext context);

class _DiscoveryCommandDelegate {
  _DiscoveryCommandDelegate({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient;

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  Future<int> run(ArgResults? argResults, _DiscoveryBody body) async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }

    final loaded = await loadRestageConfig(
      from: Directory(argResults?['directory'] as String? ?? '.'),
    );
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
      final discovery = DiscoveryApi(api);
      final organization = await resolveActiveOrganization(
        api: discovery,
        interactive: _interactive,
        stderr: _stderr,
        preferredSlug:
            (argResults?['organization'] as String?) ??
            loaded?.config.organization,
      );
      if (organization == null) return 1;
      final context = _DiscoveryContext(
        stdout: _stdout,
        stderr: _stderr,
        interactive: _interactive,
        discovery: discovery,
        loadedConfig: loaded?.config,
        organizationId: organization.organizationId,
      );
      return await body(context);
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
    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln('Could not contact the backend: ${e.body}');
    return 2;
  }
}

class _DiscoveryContext {
  _DiscoveryContext({
    required this.stdout,
    required this.stderr,
    required this.interactive,
    required this.discovery,
    required this.loadedConfig,
    required this.organizationId,
  });

  final StringSink stdout;
  final StringSink stderr;
  final Interactive interactive;
  final DiscoveryApi discovery;
  final RestageConfig? loadedConfig;
  final int organizationId;

  Future<String?> resolveProjectSlug(ArgResults? argResults) async {
    final preferred =
        (argResults?['project'] as String?) ?? loadedConfig?.project;
    final projects = await discovery.listProjects(organizationId);
    final project = await _pickProject(
      preferredSlug: preferred,
      projects: projects,
    );
    return project?.slug;
  }

  Future<ProjectSummary?> _pickProject({
    required String? preferredSlug,
    required List<ProjectSummary> projects,
  }) async {
    if (preferredSlug != null && preferredSlug.isNotEmpty) {
      for (final project in projects) {
        if (project.slug == preferredSlug) return project;
      }
      stderr.writeln('No option found for --project <slug>: $preferredSlug.');
      return null;
    }
    return pickOne<ProjectSummary>(
      interactive: interactive,
      stderr: stderr,
      prompt: 'Which project?',
      options: [
        for (final project in projects)
          (label: '${project.name} (${project.slug})', value: project),
      ],
      missingFlag: '--project <slug>',
    );
  }
}
