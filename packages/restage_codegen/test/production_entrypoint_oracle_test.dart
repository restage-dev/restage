import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Frozen raw-byte oracle for the pre-representation production corpus.
///
/// This intentionally runs the public production builders over real app source
/// entrypoints. For each generated output it pins the exact path, raw bytes,
/// byte length, SHA-256, and descriptor/artifact kind. Wire artifacts must also
/// match the tracked shipping output in the owning app package. Generated Dart
/// descriptors are compared through a token- and legacy-alias-normalized
/// identity contract. Formatting and comments are ignored, while every token
/// lexeme (including complete string literals) remains identity-bearing.
/// Generated Dart formatting may differ; wire and identity bytes may not.
/// Flow JSON has an additional canonical-codec
/// round-trip assertion. Navigation `.navplan.json` handoffs
/// are recorded as transient build outputs: required for the next builder,
/// absent from the shipped asset tree unless a pre-existing shipping corpus
/// intentionally retains one, and never mistaken for a stale artifact.
///
/// The initial freeze is a one-time bootstrap operation:
///
///   UPDATE_EXPLICIT_AUTHORING_GOLDENS=1 dart test test/production_entrypoint_oracle_test.dart
///
/// The bootstrap refuses to overwrite an existing corpus. Once the directory
/// exists, the environment switch cannot regenerate these goldens; production
/// representation work must keep them unchanged.
const _goldenRoot = 'test/fixtures/explicit_authoring_goldens';
const _updateEnvironment = 'UPDATE_EXPLICIT_AUTHORING_GOLDENS';

const _corpora = <_CorpusCase>[
  _CorpusCase(
    name: 'examples_onboarding',
    sourcePackageName: 'restage_example',
    kind: _CorpusKind.onboardingWithPaywall,
    frozenSurfaceScreenRefIsNeutral: true,
    inputPaths: <String>[
      'lib/onboarding/flows/first_run.dart',
      'lib/onboarding/flows/bare_surface.dart',
      'lib/onboarding/flows/minimal_onboarding.dart',
      'lib/onboarding/flows/tally_onboarding.dart',
      'lib/onboarding/flows/stride_first_run.dart',
      'lib/onboarding/flows/lumen_onboarding.dart',
      'lib/onboarding/screens/notify.dart',
      'lib/onboarding/screens/ready.dart',
      'lib/onboarding/screens/value.dart',
      'lib/onboarding/screens/welcome.dart',
      'lib/onboarding/screens/starter_bare_surface.dart',
      'lib/onboarding/screens/starter_done_explore.dart',
      'lib/onboarding/screens/starter_done_guided.dart',
      'lib/onboarding/screens/starter_question.dart',
      'lib/onboarding/screens/starter_welcome.dart',
      'lib/onboarding/screens/tally_debt.dart',
      'lib/onboarding/screens/tally_goal.dart',
      'lib/onboarding/screens/tally_invest.dart',
      'lib/onboarding/screens/tally_recap_debt.dart',
      'lib/onboarding/screens/tally_recap_invest.dart',
      'lib/onboarding/screens/tally_recap_savings.dart',
      'lib/onboarding/screens/tally_savings.dart',
      'lib/onboarding/screens/tally_welcome.dart',
      'lib/onboarding/screens/stride_goals.dart',
      'lib/onboarding/screens/stride_ready.dart',
      'lib/onboarding/screens/stride_reminders.dart',
      'lib/onboarding/screens/stride_welcome.dart',
      'lib/onboarding/screens/lumen_experience.dart',
      'lib/onboarding/screens/lumen_goal.dart',
      'lib/onboarding/screens/lumen_recap.dart',
      'lib/onboarding/screens/lumen_reminder.dart',
      'lib/onboarding/screens/lumen_welcome.dart',
      'lib/paywalls/lumen_premium.dart',
    ],
    absentOutputPaths: <String>[
      'assets/onboarding/flows/first_run.rfw',
    ],
    staleOutputPaths: <String>[
      'assets/onboarding/flows/first_run.capability.json',
    ],
  ),
  _CorpusCase(
    name: 'showcase_onboarding',
    sourcePackageName: 'restage_showcase',
    kind: _CorpusKind.onboardingWithPaywall,
    frozenSurfaceScreenRefIsNeutral: true,
    inputPaths: <String>[
      'lib/onboarding/flows/hs_onboarding.dart',
      'lib/onboarding/screens/hs_experience.dart',
      'lib/onboarding/screens/hs_goal.dart',
      'lib/onboarding/screens/hs_recap.dart',
      'lib/onboarding/screens/hs_reminder.dart',
      'lib/onboarding/screens/hs_welcome.dart',
      'lib/paywalls/headspace_premium.dart',
    ],
  ),
  _CorpusCase(
    name: 'examples_paywall_navigation',
    sourcePackageName: 'restage_example',
    kind: _CorpusKind.paywallNavigation,
    inputPaths: <String>[
      'lib/paywalls/fluent_pro.dart',
      'lib/paywalls/fluent_pro_choose_plan.dart',
    ],
    virtualOnlyTransientBuildOutputPaths: <String>[
      'assets/paywalls/fluent_pro.navplan.json',
    ],
    absentOutputPaths: <String>[
      'assets/paywalls/fluent_pro_choose_plan.rfwtxt',
      'assets/paywalls/fluent_pro_choose_plan.rfw',
    ],
    staleOutputPaths: <String>[
      'assets/paywalls/fluent_pro_choose_plan.capability.json',
      'assets/paywalls/fluent_pro_choose_plan.navplan.json',
    ],
    unshippedBuildOutputPaths: <String>[
      'assets/paywalls/fluent_pro.capability.json',
      'assets/paywalls/fluent_pro.rfw',
    ],
  ),
  _CorpusCase(
    name: 'showcase_paywall_navigation',
    sourcePackageName: 'restage_showcase',
    kind: _CorpusKind.paywallNavigation,
    inputPaths: <String>[
      'lib/paywalls/duolingo_super.dart',
      'lib/paywalls/duolingo_choose_plan.dart',
    ],
    retainedTransientShippingOutputPaths: <String>[
      'assets/paywalls/duolingo_super.navplan.json',
    ],
    unshippedBuildOutputPaths: <String>[
      'assets/paywalls/duolingo_super.capability.json',
      'assets/paywalls/duolingo_super.navplan.json',
      'assets/paywalls/duolingo_super.rfw',
    ],
    absentOutputPaths: <String>[
      'assets/paywalls/duolingo_choose_plan.rfwtxt',
      'assets/paywalls/duolingo_choose_plan.rfw',
    ],
    staleOutputPaths: <String>[
      'assets/paywalls/duolingo_choose_plan.capability.json',
      'assets/paywalls/duolingo_choose_plan.navplan.json',
    ],
  ),
];

