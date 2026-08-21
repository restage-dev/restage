// The shared corpus behind the delivery-path parity gate.
//
// One set of inputs, evaluated two ways, asserted to reach the same verdict:
//
//   * the SELF-CONTAINED path — the whole document arrives inline, header and
//     payload frame concatenated, and the shared codec decodes the pair;
//   * the SPLIT path — a small metadata descriptor arrives inline and the
//     payload frame is fetched separately, then the two are assembled.
//
// The split path is the one being built. The self-contained path is the one
// whose fail-closed behaviour is already trusted, so it is the reference: every
// case below is evaluated through it and the verdict is written down as a
// literal in the accompanying test. A later change that alters BOTH evaluators
// in the same direction still fails, because the literals do not move with them.
//
// Deliberately NOT a golden-bytes corpus. What must stay identical is the
// VERDICT — accepted with these assembled facts, or rejected at this stage —
// not the wire spelling, which is exactly what the split path changes.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

/// Where a delivered surface was refused.
///
/// The vocabulary is deliberately about MEANING rather than about which
/// function threw, because the two paths reach the same meanings through
/// different code. A verdict that cannot be classified is [unclassified], which
/// the parity test treats as a failure — an unrecognised rejection is a gap in
/// this instrument, never something to wave through.
enum ParityStage {
  /// The declared content hash did not match the bytes that arrived.
  contentHash,

  /// The payload frame itself was malformed: unknown kind, truncated, trailing
  /// bytes, a non-canonical requirement section, or an internally inconsistent
  /// flow closure.
  payloadFrame,

  /// The document that arrived is not the surface that was asked for.
  identity,

  /// The document decoded, but this build cannot faithfully render it.
  capability,

  /// The metadata envelope/descriptor was itself unreadable or of a version
  /// this build does not understand.
  metadata,

  /// Reached no known classification. Always a test failure.
  unclassified,
}

/// The verdict one evaluator reached for one case.
sealed class ParityOutcome {
  const ParityOutcome();
}

/// The surface was accepted, with these assembled facts.
///
/// The facts are compared field by field, not just "accepted", because a path
/// that accepts the right case while assembling the wrong document has not
/// achieved parity — it has hidden a defect behind a boolean.
final class ParityAccepted extends ParityOutcome {
  const ParityAccepted({
    required this.payloadKind,
    required this.minClient,
    required this.requiredLibraries,
    required this.version,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.publishedAtMicros,
    required this.contentHash,
    required this.canonicalBytesDigest,
  });

  final String payloadKind;
  final int minClient;

  /// Rendered `namespace@minVersion`, in assembled order.
  final List<String> requiredLibraries;
  final int version;
  final String surfaceType;
  final String surfaceSlug;
  final int publishedAtMicros;
  final String contentHash;

  /// SHA-256 of the payload's canonical bytes as RE-DERIVED from the decoded
  /// parts — not of the bytes that arrived. Re-deriving is the point: it proves
  /// the decode reconstituted the same structure rather than merely copying a
  /// buffer through.
  final String canonicalBytesDigest;

  @override
  bool operator ==(Object other) =>
      other is ParityAccepted &&
      other.payloadKind == payloadKind &&
      other.minClient == minClient &&
      _listEquals(other.requiredLibraries, requiredLibraries) &&
      other.version == version &&
      other.surfaceType == surfaceType &&
      other.surfaceSlug == surfaceSlug &&
      other.publishedAtMicros == publishedAtMicros &&
      other.contentHash == contentHash &&
      other.canonicalBytesDigest == canonicalBytesDigest;

  @override
  int get hashCode => Object.hash(
        payloadKind,
        minClient,
        Object.hashAll(requiredLibraries),
        version,
        surfaceType,
        surfaceSlug,
        publishedAtMicros,
        contentHash,
        canonicalBytesDigest,
      );

  @override
  String toString() => 'accepted('
      'kind: $payloadKind, minClient: $minClient, '
      'libs: $requiredLibraries, v$version, '
      '$surfaceType/$surfaceSlug, at: $publishedAtMicros, '
      'hash: ${_short(contentHash)}, canonical: ${_short(canonicalBytesDigest)})';
}

/// The surface was refused at [stage].
final class ParityRejected extends ParityOutcome {
  const ParityRejected(this.stage, {this.diagnostic = ''});

  final ParityStage stage;

  /// Carried for the failure message only. NOT part of equality: the two paths
  /// legitimately word the same refusal differently, and pinning prose would
  /// make this instrument fail on a comment change.
  final String diagnostic;

  @override
  bool operator ==(Object other) =>
      other is ParityRejected && other.stage == stage;

  @override
  int get hashCode => stage.hashCode;

  @override
  String toString() => 'rejected(${stage.name})'
      '${diagnostic.isEmpty ? '' : ' — $diagnostic'}';
}

/// One input, plus everything both evaluators need to judge it.
final class ParityCase {
  ParityCase({
    required this.name,
    required this.artifactBytes,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.version,
    required this.publishedAt,
    required this.installed,
    String? declaredContentHash,
    Surface? requestedSurfaceType,
    String? requestedSlug,
  })  : declaredContentHash =
            declaredContentHash ?? contentHashOf(artifactBytes),
        requestedSurfaceType = requestedSurfaceType ?? surfaceType,
        requestedSlug = requestedSlug ?? surfaceSlug;

