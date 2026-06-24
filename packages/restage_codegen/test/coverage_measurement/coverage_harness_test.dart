import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_walker.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'coverage_harness.dart';

/// Path (relative to the package root) of the directory holding
/// fixture `.dart` files the harness classifies.
const String _kFixtureDir = 'test/coverage_measurement/coverage_fixtures';

/// Path of the snapshot file the harness asserts against. Kept on disk
/// so the report `docs/custom-widget-4a-coverage-report.md` can be
/// regenerated from the same source of truth and CI catches drift.
const String _kSnapshotPath =
    'test/coverage_measurement/coverage_snapshot.json';

/// Per-fixture inputs the harness classifies. Each entry pairs the
/// in-workspace asset path (`lib/coverage_fixtures/<file>.dart`) with
/// the catalog widgets that file's customer widgets compose against —
/// each catalog entry's `flutterType` matches the `<library URI>#<Class>`
/// the classifier derives for the local stub class in the fixture.
const List<({String inputPath, String relativePath})> _kFixtures = [
  (
    inputPath: 'lib/coverage_fixtures/minimal.dart',
    relativePath: 'minimal.dart',
  ),
  (
    inputPath: 'lib/coverage_fixtures/theme_as_data.dart',
    relativePath: 'theme_as_data.dart',
  ),
  (
    inputPath: 'lib/coverage_fixtures/paywall.dart',
    relativePath: 'paywall.dart',
  ),
  (
    inputPath: 'lib/coverage_fixtures/idioms.dart',
    relativePath: 'idioms.dart',
  ),
];

/// Stub classes the fixtures construct against, grouped by the fixture
/// file that declares them. Each entry's `flutterType` is the
/// `<library URI>#<Class>` the classifier derives for the local stub.
const Map<String, List<String>> _kFixtureStubs = {
  'minimal.dart': ['Container', 'Text', 'GestureDetector'],
  'theme_as_data.dart': ['Box'],
  'paywall.dart': [
    'Row',
    'Column',
    'Container',
    'Text',
    'Image',
    'GestureDetector',
  ],
  // The broad idiom census composes a single local stand-in catalog widget
  // (`Slot`); the structural idioms use real-Flutter imperative constructs
  // (CustomPaint / LayoutBuilder / FutureBuilder / controller) which the
  // classifier buckets via blocker detection, not as catalog widgets.
  'idioms.dart': ['Slot'],
};

const String _kRealCatalogProbePath =
    'lib/coverage_measurement/real_catalog_emit_probe.dart';
const String _kRealCatalogEmitConfirmedKey =
    'package:apps_examples/coverage_measurement/real_catalog_emit_probe.dart#'
    'RealCatalogEmitConfirmed';
const String _kRealCatalogEmitFailedKey =
    'package:apps_examples/coverage_measurement/real_catalog_emit_probe.dart#'
    'RealCatalogEmitOutOfContract';
const String _kRealCatalogProbeSource = '''
// ignore_for_file: annotate_overrides, depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'RealCatalogEmitConfirmed',
  library: WidgetLibrary.custom('coverage.real_catalog'),
  category: WidgetCategory.layout,
  description: 'Real catalog + in-contract theme read, emit confirmed',
)
class RealCatalogEmitConfirmed extends StatelessWidget {
  const RealCatalogEmitConfirmed({super.key});

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.primary,
        child: Text('confirmed'),
      );
}

@RestageWidget(
  name: 'RealCatalogEmitOutOfContract',
  library: WidgetLibrary.custom('coverage.real_catalog'),
  category: WidgetCategory.layout,
  description: 'Real catalog + out-of-contract theme read, emit failed',
)
class RealCatalogEmitOutOfContract extends StatelessWidget {
  const RealCatalogEmitOutOfContract({super.key});

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Text('failed'),
      );
}
''';

Catalog _fixtureCatalog() => catalogWith(
      [
        for (final MapEntry(key: file, value: classes)
            in _kFixtureStubs.entries)
          for (final className in classes)
            entry(
              name: className,
              properties: const [],
              flutterType:
                  'package:apps_examples/coverage_fixtures/$file#$className',
            ),
      ],
      // The decompose-able structured types the real merged catalog declares —
      // a construction of one is classifier-recognised composition (the A2
      // reconciliation single-sources recognition off the catalog's
      // structuredTypes). The entries are field-less stubs, preserving the
      // snapshot's "classifier-recognised upper bound, not emit-confirmed"
      // semantics.
      structuredTypes: [structuredEntry('TextStyle')],
    );

