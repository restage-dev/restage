import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/measurement/measurement_publication_candidate_assembler.dart';
import 'package:restage_cli/src/publication/publication_bundle_reader.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

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
///
/// Pass [surface] to seed a non-paywall category. Without it every fixture in
/// this file is a paywall, which makes a mixed-category file — the shape that
/// exercises every surface-type filter — inexpressible.
Future<SurfacePublicationManifestEntry> seedGeneratedPaywall(
  Directory projectRoot, {
  String slug = 'pro_upgrade',
  int minClient = 2,
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
  List<int>? blob,
  List<String> sources = const <String>[],
  Surface surface = Surface.paywall,
}) async {
  final exactBlob = Uint8List.fromList(blob ?? ordinaryRfwBlob());
  final sidecar = CapabilitySidecar(
    blobSha256: CapabilitySidecar.hashBlob(exactBlob),
    manifest: CapabilityManifest(
      builtInFloor: minClient,
      requiredLibraries: const [],
    ),
  );
  final payload = BlobSurfacePayload(minClient: minClient, blob: exactBlob);
  // A non-paywall category is seeded as an independently published ordinary
  // screen: it reuses the same blob closure, so only the declared identity
  // differs from the paywall case.
  final screenContract = surface == Surface.paywall
      ? null
      : _screenContractFor(minClient);
  final publication = SurfacePublication(
    surface: surface,
    slug: slug,
    sourceKind: screenContract == null
        ? SurfaceSourceKind.paywall
        : SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: payload.contentHash,
    contractVersion: screenContract?.version,
    capabilities: screenContract?.capabilities,
    eventContract: screenContract?.events,
    eventContractHash: screenContract?.eventsHash,
    contractFingerprint: screenContract?.fingerprint,
  );
  final blobPath = 'assets/restage/generated/$slug/screen.rfw';
  final sidecarPath = 'assets/restage/generated/$slug/screen.capability.json';
  await _writeBytes(projectRoot, blobPath, exactBlob);
  await _writeText(projectRoot, sidecarPath, jsonEncode(sidecar.toJson()));
  final entry = SurfacePublicationManifestEntry(
    publication: publication,
    sources: sources,
    artifacts: [
      SurfacePublicationArtifact(
        contentHash: CapabilitySidecar.hashBlob(exactBlob),
        path: blobPath,
        role: SurfacePublicationArtifactRole.screenBlob,
        id: slug,
      ),
      SurfacePublicationArtifact(
        contentHash: CapabilitySidecar.hashBlob(
          utf8.encode(jsonEncode(sidecar.toJson())),
        ),
        path: sidecarPath,
        role: SurfacePublicationArtifactRole.capabilitySidecar,
        id: slug,
      ),
    ],
  );
  await writeGeneratedOutput(projectRoot, [entry], layout: layout);
  return entry;
}

/// The generated surface publication closure and matching target-neutral Measurement draft
/// used by publication command tests.
final class MeasurementPublicationFixture {
  /// Construct a Measurement publication fixture.
  const MeasurementPublicationFixture({
    required this.entry,
    required this.draft,
    required this.bytesByPath,
  });

  /// The generated publication selected by the fixture.
  final SurfacePublicationManifestEntry entry;

  /// The generated target-neutral Measurement draft.
  final MeasurementPublicationDraftV1 draft;

  /// Exact bytes for every artifact in [entry].
  final Map<String, Uint8List> bytesByPath;
}