void main() {
  final update = Platform.environment[_updateEnvironment] == '1';

  test('descriptor token identity ignores trivia but preserves wire strings',
      () {
    final canonical = utf8.encode('''
final screenType = NeutralFlowScreenRef;
final surface = Surface.onboarding;
const identities = <String>['next', 'welcome', 'welcome.rfw'];
''');
    final reformatted = utf8.encode('''
// Formatting, comments, and the source-compatible alias are trivia.
final screenType=OnboardingScreenRef;
final surface=SurfaceType.onboarding;
const identities=<String>[
  'next', // event
  'welcome', /* id */
  'welcome.rfw' // path
];
''');

    expect(
      _normalizedDescriptor(reformatted),
      _normalizedDescriptor(canonical),
    );
    expect(_descriptorHash(reformatted), _descriptorHash(canonical));

    final legacyAlias = utf8.encode('const surface = SurfaceType.onboarding;');
    final canonicalSpelling =
        utf8.encode('const surface = Surface.onboarding;');
    expect(
      _normalizedDescriptor(legacyAlias),
      _normalizedDescriptor(canonicalSpelling),
      reason: 'SurfaceType must normalize to the canonical Surface token.',
    );
    expect(
      _descriptorHash(legacyAlias),
      _descriptorHash(canonicalSpelling),
    );

    final oldNeutralScreen =
        utf8.encode('const ref = SurfaceScreenRef(id: \'welcome\');');
    final canonicalNeutralScreen =
        utf8.encode('const ref = NeutralFlowScreenRef(id: \'welcome\');');
    expect(
      _normalizedDescriptor(oldNeutralScreen),
      isNot(_normalizedDescriptor(canonicalNeutralScreen)),
      reason: 'SurfaceScreenRef must not be globally treated as neutral.',
    );
    expect(
      _normalizedDescriptor(
        oldNeutralScreen,
        legacySurfaceScreenRefIsNeutral: true,
      ),
      _normalizedDescriptor(canonicalNeutralScreen),
      reason: 'The frozen pre-category onboarding corpus used '
          'SurfaceScreenRef for neutral flow screens.',
    );

    final changedSurface = utf8.encode('const surface = Surface.message;');
    expect(
      _normalizedDescriptor(changedSurface),
      isNot(_normalizedDescriptor(canonicalSpelling)),
      reason:
          'Changing the surface enum value must change descriptor identity.',
    );
    final aliasInsideString =
        utf8.encode("const text = 'SurfaceType.onboarding';");
    final canonicalInsideString =
        utf8.encode("const text = 'Surface.onboarding';");
    expect(
      _normalizedDescriptor(aliasInsideString),
      isNot(_normalizedDescriptor(canonicalInsideString)),
      reason: 'Alias canonicalization must apply to identifier tokens only.',
    );

    final source = utf8.decode(canonical);
    final mutations = <String, String>{
      'event': source.replaceFirst("'next'", "'continue'"),
      'id': source.replaceFirst("'welcome'", "'welcome_2'"),
      'path': source.replaceFirst("'welcome.rfw'", "'welcome_v2.rfw'"),
    };
    for (final mutation in mutations.entries) {
      final bytes = utf8.encode(mutation.value);
      expect(
        _normalizedDescriptor(bytes),
        isNot(_normalizedDescriptor(canonical)),
        reason: '${mutation.key} string mutation must change token identity.',
      );
      expect(
        _descriptorHash(bytes),
        isNot(_descriptorHash(canonical)),
        reason: '${mutation.key} string mutation must change descriptor hash.',
      );
    }

    final quotedWhitespace = utf8.encode("const event = 'next step';");
    final mutatedQuotedWhitespace = utf8.encode("const event = 'next  step';");
    expect(
      _normalizedDescriptor(mutatedQuotedWhitespace),
      isNot(_normalizedDescriptor(quotedWhitespace)),
      reason: 'Whitespace inside a string literal is identity, not trivia.',
    );
    expect(
      _descriptorHash(mutatedQuotedWhitespace),
      isNot(_descriptorHash(quotedWhitespace)),
    );
  });

  test('production entrypoints preserve frozen bytes and ownership', () async {
    final snapshots = <_CorpusSnapshot>[];
    for (final corpus in _corpora) {
      snapshots.add(await _buildCorpus(corpus));
    }

    if (update) _freezeCorpus(snapshots);

    snapshots.forEach(_assertFrozenCorpus);
    snapshots.forEach(_assertMeasurementIdentityContinuity);
  });

  test('source mutation would turn the raw-byte gate red', () async {
    const corpusName = 'examples_onboarding';
    final corpus = _corpora.singleWhere((case_) => case_.name == corpusName);
    const sourcePath = 'lib/onboarding/screens/welcome.dart';
    final original =
        await _readPackageSource(corpus.sourcePackageName, sourcePath);
    const originalText = 'Welcome to Aura';
    expect(original, contains(originalText));

    final mutated = original.replaceFirst(
      originalText,
      '$originalText — mutation proof',
    );
    final snapshot = await _buildCorpus(
      corpus,
      sourceOverrides: <String, String>{sourcePath: mutated},
      assertShippingParity: false,
    );
    final frozen = _readFrozenArtifact(
      corpus,
      'assets/onboarding/screens/welcome.rfwtxt',
    );
    final actual =
        snapshot.bytesFor('assets/onboarding/screens/welcome.rfwtxt');

    expect(
      actual,
      isNot(orderedEquals(frozen)),
      reason:
          'The deliberate source edit must make the frozen byte oracle red.',
    );
    expect(
      _sha256(actual),
      isNot(_sha256(frozen)),
      reason: 'The mutation proof must also move the recorded SHA-256.',
    );
  });
}

