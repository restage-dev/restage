import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/experiment_activation_api.dart';
import 'package:restage_cli/src/api/measurement_wire.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Authenticated RPC seam for one profile-bound activation request.
///
/// An executable host adapts its authenticated endpoint client to this shape.
/// The route profile remains outside the canonical command bytes.
@experimental
abstract interface class ExperimentActivationRpc {
  /// Sends one activation request with its out-of-band route selectors.
  Future<ByteData> activate(
    String projectSlug,
    String appSlug,
    String environmentSlug,
    int environmentTargetId,
    measurement.RuntimePlane runtimePlane,
    ByteData requestBytes, {
    int? organizationId,
    int? appId,
  });
}

/// Host-owned selectors for one exact activation route.
@experimental
final class ExperimentActivationRouteProfile {
  /// Creates a complete out-of-band route profile.
  ExperimentActivationRouteProfile({
    required this.projectSlug,
    required this.appSlug,
    required this.environmentSlug,
    required this.environmentTargetId,
    required this.runtimePlane,
    this.selectedOrganizationId,
    this.selectedAppId,
  }) {
    _requireText(projectSlug, 'projectSlug');
    _requireText(appSlug, 'appSlug');
    _requireText(environmentSlug, 'environmentSlug');
    _requirePositive(environmentTargetId, 'environmentTargetId');
    final organizationId = selectedOrganizationId;
    if (organizationId != null) {
      _requirePositive(organizationId, 'selectedOrganizationId');
    }
    final appId = selectedAppId;
    if (appId != null) _requirePositive(appId, 'selectedAppId');
  }

  /// Project slug supplied to the authenticated route.
  final String projectSlug;

  /// App slug supplied to the authenticated route.
  final String appSlug;

  /// Environment slug supplied to the authenticated route.
  final String environmentSlug;

  /// Exact environment target supplied to the authenticated route.
  final int environmentTargetId;

  /// Exact runtime plane supplied to the authenticated route.
  final measurement.RuntimePlane runtimePlane;

  /// Optional organization disambiguator supplied to the authenticated route.
  final int? selectedOrganizationId;

  /// Optional app disambiguator supplied to the authenticated route.
  final int? selectedAppId;
}

/// The canonical command target disagrees with the host route profile.
@experimental
final class ExperimentActivationRouteProfileMismatchException
    implements Exception {
  /// Creates a target-binding failure without exposing selector values.
  const ExperimentActivationRouteProfileMismatchException();

  @override
  String toString() =>
      'Canonical activation command target does not match the configured '
      'activation route.';
}

/// The configured activation RPC could not complete its request.
@experimental
final class ExperimentActivationTransportUnavailableException
    implements Exception {
  /// Creates an unavailable transport failure without exposing RPC details.
  const ExperimentActivationTransportUnavailableException();

  @override
  String toString() => 'Configured activation transport is unavailable.';
}

/// Strict byte transport bound to one explicit activation route profile.
@experimental
final class ExperimentActivationHostTransport {
  /// Creates a profile-bound byte transport over one authenticated RPC seam.
  const ExperimentActivationHostTransport({
    required ExperimentActivationRouteProfile routeProfile,
    required ExperimentActivationRpc rpc,
  }) : _routeProfile = routeProfile,
       _rpc = rpc;

  final ExperimentActivationRouteProfile _routeProfile;
  final ExperimentActivationRpc _rpc;

  /// Sends only a canonical command whose known target fields match the host
  /// profile, then returns the RPC response bytes unchanged.
  Future<List<int>> execute(List<int> canonicalCommandBytes) async {
    final command = ExperimentActivationCommandWireV1.fromCanonicalBytes(
      canonicalCommandBytes,
    );
    _requireMatchingTarget(command.target);
    final requestBytes = command.canonicalBytes;
    final ByteData response;
    try {
      response = await _rpc.activate(
        _routeProfile.projectSlug,
        _routeProfile.appSlug,
        _routeProfile.environmentSlug,
        _routeProfile.environmentTargetId,
        _routeProfile.runtimePlane,
        ByteData.view(
          requestBytes.buffer,
          requestBytes.offsetInBytes,
          requestBytes.lengthInBytes,
        ),
        organizationId: _routeProfile.selectedOrganizationId,
        appId: _routeProfile.selectedAppId,
      );
    } on Object {
      throw const ExperimentActivationTransportUnavailableException();
    }
    return Uint8List.fromList(
      response.buffer.asUint8List(
        response.offsetInBytes,
        response.lengthInBytes,
      ),
    );
  }

  void _requireMatchingTarget(measurement.TargetCoordinate target) {
    final profile = _routeProfile;
    if (target.environmentTargetId.value != profile.environmentTargetId ||
        target.runtimePlane != profile.runtimePlane ||
        (profile.selectedOrganizationId != null &&
            target.organizationId.value != profile.selectedOrganizationId) ||
        (profile.selectedAppId != null &&
            target.appId.value != profile.selectedAppId)) {
      throw const ExperimentActivationRouteProfileMismatchException();
    }
  }
}

/// Creates the strict activation API only when both host prerequisites exist.
///
/// A missing route profile or RPC keeps executable activation routes gated.
@experimental
ExperimentActivationApi? composeExperimentActivationApi({
  required ExperimentActivationRouteProfile? routeProfile,
  required ExperimentActivationRpc? rpc,
}) {
  if (routeProfile == null || rpc == null) return null;
  return ExperimentActivationApi(
    transport: ExperimentActivationHostTransport(
      routeProfile: routeProfile,
      rpc: rpc,
    ).execute,
  );
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
}

void _requirePositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive');
  }
}