/// Write a generated paywall with an admitted or zero-route Measurement draft.
Future<MeasurementPublicationFixture> seedMeasurementPaywall(
  Directory projectRoot, {
  bool admittedRoute = true,
  bool mismatchEmittedCarrier = false,
  String? screenDraftHashOverride,
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
}) async {
  const slug = 'measured_upgrade';
  final placeholderPayload = BlobSurfacePayload(
    minClient: 2,
    blob: ordinaryRfwBlob(),
  );
  final publication = SurfacePublication(
    surface: Surface.paywall,
    slug: slug,
    sourceKind: SurfaceSourceKind.paywall,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: placeholderPayload.contentHash,
  );
  final placeholderArtifacts = <SurfacePublicationArtifact>[
    SurfacePublicationArtifact(
      contentHash: 'sha256:${'0' * 64}',
      path: 'assets/restage/generated/$slug/screen.rfw',
      role: SurfacePublicationArtifactRole.screenBlob,
      id: slug,
    ),
    SurfacePublicationArtifact(
      contentHash: 'sha256:${'1' * 64}',
      path: 'assets/restage/generated/$slug/screen.capability.json',
      role: SurfacePublicationArtifactRole.capabilitySidecar,
      id: slug,
    ),
  ];
  final screenId = _measurementArtifactId(
    publication,
    placeholderArtifacts.first,
  );
  final sidecarId = _measurementArtifactId(
    publication,
    placeholderArtifacts.last,
  );
  final screenEdge = ArtifactOccurrenceEdgeToken('edge.measured-screen');
  final sidecarEdge = ArtifactOccurrenceEdgeToken('edge.measured-sidecar');
  final routeArtifacts = <MeasurementPublicationRouteArtifactV1>[
    MeasurementPublicationRouteArtifactV1(
      artifactId: ArtifactId(screenId),
      artifactKind: ArtifactKindId('rfw.blob'),
      occurrenceEdgeToken: screenEdge,
      localManifestId: MeasurementManifestId('manifest.measured-screen'),
    ),
    MeasurementPublicationRouteArtifactV1(
      artifactId: ArtifactId(sidecarId),
      artifactKind: ArtifactKindId('publication.capability-sidecar'),
      occurrenceEdgeToken: sidecarEdge,
      localManifestId: MeasurementManifestId('manifest.measured-sidecar'),
      parentOccurrenceEdgeToken: screenEdge,
    ),
  ];
  final routePlan = MeasurementPublicationRoutePlanV1(
    surfaceId: SurfaceId(_measurementSurfaceId(publication)),
    analyticsSurfaceKey: AnalyticsSurfaceKey('paywall.$slug'),
    deliverySurfaceType: DeliverySurfaceTypeId('paywall'),
    minimumMeasurementClient: 1,
    completeManifestId: MeasurementManifestId('manifest.measured-complete'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.measured.v1'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.measured.v1'),
    artifacts: routeArtifacts,
    codeIdentityBindings: [
      CodeIdentityBindingV1(
        codeIdentityId: CodeIdentityId('code.measured-button'),
        canonicalNodeTokenId: NodeTokenId('node.measured-button'),
      ),
    ],
    nodes: [
      MeasurementPublicationDraftNodeV1(
        codeIdentityId: CodeIdentityId('code.measured-button'),
        artifactOccurrenceEdgeToken: screenEdge,
      ),
    ],
    events: admittedRoute
        ? [
            MeasurementPublicationDraftEventV1(
              nodeCodeIdentityId: CodeIdentityId('code.measured-button'),
              sourceEventIdentity: SourceEventIdentity('onPressed'),
              lineageId: PointLineageId('lineage.measured-button'),
              generatedReferenceId: GeneratedReferenceId(
                'reference.measured-button',
              ),
              dartSymbol: GeneratedDartSymbol('measuredButton'),
              displayMetadataRef: DisplayMetadataRef('display.measured-button'),
              normalizedInteractionKind: NormalizedInteractionKind.activate,
              privacyClass: MeasurementPrivacyClass.nonSensitive,
              semanticValueClass: SemanticValueClass.activityOnly,
              collectionClass: MeasurementCollectionClass.tier2Coalesced,
            ),
          ]
        : const [],
    routeSeeds: admittedRoute
        ? [
            MeasurementPublicationDraftRouteSeedV1(
              generatedReferenceId: GeneratedReferenceId(
                'reference.measured-button',
              ),
              artifactOccurrenceEdgeToken: screenEdge,
            ),
          ]
        : const [],
    lineageIntents: admittedRoute
        ? [
            MeasurementPublicationLineageIntentV1(
              transitionId: LineageTransitionId('transition.measured-button'),
              operation: LineageOperation.create,
              authority: LineageTransitionAuthority.exactToken,
              next: [
                MeasurementPublicationCurrentEndpointIntentV1(
                  generatedReferenceId: GeneratedReferenceId(
                    'reference.measured-button',
                  ),
                  lineageId: PointLineageId('lineage.measured-button'),
                ),
              ],
            ),
          ]
        : const [],
  );

  final Uint8List blob;
  if (admittedRoute) {
    final expectedCarrier = routePlan.routes.single.carrier;
    final emittedCarrier = mismatchEmittedCarrier
        ? '${expectedCarrier.substring(0, expectedCarrier.length - 1)}'
              '${expectedCarrier.endsWith('A') ? 'B' : 'A'}'
        : expectedCarrier;
    blob = rfw.encodeLibraryBlob(
      rfw.parseLibraryFile('''
import restage.core;
widget Preview = Button(
  onPressed: event "activate" {
    $kMeasurementPublicationRouteArgumentKeyV1: "$emittedCarrier"
  }
);
'''),
    );
  } else {
    blob = ordinaryRfwBlob();
  }

  final entry = await seedGeneratedPaywall(
    projectRoot,
    slug: slug,
    blob: blob,
    layout: layout,
  );
  final routeArtifactById = {
    for (final artifact in routeArtifacts) artifact.artifactId.value: artifact,
  };
  final draft = MeasurementPublicationDraftV1(
    routePlan: routePlan,
    artifacts: [
      for (final artifact in entry.artifacts)
        MeasurementPublicationDraftArtifactV1(
          artifactId: ArtifactId(_measurementArtifactId(publication, artifact)),
          artifactKind: ArtifactKindId(switch (artifact.role) {
            SurfacePublicationArtifactRole.flowDocument =>
              'publication.flow-document',
            SurfacePublicationArtifactRole.screenBlob => 'rfw.blob',
            SurfacePublicationArtifactRole.capabilitySidecar =>
              'publication.capability-sidecar',
          }),
          contentHash: CanonicalDigest(
            artifact.role == SurfacePublicationArtifactRole.screenBlob &&
                    screenDraftHashOverride != null
                ? screenDraftHashOverride
                : artifact.contentHash.substring(7),
          ),
          occurrenceEdgeToken:
              routeArtifactById[_measurementArtifactId(publication, artifact)]!
                  .occurrenceEdgeToken,
          localManifestId:
              routeArtifactById[_measurementArtifactId(publication, artifact)]!
                  .localManifestId,
          parentOccurrenceEdgeToken:
              routeArtifactById[_measurementArtifactId(publication, artifact)]!
                  .parentOccurrenceEdgeToken,
        ),
    ],
  );
  await writeMeasurementPublicationIndex(
    projectRoot,
    entry,
    draft,
    layout: layout,
  );
  final bytesByPath = <String, Uint8List>{
    for (final artifact in entry.artifacts)
      artifact.path: await File(
        p.join(projectRoot.path, artifact.path),
      ).readAsBytes(),
  };
  return MeasurementPublicationFixture(
    entry: entry,
    draft: draft,
    bytesByPath: bytesByPath,
  );
}