  final String name;

  /// The payload frame: what the store hands back on the split path, and what
  /// rides after the header on the self-contained one. The SAME bytes in both,
  /// which is what makes the comparison meaningful.
  final Uint8List artifactBytes;

  /// What the metadata CLAIMS the bytes hash to. Defaults to the truth; a case
  /// that is probing the hash gate overrides it.
  final String declaredContentHash;

  final Surface surfaceType;
  final String surfaceSlug;
  final int version;
  final DateTime publishedAt;

  /// The identity the caller asked for. Differs from [surfaceType] /
  /// [surfaceSlug] only in the substitution cases.
  final Surface requestedSurfaceType;
  final String requestedSlug;

  /// The capability this build presents to the render gate.
  final InstalledCapability installed;

  @override
  String toString() => name;
}

/// SHA-256 in the repo's canonical `sha256:<64 lowercase hex>` spelling.
String contentHashOf(List<int> bytes) =>
    'sha256:${crypto.sha256.convert(bytes)}';

/// Evaluates one case through the SELF-CONTAINED path: build the inline
/// document exactly as the delivery service builds it today, hand it to the
/// shared codec, then run the identity and capability gates a resolver runs.
///
/// The header is assembled by hand rather than through the encoder because the
/// encoder derives the content hash from the payload, and a corpus that cannot
/// state a hash the bytes do not have cannot probe the hash gate at all.
ParityOutcome evaluateSelfContained(ParityCase testCase) {
  final Uint8List envelope;
  try {
    envelope = _handBuildEnvelope(testCase);
  } on Object catch (error) {
    return ParityRejected(
      ParityStage.unclassified,
      diagnostic: 'could not build the inline document: $error',
    );
  }

  final SurfaceDocument document;
  try {
    document = SurfaceDocumentCodec.decode(envelope);
  } on FormatException catch (error) {
    return ParityRejected(
      classifyRejection(error.message),
      diagnostic: error.message,
    );
  }
  return gateAssembledDocument(document, testCase);
}

/// Evaluates one case through the SPLIT path: a metadata descriptor arrives
/// inline, the payload frame arrives from a store, and the seam joins them.
///
/// The descriptor is built by hand for the same reason the inline header is:
/// a descriptor produced by the encoder would derive its content hash from the
/// bytes, and a corpus that cannot state a hash the bytes do not have cannot
/// probe the hash gate at all.
///
/// It calls the seam the shipping client calls, with the same arguments, in the
/// same order — the client adds the fetch in front and the ladder behind, and
/// neither of those is what this compares.
ParityOutcome evaluateSplitPath(ParityCase testCase) {
  final SurfaceArtifactDescriptor descriptor;
  try {
    descriptor = SurfaceArtifactDescriptor(
      payloadFormatVersion: kSurfaceArtifactPayloadFormatVersion,
      surfaceType: testCase.surfaceType,
      surfaceSlug: testCase.surfaceSlug,
      version: testCase.version,
      publishedAtMicros: testCase.publishedAt.toUtc().microsecondsSinceEpoch,
      contentHash: testCase.declaredContentHash,
      artifactUrl: 'https://artifacts.invalid/artifacts/$_corpusObjectKey',
      artifactPass: 'v1.k1.4102444800.${'a' * 64}',
    );
  } on Object catch (error) {
    return ParityRejected(
      ParityStage.unclassified,
      diagnostic: 'could not build the delivery description: $error',
    );
  }

  final outcome = assembleSurfaceArtifact(
    descriptor: descriptor,
    artifactBytes: testCase.artifactBytes,
  );
  switch (outcome) {
    case SurfaceArtifactAssembled(:final document):
      return gateAssembledDocument(document, testCase);
    case SurfaceArtifactUndecodable(:final error):
      return ParityRejected(
        classifyRejection(error.message),
        diagnostic: error.message,
      );
    case SurfaceArtifactUnavailable(:final reason):
      // The seam reports "the bytes are not the artifact" as a fetch outcome
      // rather than as a decode refusal, because that is what it is and it is
      // what routes it onto the client's fallback rung. The MEANING is the same
      // refusal the inline path words as a hash mismatch, and the meaning is
      // what this instrument compares.
      return switch (reason) {
        SurfaceArtifactFetchFailure.contentHashMismatch => const ParityRejected(
            ParityStage.contentHash,
            diagnostic: 'content hash mismatch',
          ),
        SurfaceArtifactFetchFailure.unreadableDescription =>
          const ParityRejected(
            ParityStage.metadata,
            diagnostic: 'the delivery description was unreadable',
          ),
        _ => ParityRejected(
            ParityStage.unclassified,
            diagnostic: 'the seam reported ${reason.wireName} for bytes this '
                'corpus handed it directly',
          ),
      };
  }
}

/// A syntactically real object key. Nothing fetches it; it exists so the
/// descriptor under test is shaped like one that travelled.
const String _corpusObjectKey = 'orgs/1/artifacts/1/sha256:'
    '0000000000000000000000000000000000000000000000000000000000000000';

