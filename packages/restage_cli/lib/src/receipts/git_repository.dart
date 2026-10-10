import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Runs one Git command. Injected so tests drive the reader directly.
typedef GitProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// A Git command exited non-zero.
final class GitCommandException implements Exception {
  /// Construct a failure with the command and what Git reported.
  const GitCommandException({
    required this.arguments,
    required this.exitCode,
    required this.output,
  });

  /// Arguments the command was run with.
  final List<String> arguments;

  /// Exit code Git returned.
  final int exitCode;

  /// What Git wrote to its error stream.
  final String output;

  @override
  String toString() => 'git ${arguments.join(' ')} exited $exitCode: $output';
}

/// Where `HEAD` points.
@immutable
final class GitHead {
  /// Construct a head at [commit], on [branch] unless detached.
  const GitHead({required this.commit, this.branch});

  /// Full hash `HEAD` resolves to.
  final String commit;

  /// Branch `HEAD` is on, or null when `HEAD` is detached.
  final String? branch;

  /// Whether `HEAD` names a commit directly rather than a branch.
  bool get detached => branch == null;
}

/// A path-limited commit failed, and what became of the staging it did.
final class GitCommitFailure implements Exception {
  /// Construct a commit failure.
  const GitCommitFailure({required this.output, required this.indexRestored});

  /// What Git wrote to its error stream.
  final String output;

  /// Whether the paths were taken back out of the index afterwards.
  final bool indexRestored;

  @override
  String toString() => 'The commit did not go through: $output';
}

/// Git is not installed, so nothing here can be recorded.
final class GitUnavailableException implements Exception {
  /// Construct the failure.
  const GitUnavailableException();

  @override
  String toString() => 'Git is not available.';
}

/// A Git operation left half-finished in the repository.
enum GitOperationInProgress {
  /// A merge is waiting to be concluded.
  merge('a merge'),

  /// A rebase is waiting to be concluded.
  rebase('a rebase'),

  /// A cherry-pick is waiting to be concluded.
  cherryPick('a cherry-pick'),

  /// A revert is waiting to be concluded.
  revert('a revert');

  const GitOperationInProgress(this.description);

  /// Wording for a message that names what is in progress.
  final String description;
}

/// One path Git reports as carrying uncommitted content.
@immutable
final class GitPathStatus {
  /// Construct a status for [path].
  const GitPathStatus({required this.path});

  /// Repository-relative path, as Git reports it.
  final String path;
}

/// Reads the repository a project sits in, and makes the one commit a
/// receipt needs.
final class GitRepository {
  GitRepository._({required this.root, required GitProcessRunner runner})
    : _runner = runner;

