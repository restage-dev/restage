import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

/// Transported length of [byteLength] raw bytes carried as one base64 field.
int _framedLength(int byteLength) => ((byteLength + 2) ~/ 3) * 4;

/// Transported length of a byte closure split across [fieldCount] fields, each
/// of which may pad independently.
int _framedClosureLength(int byteLength, {required int fieldCount}) =>
    _framedLength(byteLength + 2 * fieldCount);

/// One artifact element costs its braces, type marker, keys, separators, and
/// the `decode('<base64>', 'base64')` wrapper the transport puts around its
/// byte field.
const int _artifactElementChars = 104;

/// The five top-level keys, their wrappers and separators, and the request
/// envelope around them.
const int _requestEnvelopeChars = 4096;

/// A declared artifact path admits quotes and control characters, each of which
/// escapes to six characters as a JSON string.
const int _pathEscapeFactor = 6;

void main() {
  group('candidate bounds derive from the stored proof and the transport', () {
    test('the framing arithmetic matches a real base64 encoding', () {
      for (final byteLength in [1, 2, 3, 4, 541, 1000, 4096]) {
        expect(
          _framedLength(byteLength),
          base64.encode(List<int>.filled(byteLength, 7)).length,
          reason: 'framing must match the encoder for $byteLength bytes',
        );
      }
    });

    test('the transport frames a byte field the way this test models it', () {
      // The transport does not send raw base64: it wraps every byte field.
      const sample = [1, 2, 3];
      final wrapped = "decode('${base64.encode(sample)}', 'base64')";
      expect(wrapped.length - base64.encode(sample).length, 20);
      expect(_artifactElementChars, greaterThan(20));
    });

    test('every bound at its maximum fits one request with headroom', () {
      final framedUpload = _framedLength(
        kMaximumMeasurementPublicationCandidateUploadBytes,
      );
      final framedManifest = _framedLength(
        kMaximumMeasurementPublicationCandidateManifestBytes,
      );
      // Declared artifact bytes are bounded by the upload they were assembled
      // from, and arrive split across one field per artifact.
      final framedArtifactBytes = _framedClosureLength(
        kMaximumMeasurementPublicationCandidateUploadBytes,
        fieldCount: kMaximumMeasurementPublicationCandidateArtifactTupleCount,
      );
      final framedDraft = _framedLength(
        kMaximumMeasurementPublicationCandidateDraftBytes,
      );
      final framedReference = _framedLength(
        MeasurementPublicationCandidateReferenceV1.canonicalByteLength,
      );
      const escapedPaths =
          kMaximumMeasurementPublicationCandidateArtifactClosureBytes *
              _pathEscapeFactor;
      const structural =
          kMaximumMeasurementPublicationCandidateArtifactTupleCount *
                  _artifactElementChars +
              _requestEnvelopeChars;

      expect(framedUpload, 5592408);
      expect(framedManifest, 699052);
      expect(framedArtifactBytes, 5595136);
      expect(framedDraft, 9786712);
      expect(framedReference, 724);
      expect(escapedPaths, 3145728);
      expect(structural, 110592);

      final transported = framedUpload +
          framedManifest +
          framedArtifactBytes +
          framedDraft +
          framedReference +
          escapedPaths +
          structural;

      expect(transported, 24930352);
      expect(
        transported,
        lessThan(kMeasurementPublicationCandidateTransportBytes),
      );
      expect(
        kMeasurementPublicationCandidateTransportBytes - transported,
        greaterThan(kMeasurementPublicationCandidateTransportBytes ~/ 4),
        reason: 'a quarter of the request must stay free',
      );
    });

    test('the stored proof ceiling binds before the transport does', () {
      expect(
        kMeasurementPublicationCandidateStoredProofCeilingBytes,
        lessThan(kMeasurementPublicationCandidateTransportBytes),
      );
      expect(
        kMaximumMeasurementPublicationCandidateProofBytes,
        kMaximumMeasurementPublicationCandidateManifestBytes +
            kMaximumMeasurementPublicationCandidateUploadBytes +
            kMaximumMeasurementPublicationCandidateArtifactClosureBytes +
            kMaximumMeasurementPublicationCandidateDraftBytes,
      );
      expect(
        kMaximumMeasurementPublicationCandidateDraftBytes,
        greaterThan(kMaximumMeasurementPublicationCandidateUploadBytes),
      );
    });

    test('a bundled registry admits one entry at every maximum', () {
      // A registry entry embeds the draft as canonical JSON and
      // base64url-frames the opaque closure beside it.
      final entryBytes = kMaximumMeasurementPublicationCandidateDraftBytes +
          _framedLength(kMaximumMeasurementPublicationCandidateUploadBytes) +
          _framedLength(kMaximumMeasurementPublicationCandidateManifestBytes) +
          _framedClosureLength(
            kMaximumMeasurementPublicationCandidateArtifactClosureBytes,
            fieldCount:
                kMaximumMeasurementPublicationCandidateArtifactTupleCount,
          ) +
          kMaximumMeasurementPublicationCandidateArtifactTupleCount * 96 +
          _requestEnvelopeChars;

      expect(entryBytes, lessThan(15 * 1024 * 1024));
      expect(
        entryBytes,
        lessThan(kMaximumMeasurementPublicationBundledRegistryBytes),
      );
    });
  });
}
