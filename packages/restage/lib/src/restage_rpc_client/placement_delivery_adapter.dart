import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_artifact_assembly.dart';

final _assembledPlacements = Expando<PlacementDeliveryArtifacts>();

@internal
PlacementDeliveryArtifacts? placementArtifactsFor(
  PlacementBatchResolvedV1 response,
) =>
    _assembledPlacements[response];

@internal
void attachPlacementArtifacts(
  PlacementBatchResolvedV1 response,
  PlacementDeliveryArtifacts artifacts,
) {
  _assembledPlacements[response] = artifacts;
}

/// Verified whole frames and the publications assembled from those frames.
@internal
final class PlacementDeliveryArtifacts {
  PlacementDeliveryArtifacts(this.frames, this.publications, this.documents);

  final Map<ArtifactIdentityV1, Uint8List> frames;
  final Map<DeliveryPublicationReferenceV1, SurfaceDocument> publications;
  final Map<PlacementArtifactReferenceV1, SurfaceDocument> documents;
}

/// Assembles complete transferred or held content without fetching any bytes.
@internal
Future<PlacementDeliveryArtifacts?> assemblePlacementDeliveryArtifacts(
  PlacementBatchResolvedV1 response, {
  Map<ArtifactIdentityV1, List<int>> heldArtifactBytes = const {},
  required bool Function() publicationGuard,
}) async {
  final frames = <ArtifactIdentityV1, Uint8List>{
    for (final artifact in response.artifacts)
      artifact.identity: artifact.bytes.asUnmodifiableView(),
  };
  final publications = <DeliveryPublicationReferenceV1, SurfaceDocument>{};
  final documents = <PlacementArtifactReferenceV1, SurfaceDocument>{};
  for (final entry
      in response.decisions.whereType<PlacementBatchAvailableV1>()) {
    for (final reference in entry.artifactClosure) {
      if (!publicationGuard()) return null;
      if (documents.containsKey(reference)) continue;
      final bytes = frames[reference.identity] ??=
          heldArtifactBytes[reference.identity] == null
              ? Uint8List(0)
              : Uint8List.fromList(
                  heldArtifactBytes[reference.identity]!,
                ).asUnmodifiableView();
      if (bytes.isEmpty) return null;
      final outcome = await loadSurfaceArtifactIconFonts(
        assembleSurfaceArtifact(
          descriptor: reference.descriptor,
          artifactBytes: bytes,
        ),
      );
      if (!publicationGuard() || outcome is! SurfaceArtifactAssembled) {
        return null;
      }
      documents[reference] = outcome.document;
      final publication = reference.publication;
      if (publication != null) publications[publication] = outcome.document;
    }
  }
  return PlacementDeliveryArtifacts(
    Map.unmodifiable(frames),
    Map.unmodifiable(publications),
    Map.unmodifiable(documents),
  );
}