  /// Open the repository containing [directory]; null when there is none.
  static Future<GitRepository?> open(
    Directory directory, {
    GitProcessRunner? processRunner,
  }) async {
    final runner = processRunner ?? _runGit;
    final start = _resolve(directory);
    if (start == null) return null;
    final ProcessResult result;
    try {
      result = await runner('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: start);
    } on ProcessException {
      throw const GitUnavailableException();
    }
    if (result.exitCode != 0) return null;
    final top = _text(result.stdout).trim();
    if (top.isEmpty) return null;
    return GitRepository._(root: Directory(top), runner: runner);
  }

  /// Absolute repository root.
  final Directory root;

  final GitProcessRunner _runner;

  /// Where `HEAD` points; null when the repository has no commits yet.
  Future<GitHead?> head() async {
    final commit = await _optional(const [
      'rev-parse',
      '--verify',
      '--quiet',
      'HEAD',
    ]);
    if (commit == null || commit.isEmpty) return null;
    final branch = await _optional(const [
      'symbolic-ref',
      '--quiet',
      '--short',
      'HEAD',
    ]);
    return GitHead(
      commit: commit,
      branch: branch == null || branch.isEmpty ? null : branch,
    );
  }

  /// The Git operation left in progress, when there is one.
  Future<GitOperationInProgress?> operationInProgress() async {
    final gitDir = await _required(const ['rev-parse', '--absolute-git-dir']);
    bool present(String name) {
      final path = p.join(gitDir, name);
      return File(path).existsSync() || Directory(path).existsSync();
    }

    if (present('MERGE_HEAD')) return GitOperationInProgress.merge;
    if (present('rebase-merge') || present('rebase-apply')) {
      return GitOperationInProgress.rebase;
    }
    if (present('CHERRY_PICK_HEAD')) return GitOperationInProgress.cherryPick;
    if (present('REVERT_HEAD')) return GitOperationInProgress.revert;
    return null;
  }

  /// Paths under [paths] that carry uncommitted content.
  ///
  /// Ignored files are left out; untracked files are reported.
  Future<List<GitPathStatus>> uncommitted({
    required Iterable<String> paths,
  }) async {
    final pathspecs = [for (final path in paths) pathspecFor(path)];
    if (pathspecs.isEmpty) return const [];
    final result = await _run([
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--',
      ...pathspecs,
    ]);
    if (result.exitCode != 0) {
      throw GitCommandException(
        arguments: const ['status'],
        exitCode: result.exitCode,
        output: _text(result.stderr).trim(),
      );
    }
    return _parseStatus(_text(result.stdout));
  }

  /// Commit exactly [paths] with [message], running hooks and signing.
  ///
  /// Anything else staged or modified stays where it is. Returns the new
  /// commit, or null when those paths already match `HEAD`.
  Future<String?> commitPaths({
    required Iterable<String> paths,
    required String message,
  }) async {
    final pathspecs = [for (final path in paths) pathspecFor(path)];
    if (pathspecs.isEmpty) return null;
    await _required(['add', '--', ...pathspecs]);
    final unchanged = await _run([
      'diff',
      '--quiet',
      'HEAD',
      '--',
      ...pathspecs,
    ]);
    if (unchanged.exitCode == 0) return null;
    try {
      await _required([
        'commit',
        '--only',
        '--message',
        message,
        '--',
        ...pathspecs,
      ]);
    } on GitCommandException catch (error) {
      // The commit did not happen, so the staging this method did is undone:
      // the developer's next commit must not carry these paths.
      final reset = await _run(['reset', '--quiet', '--', ...pathspecs]);
      throw GitCommitFailure(
        output: error.output,
        indexRestored: reset.exitCode == 0,
      );
    }
    return _required(const ['rev-parse', 'HEAD']);
  }

  /// [path] as a repository-relative pathspec Git accepts.
  String pathspecFor(String path) {
    final absolute = p.isAbsolute(path) ? path : p.join(root.path, path);
    return p.posix.joinAll(p.split(p.relative(absolute, from: root.path)));
  }

  Future<ProcessResult> _run(List<String> arguments) =>
      _runner('git', arguments, workingDirectory: root.path);

  Future<String> _required(List<String> arguments) async {
    final result = await _run(arguments);
    if (result.exitCode != 0) {
      throw GitCommandException(
        arguments: arguments,
        exitCode: result.exitCode,
        output: _text(result.stderr).trim(),
      );
    }
    return _text(result.stdout).trim();
  }

  Future<String?> _optional(List<String> arguments) async {
    final result = await _run(arguments);
    if (result.exitCode != 0) return null;
    return _text(result.stdout).trim();
  }
}

/// Decode the terminated short status Git writes for `--porcelain=v1 -z`.
List<GitPathStatus> _parseStatus(String output) {
  // Built at run time so the separator never sits in this file as a byte.
  final fields = output.split(String.fromCharCode(0));
  final statuses = <GitPathStatus>[];
  for (var index = 0; index < fields.length; index += 1) {
    final field = fields[index];
    if (field.length < 4) continue;
    final indexState = field[0];
    // A rename or copy is followed by its source path in the next field.
    if (indexState == 'R' || indexState == 'C') index += 1;
    statuses.add(GitPathStatus(path: field.substring(3)));
  }
  return statuses;
}

String? _resolve(Directory directory) {
  try {
    return directory.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

String _text(Object? stream) => switch (stream) {
  String value => value,
  List<int> bytes => String.fromCharCodes(bytes),
  _ => '',
};

Future<ProcessResult> _runGit(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: false,
);
