// Compile all assets/paywalls/*.rfwtxt → *.rfw using rfw's pure-Dart
// formats sublibrary. Runs on the standalone Dart VM.
//
// Usage (from apps/examples/):
//   dart run tool/build_paywall.dart           # one-shot
//   dart run tool/build_paywall.dart --watch   # rebuild on .rfwtxt change

import 'dart:io';

import 'package:rfw/formats.dart';
import 'package:watcher/watcher.dart';

const _paywallsDir = 'assets/paywalls';

Future<void> main(List<String> args) async {
  final watch = args.contains('--watch');

  _compileAll();
  if (!watch) return;

  stdout
      .writeln('Watching $_paywallsDir/ for .rfwtxt changes (Ctrl+C to stop)…');
  final watcher = DirectoryWatcher(_paywallsDir);
  await for (final event in watcher.events) {
    if (!event.path.endsWith('.rfwtxt')) continue;
    if (event.type == ChangeType.REMOVE) continue;
    _compileFile(event.path);
  }
}

void _compileAll() {
  final dir = Directory(_paywallsDir);
  if (!dir.existsSync()) {
    stderr.writeln('No $_paywallsDir/ directory.');
    exitCode = 1;
    return;
  }
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith('.rfwtxt')) {
      _compileFile(entity.path);
    }
  }
}

void _compileFile(String inputPath) {
  final outputPath = inputPath.replaceAll(RegExp(r'\.rfwtxt$'), '.rfw');
  final ts = DateTime.now().toIso8601String().split('.').first;
  try {
    final source = File(inputPath).readAsStringSync();
    final library = parseLibraryFile(source, sourceIdentifier: inputPath);
    final bytes = encodeLibraryBlob(library);
    File(outputPath).writeAsBytesSync(bytes);
    stdout.writeln(
      '[$ts] $inputPath → $outputPath '
      '(${library.widgets.length} widget(s), ${bytes.length} bytes)',
    );
  } catch (e) {
    stderr.writeln('[$ts] FAILED $inputPath: $e');
  }
}