Future<_CorpusSnapshot> _buildCorpus(
  _CorpusCase corpus, {
  Map<String, String> sourceOverrides = const <String, String>{},
  bool assertShippingParity = true,
}) async {
  final seeded = await _seedCorpus(corpus, sourceOverrides);
  final capturedLedgers = <List<int>>[];
  Future<void> captureLedger({
    required String package,
    required RestageMeasurementCompilerOutputV1 output,
  }) async {
    expect(package, corpus.sourcePackageName);
    capturedLedgers.add(List<int>.unmodifiable(output.canonicalBytes));
  }

  final sources = <String, String>{
    '${corpus.sourcePackageName}|'
            '$kRestageMeasurementCompilerLedgerSourcePath':
        utf8.decode(seeded.sourceLedgerBytes),
    for (final path in corpus.inputPaths)
      '${corpus.sourcePackageName}|$path': sourceOverrides[path] ??
          seeded.readerWriter.testing.readString(
            AssetId(corpus.sourcePackageName, path),
          ),
  };
  final logs = <LogRecord>[];
  final result = await testBuilders(
    _buildersFor(corpus.kind, captureLedger),
    sources,
    rootPackage: corpus.sourcePackageName,
    readerWriter: seeded.readerWriter,
    flattenOutput: true,
    onLog: logs.add,
  );

  final sourceLedgerBytesAfter = seeded.sourceLedgerFile.readAsBytesSync();
  expect(
    sourceLedgerBytesAfter,
    orderedEquals(seeded.sourceLedgerBytes),
    reason: '${corpus.name} changed the source Measurement ledger bytes.',
  );

  expect(
    result.succeeded,
    isTrue,
    reason: '${corpus.name} production build failed:\n'
        '${result.errors.join('\n')}\n'
        '${logs.map((log) => log.message).join('\n')}',
  );
  expect(result.errors, isEmpty, reason: corpus.name);
  expect(
    capturedLedgers,
    hasLength(1),
    reason: '${corpus.name} must persist one Measurement compiler state.',
  );
  final capturedMeasurementState =
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    capturedLedgers.single,
  );
  final generatedMeasurementBytes = result.readerWriter.testing.readBytes(
    AssetId(
      corpus.sourcePackageName,
      kRestageMeasurementCompilerOutputPath,
    ),
  );
  expect(
    capturedLedgers.single,
    orderedEquals(generatedMeasurementBytes),
    reason: '${corpus.name} captured a different Measurement compiler state.',
  );

  final outputs = result.outputs
      .where((asset) => asset.package == corpus.sourcePackageName)
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final allBytesByPath = <String, List<int>>{
    for (final output in outputs)
      output.path: result.readerWriter.testing.readBytes(output),
  };
  for (final path in <String>[
    ...corpus.virtualOnlyTransientBuildOutputPaths,
    ...corpus.retainedTransientShippingOutputPaths,
  ]) {
    expect(
      allBytesByPath,
      contains(path),
      reason: '${corpus.name} did not emit required transient build output '
          '$path.',
    );
  }
  final bytesByPath = <String, List<int>>{
    for (final entry in allBytesByPath.entries)
      if (!corpus.virtualOnlyTransientBuildOutputPaths.contains(entry.key) &&
          // Compiler outputs are builder-to-builder intermediates, not
          // publication delivery artifacts under test. They are only present
          // because the generated-Dart owner reads them, and are neither
          // shipped nor frozen by this publication oracle.
          entry.key != kRestageSurfacePublicationCompilerBundlePath &&
          entry.key != kRestageMeasurementCompilerOutputPath &&
          entry.key != kRestageAnalyticsIdControlOutputPath &&
          entry.key !=
              RestageOutputPlacementPlan.defaults.analyticsIdMetadataPath)
        entry.key: entry.value,
  };
  final snapshot = _CorpusSnapshot(
    corpus,
    bytesByPath,
    priorMeasurementState: seeded.sourceLedger,
    capturedMeasurementState: capturedMeasurementState,
  );

  for (final path in corpus.absentOutputPaths) {
    expect(
      allBytesByPath,
      isNot(contains(path)),
      reason: '${corpus.name} unexpectedly emitted absent output $path.',
    );
  }
  for (final path in corpus.staleOutputPaths) {
    expect(
      allBytesByPath,
      isNot(contains(path)),
      reason: '${corpus.name} unexpectedly emitted stale output $path.',
    );
  }

  if (assertShippingParity) {
    await _assertShippingParity(snapshot);
  }
  _assertCanonicalFlowJson(snapshot);
  return snapshot;
}

