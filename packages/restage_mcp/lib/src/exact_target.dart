import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Resolves declared slugs to the one exact target they authorize.
///
/// Returns null unless the app slug names exactly one active app and the
/// environment target matches on id, slug, and plane together.
Future<measurement.TargetCoordinate?> resolveExactTarget({
  required RestageApi api,
  required int organizationId,
  required String projectSlug,
  required String appSlug,
  required String environmentSlug,
  required int environmentTargetId,
  required RuntimePlane runtimePlane,
}) async {
  final discovery = DiscoveryApi(api);
  final apps = await discovery.listApps(
    organizationId: organizationId,
    projectSlug: projectSlug,
  );
  final matchingApps = [
    for (final app in apps)
      if (app.slug == appSlug && app.appId != null) app,
  ];
  if (matchingApps.length != 1) return null;
  final appId = matchingApps.single.appId!;

  final targets = await discovery.listEnvironmentTargets(
    organizationId: organizationId,
    projectSlug: projectSlug,
    appSlug: appSlug,
    appId: appId,
    runtimePlane: runtimePlane,
  );
  final matchingTargets = [
    for (final target in targets)
      if (target.environmentTargetId == environmentTargetId &&
          target.environmentSlug == environmentSlug &&
          target.runtimePlane == runtimePlane)
        target,
  ];
  if (matchingTargets.length != 1) return null;
  final target = matchingTargets.single;

  return measurement.TargetCoordinate(
    organizationId: measurement.OrganizationId(organizationId),
    appId: measurement.ApplicationId(appId),
    environmentTargetId: measurement.EnvironmentTargetId(
      target.environmentTargetId,
    ),
    namedEnvironmentId: measurement.NamedEnvironmentId(
      target.namedEnvironmentId,
    ),
    runtimePlane: target.runtimePlane == RuntimePlane.live
        ? measurement.RuntimePlane.live
        : measurement.RuntimePlane.sandbox,
  );
}
