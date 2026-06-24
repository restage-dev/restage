import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/coverage_measurement/idiom_histogram.dart';
import 'package:restage_codegen/src/coverage_measurement/pubdev_fetch.dart';
import 'package:restage_codegen/src/coverage_measurement/real_package_scanner.dart';

/// Fetches a published Flutter package from pub.dev and measures the
/// inlinability of its widget surface against this workspace's committed
/// catalog, printing a coverage report plus an idiom histogram.
///
/// Usage:
///
///     dart run restage_codegen:measure_pubdev_coverage <package> \
///         [--version <v>] [--json] [--annotated-only]
///
/// By default every `StatelessWidget` / `StatefulWidget` subclass is measured
/// (published packages carry no custom-widget annotations, so the annotated
/// set would be empty); `--annotated-only` restricts to annotated widgets.
/// `--json` additionally prints the machine-readable per-bucket + idiom
/// snapshot. Requires network and a Flutter SDK on `PATH`.
///
/// The reference catalog is the three committed built-in library catalogs of
/// this workspace; measuring against a customer's own catalog version is a
/// future refinement.
Future<void> main(List<String> args) async {
  final wantJson = args.contains('--json');
  final annotatedOnly = args.contains('--annotated-only');
  final version = _flagValue(args, '--version');
  final positional = _positionalArgs(args, valueFlags: const {'--version'});

  // A dangling `--version` with no value would otherwise silently measure the
  // latest version while the user tried to pin one — fail loud instead.
  if (args.contains('--version') && version == null) {
    stderr.writeln('--version requires a value, e.g. --version 3.0.1');
    exitCode = 64; // EX_USAGE
    return;
  }

  if (positional.length != 1) {
    stderr
      ..writeln('Usage: dart run restage_codegen:measure_pubdev_coverage '
          '<package> [--version <v>] [--json] [--annotated-only]')
      ..writeln()
      ..writeln('Fetches a published Flutter package and measures the '
          'inlinability of its widget surface.')
      ..writeln('Requires network and a Flutter SDK on PATH.');
    exitCode = 64; // EX_USAGE
    return;
  }
  final package = positional.single;

  final catalog = await loadMergedCatalogFromDisk();

  final FetchedPackage fetched;
  try {
    fetched = await fetchPubPackageToTemp(package: package, version: version);
  } on PubFetchException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }

  try {
    final result = await scanPackage(
      packagePath: fetched.directory,
      catalog: catalog,
      widgetSelector:
          annotatedOnly ? restageAnnotatedWidgets : allFlutterWidgets,
    );
    final histogram = IdiomHistogram.from(result.classifications);

    stdout
      ..writeln('Package: ${fetched.package} ${fetched.version}')
      ..write(renderScanReport(result))
      ..writeln()
      ..write(histogram.render());

    if (wantJson) {
      final snapshot = <String, dynamic>{
        'package': fetched.package,
        'version': fetched.version,
        'widgetCount': result.widgetCount,
        'classifierRecognised': result.classifierReport.toSnapshotJson(),
        'emitConfirmed': result.emitConfirmedReport.toSnapshotJson(),
        'idioms': histogram.toJson(),
      };
      stdout
        ..writeln()
        ..writeln(const JsonEncoder.withIndent('  ').convert(snapshot));
    }
  } finally {
    await fetched.dispose();
  }
}

/// The value of [flag] in [args], in either form: `--flag value` (space) or
/// `--flag=value` (equals). Null when absent. Handling both forms keeps a
/// pinned `--version=3.0.1` from being silently ignored.
String? _flagValue(List<String> args, String flag) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == flag && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
  }
  return null;
}

/// The positional arguments in [args] — every token that is neither a `--flag`
/// nor the value consumed by a space-form value flag (`--version 3.0.1`). An
/// equals-form flag (`--version=3.0.1`) is self-contained, so it consumes no
/// following token.
List<String> _positionalArgs(
  List<String> args, {
  required Set<String> valueFlags,
}) {
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      if (valueFlags.contains(arg)) i++; // space-form: consume the value
      continue; // '--flag=value' is self-contained; '--bool' consumes nothing
    }
    positional.add(arg);
  }
  return positional;
}
