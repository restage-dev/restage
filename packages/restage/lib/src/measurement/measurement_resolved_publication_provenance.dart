import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart'
    show CanonicalSurfaceExperimentAssignmentV1;

final Expando<MeasurementPublicationBindingReferenceV1>
    _resolvedPublicationBindingReferences =
    Expando<MeasurementPublicationBindingReferenceV1>(
  'restage.measurement.resolvedPublicationBindingReference',
);

final Expando<CanonicalSurfaceExperimentAssignmentV1>
    _resolvedExperimentAssignments =
    Expando<CanonicalSurfaceExperimentAssignmentV1>(
  'restage.measurement.resolvedExperimentAssignment',
);

/// Attaches immutable Measurement provenance to one SDK-resolved payload.
///
/// This stays outside the public resolver-result API. It is read only by the
/// later SDK host-composition seam after it has received an already validated
/// hosted payload.
@internal
T attachMeasurementPublicationBindingReference<T extends Object>(
  T resolved,
  MeasurementPublicationBindingReferenceV1? reference, {
  CanonicalSurfaceExperimentAssignmentV1? canonicalExperimentAssignment,
}) {
  final existing = _resolvedPublicationBindingReferences[resolved];
  if (reference != null && existing != null && existing != reference) {
    throw StateError(
      'A resolved payload cannot be rebound to different Measurement provenance.',
    );
  }
  final existingAssignment = _resolvedExperimentAssignments[resolved];
  if (canonicalExperimentAssignment != null &&
      existingAssignment != null &&
      existingAssignment != canonicalExperimentAssignment) {
    throw StateError(
      'A resolved payload cannot be rebound to a different experiment assignment.',
    );
  }
  if (reference != null) {
    _resolvedPublicationBindingReferences[resolved] = reference;
  }
  if (canonicalExperimentAssignment != null) {
    _resolvedExperimentAssignments[resolved] = canonicalExperimentAssignment;
  }
  return resolved;
}

/// Returns the exact immutable Measurement provenance attached to [resolved].
///
/// A null result is a closed no-Measurement outcome for that payload. Callers
/// must never derive a replacement from identity, bytes, or active state.
@internal
MeasurementPublicationBindingReferenceV1?
    measurementPublicationBindingReferenceFor(Object resolved) =>
        _resolvedPublicationBindingReferences[resolved];

/// Returns the exact assignment delivered with [resolved], if any.
@internal
CanonicalSurfaceExperimentAssignmentV1? measurementExperimentAssignmentFor(
  Object resolved,
) =>
    _resolvedExperimentAssignments[resolved];