// The harness runs the owner of
// generated Dart. Since the unified-builder work it is `generated_dart`, not
// the surface builders, that writes a library's neutral part — without it this
// harness produces no descriptor at all and the frozen roster can never match.
// `restage_package_surface_compiler` comes with it because the generated-Dart
// builder reads its handoff and returns silently when it is absent.
List<Builder> _generatedDartOwners(
  MeasurementCompilerLedgerWriter ledgerWriter,
) =>
    <Builder>[
      PackageSurfaceCompilerBuilder(
        BuilderOptions.empty,
        ledgerWriter: ledgerWriter,
      ),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ];

List<Builder> _buildersFor(
  _CorpusKind kind,
  MeasurementCompilerLedgerWriter ledgerWriter,
) =>
    switch (kind) {
      _CorpusKind.onboarding => <Builder>[
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
          ..._generatedDartOwners(ledgerWriter),
        ],
      _CorpusKind.onboardingWithPaywall => <Builder>[
          onboardingScreenBuilder(BuilderOptions.empty),
          restageCodegenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
          ..._generatedDartOwners(ledgerWriter),
        ],
      _CorpusKind.paywallNavigation => <Builder>[
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
          ..._generatedDartOwners(ledgerWriter),
        ],
    };

Future<_SeededCorpus> _seedCorpus(
  _CorpusCase corpus,
  Map<String, String> sourceOverrides,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: corpus.sourcePackageName,
    includeFlutter: true,
  );
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final reader = PackageAssetReader(config, 'restage_codegen');
  final seen = <AssetId>{};
  final queue = Queue<AssetId>()
    ..add(AssetId('restage', 'lib/restage.dart'))
    ..add(AssetId('restage_material', 'lib/restage_material.dart'))
    ..add(AssetId('restage_cupertino', 'lib/restage_cupertino.dart'));
  for (final path in corpus.inputPaths) {
    queue.add(AssetId(corpus.sourcePackageName, path));
  }

  while (queue.isNotEmpty) {
    final asset = queue.removeFirst();
    if (!seen.add(asset)) continue;
    if (!asset.path.startsWith('lib/') || !asset.path.endsWith('.dart')) {
      continue;
    }
    if (await readerWriter.canRead(asset)) continue;
    if (!await reader.canRead(asset)) continue;

    final bytes = await reader.readAsBytes(asset);
    readerWriter.testing.writeBytes(asset, bytes);
    queue.addAll(_importDependencies(asset, utf8.decode(bytes)));
  }

  for (final override in sourceOverrides.entries) {
    readerWriter.testing.writeString(
      AssetId(corpus.sourcePackageName, override.key),
      override.value,
    );
  }

  final packageRoot = await _packageRoot(corpus.sourcePackageName);
  final sourceLedgerFile = File.fromUri(
    packageRoot.resolve(kRestageMeasurementCompilerLedgerSourcePath),
  );
  expect(
    sourceLedgerFile.existsSync(),
    isTrue,
    reason: '${corpus.name} source Measurement ledger is absent.',
  );
  final sourceLedgerBytes = sourceLedgerFile.readAsBytesSync();
  final sourceLedger = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    sourceLedgerBytes,
  );
  expect(sourceLedger.valid, isTrue, reason: corpus.name);
  expect(sourceLedger.policy, isNotNull, reason: corpus.name);
  expect(
    sourceLedger.canonicalBytes,
    orderedEquals(sourceLedgerBytes),
    reason: '${corpus.name} source Measurement ledger is not canonical.',
  );
  readerWriter.testing.writeBytes(
    AssetId(
      corpus.sourcePackageName,
      kRestageMeasurementCompilerLedgerSourcePath,
    ),
    sourceLedgerBytes,
  );
  return _SeededCorpus(
    readerWriter: readerWriter,
    sourceLedgerFile: sourceLedgerFile,
    sourceLedgerBytes: List<int>.unmodifiable(sourceLedgerBytes),
    sourceLedger: sourceLedger,
  );
}

