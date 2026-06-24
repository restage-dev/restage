import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/real_package_scanner.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The authored `@RestageWidget` custom widgets in the real example package's
/// `lib/widgets/` directory — the real-package surface B3 measures.
const _kExampleWidgetNames = {
  'AcmeBorder',
  'AcmeStack',
  'PromoBadge',
};

void main() {
  group('scanPackage — unresolved target', () {
    test(
      'throws an actionable PackageNotResolvedException when the target has '
      'no discoverable package config',
      () async {
        // A package directory with a pubspec but no .dart_tool, created under
        // the system temp dir so no ancestor package_config resolves it.
        final dir = Directory.systemTemp.createTempSync('b3_unbootstrapped_');
        addTearDown(() => dir.deleteSync(recursive: true));
        File('${dir.path}/pubspec.yaml').writeAsStringSync(
          'name: unbootstrapped_example\n'
          'environment:\n  sdk: ">=3.0.0 <4.0.0"\n',
        );

        await expectLater(
          scanPackage(packagePath: dir.path, catalog: kEmptyCatalog),
          throwsA(
            isA<PackageNotResolvedException>()
                .having((e) => e.message, 'message', contains('pub get'))
                .having((e) => e.packagePath, 'packagePath', dir.path),
          ),
        );
      },
    );

    test('throws when the resolved config does not cover the target package',
        () async {
      // A config that exists but lists only some OTHER package (a stale or
      // partial workspace config resolved against an enclosing root that does
      // not include this package) must fail closed with the actionable
      // diagnostic, not yield a silently-empty scan.
      final dir = Directory.systemTemp.createTempSync('b3_stale_config_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dirPath = dir.resolveSymbolicLinksSync();
      File('$dirPath/pubspec.yaml').writeAsStringSync(
        'name: stale_fixture\n'
        'environment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      Directory('$dirPath/.dart_tool').createSync();
      File('$dirPath/.dart_tool/package_config.json').writeAsStringSync(
        '{"configVersion":2,"packages":['
        '{"name":"some_other_pkg",'
        '"rootUri":"file:///definitely/not/the/target",'
        '"packageUri":"lib/","languageVersion":"3.0"}]}',
      );

      await expectLater(
        scanPackage(packagePath: dirPath, catalog: kEmptyCatalog),
        throwsA(
          isA<PackageNotResolvedException>()
              .having((e) => e.message, 'message', contains('pub get')),
        ),
      );
    });

    test('normalizes a non-normalized package path before resolving', () async {
      // The analyzer rejects non-absolute / non-normalized paths; the scanner
      // must normalize first so a path like `dir/.` or a relative CLI path
      // fails closed (PackageNotResolvedException) instead of ArgumentError.
      final dir = Directory.systemTemp.createTempSync('b3_nonnormalized_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');

      await expectLater(
        scanPackage(packagePath: '${dir.path}/.', catalog: kEmptyCatalog),
        throwsA(isA<PackageNotResolvedException>()),
      );
    });
  });

  group('scanPackage — generated-file skips', () {
    test('skips generated files beyond .g.dart (.freezed/.mocks/.config)',
        () async {
      // A resolvable temp package whose lib/ holds ONLY generated files. The
      // scan never invokes the resolver (generated files are skipped before
      // resolution), so this exercises the skip predicate end-to-end without an
      // SDK dependency.
      final dir = Directory.systemTemp.createTempSync('b3_generated_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dirPath = dir.resolveSymbolicLinksSync();
      File('$dirPath/pubspec.yaml').writeAsStringSync(
        'name: gen_fixture\n'
        'environment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      Directory('$dirPath/.dart_tool').createSync();
      File('$dirPath/.dart_tool/package_config.json').writeAsStringSync(
        '{"configVersion":2,"packages":['
        '{"name":"gen_fixture","rootUri":"../","packageUri":"lib/",'
        '"languageVersion":"3.0"}]}',
      );
      Directory('$dirPath/lib').createSync();
      File('$dirPath/lib/foo.freezed.dart').writeAsStringSync('// generated');
      File('$dirPath/lib/bar.mocks.dart').writeAsStringSync('// generated');
      File('$dirPath/lib/baz.config.dart').writeAsStringSync('// generated');

      final result =
          await scanPackage(packagePath: dirPath, catalog: kEmptyCatalog);

      final skipped = {for (final s in result.skips) s.identifier: s.reason};
      expect(
        skipped.keys,
        containsAll(<String>[
          'lib/foo.freezed.dart',
          'lib/bar.mocks.dart',
          'lib/baz.config.dart',
        ]),
      );
      expect(skipped['lib/foo.freezed.dart'], contains('generated file'));
      // None of the generated files resolve.
      expect(result.filesResolved, 0);
    });
  });

  group('scanPackage — real example package self-test', () {
    late ScanResult result;

    setUpAll(() async {
      final examplesDir = await _examplesPackageDir();
      final catalog = await loadMergedCatalogFromDisk();
      result = await scanPackage(packagePath: examplesDir, catalog: catalog);
    });

    test('measures all authored custom widgets', () {
      final measured = result.classifications.keys.map(_classNameOf).toSet();
      for (final name in _kExampleWidgetNames) {
        expect(
          measured,
          contains(name),
          reason: '$name must be measured (found: $measured)',
        );
      }
    });

    test('reports classifier-recognised and emit-confirmed totals distinctly',
        () {
      final classifier = result.classifierReport;
      final emit = result.emitConfirmedReport;
      // Same corpus measured both ways.
      expect(emit.total, equals(classifier.total));
      expect(
        classifier.total,
        greaterThanOrEqualTo(_kExampleWidgetNames.length),
      );
      // Emit-confirmed inlinable can only be a subset of classifier-recognised.
      expect(
        emit.inlinableTotal,
        lessThanOrEqualTo(classifier.inlinableTotal),
      );
    });

    test('emit-confirmed inlinable buckets are a subset of classifier-only',
        () {
      final classifier = result.classifierReport.toSnapshotJson();
      final emit = result.emitConfirmedReport.toSnapshotJson();
      for (final bucket in const {
        CoverageBucket.inlinableComposition,
        CoverageBucket.inlinableConstantFold,
        CoverageBucket.inlinableThemeAsData,
        CoverageBucket.inlinableDeclarativeState,
      }) {
        expect(
          emit[bucket.snapshotKey]!.toSet().difference(
                classifier[bucket.snapshotKey]!.toSet(),
              ),
          isEmpty,
          reason: 'emit-confirmed ${bucket.snapshotKey} cannot gain widgets '
              'the classifier did not recognise',
        );
      }
    });

    test('surfaces skipped files rather than silently capping coverage', () {
      // Honesty contract: generated files are skipped, but every skip is
      // recorded with a reason — the metric never silently omits a file.
      expect(result.filesScanned, greaterThan(result.filesResolved));
      expect(result.skips, isNotEmpty);
      for (final skip in result.skips) {
        expect(skip.reason, isNotEmpty);
      }
      final generatedSkips =
          result.skips.where((s) => s.reason.contains('generated')).toList();
      expect(
        generatedSkips.map((s) => s.identifier),
        contains(endsWith('user_factories.g.dart')),
        reason: 'generated files must be recorded as skips',
      );
    });

    test('bucketing matches the committed real-package snapshot', () async {
      // Value-asserts the exact per-bucket measurement of the example
      // package's custom widgets — both the classifier-recognised upper bound
      // and the emit-confirmed metric. Regenerate intentionally with
      // `REGEN_REAL_PACKAGE_SNAPSHOT=1 dart test <thisfile>` when codegen
      // gains a mechanism that moves a real widget between buckets, and commit
      // the regenerated snapshot alongside the coverage report update.
      final actual = <String, dynamic>{
        'classifierRecognised': result.classifierReport.toSnapshotJson(),
        'emitConfirmed': result.emitConfirmedReport.toSnapshotJson(),
      };

      final snapshotFile = File.fromUri(
        (await _packageRoot()).uri.resolve(_kRealPackageSnapshotPath),
      );
      if (Platform.environment['REGEN_REAL_PACKAGE_SNAPSHOT'] == '1') {
        snapshotFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(actual)}\n',
        );
      }
      expect(
        snapshotFile.existsSync(),
        isTrue,
        reason: 'Snapshot missing at ${snapshotFile.path}; regenerate with '
            'REGEN_REAL_PACKAGE_SNAPSHOT=1.',
      );
      final expected =
          jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;
      expect(
        actual,
        expected,
        reason: 'Real-package coverage bucketing drifted from the committed '
            'snapshot. If intentional (a codegen mechanism landed), regenerate '
            'with REGEN_REAL_PACKAGE_SNAPSHOT=1 and update the report.',
      );
    });
  });

  group('renderScanReport', () {
    test(
        'shows classifier-recognised and emit-confirmed totals distinctly '
        'and lists skips', () {
      final report = renderScanReport(
        ScanResult(
          packagePath: '/tmp/example_pkg',
          classifications: const {},
          emitOutcomes: const {},
          skips: [
            WidgetSkip(
              identifier: 'lib/foo.g.dart',
              reason: 'generated file (not an authored widget)',
            ),
          ],
          filesScanned: 3,
          filesResolved: 1,
        ),
      );
      expect(report, contains('Classifier-recognised inlinable:'));
      expect(report, contains('Emit-confirmed inlinable:'));
      expect(report, contains('Skipped'));
      expect(report, contains('lib/foo.g.dart'));
      expect(report, contains('/tmp/example_pkg'));
    });
  });

  group('loadMergedCatalogFromDisk', () {
    test(
      'merged catalog from disk matches the build-step loader '
      '(widget identities + collection counts)',
      () async {
        final fromDisk = await loadMergedCatalogFromDisk();
        final fromBuildStep = await _loadMergedCatalogViaBuildStep();

        Set<(WidgetLibrary, String)> ids(Catalog c) =>
            {for (final w in c.widgets) (w.library, w.name)};

        expect(
          ids(fromDisk),
          equals(ids(fromBuildStep)),
          reason: 'disk-merged widget (library,name) set must match the '
              'production build-step merge',
        );
        expect(fromDisk.widgets.length, fromBuildStep.widgets.length);
        expect(
          fromDisk.structuredTypes.length,
          fromBuildStep.structuredTypes.length,
        );
        expect(fromDisk.unions.length, fromBuildStep.unions.length);
        expect(fromDisk.schemaVersion, fromBuildStep.schemaVersion);
      },
    );
  });
}

/// Path (relative to the package root) of the committed real-package coverage
/// snapshot the self-test value-asserts against.
const _kRealPackageSnapshotPath =
    'test/coverage_measurement/real_package_coverage_snapshot.json';

/// The class name from a classifier `classKey` (`'<library URI>#<Class>'`).
String _classNameOf(String classKey) => classKey.split('#').last;

/// The `restage_codegen` package root on disk.
Future<Directory> _packageRoot() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_codegen/restage_codegen.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Unable to resolve package:restage_codegen.');
  }
  return File.fromUri(libraryUri).parent.parent;
}

/// Resolves the on-disk directory of the real example package via the running
/// isolate's package config (CWD-independent).
Future<String> _examplesPackageDir() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_example/main.dart'),
  );
  if (libUri == null) {
    throw StateError('Unable to resolve package:restage_example.');
  }
  // <pkg>/lib/main.dart -> <pkg>
  return File.fromUri(libUri).parent.parent.path;
}

/// Loads the merged catalog the production way — through `loadMergedCatalog`
/// inside a `build_test` build step — so the disk loader can be parity-checked
/// against it.
Future<Catalog> _loadMergedCatalogViaBuildStep() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  const probeAssetPath = 'lib/_real_package_scanner_parity_probe.dart';
  final sources = {'apps_examples|$probeAssetPath': 'class _Probe {}'};
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
    throw StateError('Unable to load the merged catalog via the build step');
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
