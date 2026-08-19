import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_shared/restage_shared.dart';

class DefaultConsoleRepository implements ConsoleRepository {
  DefaultConsoleRepository({
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Directory? directory,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient,
       _directory = directory;

  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final Directory? _directory;

  SurfaceApi? _surfaceApi;
  ConsoleContext? _context;
  int? _organizationId;
  Map<String, SurfaceLifecycleIdentity> _manifestIdentities = const {};

  @override
  Future<ConsoleSnapshot> load() async {
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await _readCredential(store);
    final loaded = await _loadConfig();
    _manifestIdentities = await _loadManifestIdentities(loaded.source.parent);
    final config = loaded.config;
    final environment = _requireEnvironment(config);
    final endpoint = _resolveEndpoint(config, credential);
    final api = _buildApi(endpoint, credential);
    _surfaceApi = SurfaceApi(api);

    final discovery = DiscoveryApi(api);
    final organization = await _resolveOrganization(api, discovery, config);
    _organizationId = organization.organizationId;

    final projects = await _loadProjects(discovery, config, organization);
    final apps = await _loadApps(discovery, config, organization);
    final selectedApp = apps.singleWhere((app) => app.slug == config.app);
    final environmentSelection = await _loadEnvironments(
      discovery,
      config,
      organization,
      selectedApp,
      environment,
    );
    final selectedEnvironment = environmentSelection.selected;
    _context = ConsoleContext(
      organizationSlug: organization.slug,
      project: config.project,
      appId: selectedApp.appId,
      app: config.app,
      environmentTargetId: selectedEnvironment.environmentTargetId,
      namedEnvironmentId: selectedEnvironment.namedEnvironmentId,
      environment: selectedEnvironment.slug,
      runtimePlane: selectedEnvironment.runtimePlane,
    );
    final surfaces = await _loadSurfaces(config, organization, selectedApp);

    return ConsoleSnapshot(
      context: _context!,
      projects: projects,
      apps: apps,
      environments: environmentSelection.targets,
      surfaces: surfaces,
    );
  }

  @override
  Future<SurfaceStatusResult> status(
    ConsoleSurface surface, {
    required ConsoleContext context,
  }) async {
    final surfaceApi = _surfaceApi;
    final organizationId = _organizationId;
    if (_context == null || surfaceApi == null || organizationId == null) {
      throw const ConsoleLoadException('Console is not loaded.');
    }

    try {
      final identity =
          _manifestIdentities[_identityKey(surface.surfaceType, surface.slug)];
      return await surfaceApi.surfaceStatus(
        project: context.project,
        app: context.app,
        surfaceType:
            identity?.surface ?? SurfaceType.fromWireName(surface.surfaceType),
        surfaceSlug: surface.slug,
        environment: context.environment,
        organizationId: organizationId,
        environmentTargetId: context.environmentTargetId,
        runtimePlane: context.runtimePlane,
        contractVersion: identity?.contractVersion,
      );
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    } on FormatException catch (e) {
      throw ConsoleLoadException(e.message);
    }
  }

  @override
  Future<List<SurfaceAuditLogEntry>> auditLog({
    required ConsoleContext context,
  }) async {
    final surfaceApi = _surfaceApi;
    final organizationId = _organizationId;
    if (_context == null || surfaceApi == null || organizationId == null) {
      throw const ConsoleLoadException('Console is not loaded.');
    }

    try {
      return await surfaceApi.listAuditLog(organizationId: organizationId);
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  @override
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required ConsoleContext context,
  }) async {
    final surfaceApi = _surfaceApi;
    final organizationId = _organizationId;
    if (_context == null || surfaceApi == null || organizationId == null) {
      throw const ConsoleLoadException('Console is not loaded.');
    }

    try {
      return await surfaceApi.surfaceChainVerdict(
        organizationId: organizationId,
      );
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  Future<Credential> _readCredential(FileCredentialStore store) async {
    try {
      final credential = await store.read();
      if (credential == null) {
        throw const ConsoleLoadException('Not signed in. Run `restage login`.');
      }
      return credential;
    } on MalformedCredentialFileException catch (e) {
      throw ConsoleLoadException(e.toString());
    } on FileSystemException catch (e) {
      throw ConsoleLoadException('Could not read credentials: $e');
    }
  }

  Future<({RestageConfig config, File source})> _loadConfig() async {
    try {
      final loaded = await loadRestageConfig(from: _directory);
      if (loaded == null) {
        throw const ConsoleLoadException(
          'No restage_config.yaml found. Run `restage init`.',
        );
      }
      return loaded;
    } on RestageConfigFormatException catch (e) {
      throw ConsoleLoadException(e.message);
    } on FileSystemException catch (e) {
      throw ConsoleLoadException('Could not read restage_config.yaml: $e');
    }
  }

  String _requireEnvironment(RestageConfig config) {
    final environment = config.defaultEnvironment?.trim();
    if (environment == null || environment.isEmpty) {
      throw const ConsoleLoadException(
        'restage_config.yaml is missing defaultEnvironment.',
      );
    }
    return environment;
  }

  Uri _resolveEndpoint(RestageConfig config, Credential credential) {
    try {
      return resolveApiEndpoint(config: config, credential: credential);
    } on EndpointConfigurationException catch (e) {
      throw ConsoleLoadException(e.toString());
    }
  }

  RestageApi _buildApi(Uri endpoint, Credential credential) {
    try {
      return RestageApi(
        endpoint: endpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      throw ConsoleLoadException(e.toString());
    }
  }

  Future<_ConsoleOrganization> _resolveOrganization(
    RestageApi api,
    DiscoveryApi discovery,
    RestageConfig config,
  ) async {
    final configuredSlug = config.organization?.trim();
    if (configuredSlug != null && configuredSlug.isNotEmpty) {
      final stderr = StringBuffer();
      final resolved = await resolveConfiguredOrganization(
        api: api,
        config: config,
        stderr: stderr,
      );
      if (resolved?.organizationId != null) {
        return _ConsoleOrganization(
          organizationId: resolved!.organizationId!,
          slug: configuredSlug,
        );
      }
      final message = stderr.toString().trim();
      throw ConsoleLoadException(
        message.isEmpty
            ? 'Could not resolve organization "$configuredSlug".'
            : message,
      );
    }

    try {
      final organizations = await discovery.listOrganizations();
      if (organizations.isEmpty) {
        throw const ConsoleLoadException(
          'No organizations found for this account.',
        );
      }
      if (organizations.length > 1) {
        throw const ConsoleLoadException(
          'restage_config.yaml is missing organization.',
        );
      }
      final organization = organizations.single;
      return _ConsoleOrganization(
        organizationId: organization.organizationId,
        slug: organization.slug,
      );
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  Future<List<ConsoleProject>> _loadProjects(
    DiscoveryApi discovery,
    RestageConfig config,
    _ConsoleOrganization organization,
  ) async {
    try {
      final projects = await discovery.listProjects(
        organization.organizationId,
      );
      if (!_containsSlug(projects, config.project)) {
        throw ConsoleLoadException(
          'No project found for restage_config.yaml project: ${config.project}.',
        );
      }
      return [
        for (final project in projects)
          ConsoleProject(slug: project.slug, name: project.name),
      ];
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  Future<List<ConsoleAppTarget>> _loadApps(
    DiscoveryApi discovery,
    RestageConfig config,
    _ConsoleOrganization organization,
  ) async {
    try {
      final apps = await discovery.listApps(
        organizationId: organization.organizationId,
        projectSlug: config.project,
      );
      if (!_containsSlug(apps, config.app)) {
        throw ConsoleLoadException(
          'No app found for restage_config.yaml app: ${config.app}.',
        );
      }
      return [
        for (final app in apps)
          ConsoleAppTarget(
            appId: _requireAppId(app),
            slug: app.slug,
            name: app.name,
          ),
      ];
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  Future<_ConsoleEnvironmentSelection> _loadEnvironments(
    DiscoveryApi discovery,
    RestageConfig config,
    _ConsoleOrganization organization,
    ConsoleAppTarget app,
    String environment,
  ) async {
    try {
      final legacyEnvironments = await discovery.listEnvironments(
        organizationId: organization.organizationId,
        projectSlug: config.project,
      );
      final legacyMatches = [
        for (final candidate in legacyEnvironments)
          if (candidate.appId == app.appId && candidate.slug == environment)
            candidate,
      ];
      if (legacyMatches.length != 1 ||
          legacyMatches.single.environmentTargetId == null) {
        throw ConsoleLoadException(
          'No environment found for defaultEnvironment: $environment.',
        );
      }
      final legacyTargetId = legacyMatches.single.environmentTargetId!;
      final discoveredTargets = await discovery.listEnvironmentTargets(
        organizationId: organization.organizationId,
        projectSlug: config.project,
        appSlug: app.slug,
        appId: app.appId,
      );
      final targets = [
        for (final target in discoveredTargets)
          ConsoleEnvironmentTarget(
            environmentTargetId: target.environmentTargetId,
            namedEnvironmentId: target.namedEnvironmentId,
            slug: target.environmentSlug,
            runtimePlane: target.runtimePlane,
          ),
      ];
      final selected = targets.where(
        (target) =>
            target.environmentTargetId == legacyTargetId &&
            target.slug == environment,
      );
      if (selected.length != 1) {
        throw ConsoleLoadException(
          'No environment found for defaultEnvironment: $environment.',
        );
      }
      return (targets: targets, selected: selected.single);
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  Future<List<ConsoleSurface>> _loadSurfaces(
    RestageConfig config,
    _ConsoleOrganization organization,
    ConsoleAppTarget app,
  ) async {
    final surfaceApi = _surfaceApi!;
    final surfaces = <ConsoleSurface>[];
    try {
      for (final surfaceType in const [
        SurfaceType.paywall,
        SurfaceType.onboarding,
        SurfaceType.message,
        SurfaceType.survey,
        SurfaceType.general,
      ]) {
        final summaries = await surfaceApi.list(
          project: config.project,
          app: config.app,
          surfaceType: surfaceType,
          organizationId: organization.organizationId,
          appId: app.appId,
        );
        for (final summary in summaries) {
          final identity =
              _manifestIdentities[_identityKey(
                summary.surfaceType,
                summary.slug,
              )];
          surfaces.add(
            ConsoleSurface(
              surfaceType: summary.surfaceType,
              slug: summary.slug,
              name: summary.name,
              contractVersion: identity?.contractVersion,
              sourceKind: identity?.sourceKind.wireName,
              payloadKind: identity?.payloadKind?.wireName,
              hasManifestIdentity: identity != null,
            ),
          );
        }
      }
      return surfaces;
    } on RestageApiException catch (e) {
      throw _apiException(e);
    } on SocketException catch (e) {
      throw ConsoleLoadException('Could not contact the backend: $e');
    }
  }

  ConsoleLoadException _apiException(RestageApiException e) {
    final outcome = renderGenericTypedError(e);
    if (outcome != null) return ConsoleLoadException(outcome.message);
    return ConsoleLoadException('Could not contact the backend: ${e.body}');
  }

  Future<Map<String, SurfaceLifecycleIdentity>> _loadManifestIdentities(
    Directory projectRoot,
  ) async {
    final manifestFile = File(
      p.join(projectRoot.path, surfacePublicationManifestRelativePath),
    );
    final invalidMarker = File(
      p.join(projectRoot.path, surfacePublicationInvalidRelativePath),
    );
    if (!manifestFile.existsSync() && !invalidMarker.existsSync()) {
      return const {};
    }
    try {
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: projectRoot,
      );
      return {
        for (final entry in loaded.manifest.publications)
          _identityKey(
            entry.publication.surface.wireName,
            entry.publication.slug,
          ): SurfaceLifecycleIdentity(
            surface: entry.publication.surface,
            slug: entry.publication.slug,
            sourceKind: entry.publication.sourceKind,
            payloadKind: entry.publication.payloadKind,
            contractVersion: entry.publication.contractVersion,
            fromManifest: true,
          ),
      };
    } on PublicationManifestException catch (e) {
      throw ConsoleLoadException(e.message);
    }
  }

  bool _containsSlug(List<Object> values, String slug) {
    for (final value in values) {
      final itemSlug = switch (value) {
        ProjectSummary(:final slug) => slug,
        AppSummary(:final slug) => slug,
        EnvironmentSummary(:final slug) => slug,
        _ => null,
      };
      if (itemSlug == slug) return true;
    }
    return false;
  }

  int _requireAppId(AppSummary app) {
    final appId = app.appId;
    if (appId != null) return appId;
    throw ConsoleLoadException(
      'Could not resolve the numeric app id for app: ${app.slug}.',
    );
  }
}

String _identityKey(String surfaceType, String slug) =>
    '$surfaceType\u0000$slug';

typedef _ConsoleEnvironmentSelection = ({
  List<ConsoleEnvironmentTarget> targets,
  ConsoleEnvironmentTarget selected,
});

class _ConsoleOrganization {
  const _ConsoleOrganization({
    required this.organizationId,
    required this.slug,
  });

  final int organizationId;
  final String slug;
}
