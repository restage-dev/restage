import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_slug.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Largest canonical funnel reading this tool accepts from the route.
const int kMaximumSurfaceFunnelWireBytes = 16 * 1024 * 1024;

/// The route answered with a reading addressed to another surface or target.
@experimental
final class SurfaceFunnelMismatchException implements Exception {
  /// Creates the response-binding failure.
  const SurfaceFunnelMismatchException();

  @override
  String toString() =>
      'The funnel route answered with a reading bound to another surface or '
      'target.';
}

/// Reads published funnel figures for one surface.
@experimental
class SurfaceFunnelApi {
  /// Binds the read to [_api].
  SurfaceFunnelApi(this._api);

  final RestageApi _api;

  /// Reads [selection]'s funnel at [target].
  ///
  /// Throws [SurfaceFunnelMismatchException] when the reading names another
  /// surface or target, and [CanonicalFormatException] when the bytes are not
  /// the canonical form of the published contract.
  Future<SurfaceFunnelViewV1> read({
    required TargetCoordinate target,
    required SurfaceFunnelSelectionV1 selection,
  }) async {
    final surfaceId = await resolveSurfaceId(_api, target, selection.surfaceId);
    if (surfaceId != selection.surfaceId) {
      selection = SurfaceFunnelSelectionV1(
        surfaceId: surfaceId,
        windowStartMicros: selection.windowStartMicros,
        windowEndExclusiveMicros: selection.windowEndExclusiveMicros,
        surfaceRevisionIds: selection.surfaceRevisionIds,
      );
    }
    final raw = await _api.call(_endpointName, 'readSurfaceFunnel', {
      'organizationId': target.organizationId.value,
      'appId': target.appId.value,
      'environmentTargetId': target.environmentTargetId.value,
      'namedEnvironmentId': target.namedEnvironmentId.value,
      'runtimePlane': target.runtimePlane.wireName,
      'surfaceId': selection.surfaceId,
      'windowStartMicros': selection.windowStartMicros,
      'windowEndExclusiveMicros': selection.windowEndExclusiveMicros,
      'surfaceRevisionIds': ?selection.surfaceRevisionIds,
    });
    final bytes = decodeByteDataWire(
      raw,
      maximumBytes: kMaximumSurfaceFunnelWireBytes,
      malformed: (detail) =>
          CanonicalFormatException('The funnel reading $detail'),
    );
    final view = SurfaceFunnelViewV1.fromCanonicalBytes(bytes);
    if (view.target != target || view.surfaceId != selection.surfaceId) {
      throw const SurfaceFunnelMismatchException();
    }
    return view;
  }
}

const _endpointName = 'surfaceFunnel';
