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
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );
      // Re-encode the bundle around different screen bytes. The bundle stays
      // internally consistent, so only the cross-layer comparison against the
      // index and manifest can catch it.
      await rewriteBundleEntryBytes(
        tempDir,
        bundlePath: loaded.outputIndex.locatorFor(blobArtifact.path).bundle,
        entryPath: blobArtifact.path,
        bytes: ordinaryRfwBlob().reversed.toList(),
      );

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        throwsA(
          isA<PublicationAssemblyException>().having(
            (error) => error.message,
            'message',
            contains('bundle entry hash mismatch'),
          ),
        ),
      );
    },
  );

  test('reads only the bundle entries the closure declares', () async {
    final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
    await addUnrelatedBundleEntry(
      tempDir,
      bundlePath: GeneratedOutputLayout.generatedDirectory.bundlePathFor(
        fixtureLibraryPath,
      ),
      entryPath: 'assets/restage/generated/unrelated/screen.rfw',
    );
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: entry,
    );

    expect(
      assembled.artifactBytes.keys,
      entry.artifacts.map((artifact) => artifact.path),
    );
  });

  test(
    'assembles successfully when the bundle carries an rfw-text sibling',
    () async {
      // Every real bundle now carries a .rfwtxt entry alongside its
      // manifest-closure artifacts. The manifest closure never declares one
      // (rfw-text has no manifest-role counterpart), so this proves the
      // reader only converts the role of the entry it was asked for — never
      // eagerly over every entry in the bundle, which would throw on this
      // bundle before assembly ever got this far.
      final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
      await addUnrelatedBundleEntry(
        tempDir,
        bundlePath: GeneratedOutputLayout.generatedDirectory.bundlePathFor(
          fixtureLibraryPath,
        ),
        entryPath: 'assets/restage/generated/checkout/screen.rfwtxt',
        role: RestageBundleEntryRoleV1.rfwText,
      );
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      final assembled = await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: entry,
      );

      expect(
        assembled.artifactBytes.keys,
        entry.artifacts.map((artifact) => artifact.path),
      );
    },
  );

  test(
    'rejects a closure artifact whose bundle entry is recorded as rfw-text',
    () async {
      // A crafted/corrupted bundle could record a manifest-closure path
      // under the bundle-only rfw-text role, which has no manifest-role
      // counterpart. This must surface as the CLI's own drift diagnostic
      // (naming the artifact and the bundle it came from), never as an
      // unhandled StateError from the role conversion itself.
      final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );
      final artifact = entry.artifacts.singleWhere(
        (candidate) =>
            candidate.role == SurfacePublicationArtifactRoleV1.screenBlob,
      );
      await rewriteBundleEntryRole(
        tempDir,
        bundlePath: loaded.outputIndex.locatorFor(artifact.path).bundle,
        entryPath: artifact.path,
        role: RestageBundleEntryRoleV1.rfwText,
      );

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        throwsA(
          isA<PublicationAssemblyException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(artifact.path),
              contains(
                GeneratedOutputLayout.generatedDirectory.bundlePathFor(
                  fixtureLibraryPath,
                ),
              ),
              contains('rfw-text'),
            ),
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
  await writeGeneratedOutput(root, [entry]);
  return entry;
}
