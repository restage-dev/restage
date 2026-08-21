// The assembly seam, driven directly.
//
// The parity gate next door proves the seam reaches the SAME verdicts the
// self-contained path reached. It cannot prove anything about a check that has
// no self-contained counterpart — and the shape claim is exactly that: it used
// to be a comparison the delivery service made while it held the bytes, and it
// is now a claim that travels and is checked by the reader. There is nothing
// for parity to compare it to, so it is proven here instead.
//
// Its absence is what makes this file necessary rather than nice: with no case
// setting a claim, every code path through step 4 is skipped and deleting the
// check leaves every suite in the repository green.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  final blob = BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(const <int>[1, 2, 3]),
  );

  SurfaceArtifactDescriptor describing(
    SurfacePayload payload, {
    String? payloadKind,
    String? contentHash,
    int payloadFormatVersion = kSurfaceArtifactPayloadFormatVersion,
  }) =>
      SurfaceArtifactDescriptor(
        payloadFormatVersion: payloadFormatVersion,
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 4,
        publishedAtMicros: DateTime.utc(2026, 8, 13).microsecondsSinceEpoch,
        contentHash: contentHash ?? payload.contentHash,
        artifactUrl: 'https://artifacts.test/artifacts/orgs/1/artifacts/1/'
            '${payload.contentHash}',
        artifactPass: 'v1.k1.4102444800.${'a' * 64}',
        payloadKind: payloadKind,
      );

  group('the routing shape claim', () {
    test('an agreeing claim assembles', () {
      final outcome = assembleSurfaceArtifact(
        descriptor: describing(blob, payloadKind: kBlobPayloadKind),
        artifactBytes: blob.canonicalBytes,
      );
      expect(outcome, isA<SurfaceArtifactAssembled>());
      expect(
        (outcome as SurfaceArtifactAssembled).document.payload.payloadKind,
        kBlobPayloadKind,
      );
    });

    test('a claim that disagrees with the frame refuses the delivery', () {
      // The record says one shape and the bytes are another. That is a record
      // and its payload having diverged, and it is the state that could route a
      // delivery through the wrong arm entirely — so it is refused, not
      // rendered as whichever of the two happens to be read next.
      final outcome = assembleSurfaceArtifact(
        descriptor: describing(blob, payloadKind: kFlowPayloadKind),
        artifactBytes: blob.canonicalBytes,
      );
      expect(outcome, isA<SurfaceArtifactUndecodable>());
      expect(
        (outcome as SurfaceArtifactUndecodable).error.message,
        allOf(contains(kBlobPayloadKind), contains(kFlowPayloadKind)),
        reason: 'the refusal names both the claim and what arrived',
      );
    });

    test('a claim of a shape nothing understands refuses the delivery', () {
      // Not rejected when the description was decoded — a value this build does
      // not recognise has to reach the frame check, or an unrecognised claim
      // would fail as a malformed description instead of as the mismatch it is.
      expect(
        assembleSurfaceArtifact(
          descriptor: describing(blob, payloadKind: 'sculpture'),
          artifactBytes: blob.canonicalBytes,
        ),
        isA<SurfaceArtifactUndecodable>(),
      );
    });

    test('an absent claim checks nothing and assembles', () {
      // The shape-agnostic route makes no claim, and never checked one. A
      // reader that invented a default here would refuse deliveries that are
      // fine.
      expect(
        assembleSurfaceArtifact(
          descriptor: describing(blob),
          artifactBytes: blob.canonicalBytes,
        ),
        isA<SurfaceArtifactAssembled>(),
      );
    });
  });

  group('the order of the seam', () {
    test('the hash is checked before the frame is decoded', () {
      // Bytes that are not the artifact are not decoded at all. Asserted on the
      // OUTCOME TYPE rather than a message: a frame refusal and a content
      // refusal route to different rungs of every resolver's ladder, so which
      // one comes back is the observable difference.
      final outcome = assembleSurfaceArtifact(
        descriptor: describing(
          blob,
          contentHash: 'sha256:${crypto.sha256.convert(const <int>[9])}',
        ),
        artifactBytes: Uint8List.fromList(const <int>[9, 9, 9, 9]),
      );
      expect(outcome, isA<SurfaceArtifactUnavailable>());
      expect(
        (outcome as SurfaceArtifactUnavailable).reason,
        SurfaceArtifactFetchFailure.contentHashMismatch,
      );
    });

    test(
        'a payload format this build cannot read is refused before anything '
        'else', () {
      // Restated inside the seam as well as in the description's codec: a
      // description that reached here some other way must not be the one case
      // that skips the gate.
      final outcome = assembleSurfaceArtifact(
        descriptor: describing(
          blob,
          payloadFormatVersion:
              kMaxSupportedSurfaceArtifactPayloadFormatVersion + 1,
        ),
        artifactBytes: blob.canonicalBytes,
      );
      expect(
        (outcome as SurfaceArtifactUnavailable).reason,
        SurfaceArtifactFetchFailure.unreadableDescription,
      );
    });

    test('content that never arrived carries the reason it did not', () {
      for (final failure in SurfaceArtifactFetchFailure.values) {
        final outcome = assembleSurfaceArtifact(
          descriptor: describing(blob),
          artifactBytes: null,
          fetchFailure: failure,
        );
        expect(
          (outcome as SurfaceArtifactUnavailable).reason,
          failure,
          reason: 'the reported reason is the one the fetch gave',
        );
      }
    });
  });
}
