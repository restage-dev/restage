// Prove RestageOutputsBuilder's own semantics under a changing world — cold
// build, warm no-change rebuild, and add/edit/remove/rename of an authored
// library — using a minimal hand-built compiler handoff so this stays scoped
// to the outputs builder alone. It deliberately does not run the real
// roster/screen/flow builders, which have their own suites.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'output_builder_fixtures.dart';

Future<TestBuilderResult> _run(
  Map<String, String> dartSources,
  List<OutputsFixture> fixtures,
  TestReaderWriter readerWriter,
) {
  final sources = <String, String>{
    for (final entry in dartSources.entries)
      'apps_examples|${entry.key}': entry.value,
    'apps_examples|$compilerJsonPath': compilerJsonFor(fixtures),
  };
  return testBuilder(
    RestageOutputsBuilder(BuilderOptions.empty),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

bool _bundleExists(TestReaderWriter readerWriter, String path) =>
    readerWriter.testing.exists(AssetId('apps_examples', path));

List<int> _bundleBytes(TestReaderWriter readerWriter, String path) =>
    readerWriter.testing.readBytes(AssetId('apps_examples', path));

void main() {
  const alphaBundlePath = 'lib/features/restage.generated/alpha.rsbundle';
  const betaBundlePath = 'lib/features/restage.generated/beta.rsbundle';
  const renamedBundlePath = 'lib/journeys/restage.generated/alpha.rsbundle';

  test('cold build from empty state materializes the expected bundle',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final result = await _run(
      {'lib/features/alpha.dart': '// authored\n'},
      [alpha],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(_bundleExists(readerWriter, alphaBundlePath), isTrue);
    final bundle = RestageBundleCodec.decode(
      _bundleBytes(readerWriter, alphaBundlePath),
    );
    expect(bundle.authoredLibraryPath, 'lib/features/alpha.dart');
    // flowDocument, screenBlob, capabilitySidecar, and the screen blob's
    // canonical .rfwtxt sibling.
    expect(bundle.entries, hasLength(4));
    expect(
      bundle.entries.map((entry) => entry.role),
      contains(RestageBundleEntryRoleV1.rfwText),
    );
  });

  test('warm no-change rebuild is byte-identical', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final dartSources = {'lib/features/alpha.dart': '// authored\n'};

    final first = await _run(dartSources, [alpha], readerWriter);
    expect(first.succeeded, isTrue, reason: first.errors.join('\n'));
    final firstBytes = _bundleBytes(readerWriter, alphaBundlePath);

    final second = await _run(dartSources, [alpha], readerWriter);
    expect(second.succeeded, isTrue, reason: second.errors.join('\n'));
    final secondBytes = _bundleBytes(readerWriter, alphaBundlePath);

    expect(secondBytes, orderedEquals(firstBytes));
  });

  test(
      'adding an authored library adds its bundle without disturbing '
      'the existing one', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final beta = flowFixture(
      slug: 'beta',
      libraryPath: 'lib/features/beta.dart',
      screenBytes: const [4, 5, 6],
    );

    final before = await _run(
      {'lib/features/alpha.dart': '// authored\n'},
      [alpha],
      readerWriter,
    );
    expect(before.succeeded, isTrue, reason: before.errors.join('\n'));
    final alphaBytesBefore = _bundleBytes(readerWriter, alphaBundlePath);

    final after = await _run(
      {
        'lib/features/alpha.dart': '// authored\n',
        'lib/features/beta.dart': '// authored\n',
      },
      [alpha, beta],
      readerWriter,
    );
    expect(after.succeeded, isTrue, reason: after.errors.join('\n'));

    expect(_bundleExists(readerWriter, betaBundlePath), isTrue);
    expect(
      _bundleBytes(readerWriter, alphaBundlePath),
      orderedEquals(alphaBytesBefore),
      reason: 'Adding a sibling library must not perturb an unrelated '
          "library's bundle.",
    );
  });

  test('editing an artifact updates only the owning bundle', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final beta = flowFixture(
      slug: 'beta',
      libraryPath: 'lib/features/beta.dart',
      screenBytes: const [4, 5, 6],
    );
    final dartSources = {
      'lib/features/alpha.dart': '// authored\n',
      'lib/features/beta.dart': '// authored\n',
    };

    final before = await _run(dartSources, [alpha, beta], readerWriter);
    expect(before.succeeded, isTrue, reason: before.errors.join('\n'));
    final betaBytesBefore = _bundleBytes(readerWriter, betaBundlePath);

    final editedAlpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [9, 9, 9],
    );
    final after = await _run(
      dartSources,
      [editedAlpha, beta],
      readerWriter,
    );
    expect(after.succeeded, isTrue, reason: after.errors.join('\n'));

    final editedBundle = RestageBundleCodec.decode(
      _bundleBytes(readerWriter, alphaBundlePath),
    );
    final editedBlob = editedBundle.entries.singleWhere(
      (entry) => entry.logicalPath == 'assets/general/screens/alpha.rfw',
    );
    expect(editedBlob.bytes, orderedEquals(const [9, 9, 9]));
    expect(
      _bundleBytes(readerWriter, betaBundlePath),
      orderedEquals(betaBytesBefore),
      reason: "Editing alpha's artifact must not perturb beta's bundle.",
    );
  });

  // NOTE on "stale output deletion": `testBuilder()` runs each call through a
  // brand-new `BuildPlan`/asset graph (`BuildPlan.load` +
  // `deleteFilesAndFolders()` at the start of every invocation) — it has no
  // memory of a *previous* `testBuilder()` call's build. A file this harness
  // left behind from an earlier round persists in the shared `TestReaderWriter`
  // purely as a filesystem artifact of the test harness, not because a real
  // incremental build chose to keep it. Proving that a real `build_runner`
  // watch/incremental run deletes a stale output for a removed/renamed input
  // is build_runner's own persistent asset-graph responsibility (exercised by
  // its own test suite, not by this package's builder-level unit tests) — the
  // property this builder must uphold, and the one provable here, is that
  // every physical output path is one `output_placement_test.dart` already
  // proves is statically enumerable from `buildExtensions` (never an
  // arbitrary runtime-chosen path), which is exactly the precondition
  // build_runner's real engine needs to prune it. What's provable per build
  // round via `TestBuilderResult.outputs` is that a round which no longer
  // admits a library does not (re)write that library's bundle, and that a
  // renamed library's bundle is written at its new path with its bytes
  // intact.
  test('removing an authored library stops producing its bundle', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final beta = flowFixture(
      slug: 'beta',
      libraryPath: 'lib/features/beta.dart',
      screenBytes: const [4, 5, 6],
    );
    final before = await _run(
      {
        'lib/features/alpha.dart': '// authored\n',
        'lib/features/beta.dart': '// authored\n',
      },
      [alpha, beta],
      readerWriter,
    );
    expect(before.succeeded, isTrue, reason: before.errors.join('\n'));
    expect(_bundleExists(readerWriter, betaBundlePath), isTrue);

    readerWriter.testing.delete(
      AssetId('apps_examples', 'lib/features/beta.dart'),
    );
    final after = await _run(
      {'lib/features/alpha.dart': '// authored\n'},
      [alpha],
      readerWriter,
    );
    expect(after.succeeded, isTrue, reason: after.errors.join('\n'));

    expect(
      after.outputs,
      isNot(contains(AssetId('apps_examples', betaBundlePath))),
      reason: 'A build round that no longer admits beta must not (re)write '
          "beta's bundle.",
    );
    expect(
      after.outputs,
      contains(AssetId('apps_examples', alphaBundlePath)),
    );
  });

  test('renaming an authored library produces its bundle at the new path',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final before = await _run(
      {'lib/features/alpha.dart': '// authored\n'},
      [alpha],
      readerWriter,
    );
    expect(before.succeeded, isTrue, reason: before.errors.join('\n'));
    expect(_bundleExists(readerWriter, alphaBundlePath), isTrue);

    readerWriter.testing.delete(
      AssetId('apps_examples', 'lib/features/alpha.dart'),
    );
    final moved = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/journeys/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    final after = await _run(
      {'lib/journeys/alpha.dart': '// authored\n'},
      [moved],
      readerWriter,
    );
    expect(after.succeeded, isTrue, reason: after.errors.join('\n'));

    expect(
      after.outputs,
      isNot(contains(AssetId('apps_examples', alphaBundlePath))),
      reason: 'A build round rooted at the new library path must not '
          "(re)write the old path's bundle.",
    );
    expect(
      after.outputs,
      contains(AssetId('apps_examples', renamedBundlePath)),
    );
    final movedBundle = RestageBundleCodec.decode(
      _bundleBytes(readerWriter, renamedBundlePath),
    );
    expect(movedBundle.authoredLibraryPath, 'lib/journeys/alpha.dart');
  });

  test(
      'restage.outputs.json sorts by UTF-8 path-byte order, not UTF-16 '
      'code-unit order', () async {
    // U+E000 (a lone BMP character above the surrogate range) and U+1F600
    // (an astral character requiring a UTF-16 surrogate pair) order
    // oppositely under the two comparators: U+E000 encodes to 3 UTF-8 bytes
    // starting with 0xEE, while U+1F600's high surrogate (0xD83D) is a
    // *smaller* UTF-16 code unit than U+E000 itself, even though U+1F600's
    // own 4-byte UTF-8 encoding starts with 0xF0 — a larger leading byte.
    // So UTF-16 code-unit order places the astral slug first; UTF-8 byte
    // order places the BMP slug first.
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final bmpSlug = flowFixture(
      slug: 'bmp',
      libraryPath: 'lib/features/bmp.dart',
      screenBytes: const [1],
      pathSegment: 'x',
    );
    final astralSlug = flowFixture(
      slug: 'astral',
      libraryPath: 'lib/features/astral.dart',
      screenBytes: const [2],
      pathSegment: 'x😀',
    );

    // Sanity-check the fixture actually exercises the claimed divergence
    // before trusting the assertion below.
    const bmpPath = 'assets/general/flows/x.flow.json';
    const astralPath = 'assets/general/flows/x😀.flow.json';
    expect(
      bmpPath.compareTo(astralPath) > 0,
      isTrue,
      reason: 'Fixture must place the BMP path after the astral path under '
          'UTF-16 code-unit order for this regression to be meaningful.',
    );

    final result = await _run(
      {
        'lib/features/bmp.dart': '// authored\n',
        'lib/features/astral.dart': '// authored\n',
      },
      [bmpSlug, astralSlug],
      readerWriter,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final indexJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/generated/restage.outputs.json'),
      ),
    ) as Map<String, Object?>;
    final paths = [
      for (final entry in (indexJson['entries']! as List<Object?>)
          .cast<Map<String, Object?>>())
        entry['path']! as String,
    ];

    expect(
      paths.indexOf(bmpPath) < paths.indexOf(astralPath),
      isTrue,
      reason: 'restage.outputs.json must sort by UTF-8 path-byte order '
          '(bmp before astral), matching the .rsbundle codec — not by Dart '
          "String.compareTo's UTF-16 code-unit order (which would place "
          'astral before bmp).',
    );
  });

  test(
      'fails loudly on a generated text the compiler never attributed to '
      'an authored library', () async {
    // Every output file's attribution comes directly from the compiler's
    // own write choke point (package_surface_compiler.dart's _putFile) —
    // there is no derived or sibling-based fallback. An owned output the
    // compiler never attributed must fail the build rather than silently
    // vanish from every library's bundle.
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final alpha = flowFixture(
      slug: 'alpha',
      libraryPath: 'lib/features/alpha.dart',
      screenBytes: const [1, 2, 3],
    );
    const orphanTextPath = 'assets/general/screens/orphan.rfwtxt';
    final bundle = RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifestV1(publications: [alpha.entry]),
      artifacts: alpha.files,
      ownedOutputs: {
        ...alpha.ownedOutputs,
        orphanTextPath: utf8.encode('orphaned generated text'),
      },
      artifactLibraryPaths: {
        for (final path in alpha.files.keys) path: alpha.libraryPath,
        for (final path in alpha.ownedOutputs.keys) path: alpha.libraryPath,
      },
    );
    final sources = {
      'apps_examples|lib/features/alpha.dart': '// authored\n',
      'apps_examples|$compilerJsonPath': bundle.encodeCanonicalJson(),
    };

    final result = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains(orphanTextPath));
  });

  test(
      'attributes a navigation-paywall generated text with no stem-sibling '
      'blob', () async {
    // A navigation paywall's canonical text lives at assets/paywalls/<id>
    // .rfwtxt, but its screen artifacts live under a differently-named
    // assets/paywalls/screens/paywall_<id>* family — there is no
    // assets/paywalls/<id>.rfw for the text to pair with by path math. This
    // reproduces the exact shape the regen phase's hard stop found.
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final fluentPro = _navigationPaywallFixture(
      slug: 'fluent_pro',
      libraryPath: 'lib/paywalls/fluent_pro.dart',
      screenIds: const ['welcome', 'upsell'],
    );
    final sources = <String, String>{
      'apps_examples|lib/paywalls/fluent_pro.dart': '// authored\n',
      'apps_examples|$compilerJsonPath': fluentPro.bundle.encodeCanonicalJson(),
    };

    final libraryResult = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      libraryResult.succeeded,
      isTrue,
      reason: libraryResult.errors.join('\n'),
    );

    final bundleBytes = readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/paywalls/restage.generated/fluent_pro.rsbundle',
      ),
    );
    final bundle = RestageBundleCodec.decode(bundleBytes);
    final textEntry = bundle.entries.singleWhere(
      (entry) => entry.logicalPath == 'assets/paywalls/fluent_pro.rfwtxt',
    );
    expect(textEntry.role, RestageBundleEntryRoleV1.rfwText);
    expect(
      bundle.entries.map((entry) => entry.logicalPath),
      containsAll(<String>[
        'assets/paywalls/fluent_pro.flow.json',
        'assets/paywalls/screens/paywall_fluent_pro_welcome.rfw',
        'assets/paywalls/screens/paywall_fluent_pro_welcome.capability.json',
        'assets/paywalls/screens/paywall_fluent_pro_upsell.rfw',
        'assets/paywalls/screens/paywall_fluent_pro_upsell.capability.json',
      ]),
    );

    final packageResult = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      packageResult.succeeded,
      isTrue,
      reason: packageResult.errors.join('\n'),
    );
    final indexJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/generated/restage.outputs.json'),
      ),
    ) as Map<String, Object?>;
    final indexedPaths = [
      for (final entry in (indexJson['entries']! as List<Object?>)
          .cast<Map<String, Object?>>())
        entry['path']! as String,
    ];
    // The index is an exact bijection with the manifest's own artifact
    // set: the text stays in the bundle (asserted above) but is never a
    // manifest artifact, so it is never indexed either — its physical
    // location is discoverable through the manifest artifacts the index
    // does locate for this same library.
    expect(indexedPaths, isNot(contains('assets/paywalls/fluent_pro.rfwtxt')));
    expect(
      indexedPaths,
      containsAll(<String>[
        'assets/paywalls/fluent_pro.flow.json',
        'assets/paywalls/screens/paywall_fluent_pro_welcome.rfw',
        'assets/paywalls/screens/paywall_fluent_pro_welcome.capability.json',
        'assets/paywalls/screens/paywall_fluent_pro_upsell.rfw',
        'assets/paywalls/screens/paywall_fluent_pro_upsell.capability.json',
      ]),
    );
  });

  test(
      'an unattributed text in the package never fails an unrelated '
      "library's own build step", () async {
    // The single-owner failure fix: a generated text this build genuinely
    // cannot attribute must fail the package-wide step (which needs every
    // entry accounted for) without ever failing a DIFFERENT, unrelated
    // library's own per-library build step — reproducing the reported
    // defect where one paywall's unattributable text failed
    // tool/build_paywall.dart, an unrelated library in the same package.
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final known = flowFixture(
      slug: 'known',
      libraryPath: 'lib/features/known.dart',
      screenBytes: const [9, 9, 9],
    );
    const orphanTextPath = 'assets/general/screens/orphan.rfwtxt';
    final bundle = RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifestV1(publications: [known.entry]),
      artifacts: known.files,
      ownedOutputs: {
        ...known.ownedOutputs,
        orphanTextPath: utf8.encode('orphaned generated text'),
      },
      artifactLibraryPaths: {
        for (final path in known.files.keys) path: known.libraryPath,
        for (final path in known.ownedOutputs.keys) path: known.libraryPath,
        // orphanTextPath is deliberately absent: it belongs to no library.
      },
    );
    final sources = <String, String>{
      'apps_examples|lib/features/known.dart': '// authored\n',
      'apps_examples|$compilerJsonPath': bundle.encodeCanonicalJson(),
    };

    // One build processes both the $package$ node and known.dart's own
    // node — build_test runs every matching input in one pass, so this is
    // the real shape to prove against, not two separate invocations. The
    // package-wide step (which needs every entry accounted for) fails
    // loud on the orphan, but that is an independent build STEP from
    // known.dart's own: its bundle must still have been written.
    final result = await testBuilder(
      RestageOutputsBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains(orphanTextPath));
    expect(
      readerWriter.testing.exists(
        AssetId(
          'apps_examples',
          'lib/features/restage.generated/known.rsbundle',
        ),
      ),
      isTrue,
      reason: "known.dart's own build step must succeed and write its "
          "bundle independently of the package-wide step's failure over "
          'an unrelated orphan text.',
    );
    final knownBundle = RestageBundleCodec.decode(
      readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/features/restage.generated/known.rsbundle',
        ),
      ),
    );
    expect(
      knownBundle.entries.map((entry) => entry.logicalPath),
      isNot(contains(orphanTextPath)),
      reason: 'The orphan belongs to no library, so it must never appear '
          "in known's bundle either.",
    );
  });
}

