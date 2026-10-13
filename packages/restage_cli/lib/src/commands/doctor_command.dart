import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// A build flag Restage apps no longer need.
///
/// Generated registrations keep icons as compile-time constants, so icon tree
/// shaking works. Passing this flag only keeps every glyph in the app.
const _unneededBuildFlag = '--no-tree-shake-icons';

/// Relative paths (from the project root) of files that commonly carry a
/// build invocation.
const _buildConfigCandidates = <String>[
  'Makefile',
  'makefile',
  'GNUmakefile',
  'justfile',
  'Justfile',
  '.github/workflows',
  'fastlane/Fastfile',
  'ios/fastlane/Fastfile',
  'android/fastlane/Fastfile',
  'codemagic.yaml',
  'bitrise.yml',
  '.gitlab-ci.yml',
  'cloudbuild.yaml',
  'melos.yaml',
  'scripts',
  'tool',
];

/// File extensions worth scanning when we descend into a candidate
/// directory (e.g. `scripts/`, `.github/workflows`).
const _scannableExtensions = <String>{
  '.sh',
  '.bash',
  '.zsh',
  '.yaml',
  '.yml',
  '.dart',
  '.rb',
  '.ps1',
  '.bat',
  '.cmd',
  '.mk',
  '.gradle',
  '.kts',
};

/// Check the host project for common setup issues and print PASS or WARN.
///
/// Advisory only: it exits `0` either way.
class DoctorCommand extends Command<int> {
  /// Construct a doctor command bound to the given output sinks.
  DoctorCommand({required StringSink stdout, required StringSink stderr})
    : _stdout = stdout,
      _stderr = stderr {
    argParser.addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'Project root (defaults to the current directory).',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the project for common setup issues, such as a build command '
      'that turns off icon tree shaking.';

  @override
  Future<int> run() async {
    final root = Directory(argResults!['directory'] as String).absolute;
    if (!root.existsSync()) {
      _stderr.writeln(
        'No directory at ${root.path}. Run `restage doctor` from a project '
        'root, or pass `--directory <path>`.',
      );
      return 1;
    }

    final evidence = _findFlagEvidence(root);

    _stdout.writeln('restage doctor');
    _stdout.writeln('');

    if (evidence != null) {
      _stdout.writeln('WARN  Icon tree shaking is turned off');
      _stdout.writeln(
        '      ${p.relative(evidence, from: root.path)} passes '
        '$_unneededBuildFlag. Restage apps don\'t need it, and it keeps '
        'every icon glyph in your app. Remove it unless another dependency '
        'needs it.',
      );
    } else {
      _stdout.writeln('PASS  Icon tree shaking');
      _stdout.writeln(
        '      No build command found that passes $_unneededBuildFlag.',
      );
    }

    return 0;
  }

  /// Returns the first build-config file under [root] that mentions the flag.
  String? _findFlagEvidence(Directory root) {
    for (final candidate in _buildConfigCandidates) {
      final path = p.join(root.path, candidate);
      final asFile = File(path);
      if (asFile.existsSync()) {
        if (_fileMentionsFlag(asFile)) return asFile.path;
        continue;
      }
      final asDir = Directory(path);
      if (asDir.existsSync()) {
        final hit = _scanDirectory(asDir);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// Scans text files under [dir], limited to [_scannableExtensions].
  String? _scanDirectory(Directory dir) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      return null;
    }
    for (final entry in entries) {
      if (entry is! File) continue;
      final ext = p.extension(entry.path).toLowerCase();
      // Files with no extension (e.g. a CI shell step file) are scanned
      // too; extension-bearing files must be in the allow-list.
      if (ext.isNotEmpty && !_scannableExtensions.contains(ext)) continue;
      if (_fileMentionsFlag(entry)) return entry.path;
    }
    return null;
  }

  /// True when [file] reads as text and contains the flag.
  bool _fileMentionsFlag(File file) {
    try {
      return file.readAsStringSync().contains(_unneededBuildFlag);
    } on FileSystemException {
      return false;
    } on FormatException {
      // Binary content — not a build script we can read as text.
      return false;
    }
  }
}