void main() {
  test('coverage fixtures bucket to match the on-disk snapshot', () async {
    final catalog = _fixtureCatalog();
    final sources = await _fixtureSources();
    final packageRoot = await _packageRoot();
    final corpus = await _classifyCorpus(
      sources: sources,
      catalog: catalog,
      probeEmit: false,
    );
    final allClassifications = corpus.classifications;

    // This committed snapshot is the **classifier-recognised upper bound** —
    // it measures what the classifier recognises as inlinable, NOT what the
    // translator emit-confirms. The fixtures compose against a thin synthetic
    // catalog (empty-property stubs) that cannot emit, so emit-confirmation
    // would be meaningless here; the lie-catcher (emit-confirmed bucketing
    // via `EmitOutcome`) is exercised in the unit tests + the real-Flutter
    // proof test, and the full real-catalog emit-confirmed corpus is the
    // post-L12 closure-phase harness conversion. The `classifier-only/
    // emit-failed` bucket is therefore always empty in this snapshot.
    final report = CoverageReport.from(allClassifications);

    final snapshotFile = File.fromUri(
      packageRoot.uri.resolve(_kSnapshotPath),
    );
    expect(
      snapshotFile.existsSync(),
      isTrue,
      reason: 'Snapshot missing at ${snapshotFile.path}; regenerate by '
          'running this test and copying the actual output into the file.',
    );

    final actual = report.toSnapshotJson();

    // Regenerate the on-disk snapshot when the drift is intentional. Run
    // `REGEN_COVERAGE_SNAPSHOT=1 dart test <thisfile>` to rewrite it, then
    // re-run without the flag to confirm + commit alongside the coverage
    // report. Keeps the metric honest as recognised-mechanism wins land.
    if (Platform.environment['REGEN_COVERAGE_SNAPSHOT'] == '1') {
      snapshotFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(actual)}\n',
      );
    }

    final expected =
        jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;
    expect(
      actual,
      expected,
      reason: 'Coverage bucketing drifted from the on-disk snapshot. If the '
          'drift is intentional (a new fixture, a recognised mechanism that '
          'moved widgets between buckets), regenerate with '
          'REGEN_COVERAGE_SNAPSHOT=1 and update the accompanying coverage '
          'report in the same commit.',
    );
  });

  test(
    'real-catalog emit confirmation distinguishes confirmed from emit-failed',
    () async {
      final catalog = await _loadMergedCatalogForHarness();
      final probe = await classifyAllInFixture(
        {_kRealCatalogProbePath: _kRealCatalogProbeSource},
        inputPath: _kRealCatalogProbePath,
        catalog: catalog,
        probeEmit: true,
      );

      final confirmed = probe.classifications[_kRealCatalogEmitConfirmedKey];
      final failed = probe.classifications[_kRealCatalogEmitFailedKey];
      expect(confirmed, isNotNull, reason: 'Confirmed widget missing');
      expect(failed, isNotNull, reason: 'Emit-failed widget missing');
      expect(bucketFor(confirmed!), CoverageBucket.inlinableThemeAsData);
      expect(bucketFor(failed!), CoverageBucket.inlinableThemeAsData);

      expect(
        probe.emitOutcomes[_kRealCatalogEmitConfirmedKey],
        EmitOutcome.confirmed,
      );
      expect(
        probe.emitOutcomes[_kRealCatalogEmitFailedKey],
        EmitOutcome.failed,
      );
      expect(
        bucketForEmit(
          confirmed,
          probe.emitOutcomes[_kRealCatalogEmitConfirmedKey]!,
        ),
        CoverageBucket.inlinableThemeAsData,
      );
      expect(
        bucketForEmit(
          failed,
          probe.emitOutcomes[_kRealCatalogEmitFailedKey]!,
        ),
        CoverageBucket.classifierOnly,
      );
    },
  );

  test(
    'real-catalog emit confirmation lowers the fixture corpus as a strict '
    'emitter-bound subset of classifier-only',
    () async {
      final catalog = await _loadMergedCatalogForHarness();
      final sources = await _fixtureSources();
      final corpus = await _classifyCorpus(
        sources: sources,
        catalog: catalog,
        probeEmit: true,
      );

      final allClassifications = corpus.classifications;
      final allEmitOutcomes = corpus.emitOutcomes;
      expect(allEmitOutcomes.length, equals(allClassifications.length));

      // Preserve the distinction: classifier-only is the broad upper bound,
      // emit-confirmed is the strict subset of widgets that the translator can
      // still emit.
      final classifierOnlyReport = CoverageReport.from(allClassifications);
      final emitConfirmedReport = CoverageReport.from(
        allClassifications,
        emitOutcomes: allEmitOutcomes,
      );
      expect(
        emitConfirmedReport.inlinableTotal,
        lessThanOrEqualTo(classifierOnlyReport.inlinableTotal),
      );
      expect(emitConfirmedReport.total, equals(classifierOnlyReport.total));

      final emitSnapshot = emitConfirmedReport.toSnapshotJson();
      final upperBoundSnapshot = classifierOnlyReport.toSnapshotJson();
      expect(
        emitSnapshot[CoverageBucket.deferred.snapshotKey],
        equals(upperBoundSnapshot[CoverageBucket.deferred.snapshotKey]),
      );
      expect(
        emitSnapshot[CoverageBucket.structural.snapshotKey],
        equals(upperBoundSnapshot[CoverageBucket.structural.snapshotKey]),
      );
      for (final bucket in const {
        CoverageBucket.inlinableComposition,
        CoverageBucket.inlinableConstantFold,
        CoverageBucket.inlinableThemeAsData,
        CoverageBucket.inlinableDeclarativeState,
      }) {
        expect(
          emitSnapshot[bucket.snapshotKey]!.toSet().difference(
                upperBoundSnapshot[bucket.snapshotKey]!.toSet(),
              ),
          isEmpty,
          reason: '${bucket.snapshotKey} cannot gain widgets under emit',
        );
      }
    },
  );
}

