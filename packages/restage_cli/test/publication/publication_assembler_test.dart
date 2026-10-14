import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
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
    expect(
      assembled.request.artifactManifest!.publications.single.publication,
      entry.publication,
    );
    expect(assembled.request.artifactBytesByPath, assembled.artifactBytes);
    final decoded = SurfacePublicationUploadRequestV1Codec.decodeJson(
      SurfacePublicationUploadRequestV1Codec.encodeCanonicalJson(
        assembled.request,
      ),
    );
    expect(decoded.artifactBytesByPath, assembled.artifactBytes);
    expect(
      assembled.selectedBundleFiles.map((file) => file.path).toSet(),
      <String>{
        for (final artifact in entry.artifacts)
          p.normalize(
            p.join(
              tempDir.path,
              loaded.outputIndex.locatorFor(artifact.path).bundle,
            ),
          ),
      },
    );
    expect(assembled.hasBundledMeasurementSourceClosure, isFalse);
  });

  test(
    'retains the exact bundled-runtime source closure for packaging',
    () async {
      final entry = await seedGeneratedPaywall(
        tempDir,
        slug: 'checkout',
        layout: GeneratedOutputLayout.bundledRuntime,
      );
      final loaded = await SurfacePublicationManifestLoader().load(
        projectRoot: tempDir,
      );

      final assembled = await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: entry,
      );

      expect(assembled.hasBundledMeasurementSourceClosure, isTrue);
      expect(
        assembled.selectedBundleAssetPaths,
        everyElement(startsWith('assets/restage/bundles/')),
      );
    },
  );

  test('assembles a multi-screen flow over its whole closure', () async {
    await seedGeneratedFlow(tempDir, slug: 'first_run');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
    );

    final payload = assembled.payload;
    expect(payload, isA<FlowSurfacePayload>());
    expect((payload as FlowSurfacePayload).screenBlobs, hasLength(4));
    expect(payload.requiredLibraries, isEmpty);
    expect(
      assembled.request.publication.payloadContentHash,
      payload.contentHash,
    );
    expect(assembled.measurementUpload, isNotNull);
    // Root files use the bound envelope's existing declared closure once.
    expect(assembled.request.artifactBytesByPath, isEmpty);
    expect(assembled.request.artifactManifest!.publications, hasLength(1));
    expect({
      for (final artifact
          in assembled.measurementUpload!.declaredArtifactClosure)
        artifact.path: artifact.bytes,
    }, assembled.artifactBytes);
  });

  test('notes a flow whose screen emits an event no state handles', () async {
    await seedGeneratedFlow(tempDir, slug: 'first_run');
    final clean = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );
    expect(
      (await SurfacePublicationAssembler().assemble(
        loaded: clean,
        entry: clean.manifest.publications.single,
      )).unhandledEventsWarning,
      isNull,
    );

    final dropping = await tempDir.createTemp('dropping');
    await seedDroppingFlow(dropping);
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: dropping,
    );
    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
    );

    expect(
      assembled.unhandledEventsWarning,
      'The flow "notice" does not handle every event its screens emit:\n'
      '- the screen "notice" in the state "notice" emits "dropped"\n'
      'Add a transition for each event in that state, or declare it as a '
      'custom event if the app handles it.',
    );
  });

  test('assembles the largest generated flow and its draft', () async {
    await seedGeneratedFlow(tempDir, slug: 'tally_onboarding');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
    );

    final upload = assembled.measurementUpload;
    expect(upload, isNotNull);
    final draftBytes =
        upload!.proof.measurementPublicationDraft.canonicalBytes.length;
    expect(
      draftBytes,
      greaterThan(512 * 1024),
      reason: 'this flow must stay the one that outgrew the older draft bound',
    );
    expect(
      draftBytes,
      lessThan(kMaximumMeasurementPublicationCandidateDraftBytes),
    );
    expect((assembled.payload as FlowSurfacePayload).screenBlobs, hasLength(8));
    expect(
      upload.proof.assembledPublicationUploadCanonicalBytes.length,
      lessThan(kMaximumMeasurementPublicationCandidateUploadBytes),
    );
    expect(
      upload.proof.selectedPublicationManifestCanonicalBytes.length,
      lessThan(kMaximumMeasurementPublicationCandidateManifestBytes),
    );
    expect(
      assembled.request.publication.payloadContentHash,
      assembled.payload.contentHash,
    );
  });

  test('unions verified sidecar requirements into the flow payload', () async {
    await seedGeneratedFlow(tempDir, slug: 'plan_board_showcase');
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: tempDir,
    );

    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
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
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
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
        role: RestageBundleEntryRole.rfwText,
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
            candidate.role == SurfacePublicationArtifactRole.screenBlob,
      );
      await rewriteBundleEntryRole(
        tempDir,
        bundlePath: loaded.outputIndex.locatorFor(artifact.path).bundle,
        entryPath: artifact.path,
        role: RestageBundleEntryRole.rfwText,
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
