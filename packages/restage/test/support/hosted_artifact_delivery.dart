// Standing in for hosted delivery in a test.
//
// Delivery is two exchanges now: the client asks the service for a surface and
// gets a description back, then fetches the content that description names.
// A test that stubs only the first exchange stubs half a wire, so this owns
// both — describe a document, and the same fixture will serve its bytes when
// the client comes asking.
//
// Two ways in, deliberately. [describe] takes a document and is what almost
// every test wants. [describeRaw] takes bytes and metadata separately, and
// exists because a corpus that can only express well-formed content cannot
// probe what happens to the other kind: a frame the shared types refuse to
// build, or a description whose hash is not the hash of what arrives.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

/// The origin test deliveries point their content at.
const String testArtifactOrigin = 'https://artifacts.test';

/// The pass every test delivery carries. Shaped like a real one; nothing in the
/// SDK inspects it, because verifying a pass is the edge's job.
const String testArtifactPass = 'v1.k1.4102444800.'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A single-screen document, the shape most delivery tests only need to be
/// well-formed.
SurfaceDocument testBlobDocument(
  List<int> blob, {
  Surface surfaceType = Surface.paywall,
  String surfaceSlug = 'pro_upgrade',
  int version = 1,
  int minClient = 1,
  DateTime? publishedAt,
}) =>
    SurfaceDocument(
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      version: version,
      minClient: minClient,
      payload: BlobSurfacePayload(
        minClient: minClient,
        blob: Uint8List.fromList(blob),
      ),
      publishedAt: publishedAt ?? DateTime.utc(2026),
    );

/// The blob an outcome assembled.
///
/// Throws rather than returning null: a test that reaches for the content of a
/// delivery that produced none has already failed, and should say so where it
/// asked rather than three assertions later.
Uint8List assembledBlob(SurfaceArtifactOutcome outcome) {
  if (outcome is! SurfaceArtifactAssembled) {
    throw StateError('the delivery produced no document: $outcome');
  }
  final payload = outcome.document.payload;
  if (payload is! BlobSurfacePayload) {
    throw StateError('the delivery produced a ${payload.payloadKind} payload');
  }
  return payload.blob;
}

/// The document an outcome assembled.
SurfaceDocument assembledDocument(SurfaceArtifactOutcome outcome) {
  if (outcome is! SurfaceArtifactAssembled) {
    throw StateError('the delivery produced no document: $outcome');
  }
  return outcome.document;
}

/// One test's hosted delivery: descriptions out, content back.
final class HostedArtifactFixture {
  final Map<String, Uint8List> _content = <String, Uint8List>{};

  /// Requests this fixture answered for content, in order.
  final List<http.Request> artifactRequests = <http.Request>[];

  /// Describes [document] and holds its content ready to serve.
  ///
  /// Returns the JSON body a delivery response carries. Callers merge their own
  /// sibling keys — decision, assignment, contract-retry flags — around it.
  Map<String, Object?> describe(
    SurfaceDocument document, {
    String? payloadKind,
  }) =>
      describeRaw(
        surfaceType: document.surfaceType,
        surfaceSlug: document.surfaceSlug,
        version: document.version,
        publishedAt: document.publishedAt,
        content: document.payload.canonicalBytes,
        payloadKind: payloadKind,
      );

  /// Describes the surface a self-contained document carries.
  ///
  /// The bridge for the many fixtures that already build one. A document and a
  /// description-plus-content are the same facts in two arrangements, so this
  /// takes the arrangement the fixture has and produces the one the wire wants.
  /// Only well-formed documents go through here — a fixture probing what
  /// happens to a broken one has to say what is broken about it, which is what
  /// [describeRaw] is for.
  Map<String, Object?> describeEnvelope(List<int> envelopeBytes) =>
      describe(SurfaceDocumentCodec.decode(envelopeBytes));

  /// Describes arbitrary [content] under explicit metadata.
  ///
  /// [declaredContentHash] overrides what the description claims the content
  /// hashes to — the only way to exercise a description that does not match
  /// what arrives.
  Map<String, Object?> describeRaw({
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required DateTime publishedAt,
    required List<int> content,
    String? declaredContentHash,
    String? payloadKind,
    int payloadFormatVersion = kSurfaceArtifactPayloadFormatVersion,
  }) =>
      <String, Object?>{
        'artifact': descriptorFor(
          surfaceType: surfaceType,
          surfaceSlug: surfaceSlug,
          version: version,
          publishedAt: publishedAt,
          content: content,
          declaredContentHash: declaredContentHash,
          payloadKind: payloadKind,
          payloadFormatVersion: payloadFormatVersion,
        ).toJson(),
      };

