/// The one place a delivered surface is put back together.
///
/// Delivery arrives in two halves now: a small description of the artifact, and
/// the artifact itself, fetched separately. Joining them is the only step in
/// the SDK that can turn "some bytes arrived" into "a surface this build is
/// willing to render", so it is written once and every caller goes through it.
///
/// The order is the contract:
///
///   1. **Both version domains are gated before anything else** — before the
///      fetch, not just before the decode. A build that does not understand the
///      description has no business spending a request on bytes it could not
///      read, and no business acting on a shape it half-recognises. The gate
///      lives in the description's own strict codec, which is the only way one
///      arrives off the wire, so it has already run by the time the fetch is
///      considered. It is restated here anyway, because a description that
///      reached this function some other way must not be the one case that
///      skips it.
///   2. **The bytes are hashed and compared to what the description said they
///      would be.** Bytes that are not the artifact are not the artifact,
///      whatever served them.
///   3. **The frame is decoded strictly**, at the strictness the payload format
///      calls for — so a frame whose capability section has been stripped fails
///      rather than reading as "requires nothing".
///   4. **The record's shape claim, if it made one, is checked against the kind
///      the frame declares.**
///   5. The document is assembled, with the capability facts read from the
///      FRAME, never from the description. They are covered by the content
///      hash there; a second copy alongside could only agree or disagree, and
///      this design removes the disagreement by not carrying one.
///
/// What the description can no longer do is state a capability floor or a
/// library requirement that differs from the hashed one. That was a real class
/// of tampering and it is now unrepresentable rather than merely rejected.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

/// What the artifact half of one delivery produced.
@internal
sealed class SurfaceArtifactOutcome {
  const SurfaceArtifactOutcome();
}

/// The artifact was fetched, verified, decoded, and assembled.
@internal
final class SurfaceArtifactAssembled extends SurfaceArtifactOutcome {
  /// Creates an assembled outcome.
  const SurfaceArtifactAssembled(this.document);

  /// The surface document, exactly as a self-contained delivery would have
  /// produced.
  final SurfaceDocument document;
}

/// No artifact arrived, or what arrived was not it.
///
/// The caller's existing "nothing came back" path, unchanged: every resolver
/// already has one and it is the fail-safe rung.
@internal
final class SurfaceArtifactUnavailable extends SurfaceArtifactOutcome {
  /// Creates an unavailable outcome.
  const SurfaceArtifactUnavailable(this.reason);

  /// Why the artifact did not arrive. Carried for evidence, never for a
  /// decision — every reason funnels to the same fallback.
  final SurfaceArtifactFetchFailure reason;
}

/// The artifact arrived and would not decode into something renderable.
///
/// Distinct from [SurfaceArtifactUnavailable] because it always has been: a
/// caller that reports "could not read the content" for a delivery that never
/// arrived tells its host the wrong thing.
@internal
final class SurfaceArtifactUndecodable extends SurfaceArtifactOutcome {
  /// Creates an undecodable outcome.
  const SurfaceArtifactUndecodable(this.error);

  /// The refusal, worded by whichever gate refused.
  final FormatException error;
}

/// Why an artifact fetch produced nothing usable.
///
/// A closed set because it is reported: an open string would grow a value per
/// call site and stop being comparable.
@internal
enum SurfaceArtifactFetchFailure {
  /// The description itself was of a version or shape this build cannot read.
  unreadableDescription('unreadable_description'),

  /// The request did not complete.
  transport('transport'),

  /// The store refused the request — typically an expired or wrong pass.
  refused('refused'),

  /// The store answered, but not with the artifact.
  status('status'),

  /// Bytes arrived and are not the ones the description named.
  contentHashMismatch('content_hash_mismatch');

  const SurfaceArtifactFetchFailure(this.wireName);

  /// Stable name for reporting.
  final String wireName;
}

/// Verifies, decodes and assembles one delivered artifact.
///
/// [artifactBytes] is null when the fetch itself did not produce bytes; the
/// caller passes [fetchFailure] to say why.
@internal
SurfaceArtifactOutcome assembleSurfaceArtifact({
  required SurfaceArtifactDescriptorV1 descriptor,
  required Uint8List? artifactBytes,
  SurfaceArtifactFetchFailure fetchFailure =
      SurfaceArtifactFetchFailure.transport,
}) {
  if (descriptor.payloadFormatVersion >
      kMaxSupportedSurfaceArtifactPayloadFormatVersion) {
    return const SurfaceArtifactUnavailable(
      SurfaceArtifactFetchFailure.unreadableDescription,
    );
  }
  if (artifactBytes == null) {
    return SurfaceArtifactUnavailable(fetchFailure);
  }

  // Step 2. Not a formality: everything after this point treats the bytes as
  // the publisher's, and this is the only thing that makes that true.
  final actual = 'sha256:${crypto.sha256.convert(artifactBytes)}';
  if (actual != descriptor.contentHash) {
    return const SurfaceArtifactUnavailable(
      SurfaceArtifactFetchFailure.contentHashMismatch,
    );
  }

  final SurfacePayload payload;
  try {
    // Step 3. The strictness comes from the PAYLOAD format version, translated
    // once in the shared contract — reading it off the document envelope's
    // version would be reading one version domain as another.
    payload = SurfacePayload.decode(
      artifactBytes,
      requireRequiredLibraries: surfaceArtifactFrameRequiresManifest(
        descriptor.payloadFormatVersion,
      ),
    );
  } on FormatException catch (error) {
    return SurfaceArtifactUndecodable(error);
  }

  // Step 4. The publication record can claim which shape it routed on. When it
  // did, the claim and the bytes have to agree — a record whose discriminator
  // disagrees with its own payload could route a delivery through the wrong
  // arm entirely. Absent claim, no check: the shape-agnostic route never made
  // one and never checked one.
  final claimed = descriptor.payloadKind;
  if (claimed != null && payload.payloadKind != claimed) {
    return SurfaceArtifactUndecodable(
      FormatException(
        'Invalid surface payload: the delivered payload kind '
        '"${payload.payloadKind}" disagrees with the record\'s "$claimed".',
      ),
    );
  }

  try {
    return SurfaceArtifactAssembled(
      SurfaceDocument(
        surfaceType: descriptor.surfaceType,
        surfaceSlug: descriptor.surfaceSlug,
        version: descriptor.version,
        // Step 5. Both read off the frame, which is what the content hash
        // covers. There is no second copy to disagree with.
        minClient: payload.minClient,
        requiredLibraries: payload.requiredLibraries,
        payload: payload,
        publishedAt: descriptor.publishedAt,
      ),
    );
  } on ArgumentError catch (error) {
    // The document's own construction checks are unchanged and still run. They
    // cannot fail on the values passed above, which all come from one source —
    // but "cannot" is a claim about today's field list, and a silent throw out
    // of an assembly seam is a crash in a resolver.
    return SurfaceArtifactUndecodable(
      FormatException('Invalid surface payload: ${error.message}'),
    );
  }
}