/// Write the generated Measurement publication index for [entry] and [draft].
Future<void> writeMeasurementPublicationIndex(
  Directory projectRoot,
  SurfacePublicationManifestEntry entry,
  MeasurementPublicationDraftV1 draft, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
}) async {
  final file = File(
    p.join(
      projectRoot.path,
      layout.metadataDirectory,
      restageMeasurementPublicationIndexFileName,
    ),
  );
  await file.writeAsBytes(
    CanonicalJsonCodec.encode({
      'entries': [
        {
          'draftBase64': base64UrlEncode(
            draft.canonicalBytes,
          ).replaceAll('=', ''),
          'draftDigest': draft.canonicalDigest.hex,
          'routePlanDigest': draft.routeDraftClosureDigest.hex,
          'selector': {
            if (entry.publication.sourceKind == SurfaceSourceKind.screen)
              'contractVersion': entry.publication.contractVersion,
            'slug': entry.publication.slug,
            'sourceKind': entry.publication.sourceKind.wireName,
            'surface': entry.publication.surface.wireName,
          },
          'surfaceId': draft.surfaceId.value,
        },
      ],
      'kind': 'restageMeasurementPublicationIndex',
      'package': fixturePackageName,
      'schemaVersion': 1,
    }),
  );
}

/// Compute the candidate reference expected for an exact generated closure.
MeasurementPublicationCandidateReferenceV1
expectedMeasurementCandidateReference({
  required SurfacePublicationManifestEntry entry,
  required List<int> manifestBytes,
  required List<int> uploadBytes,
  required MeasurementPublicationDraftV1 draft,
  required Map<String, Uint8List> bytesByPath,
}) {
  final tuples = <({Uint8List bytes, Map<String, Object?> value})>[];
  for (final artifact in entry.artifacts) {
    final bytes = bytesByPath[artifact.path]!;
    final value = <String, Object?>{
      'byteLength': bytes.length,
      if (artifact.id != null) 'id': artifact.id,
      'kind': 'restageSurfacePublicationDeclaredArtifactTuple',
      'path': artifact.path,
      'role': artifact.role.wireName,
      'schemaVersion': 1,
      'sha256': crypto.sha256.convert(bytes).toString(),
    };
    tuples.add((
      bytes: Uint8List.fromList(CanonicalJsonCodec.encode(value)),
      value: value,
    ));
  }
  tuples.sort((left, right) => _compareBytes(left.bytes, right.bytes));
  final declaredBytesDigest = CanonicalDigest(
    _privateDigest('restage-surface-publication-declared-artifact-bytes-v1', {
      'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
      'schemaVersion': 1,
      'tuples': [for (final tuple in tuples) tuple.value],
    }),
  );
  return MeasurementPublicationCandidateProofV1(
    selectedPublicationManifestCanonicalBytes: manifestBytes,
    declaredArtifactTuples: [
      for (final tuple in tuples)
        MeasurementPublicationCandidateArtifactTupleV1(
          canonicalTupleBytes: tuple.bytes,
        ),
    ],
    declaredArtifactBytesDigest: declaredBytesDigest,
    assembledPublicationUploadCanonicalBytes: uploadBytes,
    measurementPublicationDraft: draft,
  ).reference;
}