/// The identity + capability gates every resolver applies to an assembled
/// document, factored out so BOTH evaluators run the identical code for the
/// part of the chain that is genuinely shared. Only the steps ahead of this —
/// obtaining and decoding the bytes — differ between the two paths.
ParityOutcome gateAssembledDocument(
  SurfaceDocument document,
  ParityCase testCase,
) {
  if (document.surfaceType != testCase.requestedSurfaceType ||
      document.surfaceSlug != testCase.requestedSlug) {
    return const ParityRejected(
      ParityStage.identity,
      diagnostic: 'served a surface other than the one requested',
    );
  }
  final verdict = BlobRenderCapabilityGate.evaluate(
    required: CapabilityManifest(
      builtInFloor: document.minClient,
      requiredLibraries: document.requiredLibraries,
    ),
    installed: testCase.installed,
  );
  if (verdict is BlobRenderRejected) {
    return ParityRejected(
      ParityStage.capability,
      diagnostic: verdict.message,
    );
  }
  final payload = document.payload;
  return ParityAccepted(
    payloadKind: payload.payloadKind,
    minClient: document.minClient,
    requiredLibraries: [
      for (final requirement in document.requiredLibraries)
        '${requirement.namespace}@${requirement.minVersion}',
    ],
    version: document.version,
    surfaceType: document.surfaceType.wireName,
    surfaceSlug: document.surfaceSlug,
    publishedAtMicros: document.publishedAt.toUtc().microsecondsSinceEpoch,
    contentHash: document.contentHash,
    canonicalBytesDigest: contentHashOf(payload.canonicalBytes),
  );
}

/// Maps a refusal message onto the shared vocabulary.
///
/// Substring matching on messages this repo owns, ordered most-specific first.
/// Anything unmatched becomes [ParityStage.unclassified] rather than being
/// bucketed by proximity — a classifier that guesses would let a real
/// divergence pass as a match.
ParityStage classifyRejection(String message) {
  const hash = <String>['content hash mismatch'];
  const metadata = <String>[
    'Unsupported surface envelope format version',
    'Unsupported header field',
    'envelope is missing the "requiredLibraries" header',
    'header requires format version',
    'Missing required header field',
    'Header field',
    'header must be an object',
    'Expected "',
    'Header minClient does not match the payload',
    'Header requiredLibraries do not match the payload',
    'Unsupported artifact descriptor version',
    'Unsupported payload format version',
  ];
  const frame = <String>[
    'Unsupported surface payload kind',
    'Truncated ',
    'Unexpected trailing payload bytes',
    'payload is missing its required-libraries section',
    'requiredLibraries must be strictly ascending',
    'requiredLibrary namespace must not be empty',
    'requiredLibrary minVersion must be',
    'Duplicate screen blob id',
    'Invalid flow payload',
    'Invalid surface payload',
    'Invalid UTF-8 for',
    'Unsupported surface "',
  ];

  for (final needle in hash) {
    if (message.contains(needle)) return ParityStage.contentHash;
  }
  for (final needle in frame) {
    if (message.contains(needle)) return ParityStage.payloadFrame;
  }
  for (final needle in metadata) {
    if (message.contains(needle)) return ParityStage.metadata;
  }
  return ParityStage.unclassified;
}

/// Writes the inline document by hand: `[u32 headerLen][header][payload]`.
///
/// `minClient` and `requiredLibraries` are recovered from the payload frame,
/// because that is where the delivery service recovers them from too — they are
/// covered by the content hash there, and the header copy is only ever a mirror
/// of it. A frame this build cannot decode contributes its placeholder mirror
/// and is refused a step later at the frame gate, which is the stage under test
/// in exactly those cases.
Uint8List _handBuildEnvelope(ParityCase testCase) {
  var minClient = 1;
  var requiredLibraries = const <LibraryRequirement>[];
  try {
    final payload = SurfacePayload.decode(
      testCase.artifactBytes,
      requireRequiredLibraries: true,
    );
    minClient = payload.minClient;
    requiredLibraries = payload.requiredLibraries;
  } on Object {
    // Left at the placeholder mirror on purpose — see the doc comment.
  }

  final header = utf8.encode(
    jsonEncode(<String, Object?>{
      'contentHash': testCase.declaredContentHash,
      'formatVersion': kSurfaceEnvelopeFormatVersion,
      'minClient': minClient,
      'publishedAtMicros': testCase.publishedAt.toUtc().microsecondsSinceEpoch,
      'requiredLibraries': [
        for (final requirement in requiredLibraries) requirement.toJson(),
      ],
      'surfaceSlug': testCase.surfaceSlug,
      'surfaceType': testCase.surfaceType.wireName,
      'version': testCase.version,
    }),
  );

  final length = Uint8List(4);
  ByteData.view(length.buffer).setUint32(0, header.length);
  return Uint8List.fromList(<int>[
    ...length,
    ...header,
    ...testCase.artifactBytes,
  ]);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

String _short(String hash) =>
    hash.length <= 17 ? hash : '${hash.substring(0, 17)}…';
