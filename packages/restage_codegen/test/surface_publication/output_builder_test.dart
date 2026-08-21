import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
      'materializes one deterministic bundle per authored library plus the '
      'package-wide index and publication manifest', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

part 'restage.generated/launch.restage.g.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
      'apps_examples|lib/journeys/launch.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    final compilerResult = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      compilerResult.succeeded,
      isTrue,
      reason: compilerResult.errors.join('\n'),
    );

    final outputsResult = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      outputsResult.succeeded,
      isTrue,
      reason: outputsResult.errors.join('\n'),
    );

    // Default `generated_directory` layout: one bundle per authored library,
    // collected under a `restage.generated/` sibling of the source.
    final announcementBundleBytes = readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/features/restage.generated/announcement.rsbundle',
      ),
    );
    final announcementBundle = RestageBundleCodec.decode(
      announcementBundleBytes,
    );
    expect(announcementBundle.packageName, 'apps_examples');
    expect(
      announcementBundle.authoredLibraryPath,
      'lib/features/announcement.dart',
    );
    expect(
      announcementBundle.entries.map((entry) => entry.logicalPath),
      containsAll(<String>[
        'assets/general/screens/announcement.rfw',
        'assets/general/screens/announcement.capability.json',
        'assets/general/screens/announcement.rfwtxt',
      ]),
    );
    final rfwTextEntry = announcementBundle.entries.singleWhere(
      (entry) =>
          entry.logicalPath == 'assets/general/screens/announcement.rfwtxt',
    );
    expect(rfwTextEntry.role, RestageBundleEntryRole.rfwText);

    final launchBundleBytes = readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/journeys/restage.generated/launch.rsbundle',
      ),
    );
    final launchBundle = RestageBundleCodec.decode(launchBundleBytes);
    expect(launchBundle.authoredLibraryPath, 'lib/journeys/launch.dart');
    expect(
      launchBundle.entries.map((entry) => entry.logicalPath),
      contains('assets/general/flows/launch.flow.json'),
    );

    // No inspection report by default.
    expect(
      readerWriter.testing.exists(
        AssetId(
          'apps_examples',
          'lib/features/restage.generated/announcement.restage.md',
        ),
      ),
      isFalse,
    );

    // Package-wide publication manifest and physical output index.
    final manifestJson = readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/generated/restage.publication.json'),
    );
    final manifest = SurfacePublicationManifestV1Codec.decode(
      jsonDecode(manifestJson),
    );
    expect(
      manifest.publications.map((entry) => entry.publication.slug),
      containsAll(<String>['announcement', 'launch']),
    );

    // The authoring sources must survive the whole write path, not just the
    // compiler's in-memory bundle: the manifest is canonicalized on the way
    // into the handoff and again on the way out of it, and this file on disk
    // is the only thing the CLI ever reads. A `sources`-blind canonicalizer
    // leaves every entry empty here while every in-memory assertion elsewhere
    // still passes.
    final sourcesBySlug = <String, List<String>>{
      for (final entry in manifest.publications)
        entry.publication.slug: entry.sources,
    };
    expect(
      sourcesBySlug['announcement'],
      <String>['lib/features/announcement.dart'],
    );
    // The flow names the file declaring it AND the file declaring the screen
    // in its closure, which lives in a different library.
    expect(
      sourcesBySlug['launch'],
      <String>['lib/features/announcement.dart', 'lib/journeys/launch.dart'],
    );

    final indexJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/generated/restage.outputs.json'),
      ),
    ) as Map<String, Object?>;
    expect(indexJson['package'], 'apps_examples');
    expect(indexJson['physicalRoot'], '.');
    expect(
      indexJson['publicationManifestPath'],
      'lib/generated/restage.publication.json',
    );
    final indexEntries = indexJson['entries']! as List<Object?>;
    final byPath = {
      for (final entry in indexEntries.cast<Map<String, Object?>>())
        entry['path']! as String: entry,
    };
    expect(
      byPath['assets/general/screens/announcement.rfw']!['bundle'],
      'lib/features/restage.generated/announcement.rsbundle',
    );
    // The index is an exact bijection with the manifest's own artifact
    // set: text-role entries stay in the bundle but never appear here —
    // their physical location is discoverable through the manifest
    // artifact the index does locate for this same library.
    expect(
      byPath,
      isNot(contains('assets/general/screens/announcement.rfwtxt')),
    );
    expect(
      byPath['assets/general/flows/launch.flow.json']!['bundle'],
      'lib/journeys/restage.generated/launch.rsbundle',
    );
    // Entries are sorted by logical path.
    final indexPaths = [
      for (final entry in indexEntries.cast<Map<String, Object?>>())
        entry['path']! as String,
    ];
    expect(indexPaths, orderedEquals(indexPaths.toList()..sort()));
  });

  test(
      'inspection report text matches the bundle entry byte-for-byte '
      'after UTF-8 decoding', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    final compilerResult = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      compilerResult.succeeded,
      isTrue,
      reason: compilerResult.errors.join('\n'),
    );

    final outputsResult = await testBuilder(
      RestageOutputsBuilder(
        const BuilderOptions(<String, Object?>{'inspection_report': true}),
      ),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      outputsResult.succeeded,
      isTrue,
      reason: outputsResult.errors.join('\n'),
    );

    final bundleBytes = readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/features/restage.generated/announcement.rsbundle',
      ),
    );
    final bundle = RestageBundleCodec.decode(bundleBytes);
    expect(bundle.entries, isNotEmpty);

    final reportText = readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/features/restage.generated/announcement.restage.md',
      ),
    );

    // Every entry's identity metadata is present, and text entries appear
    // byte-for-byte (after UTF-8 decoding) in a fenced block; binary entries
    // never have their raw bytes embedded as text.
    var sawJsonEntry = false;
    var sawBinaryEntry = false;
    var sawRfwTextEntry = false;
    for (final entry in bundle.entries) {
      expect(reportText, contains(entry.logicalPath));
      expect(reportText, contains(entry.sha256));
      expect(reportText, contains('${entry.byteLength}'));
      if (entry.logicalPath.endsWith('.rfwtxt')) {
        // Checked before the generic `.json` branch below: role and fenced
        // block form are exclusive to rfw-text, never JSON.
        sawRfwTextEntry = true;
        expect(entry.role, RestageBundleEntryRole.rfwText);
        final decoded = utf8.decode(entry.bytes);
        expect(
          reportText,
          contains('```text\n$decoded\n```'),
          reason: 'Report text for ${entry.logicalPath} must equal the '
              'bundle entry byte-for-byte after UTF-8 decoding.',
        );
      } else if (entry.logicalPath.endsWith('.json')) {
        sawJsonEntry = true;
        final decoded = utf8.decode(entry.bytes);
        expect(
          reportText,
          contains('```json\n$decoded\n```'),
          reason: 'Report text for ${entry.logicalPath} must equal the '
              'bundle entry byte-for-byte after UTF-8 decoding.',
        );
      } else if (entry.logicalPath.endsWith('.rfw')) {
        sawBinaryEntry = true;
        // The binary payload is never dumped as raw bytes or fenced text —
        // only its identity metadata (already asserted above) appears.
        expect(reportText, contains('Binary artifact; content omitted.'));
      }
    }
    expect(sawJsonEntry, isTrue, reason: 'Fixture must cover a JSON entry.');
    expect(
      sawBinaryEntry,
      isTrue,
      reason: 'Fixture must cover a binary .rfw entry.',
    );
    expect(
      sawRfwTextEntry,
      isTrue,
      reason: 'Fixture must cover a .rfwtxt entry.',
    );
  });

  test(
      'bundled_runtime emits a locator whose hashes and lengths are '
      'byte-equal to the decoded bundle entries', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    const options = BuilderOptions(<String, Object?>{
      'bundled_runtime': true,
    });

    final compilerResult = await testBuilder(
      const PackageSurfaceCompilerBuilder(options),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      compilerResult.succeeded,
      isTrue,
      reason: compilerResult.errors.join('\n'),
    );

    final generatedDartResult = await testBuilder(
      RestageGeneratedDartBuilder(options),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      generatedDartResult.succeeded,
      isTrue,
      reason: generatedDartResult.errors.join('\n'),
    );

    final outputsResult = await testBuilder(
      RestageOutputsBuilder(options),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      outputsResult.succeeded,
      isTrue,
      reason: outputsResult.errors.join('\n'),
    );

    // bundled_runtime routes ONLY the bundle into assets/; the generated
    // Dart part's own placement is unaffected.
    const bundleAssetKey = 'assets/restage/bundles/lib/features/announcement'
        '.rsbundle';
    final bundleBytes = readerWriter.testing.readBytes(
      AssetId('apps_examples', bundleAssetKey),
    );
    final bundle = RestageBundleCodec.decode(bundleBytes);
    final blobEntry = bundle.entries.singleWhere(
      (entry) => entry.role == RestageBundleEntryRole.screenBlob,
    );
    final sidecarEntry = bundle.entries.singleWhere(
      (entry) => entry.role == RestageBundleEntryRole.capabilitySidecar,
    );

    final generatedPart = readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/features/restage.generated/announcement.restage.g.dart',
      ),
    );

    expect(generatedPart, contains('SurfaceScreenBundleLocator('));
    expect(generatedPart, contains('assetKey: "$bundleAssetKey"'));
    expect(generatedPart, contains('packageName: "apps_examples"'));
    expect(
      generatedPart,
      contains('authoredLibraryPath: "lib/features/announcement.dart"'),
    );
    // Asserted against the DECODED bundle's own META-INF-derived entry
    // records, never against an independent recomputation of the hash.
    expect(
      generatedPart,
      contains(
        'logicalPath: "${blobEntry.logicalPath}"',
      ),
    );
    expect(
      generatedPart,
      contains('role: RestageBundleEntryRole.screenBlob'),
    );
    expect(
      generatedPart,
      contains('byteLength: ${blobEntry.byteLength}'),
    );
    // Matched on the quoted value alone, not `sha256: "..."` on one line:
    // dart_format wraps the key onto its own line when the value is this
    // long, but the quoted literal itself stays intact.
    expect(generatedPart, contains('"${blobEntry.sha256}"'));
    expect(
      generatedPart,
      contains('logicalPath: "${sidecarEntry.logicalPath}"'),
    );
    expect(
      generatedPart,
      contains('role: RestageBundleEntryRole.capabilitySidecar'),
    );
    expect(
      generatedPart,
      contains('byteLength: ${sidecarEntry.byteLength}'),
    );
    expect(generatedPart, contains('"${sidecarEntry.sha256}"'));
  });

  test('bundled_runtime: false emits no bundle locator', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    final compilerResult = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      compilerResult.succeeded,
      isTrue,
      reason: compilerResult.errors.join('\n'),
    );

    final generatedDartResult = await testBuilder(
      RestageGeneratedDartBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      generatedDartResult.succeeded,
      isTrue,
      reason: generatedDartResult.errors.join('\n'),
    );

    final generatedPart = readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/features/restage.generated/announcement.restage.g.dart',
      ),
    );
    expect(generatedPart, isNot(contains('SurfaceScreenBundleLocator(')));
    expect(generatedPart, isNot(contains('bundle:')));
  });

  test('emits no bundle for a library with no delivery artifacts', () async {
    final bundle = RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifest(publications: const []),
      artifacts: const {},
    );
    final sources = <String, String>{
      'apps_examples|lib/features/empty.dart': '// no Restage declarations\n',
      'apps_examples|lib/src/surface_publication/surface_publication.compiler.json':
          bundle.encodeCanonicalJson(),
      'apps_examples|$kRestageMeasurementCompilerOutputPath':
          RestageMeasurementCompilerOutputV1.empty().encodeCanonicalJson(),
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    // The package-wide manifest/index still materialize (empty), but the
    // library with no delivery artifacts gets no bundle.
    expect(
      readerWriter.testing.exists(
        AssetId(
          'apps_examples',
          'lib/features/restage.generated/empty.rsbundle',
        ),
      ),
      isFalse,
    );
    final manifest = SurfacePublicationManifestV1Codec.decode(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId('apps_examples', 'lib/generated/restage.publication.json'),
        ),
      ),
    );
    expect(manifest.publications, isEmpty);
  });
}
