import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_bundle_reader.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_shared/restage_shared.dart';

import 'test_fixtures.dart';

/// The package name every generated fixture records.
const String fixturePackageName = 'fixture_package';

/// The authored library every generated fixture attributes output to unless a
/// test supplies its own attribution.
const String fixtureLibraryPath = 'lib/fixture.dart';

/// The configured portable output root used by the `outputRoot` layout.
const String fixtureOutputRoot = 'restage_out';

/// The generated-output placement a fixture materializes.
///
/// Each value mirrors one resolved placement the build-time toolchain can
/// emit. The fixtures write the physical files where that placement puts them
/// and record those exact paths in the index, so a reader that re-derives
/// placement instead of reading the index fails on at least three of them.
enum GeneratedOutputLayout {
  /// The default `restage.generated/` collection directory per source
  /// directory.
  generatedDirectory,

  /// Flat placement beside the authored source.
  adjacent,

  /// A configured purpose-partitioned portable output root.
  outputRoot,

  /// Bundles routed into the application asset tree.
  bundledRuntime;

  /// The package-relative directory holding the portable metadata pair.
  String get metadataDirectory => switch (this) {
    outputRoot => p.posix.join(fixtureOutputRoot, 'metadata'),
    _ => 'lib/generated',
  };

  /// The package-relative output index path.
  String get outputIndexPath =>
      p.posix.join(metadataDirectory, restageOutputsFileName);

  /// The package-relative publication manifest path.
  String get publicationManifestPath =>
      p.posix.join(metadataDirectory, restagePublicationFileName);

  /// The physical root this placement records in the index.
  String get physicalRoot =>
      this == outputRoot ? fixtureOutputRoot : restagePackageRootSentinel;

  /// The package-relative bundle path for [libraryPath].
  String bundlePathFor(String libraryPath) {
    final withoutExtension = p.posix.withoutExtension(libraryPath);
    final directory = p.posix.dirname(libraryPath);
    final stem = p.posix.basenameWithoutExtension(libraryPath);
    return switch (this) {
      generatedDirectory => p.posix.join(
        directory,
        'restage.generated',
        '$stem.rsbundle',
      ),
      adjacent => p.posix.join(directory, '$stem.rsbundle'),
      outputRoot => p.posix.join(
        fixtureOutputRoot,
        'bundles',
        '$withoutExtension.rsbundle',
      ),
      bundledRuntime => p.posix.join(
        'assets/restage/bundles',
        '$withoutExtension.rsbundle',
      ),
    };
  }
}

/// Write one generated paywall closure and its generated metadata.
Future<SurfacePublicationManifestEntryV1> seedGeneratedPaywall(
  Directory projectRoot, {
  String slug = 'pro_upgrade',
  int minClient = 2,
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
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
  await writeGeneratedOutput(projectRoot, [entry], layout: layout);
  return entry;
}

/// Materialize the complete generated output for [entries]: one real bundle
/// per authored library, the canonical publication manifest, the output index
/// that locates every logical artifact, and the package metadata a reader
/// consults.
///
/// Bundles are produced by the shared deterministic codec from the exact
/// artifact bytes already on disk — no hand-written archive bytes.
Future<void> writeGeneratedOutput(
  Directory projectRoot,
  List<SurfacePublicationManifestEntryV1> entries, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
  String Function(String artifactPath)? libraryFor,
}) async {
  PublicationBundleReaderProvider.override = null;
  await _writePackageMetadata(projectRoot, layout);

  final artifactsByPath = <String, SurfacePublicationArtifactV1>{};
  for (final entry in entries) {
    for (final artifact in entry.artifacts) {
      artifactsByPath[artifact.path] = artifact;
    }
  }

  final byLibrary = <String, List<RestageBundleEntry>>{};
  final bundleByArtifact = <String, String>{};
  for (final path in artifactsByPath.keys) {
    final library = libraryFor?.call(path) ?? fixtureLibraryPath;
    final bytes = await File(p.join(projectRoot.path, path)).readAsBytes();
    byLibrary
        .putIfAbsent(library, () => <RestageBundleEntry>[])
        .add(
          RestageBundleEntry(
            logicalPath: path,
            role: RestageBundleEntryRoleV1.fromManifestRole(
              artifactsByPath[path]!.role,
            ),
            bytes: bytes,
          ),
        );
    bundleByArtifact[path] = layout.bundlePathFor(library);
  }
  for (final library in byLibrary.keys) {
    await writeGeneratedBundle(
      projectRoot,
      bundlePath: layout.bundlePathFor(library),
      libraryPath: library,
      entries: byLibrary[library]!,
    );
  }

  final manifestSource = SurfacePublicationManifestV1Codec.encodeCanonicalJson(
    SurfacePublicationManifestV1(publications: entries),
  );
  await _writeText(projectRoot, layout.publicationManifestPath, manifestSource);

  final paths = artifactsByPath.keys.toList()
    ..sort(compareGeneratedOutputPaths);
  final index = RestageOutputIndex(
    packageName: fixturePackageName,
    physicalRoot: layout.physicalRoot,
    generationFingerprint: CapabilitySidecar.hashBlob(
      utf8.encode(manifestSource),
    ),
    publicationManifestPath: layout.publicationManifestPath,
    entries: [
      for (final path in paths)
        RestageOutputIndexEntry(
          bundle: bundleByArtifact[path]!,
          entry: path,
          path: path,
          sha256: artifactsByPath[path]!.contentHash,
        ),
    ],
  );
  await _writeText(projectRoot, layout.outputIndexPath, index.encodeJson());
}

