import 'package:meta/meta.dart';

import '../measurement/measurement_resolved_publication_provenance.dart';
import '../runtime/restage.dart';
import 'surface_resolution_report.dart';

/// Labels a resolved leaf and safely reports its delivery source.
@internal
T reportSurfaceResolution<T extends Object>(
  String surface,
  T resolved,
  SurfaceResolutionSource source,
) {
  attachMeasurementPublicationBindingReference(
    resolved,
    null,
    surfaceResolutionSource: source,
  );
  final selection = routingSelectionProvenanceFor(resolved);
  try {
    Restage.configuredSurfaceResolutionCallback?.call(
      SurfaceResolutionReport(
        surface: surface,
        source: source,
        selectedRouteId: selection?.selectedRouteId,
        audienceRevisionRef: selection?.audienceRevisionRef,
        routingRevisionOrdinal: selection?.routingRevisionOrdinal,
        rolloutAllocationId: selection?.rolloutAllocationId,
        rolloutBranch: selection?.rolloutBranch,
        defaultSelectionReason: selection?.defaultSelectionReason,
      ),
    );
  } on Object {
    // A host's reporting callback never fails a resolution.
  }
  return resolved;
}
