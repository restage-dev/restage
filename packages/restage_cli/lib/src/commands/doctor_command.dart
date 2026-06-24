import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// The build flag every app shipping the renderer must pass.
///
/// The generated catalog reconstructs icon glyphs from runtime codepoint
/// values rather than from compile-time constants, so the framework's
/// icon tree-shaker cannot see them and strips the font glyphs from a
/// release build. Without this flag every catalog icon renders as a
/// missing-glyph box ("tofu") — a failure visible only on a real
/// release-mode device build, never in tests or debug.
const _requiredBuildFlag = '--no-tree-shake-icons';

/// The exact build/run invocations the app must use, copy-pasteable.
const _recommendedBuildCommands = <String>[
  'flutter build ios --no-tree-shake-icons',
  'flutter build appbundle --no-tree-shake-icons',
  'flutter build web --wasm --no-tree-shake-icons',
  'flutter run --no-tree-shake-icons',
];

/// Relative paths (from the project root) of files that commonly carry a
/// build invocation. If any of these mentions the required flag we treat
/// it as evidence the project enforces it; otherwise we cannot prove it
/// and emit an actionable reminder instead.
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

/// Check the host project for the build-flag requirement and print a
/// clear PASS / WARN result plus a copy-pasteable reminder.
///
/// `doctor` never fails the build; it is advisory. It exits `0` whether
/// or not the flag is detected — a WARN result is informational, because
/// the flag lives in the host app's build invocation (a Makefile, a CI
/// job, a release script) which the tool cannot always see. The reminder
/// block is always printed so the developer can copy the correct
/// commands regardless of the detection outcome.
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
      'Check the host project for common configuration issues — currently '
      'the $_requiredBuildFlag build-flag requirement.';

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
      _stdout.writeln('PASS  $_requiredBuildFlag');
      _stdout.writeln(
        '      Found in ${p.relative(evidence, from: root.path)} — your '
        'build invocation passes the flag.',
      );
    } else {
      _stdout.writeln('WARN  $_requiredBuildFlag');
      _stdout.writeln(
        '      Could not confirm your release build passes the flag. This '
        'is informational: the flag lives in your build command (a '
        'Makefile, CI job, or release script), which this check cannot '
        'always see.',
      );
    }

    _stdout.writeln('');
    _printReminder();

    return 0;
  }

  /// Print the always-on reminder block: the failure mode in plain terms
  /// and the exact commands to copy.
  void _printReminder() {
    _stdout.writeln('Build with $_requiredBuildFlag.');
    _stdout.writeln(
      'Why: the renderer builds icons from runtime values, so the icon '
      'tree-shaker strips the glyphs from a release build unless this flag '
      'is set. Every icon then renders as a missing-glyph box ("tofu") — '
      'visible only on a real release-mode device build, not in debug or '
      'tests.',
    );
    _stdout.writeln('');
    _stdout.writeln('Use these invocations (copy as needed):');
    for (final command in _recommendedBuildCommands) {
      _stdout.writeln('  $command');
    }
  }

  /// Walk the known build-config candidates under [root] and return the
  /// path of the first file that mentions the required flag, or null when
  /// none is found.
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

  /// Scan the scannable files directly under [dir] (recursing into
  /// subdirectories) for the required flag. Bounded by [_scannableExtensions]
  /// so we never read large binary trees.
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

  /// True when [file] can be read as text and contains the required flag.
  bool _fileMentionsFlag(File file) {
    try {
      return file.readAsStringSync().contains(_requiredBuildFlag);
    } on FileSystemException {
      return false;
    } on FormatException {
      // Binary content — not a build script we can read as text.
      return false;
    }
  }
}