  /// The typed description of [content], with the bytes held ready to serve.
  SurfaceArtifactDescriptor descriptorFor({
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required DateTime publishedAt,
    required List<int> content,
    String? declaredContentHash,
    String? payloadKind,
    int payloadFormatVersion = kSurfaceArtifactPayloadFormatVersion,
  }) {
    final bytes = Uint8List.fromList(content);
    final truthfulHash = 'sha256:${crypto.sha256.convert(bytes)}';
    final url = '$testArtifactOrigin/artifacts/orgs/1/artifacts/'
        '$payloadFormatVersion/$truthfulHash';
    _content[url] = bytes;
    return SurfaceArtifactDescriptor(
      payloadFormatVersion: payloadFormatVersion,
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      version: version,
      publishedAtMicros: publishedAt.toUtc().microsecondsSinceEpoch,
      contentHash: declaredContentHash ?? truthfulHash,
      artifactUrl: url,
      artifactPass: testArtifactPass,
      payloadKind: payloadKind,
    );
  }

  /// Describes a standalone screen: the artifact plus the contract facts that
  /// travel beside it.
  SurfaceScreenDeliveryDescriptor describeScreen({
    required SurfaceDocument document,
    required int contractVersion,
    required String contractFingerprint,
    required String eventContractHash,
    SurfaceExperimentAssignment? assignment,
    String? declaredContentHash,
  }) =>
      SurfaceScreenDeliveryDescriptor(
        artifact: descriptorFor(
          surfaceType: document.surfaceType,
          surfaceSlug: document.surfaceSlug,
          version: document.version,
          publishedAt: document.publishedAt,
          content: document.payload.canonicalBytes,
          declaredContentHash: declaredContentHash,
          payloadKind: SurfacePayloadKind.blob.wireName,
        ),
        sourceKind: SurfaceSourceKind.screen,
        contractVersion: contractVersion,
        publishedRevision: document.version,
        contractFingerprint: contractFingerprint,
        eventContractHash: eventContractHash,
        assignment: assignment,
      );

  /// The complete body for a delivery of [document], ready to `jsonEncode`.
  Map<String, Object?> deliveryBody(
    SurfaceDocument document, {
    String? payloadKind,
    Map<String, Object?> extra = const <String, Object?>{},
  }) =>
      <String, Object?>{
        ...describe(document, payloadKind: payloadKind),
        ...extra
      };

  /// Serves [content] at [url] instead of whatever was described there.
  ///
  /// The only way to stage a store that answers with bytes other than the ones
  /// a description names — which is the substitution the hash check exists to
  /// catch, and therefore the thing a test of it has to be able to build.
  void substituteContent(String url, List<int> content) {
    _content[url] = Uint8List.fromList(content);
  }

  /// Answers a content request, or null when [request] is not one.
  ///
  /// Demands the pass, exactly as the edge does. A fixture that served bytes to
  /// anyone would let a client that stopped sending the header stay green here
  /// and 403 against every real store.
  http.Response? contentResponse(http.Request request) {
    final url = request.url.toString();
    if (!url.startsWith(testArtifactOrigin)) return null;
    artifactRequests.add(request);
    if (request.headers[surfaceArtifactPassHeader] != testArtifactPass) {
      return http.Response('', 403);
    }
    final bytes = _content[url];
    if (bytes == null) return http.Response('', 404);
    return http.Response.bytes(bytes, 200);
  }

  /// A client that answers content requests itself and passes everything else
  /// to [onDelivery].
  MockClient client(
    Future<http.Response> Function(http.Request request) onDelivery,
  ) =>
      MockClient((request) async {
        return contentResponse(request) ?? await onDelivery(request);
      });

  /// A client that answers every delivery request with [body] and serves the
  /// content it describes.
  MockClient serving(
    Map<String, Object?> body, {
    void Function(http.Request request)? onDelivery,
  }) =>
      client((request) async {
        onDelivery?.call(request);
        return http.Response(jsonEncode(body), 200);
      });
}
