import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'governed_measurement_transport.dart';

/// Explicit, opt-in governed Measurement operations.
///
/// Ordinary subjectless measurement remains zero-ceremony. This domain is for
/// callers that deliberately supply the challenge, authenticated evidence,
/// and generation preconditions required by the governed identity contract.
final class RestageMeasurement {
  /// Internal construction used by the SDK facade.
  @internal
  RestageMeasurement.internal();

  /// Issues one exact direct host/IDP link challenge.
  Future<MeasurementLinkChallengeOperationResultV1> issueLinkChallenge(
    MeasurementLinkChallengeRequestV1 request,
  ) async {
    try {
      return await GovernedMeasurementPortRegistry.measurement
          .issueLinkChallenge(request);
    } on Object {
      return unavailableLinkChallengeResult();
    }
  }

  /// Links a subject through the complete direct host/IDP path.
  Future<MeasurementLinkOperationResultV1> linkSubject(
    MeasurementLinkRequestV1 request,
  ) async {
    try {
      return await GovernedMeasurementPortRegistry.measurement.linkSubject(
        request,
      );
    } on Object {
      return unavailableLinkResult();
    }
  }

  /// Resets the Measurement-owned subject link state explicitly.
  Future<MeasurementSubjectOperationResultV1> resetSubject(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    if (request.action != MeasurementSubjectOperationAction.resetSubject) {
      return _invalidSubjectOperationResult();
    }
    try {
      return await GovernedMeasurementPortRegistry.measurement.resetSubject(
        request,
      );
    } on Object {
      return unavailableSubjectOperationResult();
    }
  }

  /// Withdraws consent for future governed Measurement operations explicitly.
  Future<MeasurementSubjectOperationResultV1> withdrawConsent(
    MeasurementSubjectOperationRequestV1 request,
  ) async {
    if (request.action != MeasurementSubjectOperationAction.withdrawConsent) {
      return _invalidSubjectOperationResult();
    }
    try {
      return await GovernedMeasurementPortRegistry.measurement.withdrawConsent(
        request,
      );
    } on Object {
      return unavailableSubjectOperationResult();
    }
  }
}

MeasurementSubjectOperationResultV1 _invalidSubjectOperationResult() =>
    const MeasurementSubjectOperationResultV1.failed(
      MeasurementLinkFailureV1(code: MeasurementLinkFailureCode.notAllowed),
    );