Iterable<AssetId> _importDependencies(AssetId from, String source) sync* {
  final parsed = parseString(
    content: source,
    path: from.path,
    throwIfDiagnostics: false,
  );
  for (final directive in parsed.unit.directives) {
    if (directive is! ImportDirective && directive is! ExportDirective) {
      continue;
    }
    final uriText = (directive as UriBasedDirective).uri.stringValue;
    if (uriText == null) continue;
    final uri = Uri.tryParse(uriText);
    if (uri == null || uri.scheme == 'dart') continue;
    if (uri.hasScheme && uri.scheme != 'package' && uri.scheme != 'asset') {
      continue;
    }
    final asset = AssetId.resolve(uri, from: from);
    if (asset.path.endsWith('.dart')) yield asset;
  }
}

Future<void> _assertShippingParity(_CorpusSnapshot snapshot) async {
  final root = await _packageRoot(snapshot.corpus.sourcePackageName);
  // Delivery artifacts no longer ship as loose files: they are entries inside
  // the deterministic bundles the package packages. Parity is therefore
  // asserted against the bytes actually shipped, extracted from those
  // containers, rather than against a file tree that no longer exists.
  // Generated Dart is still an ordinary source file and is read as one.
  final shipped = _shippedBundleEntries(root);
  final unshipped = <String>[];

  for (final entry in snapshot.bytesByPath.entries) {
    if (_isGeneratedDart(entry.key)) {
      final file = File.fromUri(root.resolve(entry.key));
      expect(
        file.existsSync(),
        isTrue,
        reason: '${snapshot.corpus.name} generated ${entry.key}, but the '
            'tracked shipping source is absent at ${file.path}.',
      );
      expect(
        _normalizedDescriptor(entry.value),
        _normalizedDescriptor(file.readAsBytesSync()),
        reason: '${snapshot.corpus.name} production descriptor identity '
            'diverged from shipping output for ${entry.key}.',
      );
      continue;
    }
    final packaged = shipped[entry.key];
    if (packaged == null) {
      unshipped.add(entry.key);
      continue;
    }
    expect(
      entry.value,
      orderedEquals(packaged),
      reason: '${snapshot.corpus.name} production builder diverged from '
          'shipped bytes for ${entry.key}.',
    );
  }

  expect(
    unshipped..sort(),
    orderedEquals(snapshot.corpus.unshippedBuildOutputPaths),
    reason: '${snapshot.corpus.name} the set of artifacts this builder subset '
        'emits without a shipped counterpart moved. Every shipped artifact is '
        'byte-compared above; this guards the boundary itself.',
  );

  for (final path in <String>[
    ...snapshot.corpus.virtualOnlyTransientBuildOutputPaths,
    ...snapshot.corpus.absentOutputPaths,
    ...snapshot.corpus.staleOutputPaths,
  ]) {
    final file = File.fromUri(root.resolve(path));
    expect(
      file.existsSync(),
      isFalse,
      reason: '${snapshot.corpus.name} stale or suppressed artifact exists as '
          'a loose file: ${file.path}.',
    );
    expect(
      shipped,
      isNot(contains(path)),
      reason: '${snapshot.corpus.name} stale or suppressed artifact $path is '
          'packaged in a shipped bundle.',
    );
  }
}

/// Every logical delivery artifact the package actually ships, keyed by
/// logical path and read out of the deterministic bundle containers.
Map<String, List<int>> _shippedBundleEntries(Uri packageRoot) {
  final bundles =
      Directory.fromUri(packageRoot.resolve('assets/restage/bundles'));
  final shipped = <String, List<int>>{};
  if (!bundles.existsSync()) return shipped;
  for (final file in bundles.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.rsbundle')) continue;
    for (final entry
        in RestageBundleCodec.decode(file.readAsBytesSync()).entries) {
      final previous = shipped[entry.logicalPath];
      expect(
        previous == null || _sha256(previous) == _sha256(entry.bytes),
        isTrue,
        reason: 'Two shipped bundles disagree on ${entry.logicalPath}.',
      );
      shipped[entry.logicalPath] = entry.bytes;
    }
  }
  return shipped;
}

void _assertCanonicalFlowJson(_CorpusSnapshot snapshot) {
  for (final entry in snapshot.bytesByPath.entries) {
    if (!entry.key.endsWith('.flow.json')) continue;
    final raw = utf8.decode(entry.value);
    final document = FlowDocumentCodec.decodeJson(raw);
    expect(
      raw,
      utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document)),
      reason: '${snapshot.corpus.name} emitted non-canonical flow JSON at '
          '${entry.key}.',
    );
  }
}