/// Encode one real bundle through the shared codec and write it.
Future<void> writeGeneratedBundle(
  Directory projectRoot, {
  required String bundlePath,
  required String libraryPath,
  required List<RestageBundleEntry> entries,
}) async {
  await _writeBytes(
    projectRoot,
    bundlePath,
    RestageBundleCodec.encode(
      RestageBundle(
        packageName: fixturePackageName,
        authoredLibraryPath: libraryPath,
        entries: entries,
      ),
    ),
  );
}

/// Re-encode the bundle at [bundlePath] with [entryPath] rebuilt from
/// [bytes]. The bundle stays internally consistent, so only a cross-layer
/// comparison against the index and manifest can detect the drift.
Future<void> rewriteBundleEntryBytes(
  Directory projectRoot, {
  required String bundlePath,
  required String entryPath,
  required List<int> bytes,
}) => _rebuildBundle(
  projectRoot,
  bundlePath,
  (entries) => [
    for (final entry in entries)
      if (entry.logicalPath == entryPath)
        RestageBundleEntry(
          logicalPath: entry.logicalPath,
          role: entry.role,
          bytes: bytes,
        )
      else
        entry,
  ],
);

/// Re-encode the bundle at [bundlePath] with [entryPath] recorded under
/// [role] instead of the role its publication manifest declares.
Future<void> rewriteBundleEntryRole(
  Directory projectRoot, {
  required String bundlePath,
  required String entryPath,
  required RestageBundleEntryRoleV1 role,
}) => _rebuildBundle(
  projectRoot,
  bundlePath,
  (entries) => [
    for (final entry in entries)
      if (entry.logicalPath == entryPath)
        RestageBundleEntry(
          logicalPath: entry.logicalPath,
          role: role,
          bytes: entry.bytes,
        )
      else
        entry,
  ],
);

/// Re-encode the bundle at [bundlePath] without [entryPath].
Future<void> removeBundleEntry(
  Directory projectRoot, {
  required String bundlePath,
  required String entryPath,
}) => _rebuildBundle(
  projectRoot,
  bundlePath,
  (entries) => [
    for (final entry in entries)
      if (entry.logicalPath != entryPath) entry,
  ],
);

/// Re-encode the bundle at [bundlePath] with one extra entry no publication
/// declares.
///
/// Defaults to [RestageBundleEntryRoleV1.screenBlob]; pass
/// [RestageBundleEntryRoleV1.rfwText] to add the kind of entry a real bundle
/// now always carries alongside its manifest-closure artifacts.
Future<void> addUnrelatedBundleEntry(
  Directory projectRoot, {
  required String bundlePath,
  required String entryPath,
  RestageBundleEntryRoleV1 role = RestageBundleEntryRoleV1.screenBlob,
}) => _rebuildBundle(
  projectRoot,
  bundlePath,
  (entries) => [
    ...entries,
    RestageBundleEntry(
      logicalPath: entryPath,
      role: role,
      bytes: ordinaryRfwBlob(),
    ),
  ],
);

Future<void> _rebuildBundle(
  Directory projectRoot,
  String bundlePath,
  List<RestageBundleEntry> Function(List<RestageBundleEntry> entries) rebuild,
) async {
  final file = File(p.join(projectRoot.path, bundlePath));
  final bundle = RestageBundleCodec.decode(await file.readAsBytes());
  await writeGeneratedBundle(
    projectRoot,
    bundlePath: bundlePath,
    libraryPath: bundle.authoredLibraryPath,
    entries: rebuild(bundle.entries),
  );
}

/// Read the generated index document as written.
Future<String> readGeneratedIndexSource(
  Directory projectRoot, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
}) => File(p.join(projectRoot.path, layout.outputIndexPath)).readAsString();

/// Overwrite the generated index document with exact [source] bytes.
Future<void> writeGeneratedIndexSource(
  Directory projectRoot,
  String source, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
  String? at,
}) => _writeText(projectRoot, at ?? layout.outputIndexPath, source);

/// Rewrite the generated index after applying [mutate] to its decoded JSON.
Future<void> mutateGeneratedIndex(
  Directory projectRoot,
  void Function(Map<String, Object?> index) mutate, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
}) async {
  final document =
      jsonDecode(await readGeneratedIndexSource(projectRoot, layout: layout))
          as Map<String, Object?>;
  mutate(document);
  await writeGeneratedIndexSource(
    projectRoot,
    const JsonEncoder.withIndent('  ').convert(document),
    layout: layout,
  );
}

/// The decoded locator entries of a generated index document.
List<Map<String, Object?>> indexEntriesOf(Map<String, Object?> index) => [
  for (final entry in index['entries']! as List<Object?>)
    entry! as Map<String, Object?>,
];

Future<void> _writePackageMetadata(
  Directory projectRoot,
  GeneratedOutputLayout layout,
) async {
  await _writeText(
    projectRoot,
    'pubspec.yaml',
    'name: $fixturePackageName\n'
        'environment:\n'
        "  sdk: '>=3.8.0 <4.0.0'\n",
  );
  if (layout == GeneratedOutputLayout.outputRoot) {
    await _writeText(
      projectRoot,
      'build.yaml',
      'targets:\n'
          r'  $default:'
          '\n'
          '    builders:\n'
          '      $restageOutputsBuilderKey:\n'
          '        options:\n'
          '          output_root: $fixtureOutputRoot\n',
    );
  }
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

/// The package-relative publication manifest path of the default layout.
const String defaultGeneratedManifestPath =
    surfacePublicationManifestRelativePath;
