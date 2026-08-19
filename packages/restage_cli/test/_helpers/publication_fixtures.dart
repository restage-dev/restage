import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

import 'test_fixtures.dart';

/// Write one generated paywall blob closure and its fixed manifest.
Future<SurfacePublicationManifestEntryV1> seedGeneratedPaywall(
  Directory projectRoot, {
  String slug = 'pro_upgrade',
  int minClient = 2,
}) async {
  final blob = ordinaryRfwBlob();
  final sidecar = CapabilitySidecar(
    blobSha256: CapabilitySidecar.hashBlob(blob),
    manifest: CapabilityManifest(
      builtInFloor: minClient,
      requiredLibraries: const [],
    ),
  );
  final payload = BlobSurfacePayload(minClient: minClient, blob: blob);
  final publication = SurfacePublicationV1(
    surface: Surface.paywall,
    slug: slug,
    sourceKind: SurfaceSourceKind.paywall,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: payload.contentHash,
  );
  final blobPath = 'assets/restage/generated/$slug/screen.rfw';
  final sidecarPath = 'assets/restage/generated/$slug/screen.capability.json';
  await _writeBytes(projectRoot, blobPath, blob);
  await _writeText(projectRoot, sidecarPath, jsonEncode(sidecar.toJson()));
  final entry = SurfacePublicationManifestEntryV1(
    publication: publication,
    artifacts: [
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(blob),
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: slug,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(
          utf8.encode(jsonEncode(sidecar.toJson())),
        ),
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: slug,
      ),
    ],
  );
  await writeGeneratedManifest(projectRoot, [entry]);
  return entry;
}

/// Write the fixed generated manifest with canonical JSON bytes.
Future<void> writeGeneratedManifest(
  Directory projectRoot,
  List<SurfacePublicationManifestEntryV1> entries,
) async {
  final manifestFile = File(
    p.join(
      projectRoot.path,
      'assets/restage/surface-publication-manifest.json',
    ),
  );
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString(
    SurfacePublicationManifestV1Codec.encodeCanonicalJson(
      SurfacePublicationManifestV1(publications: entries),
    ),
  );
}

Future<void> _writeBytes(
  Directory projectRoot,
  String packagePath,
  List<int> bytes,
) async {
  final file = File(p.join(projectRoot.path, packagePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

Future<void> _writeText(
  Directory projectRoot,
  String packagePath,
  String source,
) => _writeBytes(projectRoot, packagePath, utf8.encode(source));
