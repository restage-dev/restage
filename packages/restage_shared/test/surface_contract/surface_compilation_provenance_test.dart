import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('compilation provenance is canonical and validates its fields', () {
    final versions = {'restage_codegen': '2.1.0', 'restage': '2.0.0'};
    final provenance = SurfaceCompilationProvenance(
      sourceHash: _hash('a'),
      toolchainHash: _hash('b'),
      packageVersions: versions,
    );
    versions['restage'] = 'different';
    expect(provenance.packageVersions.keys, ['restage', 'restage_codegen']);
    expect(provenance.packageVersions['restage'], '2.0.0');
    expect(
      SurfaceCompilationProvenance.fromJson(
        jsonDecode(jsonEncode(provenance.toJson())),
      ).toJson(),
      provenance.toJson(),
    );
    for (final invalid in [
      {...provenance.toJson(), 'sourceHash': 'not-a-hash'},
      {...provenance.toJson(), 'toolchainHash': 'not-a-hash'},
      {...provenance.toJson(), 'extra': true},
      {...provenance.toJson(), 'packageVersions': <String, Object?>{}},
      {
        ...provenance.toJson(),
        'packageVersions': {'restage': 2},
      },
    ]) {
      expect(
        () => SurfaceCompilationProvenance.fromJson(invalid),
        throwsFormatException,
      );
    }
  });

  test(
      'compilation provenance survives an upload without changing its contract',
      () {
    final payload =
        BlobSurfacePayload(minClient: 1, blob: Uint8List.fromList([1, 2, 3]));
    final capabilities =
        CapabilityManifest(builtInFloor: 1, requiredLibraries: const []);
    final events = SurfaceScreenEventSchema(events: const []);
    final eventHash = SurfaceScreenEventContractHash.hash(events);
    final base = SurfacePublication(
      surface: Surface.general,
      slug: 'notice',
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      payloadContentHash: payload.contentHash,
      contractVersion: 1,
      capabilities: capabilities,
      eventContract: events,
      eventContractHash: eventHash,
      contractFingerprint: SurfaceScreenContractFingerprint.hash(
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        capabilities: capabilities,
        eventContractHash: eventHash,
      ),
    );
    final upgraded = SurfacePublication.fromJson(
      {
        ...base.toJson(),
        'compilationProvenance': SurfaceCompilationProvenance(
          sourceHash: _hash('a'),
          toolchainHash: _hash('b'),
          packageVersions: const {'restage_codegen': '2.1.0'},
        ).toJson(),
      },
      path: 'publication',
    );
    final request = SurfacePublicationUploadRequest(
      publication: upgraded,
      payload: payload.canonicalBytes,
    );
    final decoded = SurfacePublicationUploadRequestV1Codec.decodeJson(
      SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(request),
    );
    expect(
      decoded.publication.compilationProvenance!.toJson(),
      upgraded.compilationProvenance!.toJson(),
    );
    expect(decoded.publication.contractFingerprint, base.contractFingerprint);
    expect(decoded.publication.payloadContentHash, base.payloadContentHash);
  });
}

String _hash(String character) => 'sha256:${character * 64}';
