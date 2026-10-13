import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:flutter_test/flutter_test.dart' show Timeout;

/// A probe resolves package:flutter from source on a cold analyzer, which
/// takes seconds locally and far longer on a loaded runner.
const Timeout staticAnalysisTimeout = Timeout(Duration(minutes: 2));

/// Resolves [source] in-process as a library of this package and returns its
/// error-severity diagnostics. The probe exists only in memory.
Future<List<Diagnostic>> staticAnalysisErrors({
  required String fileName,
  required String source,
}) async {
  final probePath = [
    Directory.current.absolute.path,
    'test',
    'static_analysis_probe',
    fileName,
  ].join(Platform.pathSeparator);
  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE)
    ..setOverlay(probePath, content: source, modificationStamp: 0);
  final collection = AnalysisContextCollection(
    includedPaths: [probePath],
    resourceProvider: provider,
    sdkPath: _dartSdkPath(),
  );
  try {
    final result = await collection
        .contextFor(probePath)
        .currentSession
        .getErrors(probePath);
    if (result is! ErrorsResult) {
      throw StateError('Probe was not analyzed: $result');
    }
    return result.diagnostics
        .where((d) => d.severity == Severity.error)
        .toList();
  } finally {
    await collection.dispose();
  }
}

/// Renders diagnostics for a failure message.
String describeDiagnostics(List<Diagnostic> diagnostics) => diagnostics
    .map((d) => '${d.diagnosticCode.lowerCaseName}: ${d.message}')
    .join('\n');

// Tests run on flutter_tester, so the analyzer's executable-relative default
// does not find the SDK; use the Dart SDK bundled with the running Flutter.
String _dartSdkPath() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    final candidate = Directory(
      [dir.path, 'bin', 'cache', 'dart-sdk'].join(Platform.pathSeparator),
    );
    if (File('${candidate.path}${Platform.pathSeparator}version')
        .existsSync()) {
      return candidate.path;
    }
    dir = dir.parent;
  }
  throw StateError(
    'No Dart SDK found above ${Platform.resolvedExecutable}',
  );
}
