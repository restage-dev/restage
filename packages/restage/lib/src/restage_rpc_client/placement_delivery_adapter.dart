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

/// Assembles each available row's content from [heldArtifactBytes], then
/// [inlineArtifactBytes], fetching any frame neither holds as verified bytes,
/// all at the same time. A row whose closure cannot be verified is left out.
@internal
Future<PlacementDeliveryArtifacts?> assemblePlacementDeliveryArtifacts(
  PlacementBatchResolvedV1 response, {
  Map<ArtifactIdentityV1, List<int>> heldArtifactBytes = const {},
  Map<ArtifactIdentityV1, List<int>> inlineArtifactBytes = const {},
  Future<Uint8List?> Function(PlacementArtifactReferenceV1 reference)? fetch,
  required bool Function() publicationGuard,
}) async {
  final rows =
      response.decisions.whereType<PlacementBatchAvailableV1>().toList();
  final references = <ArtifactIdentityV1, PlacementArtifactReferenceV1>{
    for (final row in rows)
      for (final reference in row.artifactClosure)
        reference.identity: reference,
  };
  final content = <ArtifactIdentityV1, PlacementBatchArtifactV1>{};
  await Future.wait([
    for (final reference in references.values)
      () async {
        PlacementBatchArtifactV1? verified(List<int>? bytes) {
          if (bytes == null) return null;
          try {
            return _artifactFrom(reference.identity, bytes);
          } on Object {
            // Bytes that do not match their identity are not content.
            return null;
          }
        }

        final artifact = verified(heldArtifactBytes[reference.identity]) ??
            verified(inlineArtifactBytes[reference.identity]) ??
            verified(await fetch?.call(reference));
        if (artifact != null) content[reference.identity] = artifact;
      }(),
  ]);
  if (!publicationGuard()) return null;
  final frames = <ArtifactIdentityV1, Uint8List>{};
  final publications = <DeliveryPublicationReferenceV1, SurfaceDocument>{};
  final documents = <PlacementArtifactReferenceV1, SurfaceDocument>{};
  var expandedBytes = 0;
  for (final row in rows) {
    final int rowBytes;
    try {
      rowBytes = validatePlacementRowContent(row, content);
    } on Object {
      continue;
    }
    if (expandedBytes + rowBytes > kMaximumPlacementExpandedClosureBytes) {
      continue;
    }
    final assembled = <PlacementArtifactReferenceV1, SurfaceDocument>{};
    for (final reference in row.artifactClosure) {
      if (!publicationGuard()) return null;
      final known = documents[reference];
      if (known != null) {
        assembled[reference] = known;
        continue;
      }
      final artifact = content[reference.identity]!;
      final bytes = artifact.bytes.asUnmodifiableView();
      // The frame was verified and decoded when its artifact was built.
      final outcome = await loadSurfaceArtifactIconFonts(
        reference.descriptor.contentHash == artifact.identity.contentHash
            ? assembleDecodedSurfaceArtifact(
                reference.descriptor, artifact.payload)
            : const SurfaceArtifactUnavailable(
                SurfaceArtifactFetchFailure.contentHashMismatch),
      );
      if (!publicationGuard()) return null;
      if (outcome is! SurfaceArtifactAssembled) break;
      assembled[reference] = outcome.document;
      frames[reference.identity] = bytes;
    }
    if (assembled.length != row.artifactClosure.length) continue;
    expandedBytes += rowBytes;
    documents.addAll(assembled);
    for (final entry in assembled.entries) {
      final publication = entry.key.publication;
      if (publication != null) publications[publication] = entry.value;
    }
  }
  return PlacementDeliveryArtifacts(
    Map.unmodifiable(frames),
    Map.unmodifiable(publications),
    Map.unmodifiable(documents),
  );
}

// Each artifact verified from the exact bytes instance it was built from.
final _verifiedArtifacts =
    Expando<PlacementBatchArtifactV1>('placement artifacts');

/// Records [artifact] as verified from exactly [bytes].
@internal
void noteVerifiedArtifact(List<int> bytes, PlacementBatchArtifactV1 artifact) =>
    _verifiedArtifacts[bytes] = artifact;

// The same bytes are verified once; any other bytes are verified in full.
PlacementBatchArtifactV1 _artifactFrom(
    ArtifactIdentityV1 identity, List<int> bytes) {
  final held = _verifiedArtifacts[bytes];
  if (held != null && held.identity == identity) return held;
  return _verifiedArtifacts[bytes] =
      PlacementBatchArtifactV1(identity: identity, bytes: bytes);
}
