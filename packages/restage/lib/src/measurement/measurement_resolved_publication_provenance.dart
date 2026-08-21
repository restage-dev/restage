import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

final Expando<MeasurementPublicationBindingReferenceV1>
    _resolvedPublicationBindingReferences =
    Expando<MeasurementPublicationBindingReferenceV1>(
  'restage.measurement.resolvedPublicationBindingReference',
);

/// Attaches immutable Measurement provenance to one SDK-resolved payload.
///
/// This stays outside the public resolver-result API. It is read only by the
/// later SDK host-composition seam after it has received an already validated
/// hosted payload.
@internal
T attachMeasurementPublicationBindingReference<T extends Object>(
  T resolved,
  MeasurementPublicationBindingReferenceV1? reference,
) {
  if (reference == null) return resolved;
  final existing = _resolvedPublicationBindingReferences[resolved];
  if (existing != null && existing != reference) {
    throw StateError(
      'A resolved payload cannot be rebound to different Measurement provenance.',
    );
  }
  _resolvedPublicationBindingReferences[resolved] = reference;
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
