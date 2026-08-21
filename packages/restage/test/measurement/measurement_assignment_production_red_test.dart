import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_assignment_diagnostics.dart';
import 'package:restage/src/measurement/measurement_assignment_transport.dart';

void main() {
  test(
    'production contract preserves exact typed ITT adaptation as diagnostics',
    () async {
      const request = _IttProductionRequest(
        requestRevision: 1,
      );
      final adapter = _TypedIttProductionAdapter();
      final result = await MeasurementAssignmentTransport<_IttProductionRequest,
          _IttProductionResult>.adapter(
        adapter,
      ).deliver(request);

      expect(adapter.request, same(request));
      expect(
        result,
        isA<MeasurementAssignmentDeliveryAssigned>().having(
          (value) => value.candidateDelivery,
          'candidate delivery',
          MeasurementAssignmentCandidateDeliveryDiagnostic
              .renderFailedButEnrolled,
        ),
      );
    },
  );
}

/// Test contract for the service-owned ITT request. It contains no selection,
/// ITT unit, credential, pseudonym, identity, or wire carrier.
final class _IttProductionRequest {
  const _IttProductionRequest({required this.requestRevision});

  final int requestRevision;
}

/// Test contract for the service-owned ITT diagnostic result.
final class _IttProductionResult {
  const _IttProductionResult(this.candidateDelivery);

  final MeasurementAssignmentCandidateDeliveryDiagnostic candidateDelivery;
}

/// The SDK receives the exact types supplied by the service's composition and only
/// maps their post-commit delivery state into a local diagnostic.
final class _TypedIttProductionAdapter
    implements
        MeasurementAssignmentTypedAdapter<_IttProductionRequest,
            _IttProductionResult> {
  _IttProductionRequest? request;

  @override
  Future<_IttProductionResult> deliver(_IttProductionRequest request) async {
    this.request = request;
    return const _IttProductionResult(
      MeasurementAssignmentCandidateDeliveryDiagnostic.renderFailedButEnrolled,
    );
  }

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(
    _IttProductionResult result,
  ) =>
      MeasurementAssignmentDeliveryAssigned(
        candidateDelivery: result.candidateDelivery,
      );
}