class _CoverageCorpusResult {
  const _CoverageCorpusResult(this.classifications, this.emitOutcomes);

  final Map<String, WidgetClassification> classifications;
  final Map<String, EmitOutcome> emitOutcomes;
}

Future<Map<String, String>> _fixtureSources() async {
  final packageRoot = await _packageRoot();
  final sources = <String, String>{};
  for (final fixture in _kFixtures) {
    final file = File.fromUri(
      packageRoot.uri.resolve('$_kFixtureDir/${fixture.relativePath}'),
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Fixture missing at ${file.path}; check the fixture '
          'directory layout.',
    );
    sources[fixture.inputPath] = file.readAsStringSync();
  }
  return sources;
}

Future<_CoverageCorpusResult> _classifyCorpus({
  required Map<String, String> sources,
  required Catalog catalog,
  required bool probeEmit,
}) async {
  final classifications = <String, WidgetClassification>{};
  final emitOutcomes = <String, EmitOutcome>{};
  for (final fixture in _kFixtures) {
    final probe = await classifyAllInFixture(
      sources,
      inputPath: fixture.inputPath,
      catalog: catalog,
      probeEmit: probeEmit,
    );
    classifications.addAll(probe.classifications);
    emitOutcomes.addAll(probe.emitOutcomes);
  }
  return _CoverageCorpusResult(classifications, emitOutcomes);
}

Future<Catalog> _loadMergedCatalogForHarness() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  const probeAssetPath = 'lib/coverage_measurement/_real_catalog_probe.dart';
  final sources = {
    'apps_examples|$probeAssetPath': 'class _RealCatalogProbe {}',
  };
  Catalog? merged;
  await testBuilder(
    _MergedCatalogProbeBuilder(
      inputPath: probeAssetPath,
      onCatalog: (catalog) => merged = catalog,
    ),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );

  final catalog = merged;
  if (catalog == null) {
    throw StateError(
      'Unable to load the merged catalog for real-catalog tests',
    );
  }
  return catalog;
}

class _MergedCatalogProbeBuilder implements Builder {
  const _MergedCatalogProbeBuilder({
    required this.inputPath,
    required this.onCatalog,
  });

  final String inputPath;
  final void Function(Catalog) onCatalog;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.noop'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId.path != inputPath) return;
    onCatalog(await loadMergedCatalog(step));
  }
}

Future<Directory> _packageRoot() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_codegen/restage_codegen.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Unable to resolve package:restage_codegen.');
  }
  return File.fromUri(libraryUri).parent.parent;
}
