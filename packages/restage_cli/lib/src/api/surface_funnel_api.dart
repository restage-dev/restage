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

/// Why [view] does not answer for a surface of [expectedType], or null when
/// it does or the service named no type.
String? surfaceFunnelTypeMismatch(
  SurfaceFunnelViewV1 view,
  String? expectedType,
) {
  final actual = view.surfaceType;
  if (expectedType == null || actual == null || actual == expectedType) {
    return null;
  }
  return '"${view.surfaceId}" has the type $actual, not $expectedType. '
      'Try leaving the type out, or naming $actual.';
}

/// `--version` values split into version numbers (`2` or `v2`) and version
/// identities.
({Set<int> ordinals, List<String> ids}) parseFunnelVersions(
  Iterable<String> values,
) {
  final ordinals = <int>{};
  final ids = <String>[];
  for (final value in values) {
    final number = RegExp(r'^v?([1-9][0-9]*)$').firstMatch(value.trim());
    if (number != null) {
      ordinals.add(int.parse(number.group(1)!));
    } else {
      ids.add(value);
    }
  }
  return (ordinals: ordinals, ids: ids);
}

/// [view] with only the versions numbered in [ordinals] or named in [ids].
SurfaceFunnelViewV1 onlyFunnelVersions(
  SurfaceFunnelViewV1 view, {
  required Set<int> ordinals,
  required Iterable<String> ids,
}) {
  final named = ids.toSet();
  return SurfaceFunnelViewV1.of(
    target: view.target,
    surfaceId: view.surfaceId,
    surfaceType: view.surfaceType,
    windowStartMicros: view.windowStartMicros,
    windowEndExclusiveMicros: view.windowEndExclusiveMicros,
    asOfMicros: view.asOfMicros,
    disclosureFloor: view.disclosureFloor,
    versions: [
      for (final version in view.versions)
        if (ordinals.contains(version.revisionOrdinal) ||
            named.contains(version.surfaceRevisionId))
          version,
    ],
  );
}
