import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../delivery/surface_delivery_receipt.dart';
import '../delivery/surface_delivery_receipt_batch.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../measurement/placement_mount_attribution.dart';
import '../runtime/restage.dart';
import 'surface_resolution_report.dart';

/// Labels a resolved leaf, reports its closed identity and source, and opens
/// its delivery receipt; [reason] says why a held or bundled copy was served.
@internal
T reportSurfaceResolution<T extends Object>(
  Surface surfaceType,
  String surface,
  T resolved,
  SurfaceResolutionSource source, {
  SurfaceDeliveryReceiptReason reason = SurfaceDeliveryReceiptReason.none,
  String? reportReason,
}) {
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
        surfaceType: surfaceType,
        source: source,
        reason: reportReason,
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
  try {
    attachSurfaceDeliveryReceipt(
      resolved,
      SurfaceDeliveryReceiptBatch.instance.open(
        surfaceType: surfaceType,
        surfaceSlug: surface,
        publishedVersion: surfaceDeliveryPublishedVersionOf(resolved),
        source: source,
        reason: reason,
        routeId: selection?.selectedRouteId ?? '',
        recordAsLatest: resolvedPlacementDeliveryFor(resolved) == null,
      ),
    );
  } on Object {
    // A receipt never fails a resolution.
  }
  return resolved;
}

/// Reports the server [reason] for a mount that showed [source] content.
@internal
void reportSurfaceFallback(Surface surfaceType, String surface,
    {required String reason,
    SurfaceResolutionSource source = SurfaceResolutionSource.bundled}) {
  try {
    Restage.configuredSurfaceResolutionCallback?.call(SurfaceResolutionReport(
      surface: surface,
      surfaceType: surfaceType,
      source: source,
      reason: reason,
    ));
  } on Object {
    // A host's reporting callback never fails a resolution.
  }
}
