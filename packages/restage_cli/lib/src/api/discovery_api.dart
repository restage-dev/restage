import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';

/// Typed wrapper over the backend discovery RPCs.
@experimental
class DiscoveryApi {
  /// Construct a discovery API wrapper.
  DiscoveryApi(this._api);

  final RestageApi _api;

  /// The organizations the signed-in user belongs to.
  Future<List<OrganizationSummary>> listOrganizations() async {
    final raw = await _api.call('organization', 'listMine', const {});
    return [
      for (final item in raw as List<dynamic>)
        OrganizationSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Projects under [organizationId].
  Future<List<ProjectSummary>> listProjects(int organizationId) async {
    final raw = await _api.call('project', 'listProjects', <String, dynamic>{
      'organizationId': organizationId,
    });
    return [
      for (final item in raw as List<dynamic>)
        ProjectSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Apps under [organizationId] and [projectSlug].
  Future<List<AppSummary>> listApps({
    required int organizationId,
    required String projectSlug,
  }) async {
    final raw = await _api.call('app', 'listApps', <String, dynamic>{
      'organizationId': organizationId,
      'projectSlug': projectSlug,
    });
    return [
      for (final item in raw as List<dynamic>)
        AppSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Environments under [organizationId] and [projectSlug].
  Future<List<EnvironmentSummary>> listEnvironments({
    required int organizationId,
    required String projectSlug,
  }) async {
    final raw = await _api.call(
      'environment',
      'listEnvironments',
      <String, dynamic>{
        'organizationId': organizationId,
        'projectSlug': projectSlug,
      },
    );
    return [
      for (final item in raw as List<dynamic>)
        EnvironmentSummary.fromJson(item as Map<String, dynamic>),
    ];
  }
}