void _assertMeasurementIdentityContinuity(_CorpusSnapshot snapshot) {
  final prior = snapshot.priorMeasurementState;
  final captured = snapshot.capturedMeasurementState;
  expect(
    captured.nextIdentitySequence,
    prior.nextIdentitySequence,
    reason: '${snapshot.corpus.name} allocated new Measurement identities.',
  );

  final priorActiveNodes = <String, MeasurementCompilerLedgerNode>{
    for (final node in prior.ledgerNodes)
      if (node.active) node.structuralOccurrenceKey: node,
  };
  final capturedActiveNodes =
      captured.ledgerNodes.where((node) => node.active).toList(growable: false);

  for (final node in capturedActiveNodes) {
    final priorNode = priorActiveNodes[node.structuralOccurrenceKey];
    if (priorNode == null) {
      fail(
        '${snapshot.corpus.name} emitted a new active Measurement locator: '
        '${node.structuralOccurrenceKey}.',
      );
    }
    expect(node.parentStructuralOccurrenceKey,
        priorNode.parentStructuralOccurrenceKey,
        reason: node.structuralOccurrenceKey);
    expect(node.reconciliationFingerprint, priorNode.reconciliationFingerprint,
        reason: node.structuralOccurrenceKey);
    expect(node.codeIdentityId, priorNode.codeIdentityId,
        reason: node.structuralOccurrenceKey);
    expect(node.canonicalNodeTokenId, priorNode.canonicalNodeTokenId,
        reason: node.structuralOccurrenceKey);

    final priorActiveEvents = <String, MeasurementCompilerLedgerEvent>{
      for (final event in priorNode.events)
        if (event.active) event.resolvedEventLocator: event,
    };
    for (final event in node.events.where((event) => event.active)) {
      final priorEvent = priorActiveEvents[event.resolvedEventLocator];
      if (priorEvent == null) {
        fail(
          '${snapshot.corpus.name} emitted a new active Measurement event: '
          '${event.resolvedEventLocator}.',
        );
      }
      expect(event.sourceEventIdentity, priorEvent.sourceEventIdentity,
          reason: event.resolvedEventLocator);
      expect(event.generatedReferenceId, priorEvent.generatedReferenceId,
          reason: event.resolvedEventLocator);
      expect(event.lineageId, priorEvent.lineageId,
          reason: event.resolvedEventLocator);
      expect(event.dartSymbol, priorEvent.dartSymbol,
          reason: event.resolvedEventLocator);
      expect(event.displayMetadataRef, priorEvent.displayMetadataRef,
          reason: event.resolvedEventLocator);
    }
  }
}

