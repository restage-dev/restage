import 'package:meta/meta.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

import 'measurement_assignment_diagnostics.dart';
import 'measurement_assignment_transport.dart';

/// Concrete SDK bridge for the callable authenticated assignment route.
///
/// It transports only the immutable carrier, an opaque credential-vault
/// locator, and typed audience input. The closed service response reduces to
/// the existing diagnostics-only seam so it cannot become selection authority.
@internal
final class IttAssignmentRpcAdapter
    implements
        MeasurementAssignmentTypedAdapter<IttAssignmentRpcRequest,
            IttAssignmentRpcOutcome> {
  /// Creates the bridge over the configured authenticated SDK client.
  const IttAssignmentRpcAdapter(this._client);

  final RestageRpcClient _client;

  @override
  Future<IttAssignmentRpcOutcome> deliver(
    IttAssignmentRpcRequest request,
  ) =>
      _client.serveIttAssignment(request);

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(
    IttAssignmentRpcOutcome result,
  ) =>
      switch (result) {
        IttAssignmentRpcAssigned(:final candidateDelivery) =>
          MeasurementAssignmentDeliveryAssigned(
            candidateDelivery: switch (candidateDelivery) {
              IttAssignmentRpcCandidateDelivery.rendered =>
                MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
              IttAssignmentRpcCandidateDelivery.renderFailedButEnrolled =>
                MeasurementAssignmentCandidateDeliveryDiagnostic
                    .renderFailedButEnrolled,
              IttAssignmentRpcCandidateDelivery.alreadyRendered =>
                MeasurementAssignmentCandidateDeliveryDiagnostic
                    .alreadyRendered,
              IttAssignmentRpcCandidateDelivery.renderInFlight =>
                MeasurementAssignmentCandidateDeliveryDiagnostic.renderInFlight,
            },
          ),
        IttAssignmentRpcOutsideAudience() =>
          const MeasurementAssignmentDeliveryOutsideAudience(),
        IttAssignmentRpcIneligible() =>
          const MeasurementAssignmentDeliveryIneligible(),
        IttAssignmentRpcAuthorityUnavailable() =>
          const MeasurementAssignmentDeliveryUnavailable(
            MeasurementAssignmentUnavailableReason.policyUnavailable,
          ),
        IttAssignmentRpcPopulationUnavailable() =>
          const MeasurementAssignmentDeliveryInferenceUnavailable(
            MeasurementInferenceUnavailableReason.eligiblePopulationUnresolved,
          ),
        IttAssignmentRpcUnauthenticated() =>
          const MeasurementAssignmentDeliveryUnavailable(
            MeasurementAssignmentUnavailableReason.unauthenticated,
          ),
        IttAssignmentRpcUnavailable(:final reason) =>
          MeasurementAssignmentDeliveryUnavailable(_unavailableReason(reason)),
      };
}

MeasurementAssignmentUnavailableReason _unavailableReason(
  IttAssignmentRpcUnavailableReason reason,
) =>
    switch (reason) {
      IttAssignmentRpcUnavailableReason.unauthenticated =>
        MeasurementAssignmentUnavailableReason.unauthenticated,
      IttAssignmentRpcUnavailableReason.forbidden =>
        MeasurementAssignmentUnavailableReason.forbidden,
      IttAssignmentRpcUnavailableReason.serviceUnavailable =>
        MeasurementAssignmentUnavailableReason.serviceUnavailable,
      IttAssignmentRpcUnavailableReason.unexpectedStatus =>
        MeasurementAssignmentUnavailableReason.unexpectedStatus,
      IttAssignmentRpcUnavailableReason.malformedResponse =>
        MeasurementAssignmentUnavailableReason.malformedResponse,
      IttAssignmentRpcUnavailableReason.transportFailure =>
        MeasurementAssignmentUnavailableReason.transportFailure,
    };
