@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:restage_codegen/src/coverage_measurement/idiom_histogram.dart';
import 'package:restage_codegen/src/coverage_measurement/pubdev_fetch.dart';
import 'package:restage_codegen/src/coverage_measurement/real_package_scanner.dart';
import 'package:test/test.dart';

/// Version-pinned targets so the committed snapshot is deterministic across
/// runs and machines (the measurement depends only on the package version + our
/// catalog). Bump deliberately and regenerate with `REGEN_PUBDEV_SNAPSHOT=1`.
const _kTargets = <(String, String)>[
  ('gap', '3.0.1'),
  ('auto_size_text', '3.0.0'),
  ('badges', '3.2.0'),
  ('dotted_border', '3.1.0'),
];

/// Repo-relative path of the committed snapshot. It lives in the workspace's
/// `docs/` rather than inside this package because it records inlinability
/// measurements of third-party packages — data kept alongside the workspace
/// documentation, not committed into the package itself.
const _kSnapshotRelPath = 'docs/pubdev-coverage/pubdev_coverage_snapshot.json';

void main() {
  test(
    'pub.dev targets match the committed coverage snapshot',
    () async {
      if (Platform.environment['RESTAGE_PUBDEV_SCAN'] != '1') {
        markTestSkipped(
          'Set RESTAGE_PUBDEV_SCAN=1 to run the live pub.dev scan '
          '(network + a Flutter SDK on PATH required). The default offline '
          'gate skips this test.',
        );
        return;
      }

      final catalog = await loadMergedCatalogFromDisk();
      final actual = <String, dynamic>{};
      for (final (package, version) in _kTargets) {
        final fetched =
            await fetchPubPackageToTemp(package: package, version: version);
        try {
          final result = await scanPackage(
            packagePath: fetched.directory,
            catalog: catalog,
            widgetSelector: allFlutterWidgets,
          );
          actual['$package-$version'] = <String, dynamic>{
            'widgetCount': result.widgetCount,
            // The skip ledger + file counts are persisted too, so a future
            // regression that starts dropping files (silently capping coverage)
            // moves the snapshot rather than hiding behind an unchanged
            // widgetCount.
            'filesScanned': result.filesScanned,
            'filesResolved': result.filesResolved,
            'skips': _skipsJson(result.skips),
            'classifierRecognised': result.classifierReport.toSnapshotJson(),
            'emitConfirmed': result.emitConfirmedReport.toSnapshotJson(),
            'idioms': IdiomHistogram.from(result.classifications).toJson(),
          };
        } finally {
          await fetched.dispose();
        }
      }

      final snapshotFile = File('${await _repoRoot()}/$_kSnapshotRelPath');
      if (Platform.environment['REGEN_PUBDEV_SNAPSHOT'] == '1') {
        snapshotFile.parent.createSync(recursive: true);
        snapshotFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(actual)}\n',
        );
      }
      expect(
        snapshotFile.existsSync(),
        isTrue,
        reason: 'Snapshot missing at ${snapshotFile.path}; regenerate with '
            'REGEN_PUBDEV_SNAPSHOT=1.',
      );
      final expected =
          jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;
      expect(
        actual,
        expected,
        reason: 'pub.dev coverage drifted from the committed snapshot. If a '
            'codegen mechanism landed (intentional), regenerate with '
            'REGEN_PUBDEV_SNAPSHOT=1 and update the findings note.',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// The scan's skip ledger as deterministic JSON — each skip's identifier +
/// reason, sorted by identifier so the snapshot is stable across runs.
List<Map<String, String>> _skipsJson(List<WidgetSkip> skips) {
  final rows = [
    for (final s in skips) {'identifier': s.identifier, 'reason': s.reason},
  ]..sort((a, b) => a['identifier']!.compareTo(b['identifier']!));
  return rows;
}

/// The repo root — three levels above the `restage_codegen` package `lib` dir
/// (`<root>/packages/restage_codegen/lib/restage_codegen.dart`), resolved via
/// the running isolate's package config (CWD-independent).
Future<String> _repoRoot() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_codegen/restage_codegen.dart'),
  );
  if (libUri == null) {
    throw StateError('Unable to resolve package:restage_codegen.');
  }
  return File.fromUri(libUri).parent.parent.parent.parent.path;
}
