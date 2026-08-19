import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('publication_assembler_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('assembles a blob from only the declared closure', () async {
    final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: entry,
    );

    expect(assembled.request.publication, entry.publication);
    expect(assembled.payload, isA<BlobSurfacePayload>());
    expect(SurfacePayload.decode(assembled.request.payload), assembled.payload);
    expect(assembled.artifactBytes.keys, entry.artifacts.map((a) => a.path));
  });

  test('assembles a flow and unions verified sidecar requirements', () async {
    final entry = await _seedGeneratedFlow(tempDir);
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: entry,
    );

    final payload = assembled.payload;
    expect(payload, isA<FlowSurfacePayload>());
    expect((payload as FlowSurfacePayload).requiredLibraries, const [
      LibraryRequirement(namespace: 'restage_example.widgets', minVersion: 3),
    ]);
    expect(
      assembled.request.publication.payloadContentHash,
      payload.contentHash,
    );
  });

  test(
    'rejects an artifact hash mismatch before constructing an upload',
    () async {
      final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
      final blobArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
      );
      final blob = File(p.join(tempDir.path, blobArtifact.path));
      await blob.writeAsBytes(const <int>[9, 8, 7]);
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        throwsA(
          isA<PublicationAssemblyException>().having(
            (error) => error.message,
            'message',
            contains('stale or incomplete'),
          ),
        ),
      );
    },
  );
}

Future<SurfacePublicationManifestEntryV1> _seedGeneratedFlow(
  Directory root,
) async {
  final flowPath = await seedSurfaceFlow(root, slug: 'first_run');
  for (final item in const <String, int>{'ready': 2, 'welcome': 3}.entries) {
    final blobPath = p.join(
      root.path,
      'assets/onboarding/screens/${item.key}.rfw',
    );
    final sidecarPath = p.join(
      root.path,
      'assets/onboarding/screens/${item.key}.capability.json',
    );
    final blob = await File(blobPath).readAsBytes();
    await File(sidecarPath).writeAsString(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: [
              LibraryRequirement(
                namespace: 'restage_example.widgets',
                minVersion: item.value,
              ),
            ],
          ),
        ).toJson(),
      ),
    );
  }
  final flowBytes = await File(flowPath).readAsBytes();
  final document = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
  final artifacts = <SurfacePublicationArtifactV1>[
    SurfacePublicationArtifactV1(
      contentHash: CapabilitySidecar.hashBlob(flowBytes),
      path: 'assets/onboarding/flows/first_run.flow.json',
      role: SurfacePublicationArtifactRoleV1.flowDocument,
    ),
  ];
  final screenBlobs = <String, Uint8List>{};
  final sidecars = <String, CapabilitySidecar>{};
  for (final screen in document.screenArtifacts.entries) {
    final blobPath = 'assets/onboarding/screens/${screen.value.path}';
    final blob = await File(p.join(root.path, blobPath)).readAsBytes();
    final sidecarPath = p.join(
      p.dirname(blobPath),
      '${p.basenameWithoutExtension(screen.value.path)}.capability.json',
    );
    final sidecar = CapabilitySidecar.fromJson(
      jsonDecode(await File(p.join(root.path, sidecarPath)).readAsString())
          as Map<String, dynamic>,
    );
    screenBlobs[screen.key] = blob;
    sidecars[screen.key] = sidecar;
    artifacts.add(
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(blob),
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: screen.key,
      ),
    );
    final sidecarBytes = await File(
      p.join(root.path, sidecarPath),
    ).readAsBytes();
    artifacts.add(
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: screen.key,
      ),
    );
  }
  final requiredLibraries = <LibraryRequirement>[
    const LibraryRequirement(
      namespace: 'restage_example.widgets',
      minVersion: 3,
    ),
  ];
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: screenBlobs,
    requiredLibraries: requiredLibraries,
  );
  final publication = SurfacePublicationV1(
    surface: Surface.onboarding,
    slug: document.flow,
    sourceKind: SurfaceSourceKind.flowGraph,
    payloadKind: SurfacePayloadKind.flow,
    payloadContentHash: payload.contentHash,
    deliveryMode: document.deliveryMode,
  );
  final entry = SurfacePublicationManifestEntryV1(
    artifacts: artifacts,
    publication: publication,
  );
  await writeGeneratedManifest(root, [entry]);
  return entry;
}
