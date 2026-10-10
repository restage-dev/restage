import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';

/// The current, admitted organization scope used for programmatic discovery.
/// Its rows are only valid for this read; callers must not cache them as
/// authorization for a later operation.
@experimental
class ProgrammaticScopeSnapshot {
  const ProgrammaticScopeSnapshot(this.document);

  final Map<String, dynamic> document;

  int? get organizationId => document['organizationId'] as int?;

  Map<String, dynamic> get session =>
      document['session']! as Map<String, dynamic>;

  List<Map<String, dynamic>> _rows(String key) => [
    for (final row in document[key]! as List<dynamic>)
      row as Map<String, dynamic>,
  ];

  List<OrganizationSummary> get organizations => [
    for (final row in session['memberships']! as List<dynamic>)
      OrganizationSummary.fromJson(row as Map<String, dynamic>),
  ];

  List<WorkspaceExperienceSummary> get workspaceExperiences => [
    for (final row in session['workspaceExperiences']! as List<dynamic>)
      WorkspaceExperienceSummary.fromJson(row as Map<String, dynamic>),
  ];

  List<ProjectSummary> get projects => [
    for (final row in _rows('projects')) ProjectSummary.fromJson(row),
  ];

  List<AppSummary> apps(String projectSlug) {
    final projectIds = {
      for (final row in _rows('projects'))
        if (row['slug'] == projectSlug) row['id'] as int,
    };
    return [
      for (final row in _rows('apps'))
        if (projectIds.contains(row['projectId'])) AppSummary.fromJson(row),
    ];
  }

  List<EnvironmentSummary> environments(String projectSlug) {
    final appIds = {
      for (final app in apps(projectSlug))
        if (app.appId != null) app.appId!,
    };
    return [
      for (final row in _rows('environments'))
        if (appIds.contains(row['appId'])) EnvironmentSummary.fromJson(row),
    ];
  }

  /// Exact target ids selected as named-environment legacy defaults.
  Set<int> get legacyDefaultTargetIds => {
    for (final id
        in document['legacyDefaultTargetIds'] as List<dynamic>? ?? const [])
      id as int,
  };

  List<EnvironmentTargetSummary> targets({
    required String projectSlug,
    required String appSlug,
    RuntimePlane? runtimePlane,
  }) {
    final appIds = {
      for (final app in apps(projectSlug))
        if (app.slug == appSlug && app.appId != null) app.appId!,
    };
    final targetIds = {
      for (final environment in _rows('environments'))
        if (appIds.contains(environment['appId'])) environment['id'] as int,
    };
    return [
      for (final row in _rows('environmentTargets'))
        if (targetIds.contains(row['environmentTargetId']))
          if (EnvironmentTargetSummary.fromJson(row) case final target
              when runtimePlane == null || target.runtimePlane == runtimePlane)
            target,
    ];
  }

  /// Surfaces in one app, filtered from the same admitted document.
  List<SurfaceSummary> surfaces({
    required int appId,
    String? surfaceType,
    bool includeArchived = false,
  }) => [
    for (final row in _rows('surfaces'))
      if (row['appId'] == appId &&
          (surfaceType == null || row['surfaceType'] == surfaceType) &&
          (includeArchived || row['archivedAt'] == null))
        SurfaceSummary.fromJson(row),
  ];
}

/// Read one admitted scope. An explicit organization id selects that scope;
/// otherwise the server chooses the account's current organization.
@experimental
Future<ProgrammaticScopeSnapshot> readProgrammaticScope(
  RestageApi api, {
  int? organizationId,
}) async {
  final raw = await api.call('scope', 'read', {
    'organizationId': ?organizationId,
  });
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('The current scope is unavailable.');
  }
  final snapshot = ProgrammaticScopeSnapshot(raw);
  if (organizationId != null && snapshot.organizationId != organizationId) {
    throw const FormatException('The requested organization is unavailable.');
  }
  return snapshot;
}