String _measurementSurfaceId(SurfacePublication publication) =>
    'surface.v1.${_privateDigest('restage-surface-publication-line-v1', {if (publication.sourceKind == SurfaceSourceKind.screen) 'contractVersion': publication.contractVersion, 'kind': 'publicationLine', 'schemaVersion': 1, 'slug': publication.slug, 'sourceKind': publication.sourceKind.wireName, 'surface': publication.surface.wireName})}';

String _measurementArtifactId(
  SurfacePublication publication,
  SurfacePublicationArtifact artifact,
) =>
    'artifact.v1.${_privateDigest('restage-measurement-artifact-definition-v1', {
      'artifactSlot': '${artifact.role.wireName}:${artifact.id ?? ''}',
      'publication': {if (publication.sourceKind == SurfaceSourceKind.screen) 'contractVersion': publication.contractVersion, 'slug': publication.slug, 'sourceKind': publication.sourceKind.wireName, 'surface': publication.surface.wireName},
    })}';

String _privateDigest(String domain, Object? value) => crypto.sha256.convert(
  <int>[...utf8.encode('$domain\u0000'), ...CanonicalJsonCodec.encode(value)],
).toString();

int _compareBytes(List<int> left, List<int> right) {
  final shared = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < shared; index++) {
    final difference = left[index] - right[index];
    if (difference != 0) return difference;
  }
  return left.length - right.length;
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
  List<SurfacePublicationManifestEntry> entries, {
  GeneratedOutputLayout layout = GeneratedOutputLayout.generatedDirectory,
  String Function(String artifactPath)? libraryFor,
}) async {
  PublicationBundleReaderProvider.override = null;
  await _writePackageMetadata(projectRoot, layout);

  final artifactsByPath = <String, SurfacePublicationArtifact>{};
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
            role: RestageBundleEntryRole.fromManifestRole(
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
    SurfacePublicationManifest(publications: entries),
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
  required RestageBundleEntryRole role,
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
/// Defaults to [RestageBundleEntryRole.screenBlob]; pass
/// [RestageBundleEntryRole.rfwText] to add the kind of entry a real bundle
/// now always carries alongside its manifest-closure artifacts.
Future<void> addUnrelatedBundleEntry(
  Directory projectRoot, {
  required String bundlePath,
  required String entryPath,
  RestageBundleEntryRole role = RestageBundleEntryRole.screenBlob,
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

/// The contract quartet an independently published screen declares.
///
/// Derived once so the fingerprint recipe lives in exactly one place.
({
  int version,
  CapabilityManifest capabilities,
  SurfaceScreenEventSchema events,
  String eventsHash,
  String fingerprint,
})
_screenContractFor(int minClient) {
  final events = SurfaceScreenEventSchema(events: const []);
  final eventsHash = SurfaceScreenEventContractHash.hash(events);
  final capabilities = CapabilityManifest(
    builtInFloor: minClient,
    requiredLibraries: const [],
  );
  return (
    version: 1,
    capabilities: capabilities,
    events: events,
    eventsHash: eventsHash,
    fingerprint: SurfaceScreenContractFingerprint.hash(
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      capabilities: capabilities,
      eventContractHash: eventsHash,
    ),
  );
}
