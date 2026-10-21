import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/config/config_target_check.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Print the signed-in identity plus the current project config context.
class StatusCommand extends Command<int> {
  /// Construct a status command.
  StatusCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Directory to start the restage_config.yaml search from.',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Print sign-in plus active workspace and project context.';

  @override
  Future<int> run() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln(notSignedInSentence());
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
      var scope = await readProgrammaticScope(
        api,
        organizationId: loaded?.config.organizationId,
      );
      _stdout.writeln(
        'signed in as ${scope.session['email'] ?? '(unknown identity)'}',
      );
      _stdout.writeln('endpoint: $apiEndpoint');

      if (loaded == null) {
        final syntax = currentSelectorSyntax;
        _stdout.writeln(
          'no restage_config.yaml. ${syntax.run} '
          '${syntax.command(initFollowUp)} to set one up.',
        );
        await _writeWorkspaceStatus(scope, null);
        return 0;
      }

      final config = loaded.config;
      if (config.organization != null) {
        _stdout.writeln('organization: ${config.organization}');
      }
      if (config.project != null) {
        _stdout.writeln('project: ${config.project}');
      }
      if (config.app != null) {
        _stdout.writeln('app: ${config.app}');
      }
      if (config.defaultEnvironment != null) {
        _stdout.writeln('environment: ${config.defaultEnvironment}');
      }
      if (config.organization != null) {
        final requested = scope.organizations
            .where((organization) => organization.slug == config.organization)
            .firstOrNull;
        if (requested != null &&
            requested.organizationId != scope.organizationId) {
          scope = await readProgrammaticScope(
            api,
            organizationId: requested.organizationId,
          );
        }
      }
      await _writeWorkspaceStatus(scope, config);
      return 0;
    } on RestageApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _stderr.writeln(staleCredentialSentence(currentSelectorSyntax));
        return 1;
      }
      _stderr.writeln('Could not contact the backend: ${e.body}');
      return 2;
    } on SocketException catch (e) {
      _stderr.writeln(backendUnreachableMessage(api.endpoint, e));
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  Future<void> _writeWorkspaceStatus(
    ProgrammaticScopeSnapshot scope,
    RestageConfig? config,
  ) async {
    final organizations = scope.organizations;
    if (organizations.isEmpty) {
      _stdout.writeln('workspace: no organizations for this account');
      return;
    }

    OrganizationSummary? organization;
    if (config != null) {
      final problems = _configProblems(scope, config);
      for (final problem in problems) {
        _stdout.writeln('config problem: $problem');
      }
      if (problems.isEmpty) {
        _stdout.writeln('config: ${configTargetConfirmed(config)}');
      }
      organization = scope.organizations
          .where(
            (candidate) => candidate.organizationId == scope.organizationId,
          )
          .firstOrNull;
      if (problems.isNotEmpty) organization = null;
    } else if (organizations.length == 1) {
      organization = organizations.single;
    } else {
      _stdout.writeln(
        'workspace: ${ambiguousOrganizationSentence(organizations)}',
      );
    }
    if (organization == null) return;

    final workspaces = scope.workspaceExperiences;
    final matchingWorkspaces = workspaces
        .where(
          (workspace) =>
              workspace.organizationId == organization!.organizationId,
        )
        .toList(growable: false);
    if (matchingWorkspaces.length != 1) {
      _stdout.writeln('workspace: unavailable');
      return;
    }
    _stdout.writeln(
      'organization: ${organization.slug} (id ${organization.organizationId})',
    );
    _renderWorkspace(matchingWorkspaces.single);
  }

  List<String> _configProblems(
    ProgrammaticScopeSnapshot scope,
    RestageConfig config,
  ) {
    final project = config.project;
    final app = config.app;
    if (project == null || app == null) {
      return [
        if (project == null) missingConfigKeySentence('project'),
        if (app == null) missingConfigKeySentence('app'),
      ];
    }
    final organizations = scope.organizations;
    final configured = config.organization;
    if (configured != null &&
        !organizations.any((organization) => organization.slug == configured)) {
      return [
        'restage_config.yaml names organization `$configured`, which is not one of yours.',
      ];
    }
    final projectOrganizations = {
      for (final app in scope.session['apps'] as List<dynamic>? ?? const [])
        if ((app as Map<String, dynamic>)['projectSlug'] == config.project)
          app['organizationId'] as int,
    };
    if (configured == null &&
        organizations.length > 1 &&
        projectOrganizations.length != 1) {
      return [ambiguousOrganizationSentence(organizations)];
    }
    final projectSlugs = scope.projects.map((project) => project.slug).toList();
    if (!projectSlugs.contains(config.project)) {
      return [
        'restage_config.yaml names project `${config.project}`, which does not '
            'exist in `${configured ?? organizations.first.slug}`. Projects: '
            '${_list(projectSlugs)}.',
      ];
    }
    final problems = <String>[];
    final appSlugs = scope.apps(project).map((app) => app.slug).toList();
    if (!appSlugs.contains(config.app)) {
      problems.add(
        'restage_config.yaml names app `${config.app}`, which does not exist in '
        'project `${config.project}` of `${configured ?? organizations.first.slug}`. '
        'Apps there: ${_list(appSlugs)}.',
      );
    }
    if (config.defaultEnvironment case final environment?) {
      final environmentSlugs =
          scope
              .environments(project)
              .map((environment) => environment.slug)
              .toSet()
              .toList()
            ..sort();
      if (!environmentSlugs.contains(environment)) {
        problems.add(
          'restage_config.yaml names environment `$environment`, which does '
          'not exist in project `${config.project}`. Environments there: '
          '${_list(environmentSlugs)}.',
        );
      }
    }
    return problems;
  }

  String _list(List<String> slugs) =>
      slugs.isEmpty ? 'none' : slugs.map((slug) => '`$slug`').join(', ');

  void _renderWorkspace(WorkspaceExperienceSummary workspace) {
    _stdout.writeln('workspace provenance: ${workspace.provenance}');
    _stdout.writeln('hosted access: ${workspace.hostedAccessState}');
    _stdout.writeln(
      'production allowed: ${workspace.productionAllowed ? 'yes' : 'no'}',
    );
  }
}