void _freezeCorpus(List<_CorpusSnapshot> snapshots) {
  final root = Directory(_goldenRoot);
  if (root.existsSync()) {
    throw StateError(
      'Refusing to overwrite the frozen corpus at ${root.path}. '
      '$_updateEnvironment is bootstrap-only.',
    );
  }

  for (final snapshot in snapshots) {
    final caseDirectory = Directory(p.join(root.path, snapshot.corpus.name));
    for (final entry in snapshot.bytesByPath.entries) {
      if (_isSupersededDescriptor(entry.key)) continue;
      final file = File(p.join(caseDirectory.path, 'artifacts', entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.value, flush: true);
    }
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'case': snapshot.corpus.name,
      'package': snapshot.corpus.sourcePackageName,
      'entries': <Map<String, Object?>>[
        for (final entry in snapshot.bytesByPath.entries)
          _isSupersededDescriptor(entry.key)
              ? _descriptorManifestEntry(entry.key, entry.value)
              : <String, Object?>{
                  'path': entry.key,
                  'kind': _artifactKind(entry.key),
                  'byteLength': entry.value.length,
                  'sha256': _sha256(entry.value),
                },
      ],
      'absentOutputPaths': snapshot.corpus.absentOutputPaths,
      'staleOutputPaths': snapshot.corpus.staleOutputPaths,
      'virtualOnlyTransientBuildOutputPaths':
          snapshot.corpus.virtualOnlyTransientBuildOutputPaths,
      'retainedTransientShippingOutputPaths':
          snapshot.corpus.retainedTransientShippingOutputPaths,
    };
    File(p.join(caseDirectory.path, 'manifest.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
  }
}

void _assertFrozenCorpus(_CorpusSnapshot snapshot) {
  final caseDirectory = Directory(p.join(_goldenRoot, snapshot.corpus.name));
  final manifestFile = File(p.join(caseDirectory.path, 'manifest.json'));
  expect(
    manifestFile.existsSync(),
    isTrue,
    reason: 'Missing frozen manifest for ${snapshot.corpus.name}. '
        'Bootstrap once with $_updateEnvironment=1 before representation work.',
  );
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  expect(manifest['schemaVersion'], 1);
  expect(manifest['case'], snapshot.corpus.name);
  expect(manifest['package'], snapshot.corpus.sourcePackageName);
  expect(manifest['absentOutputPaths'], snapshot.corpus.absentOutputPaths);
  expect(manifest['staleOutputPaths'], snapshot.corpus.staleOutputPaths);
  expect(
    manifest['virtualOnlyTransientBuildOutputPaths'],
    snapshot.corpus.virtualOnlyTransientBuildOutputPaths,
  );
  expect(
    manifest['retainedTransientShippingOutputPaths'],
    snapshot.corpus.retainedTransientShippingOutputPaths,
  );

  final entries = (manifest['entries']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList(growable: false);
  final frozenPaths =
      entries.map((entry) => entry['path']! as String).toList(growable: false);

  // The roster comparison translates a
  // frozen per-kind descriptor path to the canonical neutral part that
  // replaced it. The mapping is fixed and never adapts to builder output,
  // because only this path mapping is permitted and every other entry is
  // still compared exactly.
  //
  // The 1:1 property is a loud assertion rather than an assumption: two frozen
  // descriptors collapsing onto one neutral part would
  // silently shrink the roster — that is the one way this translation could
  // hide a real regression, so it fails here instead.
  final canonicalOwners = <String, String>{};
  final expectedPaths = <String>[];
  for (final frozen in frozenPaths) {
    if (!_isSupersededDescriptor(frozen)) {
      expectedPaths.add(frozen);
      continue;
    }
    final canonical = _canonicalDescriptorPath(frozen);
    final previous = canonicalOwners[canonical];
    expect(
      previous,
      isNull,
      reason: '${snapshot.corpus.name} frozen descriptors "$previous" and '
          '"$frozen" both map to "$canonical". The roster translation is only '
          'sound while it stays 1:1; a collapse hides a lost descriptor.',
    );
    canonicalOwners[canonical] = frozen;
    expectedPaths.add(canonical);
  }
  expectedPaths.sort();
  expect(
    snapshot.bytesByPath.keys,
    orderedEquals(expectedPaths),
    reason: '${snapshot.corpus.name} output ownership/path roster moved.',
  );

  for (final entry in entries) {
    final path = entry['path']! as String;
    expect(entry['kind'], _artifactKind(path));
    if (_isSupersededDescriptor(path)) {
      // Generated Dart is EXEMPT from frozen-byte and frozen-identity
      // equality. Merging a library's per-kind descriptors into one neutral
      // part is a deliberate change, so pinning the old shape here would
      // assert the thing being replaced. The emitter and placement suites
      // guard the new shape; this oracle guards that the part still EXISTS at
      // its canonical location, which the roster comparison above proves.
      //
      // The frozen record is still checked for internal consistency, so a
      // corrupted golden is caught rather than silently skipped.
      final storedDescriptor = entry['descriptor']! as String;
      final storedDescriptorBytes = utf8.encode(storedDescriptor);
      expect(entry['contractByteLength'], storedDescriptorBytes.length);
      expect(entry['sha256'], _sha256(storedDescriptorBytes));
      continue;
    }

    // Every delivery artifact keeps full byte equality.
    {
      final actual = snapshot.bytesFor(path);
      final frozen = _readFrozenArtifact(snapshot.corpus, path);
      expect(entry['byteLength'], frozen.length);
      expect(entry['sha256'], _sha256(frozen));
      expect(
        actual,
        orderedEquals(frozen),
        reason: '${snapshot.corpus.name} frozen bytes moved for $path.',
      );
      expect(
        _sha256(actual),
        entry['sha256'],
        reason: '${snapshot.corpus.name} frozen hash moved for $path.',
      );
    }
  }
}

Map<String, Object?> _descriptorManifestEntry(String path, List<int> bytes) {
  // Schema 1 stores valid Dart source as its descriptor contract. Readers
  // token-normalize that source, which keeps both the original whitespace-
  // normalized corpus and any future one-time bootstrap representation
  // coherent without coupling their hashes to the token-stream encoding.
  final descriptor = utf8.decode(bytes);
  final descriptorBytes = utf8.encode(descriptor);
  return <String, Object?>{
    'path': path,
    'kind': _artifactKind(path),
    'descriptor': descriptor,
    'contractByteLength': descriptorBytes.length,
    'sha256': _sha256(descriptorBytes),
  };
}

List<int> _readFrozenArtifact(_CorpusCase corpus, String path) {
  final file = File(p.join(_goldenRoot, corpus.name, 'artifacts', path));
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing frozen artifact ${file.path}.',
  );
  return file.readAsBytesSync();
}

String _artifactKind(String path) {
  if (path.endsWith('.flow.json')) return 'canonical-flow-json';
  if (path.endsWith('.navplan.json')) return 'navigation-build-plan';
  if (path.endsWith('.rfwtxt')) return 'rfw-text';
  if (path.endsWith('.rfw')) return 'rfw-binary';
  if (path.endsWith('.capability.json')) return 'capability-sidecar';
  if (path.endsWith('.rsscreen.g.dart')) return 'screen-descriptor';
  if (path.endsWith('.rsflow.g.dart')) return 'flow-descriptor';
  // The neutral part carries every declaration kind in one file, so it has no
  // per-kind role. Only produced paths reach this branch; frozen entries keep
  // the per-kind roles recorded above.
  if (path.endsWith(kNeutralGeneratedPartSuffix)) return 'descriptor';
  throw StateError('Unexpected production artifact path: $path');
}

String _sha256(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

/// Whether [path] is Restage-generated Dart in any placement.
bool _isGeneratedDart(String path) =>
    _isSupersededDescriptor(path) || path.endsWith(kNeutralGeneratedPartSuffix);

/// Whether [path] is a frozen per-kind descriptor path.
///
/// Only the frozen roster still speaks these suffixes; the builders emit one
/// neutral part per library instead. Kept so a frozen entry can still be
/// recognized and translated.
bool _isSupersededDescriptor(String path) =>
    kSupersededGeneratedPartSuffixes.any(path.endsWith);

/// The canonical neutral part that replaced the frozen descriptor at [path].
///
/// `lib/onboarding/screens/welcome.rsscreen.g.dart` becomes
/// `lib/onboarding/screens/restage.generated/welcome.restage.g.dart`.
String _canonicalDescriptorPath(String path) {
  final suffix = kSupersededGeneratedPartSuffixes.firstWhere(path.endsWith);
  final base = p.posix.basename(path);
  final stem = base.substring(0, base.length - suffix.length);
  return p.posix.join(
    p.posix.dirname(path),
    kRestageGeneratedDirectoryName,
    '$stem$kNeutralGeneratedPartSuffix',
  );
}

String _normalizedDescriptor(
  List<int> bytes, {
  bool legacySurfaceScreenRefIsNeutral = false,
}) {
  final parsed = parseString(
    content: utf8.decode(bytes),
    path: '<generated descriptor>',
    throwIfDiagnostics: false,
  );
  final normalized = StringBuffer();
  for (var token = parsed.unit.beginToken; !token.isEof; token = token.next!) {
    final lexeme = token.type == TokenType.IDENTIFIER
        ? switch (token.lexeme) {
            'OnboardingScreenRef' => 'NeutralFlowScreenRef',
            'SurfaceScreenRef' => legacySurfaceScreenRefIsNeutral
                ? 'NeutralFlowScreenRef'
                : token.lexeme,
            'OnboardingFlowRef' => 'SurfaceFlowRef',
            'SurfaceType' => 'Surface',
            final lexeme => lexeme,
          }
        : token.lexeme;
    // Length-prefix plus a separator keeps adjacent token boundaries
    // unambiguous even when a lexeme itself contains the separator.
    normalized
      ..write(lexeme.length)
      ..write(':')
      ..write(lexeme)
      ..write('|');
  }
  return normalized.toString();
}

String _descriptorHash(List<int> bytes) =>
    _sha256(utf8.encode(_normalizedDescriptor(bytes)));

Future<String> _readPackageSource(String packageName, String path) async {
  final root = await _packageRoot(packageName);
  return File.fromUri(root.resolve(path)).readAsString();
}

Future<Uri> _packageRoot(String packageName) async {
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final package = config[packageName];
  if (package == null) throw StateError('Unknown package $packageName.');
  return package.root;
}

enum _CorpusKind { onboarding, onboardingWithPaywall, paywallNavigation }

final class _CorpusCase {
  const _CorpusCase({
    required this.name,
    required this.sourcePackageName,
    required this.kind,
    required this.inputPaths,
    this.frozenSurfaceScreenRefIsNeutral = false,
    this.virtualOnlyTransientBuildOutputPaths = const <String>[],
    this.retainedTransientShippingOutputPaths = const <String>[],
    this.unshippedBuildOutputPaths = const <String>[],
    this.absentOutputPaths = const <String>[],
    this.staleOutputPaths = const <String>[],
  });

  final String name;
  final String sourcePackageName;
  final _CorpusKind kind;
  final List<String> inputPaths;
  final bool frozenSurfaceScreenRefIsNeutral;
  final List<String> virtualOnlyTransientBuildOutputPaths;
  final List<String> retainedTransientShippingOutputPaths;

  /// Artifacts this builder subset still emits that the package no longer
  /// ships.
  ///
  /// A navigation paywall publishes its per-screen blobs, not its root blob,
  /// so the root blob has no shipped counterpart to compare against. The set
  /// is declared rather than inferred: shipping parity asserts it exactly, so
  /// an artifact quietly dropping out of the shipped closure fails here
  /// instead of being waved through as "expected to be missing".
  final List<String> unshippedBuildOutputPaths;
  final List<String> absentOutputPaths;
  final List<String> staleOutputPaths;
}

final class _SeededCorpus {
  const _SeededCorpus({
    required this.readerWriter,
    required this.sourceLedgerFile,
    required this.sourceLedgerBytes,
    required this.sourceLedger,
  });

  final TestReaderWriter readerWriter;
  final File sourceLedgerFile;
  final List<int> sourceLedgerBytes;
  final RestageMeasurementCompilerOutputV1 sourceLedger;
}

final class _CorpusSnapshot {
  const _CorpusSnapshot(
    this.corpus,
    this.bytesByPath, {
    required this.priorMeasurementState,
    required this.capturedMeasurementState,
  });

  final _CorpusCase corpus;
  final Map<String, List<int>> bytesByPath;
  final RestageMeasurementCompilerOutputV1 priorMeasurementState;
  final RestageMeasurementCompilerOutputV1 capturedMeasurementState;

  List<int> bytesFor(String path) {
    final bytes = bytesByPath[path];
    if (bytes == null) {
      throw StateError('${corpus.name} did not emit required output $path.');
    }
    return bytes;
  }
}
