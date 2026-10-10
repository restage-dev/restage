import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
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
      final user = await AuthApi(api).whoami();
      if (user == null) {
        _stderr.writeln(staleCredentialSentence(currentSelectorSyntax));
        return 1;
      }

      _stdout.writeln('signed in as ${user.email ?? '(unknown identity)'}');
      _stdout.writeln('endpoint: $apiEndpoint');

      if (loaded == null) {
        final syntax = currentSelectorSyntax;
        _stdout.writeln(
          'no restage_config.yaml. ${syntax.run} '
          '${syntax.command(initFollowUp)} to set one up.',
        );
        await _writeWorkspaceStatus(api, null);
        return 0;
      }

      final config = loaded.config;
      if (config.organization != null) {
        _stdout.writeln('organization: ${config.organization}');
      }
      _stdout.writeln('project: ${config.project}');
      _stdout.writeln('app: ${config.app}');
      if (config.defaultEnvironment != null) {
        _stdout.writeln('environment: ${config.defaultEnvironment}');
      }
      await _writeWorkspaceStatus(api, config);
      return 0;
    } on RestageApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _stderr.writeln(staleCredentialSentence(currentSelectorSyntax));
        return 1;
      }
      _stderr.writeln('Could not contact the backend: ${e.body}');
      return 2;
    } on SocketException catch (e) {
      _stderr.writeln('Could not contact the backend: $e');
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  Future<void> _writeWorkspaceStatus(
    RestageApi api,
    RestageConfig? config,
  ) async {
    final discovery = DiscoveryApi(api);
    final organizations = await discovery.listOrganizations();
    if (organizations.isEmpty) {
      _stdout.writeln('workspace: no organizations for this account');
      return;
    }

    OrganizationSummary? organization;
    if (config != null) {
      final check = await checkConfigTarget(discovery, config);
      for (final problem in check.problems) {
        _stdout.writeln('config problem: $problem');
      }
      if (check.problems.isEmpty) {
        _stdout.writeln('config: ${configTargetConfirmed(config)}');
      }
      organization = check.organization;
    } else if (organizations.length == 1) {
      organization = organizations.single;
    } else {
      _stdout.writeln(
        'workspace: ${ambiguousOrganizationSentence(organizations)}',
      );
    }
    if (organization == null) return;

    final workspaces = await discovery.listWorkspaceExperiences();
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

  void _renderWorkspace(WorkspaceExperienceSummary workspace) {
    _stdout.writeln('workspace provenance: ${workspace.provenance}');
    _stdout.writeln('hosted access: ${workspace.hostedAccessState}');
    _stdout.writeln(
      'production allowed: ${workspace.productionAllowed ? 'yes' : 'no'}',
    );
  }
}