/// One navigation-paywall-shaped fixture: a flow document plus multiple
/// screen artifacts under `assets/paywalls/screens/`, with the paywall's own
/// canonical text at `assets/paywalls/<slug>.rfwtxt` — a path with no
/// `assets/paywalls/<slug>.rfw` sibling, unlike an ordinary flow screen.
({RestageSurfacePublicationBundle bundle}) _navigationPaywallFixture({
  required String slug,
  required String libraryPath,
  required List<String> screenIds,
}) {
  final screenArtifacts = <String, ScreenArtifact>{};
  final files = <String, List<int>>{};
  final artifacts = <SurfacePublicationArtifactV1>[];
  final libraryPaths = <String, String>{};
  for (final id in screenIds) {
    final blob = utf8.encode('RFW blob for $slug/$id');
    final sidecarModel = CapabilitySidecar(
      blobSha256: CapabilitySidecar.hashBlob(blob),
      manifest: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const <LibraryRequirement>[],
      ),
    );
    final sidecarBytes = utf8.encode(jsonEncode(sidecarModel.toJson()));
    final blobPath = 'assets/paywalls/screens/paywall_${slug}_$id.rfw';
    final sidecarPath =
        'assets/paywalls/screens/paywall_${slug}_$id.capability.json';
    files[blobPath] = blob;
    files[sidecarPath] = sidecarBytes;
    libraryPaths[blobPath] = libraryPath;
    libraryPaths[sidecarPath] = libraryPath;
    artifacts.addAll([
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(blob),
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: id,
      ),
      SurfacePublicationArtifactV1(
        contentHash: CapabilitySidecar.hashBlob(sidecarBytes),
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: id,
      ),
    ]);
    screenArtifacts[id] = ScreenArtifact(
      path: '$id.rfw',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      contentHash: FlowContentHash.compute(blob),
    );
  }
  final states = <String, FlowState>{
    for (var index = 0; index < screenIds.length; index += 1)
      screenIds[index]: index == screenIds.length - 1
          ? const EndFlowState(result: <String, Object?>{'completed': true})
          : ScreenFlowState(
              screen: screenIds[index],
              on: <String, FlowTransition>{
                'next': FlowTransition.goto(screenIds[index + 1]),
              },
            ),
  };
  final document = FlowDocument(
    flow: slug,
    version: 1,
    schemaVersion: 1,
    minClient: 1,
    initial: screenIds.first,
    screenArtifacts: screenArtifacts,
    states: states,
    deliveryMode: FlowDeliveryMode.general,
  );
  final flowBytes = utf8.encode(FlowDocumentCodec.encodePrettyJson(document));
  final flowPath = 'assets/paywalls/$slug.flow.json';
  files[flowPath] = flowBytes;
  libraryPaths[flowPath] = libraryPath;
  artifacts.add(
    SurfacePublicationArtifactV1(
      contentHash: CapabilitySidecar.hashBlob(flowBytes),
      path: flowPath,
      role: SurfacePublicationArtifactRoleV1.flowDocument,
    ),
  );

  final publication = SurfacePublicationV1(
    surface: Surface.paywall,
    slug: slug,
    sourceKind: SurfaceSourceKind.paywall,
    payloadKind: SurfacePayloadKind.flow,
    payloadContentHash: CapabilitySidecar.hashBlob(flowBytes),
    deliveryMode: FlowDeliveryMode.general,
  );
  final entry = SurfacePublicationManifestEntryV1(
    artifacts: artifacts,
    publication: publication,
  );

  // The paywall's own canonical text: NOT a manifest artifact, and its path
  // has no assets/paywalls/<slug>.rfw sibling — only the screens do.
  final textPath = 'assets/paywalls/$slug.rfwtxt';
  final textBytes = utf8.encode(
    'Restage widget tree text for $slug (deterministic test fixture).',
  );
  libraryPaths[textPath] = libraryPath;

  return (
    bundle: RestageSurfacePublicationBundle.valid(
      manifest: SurfacePublicationManifestV1(publications: [entry]),
      artifacts: files,
      ownedOutputs: {textPath: textBytes},
      artifactLibraryPaths: libraryPaths,
    ),
  );
}
