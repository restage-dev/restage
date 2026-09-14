import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_assignment_diagnostics.dart';
import 'package:restage/src/measurement/measurement_assignment_transport.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

const _outcomeLinkCarrier = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

CanonicalSurfaceExperimentAssignmentV1 _assignment() =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.checkout'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.checkout.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.checkout.1'),
      armId: ExperimentPublicArmIdV1('arm.treatment'),
      outcomeLinkCarrier: _outcomeLinkCarrier,
    );

void main() {
  test('an assigned delivery retains the accepted canonical assignment',
      () async {
    final delivered =
        await MeasurementAssignmentTransport<_Request, _Result>.adapter(
                _Adapter(_assignment()))
            .deliver(const _Request());

    expect(delivered.assignment, _assignment());
    expect(
      delivered.diagnostic,
      isA<MeasurementAssignmentDeliveryAssigned>().having(
        (value) => value.candidateDelivery,
        'candidate delivery',
        MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
      ),
    );
  });

  test('an unassigned delivery carries no assignment', () async {
    final delivered =
        await MeasurementAssignmentTransport<_Request, _Result>.adapter(
                const _Adapter(null))
            .deliver(const _Request());

    expect(delivered.assignment, isNull);
  });

  test('a missing adapter stays fail-closed and assigns nothing', () async {
    for (final transport in <MeasurementAssignmentTransport<_Request, _Result>>[
      const MeasurementAssignmentTransport<_Request, _Result>.disabled(),
      const MeasurementAssignmentTransport<_Request, _Result>.noAdapter(),
    ]) {
      final delivered = await transport.deliver(const _Request());
      expect(delivered.assignment, isNull);
      expect(delivered.diagnostic,
          isA<MeasurementAssignmentDeliveryUnavailable>());
    }
  });

  test('a throwing adapter stays fail-closed and assigns nothing', () async {
    final delivered =
        await MeasurementAssignmentTransport<_Request, _Result>.adapter(
                const _ThrowingAdapter())
            .deliver(const _Request());

    expect(delivered.assignment, isNull);
    expect(
      delivered.diagnostic,
      isA<MeasurementAssignmentDeliveryUnavailable>().having(
        (value) => value.reason,
        'reason',
        MeasurementAssignmentUnavailableReason.transportFailure,
      ),
    );
  });

  test('the registry hands back the installed typed transport', () async {
    addTearDown(MeasurementAssignmentTransportRegistry.debugReset);
    MeasurementAssignmentTransportRegistry.debugInstall<_Request, _Result>(
      _Adapter(_assignment()),
    );

    final delivered = await MeasurementAssignmentTransportRegistry.transportFor<
            _Request, _Result>()
        .deliver(const _Request());

    expect(delivered.assignment, _assignment());
  });
}

final class _Request {
  const _Request();
}

final class _Result {
  const _Result(this.assignment);

  final CanonicalSurfaceExperimentAssignmentV1? assignment;
}

final class _Adapter
    implements MeasurementAssignmentTypedAdapter<_Request, _Result> {
  const _Adapter(this._assignment);

  final CanonicalSurfaceExperimentAssignmentV1? _assignment;

  @override
  Future<_Result> deliver(_Request request) async => _Result(_assignment);

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(_Result result) =>
      result.assignment == null
          ? const MeasurementAssignmentDeliveryUnavailable(
              MeasurementAssignmentUnavailableReason.replayUnconfirmed,
            )
          : const MeasurementAssignmentDeliveryAssigned(
              candidateDelivery:
                  MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
            );

  @override
  CanonicalSurfaceExperimentAssignmentV1? assignmentFor(_Result result) =>
      result.assignment;
}

final class _ThrowingAdapter
    implements MeasurementAssignmentTypedAdapter<_Request, _Result> {
  const _ThrowingAdapter();

  @override
  Future<_Result> deliver(_Request request) async =>
      throw StateError('transport failed');

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(_Result result) =>
      const MeasurementAssignmentDeliveryUnavailable(
        MeasurementAssignmentUnavailableReason.replayUnconfirmed,
      );

  @override
  CanonicalSurfaceExperimentAssignmentV1? assignmentFor(_Result result) =>
      result.assignment;
}
