import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CanonicalSurfaceExperimentAssignmentV1,
        SurfaceRoutingSelectionProvenanceV1;

import '../resolver/surface_resolution_report.dart';
import 'placement_mount_attribution.dart' show resolvedPlacementDeliveryFor;

final Expando<SurfaceResolutionSource> _resolvedSurfaceResolutionSources =
    Expando<SurfaceResolutionSource>('restage.resolvedSurfaceResolutionSource');

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

final Expando<String> _resolvedRegistrationFingerprints = Expando<String>(
  'restage.measurement.resolvedRegistrationFingerprint',
);
final Expando<String> _assignmentRegistrationFingerprints = Expando<String>(
  'restage.measurement.assignmentRegistrationFingerprint',
);

/// Captures the serve lease beside the exact assignment object before delivery.
@internal
void stampAssignmentRegistrationFingerprint(
  CanonicalSurfaceExperimentAssignmentV1 assignment,
  String fingerprint,
) {
  final existing = _assignmentRegistrationFingerprints[assignment];
  if (existing != null && existing != fingerprint) {
    throw StateError('An assignment cannot be rebound to a registration.');
  }
  _assignmentRegistrationFingerprints[assignment] = fingerprint;
}

final Expando<String> _resolvedRoutingSelectionReceipts = Expando<String>(
  'restage.measurement.resolvedRoutingSelectionReceipt',
);

final Expando<SurfaceRoutingSelectionProvenanceV1>
    _resolvedRoutingSelectionProvenance =
    Expando<SurfaceRoutingSelectionProvenanceV1>(
        'restage.resolvedRoutingSelectionProvenance');

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
  String? registrationFingerprint,
  String? routingSelectionReceipt,
  SurfaceRoutingSelectionProvenanceV1? routingSelectionProvenance,
  SurfaceResolutionSource? surfaceResolutionSource,
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
  registrationFingerprint ??= canonicalExperimentAssignment == null
      ? null
      : _assignmentRegistrationFingerprints[canonicalExperimentAssignment];
  final existingFingerprint = _resolvedRegistrationFingerprints[resolved];
  if (registrationFingerprint != null &&
      ((canonicalExperimentAssignment == null &&
              resolvedPlacementDeliveryFor(resolved)?.assignment == null) ||
          existingFingerprint != null &&
              existingFingerprint != registrationFingerprint)) {
    throw StateError('A resolved payload cannot be rebound to a registration.');
  }
  final existingReceipt = _resolvedRoutingSelectionReceipts[resolved];
  if (routingSelectionReceipt != null &&
      existingReceipt != null &&
      existingReceipt != routingSelectionReceipt) {
    throw StateError(
      'A resolved payload cannot be rebound to a different routing selection receipt.',
    );
  }
  final existingSelection = _resolvedRoutingSelectionProvenance[resolved];
  if (routingSelectionProvenance != null &&
      existingSelection != null &&
      existingSelection != routingSelectionProvenance) {
    throw StateError(
        'A resolved payload cannot be rebound to different selection provenance.');
  }
  if (routingSelectionProvenance != null) {
    _resolvedRoutingSelectionProvenance[resolved] = routingSelectionProvenance;
  }
  if (reference != null) {
    _resolvedPublicationBindingReferences[resolved] = reference;
  }
  if (canonicalExperimentAssignment != null) {
    _resolvedExperimentAssignments[resolved] = canonicalExperimentAssignment;
  }
  if (registrationFingerprint != null) {
    _resolvedRegistrationFingerprints[resolved] = registrationFingerprint;
  }
  if (routingSelectionReceipt != null) {
    _resolvedRoutingSelectionReceipts[resolved] = routingSelectionReceipt;
  }
  // Source may change when a fresh payload is re-emitted as held.
  if (surfaceResolutionSource != null) {
    _resolvedSurfaceResolutionSources[resolved] = surfaceResolutionSource;
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

/// Returns the exact local registration identity captured with the assignment.
@internal
String? measurementRegistrationFingerprintFor(Object resolved) =>
    _resolvedRegistrationFingerprints[resolved];

/// Returns the exact opaque receipt delivered with [resolved], if any.
@internal
String? routingSelectionReceiptFor(Object resolved) =>
    _resolvedRoutingSelectionReceipts[resolved];

/// Returns where the resolved payload's content came from, if labelled.
@internal
SurfaceResolutionSource? surfaceResolutionSourceFor(Object resolved) =>
    _resolvedSurfaceResolutionSources[resolved];

/// Returns the selection provenance delivered with [resolved], if any.
@internal
SurfaceRoutingSelectionProvenanceV1? routingSelectionProvenanceFor(
        Object resolved) =>
    _resolvedRoutingSelectionProvenance[resolved];
