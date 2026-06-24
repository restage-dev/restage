import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/coverage_measurement/real_package_scanner.dart';

/// Measures the `@RestageWidget` custom-widget inlinability surface of a real
/// on-disk Flutter package and prints a coverage report.
///
/// Usage:
///
///     dart run restage_codegen:measure_real_package_coverage <package-path> \
///         [--json]
///
/// `<package-path>` is the directory of a Flutter package that has already been
/// fetched (`dart pub get`, or `melos bootstrap` for a workspace member). The
/// report shows the classifier-recognised upper bound and the emit-confirmed
/// metric distinctly. `--json` additionally prints the machine-readable
/// per-bucket snapshot.
///
/// The reference catalog is the three committed built-in library catalogs of
/// this workspace; measuring against a customer's own catalog version is a
/// future refinement.
Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final wantJson = args.contains('--json');

  if (positional.length != 1) {
    stderr
      ..writeln('Usage: dart run restage_codegen:measure_real_package_coverage '
          '<package-path> [--json]')
      ..writeln()
      ..writeln('Measures the @RestageWidget custom-widget inlinability of a '
          'real on-disk Flutter package.')
      ..writeln('The package must be fetched first (dart pub get / melos '
          'bootstrap).');
    exitCode = 64; // EX_USAGE
    return;
  }

  final packagePath = positional.single;
  final catalog = await loadMergedCatalogFromDisk();

  final ScanResult result;
  try {
    result = await scanPackage(packagePath: packagePath, catalog: catalog);
  } on PackageNotResolvedException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }

  stdout.write(renderScanReport(result));

  if (wantJson) {
    final json = <String, dynamic>{
      'package': result.packagePath,
      'widgetCount': result.widgetCount,
      'classifierRecognised': result.classifierReport.toSnapshotJson(),
      'emitConfirmed': result.emitConfirmedReport.toSnapshotJson(),
    };
    stdout
      ..writeln()
      ..writeln(const JsonEncoder.withIndent('  ').convert(json));
  }
}
