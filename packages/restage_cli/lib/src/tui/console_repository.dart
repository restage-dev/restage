import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/measurement_page_api.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/measurement/overview_figures.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_cli/src/measurement/page_views/overview_apps_view.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;
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

    var scope = await readProgrammaticScope(
      api,
      organizationId: config.organizationId,
    );
    final configuredOrganization = config.organization;
    if (configuredOrganization != null &&
        !scope.organizations.any(
          (organization) =>
              organization.organizationId == scope.organizationId &&
              organization.slug == configuredOrganization,
        )) {
      final match = scope.organizations
          .where((organization) => organization.slug == configuredOrganization)
          .firstOrNull;
      if (match == null) {
        throw ConsoleLoadException(
          'No organization found for `$configuredOrganization`.',
        );
      }
      scope = await readProgrammaticScope(
        api,
        organizationId: match.organizationId,
      );
    }
    final organization = _resolveOrganization(scope, config);
    _organizationId = organization.organizationId;

    final projects = _loadProjects(scope, config);
    final apps = _loadApps(scope, config);
    final selectedApp = apps.singleWhere((app) => app.slug == config.app);
    final environmentSelection = _loadEnvironments(
      scope,
      config,
      selectedApp,
      environment,
    );
    final selectedEnvironment = environmentSelection.selected;
    final confirmed = config.withResolvedIds(
      organizationId: organization.organizationId,
      appId: selectedApp.appId,
      environmentTargetId: selectedEnvironment.environmentTargetId,
      namedEnvironmentId: selectedEnvironment.namedEnvironmentId,
    );
    if (confirmed.toYaml() != config.toYaml()) {
      await writeRestageConfig(loaded.source, confirmed);
    }
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
    final surfaces = _loadSurfaces(scope, selectedApp);
    final builds = await _loadBuilds(
      api,
      config: config,
      organization: organization,
    );

    return ConsoleSnapshot(
      context: _context!,
      projects: projects,
      apps: apps,
      environments: environmentSelection.targets,
      surfaces: surfaces,
      builds: builds,
      overview: await _loadOverview(api, appCount: apps.length),
    );
  }

  /// The overview figures for the last 30 days, or null when unread.
  Future<OverviewFigures?> _loadOverview(
    RestageApi api, {
    required int appCount,
  }) async {
    final context = _context!;
    final read = pageReads.first;
    final window = resolvePageWindow(
      read,
      startMicros: null,
      endMicros: null,
      now: DateTime.now(),
    );
    try {
      final request = PageRequest(
        target: TargetCoordinate(
          organizationId: OrganizationId(_organizationId!),
          appId: ApplicationId(context.appId),
          environmentTargetId: EnvironmentTargetId(context.environmentTargetId),
          namedEnvironmentId: NamedEnvironmentId(context.namedEnvironmentId),
          runtimePlane: switch (context.runtimePlane) {
            RuntimePlane.live => measurement.RuntimePlane.live,
            RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
          },
        ),
        values: const {},
        window: window,
      );
      final reply = await MeasurementPageApi(api).read(read, request);
      final figures = overviewFiguresOf(reply);
      if (appCount < 2) return figures;
      try {
        final perApp = await MeasurementPageApi(
          api,
        ).read(read.allApps!, request);
        return OverviewFigures(
          sessions: figures.sessions,
          finished: figures.finished,
          revenue: figures.revenue,
          appLines: overviewAppLinesOf(perApp),
        );
      } on Exception {
        return figures;
      }
    } on Exception {
      return null;
    }
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

  OrganizationSummary _resolveOrganization(
    ProgrammaticScopeSnapshot scope,
    RestageConfig config,
  ) {
    final candidates = scope.organizations
        .where(
          (organization) =>
              organization.organizationId == scope.organizationId &&
              (config.organization == null ||
                  organization.slug == config.organization),
        )
        .toList();
    if (candidates.length != 1) {
      throw const ConsoleLoadException(
        'The configured organization is unavailable.',
      );
    }
    return candidates.single;
  }

  List<ConsoleProject> _loadProjects(
    ProgrammaticScopeSnapshot scope,
    RestageConfig config,
  ) {
    if (!scope.projects.any((project) => project.slug == config.project)) {
      throw ConsoleLoadException(
        'No project found for restage_config.yaml project: ${config.project}.',
      );
    }
    return [
      for (final project in scope.projects)
        ConsoleProject(slug: project.slug, name: project.name),
    ];
  }

  /// The heads the selected app's build holds. A listing the service refuses
  /// reads as no heads: the console still opens, and a push says the rest.
  Future<List<ConsoleBuildHead>> _loadBuilds(
    RestageApi api, {
    required RestageConfig config,
    required OrganizationSummary organization,
  }) async {
    final bundles = RenderBundleApi(rpc: api, uploadClient: _httpClient);
    try {
      final heads = await bundles.listHeads(
        project: config.project,
        app: config.app,
        organizationId: organization.organizationId,
      );
      return [
        for (final head in heads)
          ConsoleBuildHead(
            head: head.head,
            version: head.version,
            libraries: head.libraries,
            updatedAt: head.updatedAt,
            sourceCommit: head.sourceCommit,
            sourceDirty: head.sourceDirty,
          ),
      ];
    } on RenderBundleUploadException {
      return const [];
    } finally {
      if (_httpClient == null) bundles.close();
    }
  }

  List<ConsoleAppTarget> _loadApps(
    ProgrammaticScopeSnapshot scope,
    RestageConfig config,
  ) {
    final apps = scope.apps(config.project);
    if (!apps.any((app) => app.slug == config.app)) {
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
  }

  _ConsoleEnvironmentSelection _loadEnvironments(
    ProgrammaticScopeSnapshot scope,
    RestageConfig config,
    ConsoleAppTarget app,
    String environment,
  ) {
    final targets = [
      for (final target in scope.targets(
        projectSlug: config.project,
        appSlug: app.slug,
      ))
        ConsoleEnvironmentTarget(
          environmentTargetId: target.environmentTargetId,
          namedEnvironmentId: target.namedEnvironmentId,
          slug: target.environmentSlug,
          runtimePlane: target.runtimePlane,
        ),
    ];
    final legacyIds = scope.legacyDefaultTargetIds;
    final matching = targets
        .where(
          (target) =>
              target.slug == environment &&
              (config.plane == null || target.runtimePlane == config.plane),
        )
        .toList();
    final hinted = matching
        .where(
          (target) =>
              target.environmentTargetId == config.environmentTargetId &&
              target.namedEnvironmentId == config.namedEnvironmentId,
        )
        .toList();
    final legacy = matching
        .where((target) => legacyIds.contains(target.environmentTargetId))
        .toList();
    final selected = hinted.length == 1
        ? hinted.single
        : legacy.length == 1
        ? legacy.single
        : matching.length == 1
        ? matching.single
        : null;
    if (selected == null) {
      throw ConsoleLoadException(
        'No unambiguous environment found for defaultEnvironment: '
        '$environment.',
      );
    }
    return (targets: targets, selected: selected);
  }

  List<ConsoleSurface> _loadSurfaces(
    ProgrammaticScopeSnapshot scope,
    ConsoleAppTarget app,
  ) {
    final surfaces = <ConsoleSurface>[];
    for (final summary in scope.surfaces(appId: app.appId)) {
      final identity =
          _manifestIdentities[_identityKey(summary.surfaceType, summary.slug)];
      surfaces.add(
        ConsoleSurface(
          surfaceType: summary.surfaceType,
          slug: summary.slug,
          name: summary.name,
          contractVersion: identity?.contractVersion,
          sourceKind: identity?.sourceKind?.wireName,
          payloadKind: identity?.payloadKind?.wireName,
          hasManifestIdentity: identity != null,
        ),
      );
    }
    return surfaces;
  }

  ConsoleLoadException _apiException(RestageApiException e) {
    return ConsoleLoadException(renderApiError(e).message);
  }

  Future<Map<String, SurfaceLifecycleIdentity>> _loadManifestIdentities(
    Directory projectRoot,
  ) async {
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
    } on PublicationGenerationRequiredException {
      // A project that has not generated any output yet simply contributes no
      // local identities; only stale or invalid output is worth reporting.
      return const {};
    } on PublicationManifestException catch (e) {
      throw ConsoleLoadException(e.message);
    }
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
