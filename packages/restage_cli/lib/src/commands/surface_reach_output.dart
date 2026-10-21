import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_reach.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart';

/// After a publish: where the live version stands on devices, and how to
/// watch it climb. A reach the service cannot answer prints nothing.
Future<void> printPublishedReach({
  required SurfaceRoutingApi api,
  required StringSink stdout,
  required String projectSlug,
  required String appSlug,
  required String surfaceType,
  required String surfaceSlug,
  required int environmentId,
  required int organizationId,
}) async {
  final SurfaceReach reach;
  try {
    reach = await api.readSurfaceReach(
      projectSlug: projectSlug,
      appSlug: appSlug,
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      environmentId: environmentId,
      organizationId: organizationId,
    );
  } on RestageApiException {
    return;
  } on FormatException {
    return;
  }
  stdout
    ..writeln('Reach: ${surfaceReachHeadline(reach)}')
    ..writeln(
      'Watch it climb: restage surface status $surfaceSlug '
      '--type $surfaceType --watch',
    );
}
