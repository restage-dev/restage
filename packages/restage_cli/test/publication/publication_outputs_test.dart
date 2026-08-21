import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('publication_outputs_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<LoadedSurfacePublicationManifest> load() =>
      SurfacePublicationManifestLoader().load(projectRoot: tempDir);

  Matcher failsWith(String fragment) => throwsA(
    isA<PublicationException>().having(
      (error) => error.message,
      'message',
      contains(fragment),
    ),
  );

  group('placement is read from the index, never re-derived', () {
    for (final layout in GeneratedOutputLayout.values) {
      test('resolves and publishes the ${layout.name} layout', () async {
        final entry = await seedGeneratedPaywall(
          tempDir,
          slug: 'checkout',
          layout: layout,
        );

        final loaded = await load();
        final assembled = await SurfacePublicationAssembler().assemble(
          loaded: loaded,
          entry: entry,
        );

        expect(
          loaded.outputIndex.publicationManifestPath,
          layout.publicationManifestPath,
        );
        expect(loaded.outputIndex.physicalRoot, layout.physicalRoot);
        final expectedBundle = layout.bundlePathFor(fixtureLibraryPath);
        for (final locator in loaded.outputIndex.entries) {
          expect(locator.bundle, expectedBundle);
          expect(
            File(p.join(tempDir.path, locator.bundle)).existsSync(),
            isTrue,
          );
        }
        expect(assembled.request.publication.slug, 'checkout');
      });
    }

    test('follows a bundle relocated to an underivable path', () async {
      final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
      const relocated = 'tool/artifacts/relocated.rsbundle';
      final original = File(
        p.join(
          tempDir.path,
          GeneratedOutputLayout.generatedDirectory.bundlePathFor(
            fixtureLibraryPath,
          ),
        ),
      );
      final moved = File(p.join(tempDir.path, relocated));
      await moved.parent.create(recursive: true);
      await original.rename(moved.path);
      await mutateGeneratedIndex(tempDir, (index) {
        for (final locator in indexEntriesOf(index)) {
          locator['bundle'] = relocated;
        }
      });

      final loaded = await load();
      final assembled = await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: entry,
      );

      expect(assembled.artifactBytes.keys, hasLength(entry.artifacts.length));
    });

    test('resolves per-library bundles for a multi-library package', () async {
      final entry = await seedGeneratedPaywall(tempDir, slug: 'checkout');
      await writeGeneratedOutput(
        tempDir,
        [entry],
        libraryFor: (artifactPath) => artifactPath.endsWith('.json')
            ? 'lib/sidecars.dart'
            : 'lib/screens.dart',
      );

      final loaded = await load();
      final bundles = {
        for (final locator in loaded.outputIndex.entries)
          locator.path: locator.bundle,
      };

      expect(bundles.values.toSet(), hasLength(2));
      await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: entry,
      );
    });
  });

  group('bounded index discovery', () {
    test('reports generation required when nothing is generated', () async {
      await expectLater(
        load(),
        throwsA(
          isA<PublicationGenerationRequiredException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('No generated publication output index'),
              contains('lib/generated/restage.outputs.json'),
            ),
          ),
        ),
      );
    });

    test('finds a single transient override outside the default', () async {
      await seedGeneratedPaywall(tempDir, slug: 'checkout');
      await _moveGeneratedMetadata(tempDir, to: 'tool/generated');

      final loaded = await load();

      expect(
        loaded.outputIndex.publicationManifestPath,
        'tool/generated/restage.publication.json',
      );
      expect(loaded.select(slug: 'checkout').publication.slug, 'checkout');
    });

    test('refuses to guess between two candidate indexes', () async {
      await seedGeneratedPaywall(tempDir, slug: 'checkout');
      await _moveGeneratedMetadata(tempDir, to: 'tool/generated');
      await File(
        p.join(tempDir.path, 'tool/generated/restage.outputs.json'),
      ).copy(p.join(tempDir.path, 'tool/restage.outputs.json'));

      await expectLater(load(), failsWith('Ambiguous generated output'));
    });

    test('refuses a stray index beside the configured one', () async {
      await seedGeneratedPaywall(tempDir, slug: 'checkout');
      await _copyInto(
        tempDir,
        from: 'lib/generated/restage.outputs.json',
        to: 'tool/restage.outputs.json',
      );

      await expectLater(load(), failsWith('Ambiguous generated output'));
    });

    test('ignores an index inside an excluded directory', () async {
      await seedGeneratedPaywall(tempDir, slug: 'checkout');
      for (final excluded in const ['.dart_tool', 'build', 'node_modules']) {
        await _copyInto(
          tempDir,
          from: 'lib/generated/restage.outputs.json',
          to: '$excluded/restage.outputs.json',
        );
      }

      final loaded = await load();

      expect(
        loaded.outputIndex.publicationManifestPath,
        'lib/generated/restage.publication.json',
      );
    });

    test(
      'an excluded-directory index alone still means generation required',
      () async {
        await seedGeneratedPaywall(tempDir, slug: 'checkout');
        final index = File(
          p.join(tempDir.path, 'lib/generated/restage.outputs.json'),
        );
        final hidden = File(
          p.join(tempDir.path, '.dart_tool/restage.outputs.json'),
        );
        await hidden.parent.create(recursive: true);
        await index.rename(hidden.path);

        await expectLater(
          load(),
          failsWith('No generated publication output index'),
        );
      },
    );

    test('reads the configured output root from build.yaml', () async {
      await seedGeneratedPaywall(
        tempDir,
        slug: 'checkout',
        layout: GeneratedOutputLayout.outputRoot,
      );
      // A stale default-layout index must not win over the configured one.
      await _copyInto(
        tempDir,
        from: 'restage_out/metadata/restage.outputs.json',
        to: 'lib/generated/restage.outputs.json',
      );

      await expectLater(load(), failsWith('Ambiguous generated output'));
    });
  });

  group('index, manifest, and bundle drift', () {
    test('rejects an unsupported schema version', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => index['schemaVersion'] = 2,
      );

      await expectLater(load(), failsWith('schemaVersion 2'));
    });

    test('rejects malformed index JSON', () async {
      await seedGeneratedPaywall(tempDir);
      await writeGeneratedIndexSource(tempDir, '{"schemaVersion": 1,');

      await expectLater(load(), failsWith('is malformed'));
    });

    test('rejects an unknown index field', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(tempDir, (index) => index['extra'] = true);

      await expectLater(load(), failsWith(r'Unsupported field "$.extra"'));
    });

    test('rejects duplicate logical-path ownership', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(tempDir, (index) {
        final entries = indexEntriesOf(index);
        index['entries'] = [entries.first, entries.first, entries.last];
      });

      await expectLater(load(), failsWith('duplicate ownership'));
    });

    test('rejects unsorted locator entries', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => index['entries'] = indexEntriesOf(index).reversed.toList(),
      );

      await expectLater(load(), failsWith('sorted by logical path'));
    });

    test('rejects a locator hash that disagrees with the manifest', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => indexEntriesOf(index).first['sha256'] = 'sha256:${'0' * 64}',
      );

      await expectLater(
        load(),
        failsWith('does not match the canonical publication manifest'),
      );
    });

    test('rejects an index that omits a declared artifact', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => index['entries'] = [indexEntriesOf(index).first],
      );

      await expectLater(load(), failsWith('does not cover exactly'));
    });

    test('rejects a locator that escapes the package root', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) =>
            indexEntriesOf(index).first['bundle'] = '../outside.rsbundle',
      );

      await expectLater(load(), failsWith('canonical path segments'));
    });

    test('rejects a stale fingerprint against the manifest bytes', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => index['generationFingerprint'] = 'sha256:${'1' * 64}',
      );

      await expectLater(
        load(),
        failsWith('generation fingerprint does not match'),
      );
    });

    test('rejects an index generated for another package', () async {
      await seedGeneratedPaywall(tempDir);
      await mutateGeneratedIndex(
        tempDir,
        (index) => index['package'] = 'other_package',
      );

      await expectLater(load(), failsWith('belongs to package'));
    });

    test('rejects a missing publication manifest', () async {
      await seedGeneratedPaywall(tempDir);
      await File(
        p.join(tempDir.path, 'lib/generated/restage.publication.json'),
      ).delete();

      await expectLater(load(), failsWith('points to a missing'));
    });

    test('rejects a missing bundle file', () async {
      final entry = await seedGeneratedPaywall(tempDir);
      final loaded = await load();
      await File(
        p.join(
          tempDir.path,
          loaded.outputIndex.locatorFor(entry.artifacts.first.path).bundle,
        ),
      ).delete();

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        failsWith('could not read bundle'),
      );
    });

    test('rejects a bundle missing a declared entry', () async {
      final entry = await seedGeneratedPaywall(tempDir);
      final loaded = await load();
      final artifact = entry.artifacts.first;
      await removeBundleEntry(
        tempDir,
        bundlePath: loaded.outputIndex.locatorFor(artifact.path).bundle,
        entryPath: artifact.path,
      );

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        failsWith('does not contain declared entry'),
      );
    });

    test('rejects a bundle entry recorded under the wrong role', () async {
      final entry = await seedGeneratedPaywall(tempDir);
      final loaded = await load();
      final artifact = entry.artifacts.singleWhere(
        (candidate) =>
            candidate.role == SurfacePublicationArtifactRole.screenBlob,
      );
      await rewriteBundleEntryRole(
        tempDir,
        bundlePath: loaded.outputIndex.locatorFor(artifact.path).bundle,
        entryPath: artifact.path,
        role: RestageBundleEntryRole.flowDocument,
      );

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        failsWith('bundle entry role mismatch'),
      );
    });

    test('rejects an undecodable bundle', () async {
      final entry = await seedGeneratedPaywall(tempDir);
      final loaded = await load();
      final bundle = File(
        p.join(
          tempDir.path,
          loaded.outputIndex.locatorFor(entry.artifacts.first.path).bundle,
        ),
      );
      await bundle.writeAsBytes(const <int>[0x52, 0x53, 0x42, 0x31]);

      await expectLater(
        SurfacePublicationAssembler().assemble(loaded: loaded, entry: entry),
        failsWith('could not be decoded'),
      );
    });
  });

  group('locator order is ascending UTF-8 path bytes', () {
    // The only inputs that tell the two candidate comparators apart. In UTF-8
    // bytes U+F000 (EF 80 80) precedes U+10000 (F0 90 80 80); in UTF-16 code
    // units the astral character's leading surrogate (D800) precedes F000, so
    // the orders are exact opposites. Every ASCII path sorts identically under
    // both, which is why only a case like this one can pin the requirement.
    const basicMultilingual = 'assets/\u{F000}.rfw';
    const astral = 'assets/\u{10000}.rfw';

    String indexFor(List<String> orderedPaths) => jsonEncode({
      'schemaVersion': 1,
      'package': fixturePackageName,
      'physicalRoot': '.',
      'publicationManifestPath': 'lib/generated/restage.publication.json',
      'generationFingerprint': 'sha256:${'0' * 64}',
      'entries': [
        for (final path in orderedPaths)
          {
            'path': path,
            'bundle': 'lib/generated/fixture.rsbundle',
            'entry': path,
            'sha256': 'sha256:${'0' * 64}',
          },
      ],
    });

    test('accepts UTF-8 byte order', () {
      final index = RestageOutputIndex.decodeJson(
        indexFor(const [basicMultilingual, astral]),
      );

      expect(index.entries.map((entry) => entry.path), const [
        basicMultilingual,
        astral,
      ]);
    });

    test('rejects UTF-16 code-unit order', () {
      expect(
        () => RestageOutputIndex.decodeJson(
          indexFor(const [astral, basicMultilingual]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sorted by logical path'),
          ),
        ),
      );
    });
  });

  test('encodes the index in the exact generated document shape', () async {
    await seedGeneratedPaywall(tempDir);
    final source = await readGeneratedIndexSource(tempDir);

    final index = RestageOutputIndex.decodeJson(source);

    expect(index.encodeJson(), source);
    expect(
      (jsonDecode(source) as Map<String, Object?>).keys,
      containsAllInOrder(const [
        'schemaVersion',
        'package',
        'physicalRoot',
        'publicationManifestPath',
        'generationFingerprint',
        'entries',
      ]),
    );
  });
}

/// Copy a generated file to another package-relative path, creating any
/// directories the destination needs.
Future<void> _copyInto(
  Directory projectRoot, {
  required String from,
  required String to,
}) async {
  final destination = File(p.join(projectRoot.path, to));
  await destination.parent.create(recursive: true);
  await File(p.join(projectRoot.path, from)).copy(destination.path);
}

/// Move the generated metadata pair to [to], keeping the index's recorded
/// manifest path correct — the shape a transient build-tool override leaves
/// behind.
Future<void> _moveGeneratedMetadata(
  Directory projectRoot, {
  required String to,
}) async {
  final destination = Directory(p.join(projectRoot.path, to));
  await destination.create(recursive: true);
  final manifest = File(
    p.join(projectRoot.path, 'lib/generated/restage.publication.json'),
  );
  final index = File(
    p.join(projectRoot.path, 'lib/generated/restage.outputs.json'),
  );
  final document =
      jsonDecode(await index.readAsString()) as Map<String, Object?>;
  document['publicationManifestPath'] = p.posix.join(
    to,
    'restage.publication.json',
  );
  await manifest.rename(p.join(destination.path, 'restage.publication.json'));
  await index.delete();
  await File(
    p.join(destination.path, 'restage.outputs.json'),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));
}
