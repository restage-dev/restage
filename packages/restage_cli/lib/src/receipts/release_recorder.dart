import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/receipt_location.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';

/// Produces the generated output for the app at `projectRoot`.
typedef ReceiptGeneratorRunner =
    Future<ProcessResult> Function(Directory projectRoot);

/// How many uncommitted paths a refusal names before it counts the rest.
const int _listedPathLimit = 10;

/// Writes an operation's receipts into the repository and commits them.
final class ReleaseRecorder {
  ReleaseRecorder._({
    required this.repository,
    required this.projectRoot,
    required GitHead head,
  }) : _head = head;

  /// Open the repository the app sits in, ready to record.
  ///
  /// Returns null after writing to [stderr] the reason it cannot. Every check
  /// here runs before the first server call.
  static Future<ReleaseRecorder?> open({
    required Directory projectRoot,
    required StringSink stderr,
    GitProcessRunner? processRunner,
  }) async {
    final GitRepository? repository;
    try {
      repository = await GitRepository.open(
        projectRoot,
        processRunner: processRunner,
      );
    } on GitUnavailableException {
      stderr.writeln(
        'Git is not available, so there is no commit to record. Install it, '
        'or drop --record-git.',
      );
      return null;
    }
    if (repository == null) {
      stderr.writeln(
        'This app is not in a Git repository, so there is no commit to '
        'record. Run it inside one, or drop --record-git.',
      );
      return null;
    }
    final head = await repository.head();
    if (head == null) {
      stderr.writeln(
        'The repository has no commits yet. Commit the source you want '
        'recorded and retry.',
      );
      return null;
    }
    if (head.detached) {
      stderr.writeln(
        'HEAD is detached, so the receipt commit would belong to no branch. '
        'Check out a branch and retry.',
      );
      return null;
    }
    final operation = await repository.operationInProgress();
    if (operation != null) {
      stderr.writeln(
        'There is ${operation.description} in progress. Finish it and retry.',
      );
      return null;
    }
    return ReleaseRecorder._(
      repository: repository,
      projectRoot: projectRoot,
      head: head,
    );
  }

  /// The repository the app sits in.
  final GitRepository repository;

  /// The app package root.
  final Directory projectRoot;

  /// Where `HEAD` pointed when this recorder opened.
  GitHead get head => _head;

  final GitHead _head;
  final List<String> _written = <String>[];

  /// Prove the source is committed, then produce the output from it.
  ///
  /// Returns the source every receipt of this push records, or null after
  /// writing to [stderr] the reason it cannot proceed.
  Future<ReceiptSource?> buildFromCommittedSource({
    required StringSink stdout,
    required StringSink stderr,
    ReceiptGeneratorRunner? generator,
  }) async {
    final SourceBoundary boundary;
    try {
      boundary = await resolveSourceBoundary(
        projectRoot: projectRoot,
        repository: repository,
      );
    } on SourceBoundaryException catch (error) {
      stderr.writeln(error.message);
      return null;
    }

    final before = await _uncommitted(boundary);
    if (before.isNotEmpty) {
      stderr.writeln(
        'The source is not committed, so a receipt cannot name the commit it '
        'came from:',
      );
      _listPaths(before, stderr);
      stderr.writeln('Commit them and retry.');
      return null;
    }

    stdout.writeln('Producing the output from the committed source.');
    final result = await (generator ?? _runGenerator)(projectRoot);
    if (result.exitCode != 0) {
      stderr
        ..writeln('The output could not be produced from the committed source.')
        ..writeln(_text(result.stderr).trim())
        ..writeln(_text(result.stdout).trim());
      return null;
    }

    final after = await _uncommitted(boundary);
    if (after.isNotEmpty) {
      stderr.writeln(
        'Producing the output changed files this repository tracks, so the '
        'committed source and the output no longer agree:',
      );
      _listPaths(after, stderr);
      stderr.writeln('Commit them and retry.');
      return null;
    }

    return ReceiptSource(
      state: ReceiptSourceState.verified,
      commit: _head.commit,
      branch: _head.branch,
      packages: boundary.packages,
    );
  }

  /// The source recorded for a revision this repository already pushed.
  ///
  /// Reads that push's own receipt, so a publication names the commit the
  /// revision was built from however far `HEAD` has moved since. Unknown when
  /// no receipt here recorded that push.
  Future<ReceiptSource> sourceOfPushedRevision({
    required String organization,
    required String project,
    required String app,
    required String surfaceType,
    required String surfaceId,
    required String environment,
    required int revision,
  }) async {
    final file = File(
      p.join(
        projectRoot.path,
        surfacePushReceiptPath(
          organization: organization,
          project: project,
          app: app,
          surfaceType: surfaceType,
          surfaceId: surfaceId,
          environment: environment,
          revision: revision,
        ),
      ),
    );
    if (!file.existsSync()) return const ReceiptSource.unknown();
    final ReleaseReceipt pushed;
    try {
      pushed = ReleaseReceipt.decode(await file.readAsString());
    } on FormatException {
      return const ReceiptSource.unknown();
    }
    final commit = pushed.source.commit;
    if (commit == null || pushed.source.state != ReceiptSourceState.verified) {
      return const ReceiptSource.unknown();
    }
    return ReceiptSource(
      state: ReceiptSourceState.verified,
      commit: commit,
      from: repository.pathspecFor(file.path),
    );
  }

  /// Write [receipt] at [relativePath] under the app package.
  ///
  /// The path is the operation's identity, so recording one twice keeps the
  /// first record rather than writing a second. Returns false after printing
  /// the record when it cannot be written: the server already did the work,
  /// so the record is what must not be lost.
  Future<bool> write({
    required ReleaseReceipt receipt,
    required String relativePath,
    required StringSink stdout,
    required StringSink stderr,
  }) async {
    final file = File(p.join(projectRoot.path, relativePath));
    if (file.existsSync()) {
      if (_recordsTheSameOperation(file, receipt)) {
        _written.add(repository.pathspecFor(file.path));
        return true;
      }
      stderr.writeln(
        'A different operation is already recorded at $relativePath, so this '
        'one was not written over it. It reads:',
      );
      stdout.write(receipt.encode());
      return false;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(receipt.encode());
    } on FileSystemException catch (error) {
      stderr.writeln(
        'The receipt for $relativePath could not be written '
        '(${error.message}). It belongs at ${file.path} and reads:',
      );
      stdout.write(receipt.encode());
      return false;
    }
    _written.add(repository.pathspecFor(file.path));
    return true;
  }

  /// Whether the receipt already at [file] records what [receipt] records.
  bool _recordsTheSameOperation(File file, ReleaseReceipt receipt) {
    final ReleaseReceipt existing;
    try {
      existing = ReleaseReceipt.decode(file.readAsStringSync());
    } on FormatException {
      return false;
    } on FileSystemException {
      return false;
    }
    return existing.operation == receipt.operation &&
        existing.target.organizationId == receipt.target.organizationId &&
        existing.target.project == receipt.target.project &&
        existing.target.app == receipt.target.app &&
        existing.target.environment == receipt.target.environment &&
        existing.target.environmentTargetId ==
            receipt.target.environmentTargetId &&
        existing.surface?.type == receipt.surface?.type &&
        existing.surface?.id == receipt.surface?.id &&
        existing.bundle?.head == receipt.bundle?.head &&
        existing.bundle?.version == receipt.bundle?.version &&
        existing.revision?.stored == receipt.revision?.stored &&
        existing.revision?.activeBefore == receipt.revision?.activeBefore;
  }

  /// Commit what this operation wrote, in one commit.
  ///
  /// Returns false after reporting that the receipt is pending and naming the
  /// two commands that commit it.
  Future<bool> commit({
    required String message,
    required StringSink stdout,
    required StringSink stderr,
  }) async {
    if (_written.isEmpty) return true;
    try {
      final commit = await repository.commitPaths(
        paths: _written,
        message: message,
      );
      if (commit == null) {
        stdout.writeln('The receipt already matches the last commit.');
        return true;
      }
      final count = _written.length;
      stdout.writeln(
        'Recorded ${count == 1 ? 'the receipt' : '$count receipts'} in '
        '${commit.substring(0, 7)}.',
      );
      return true;
    } on GitCommitFailure catch (error) {
      // Named from the repository root and quoted, so the two commands work
      // from wherever the developer is standing.
      final paths = _written.map(_quoted).join(' ');
      final root = _quoted(repository.root.path);
      stderr.writeln(
        'Git receipt pending: the operation is recorded in '
        '${_written.join(', ')}, and the commit did not go through.',
      );
      if (error.output.isNotEmpty) stderr.writeln(error.output);
      stderr
        ..writeln('Commit it with:')
        ..writeln('  git -C $root add -- $paths')
        ..writeln(
          '  git -C $root commit --only -m ${_quoted(message)} -- $paths',
        );
      if (!error.indexRestored) {
        stderr.writeln(
          'The receipt is still staged. Take it back out with:\n'
          '  git -C $root reset -- $paths',
        );
      }
      return false;
    }
  }

  /// Uncommitted paths in [boundary], leaving receipts themselves out.
  ///
  /// A receipt is a record of an operation rather than an input to one, so a
  /// receipt waiting to be committed never blocks the next push.
  Future<List<String>> _uncommitted(SourceBoundary boundary) async {
    final receipts = repository.pathspecFor(
      p.join(projectRoot.path, receiptsDirectory),
    );
    final entries = await repository.uncommitted(paths: boundary.packages);
    return <String>[
      for (final entry in entries)
        if (!p.posix.isWithin(receipts, entry.path)) entry.path,
    ];
  }
}

/// [value] as one shell word: close the quote, escape the apostrophe, reopen.
String _quoted(String value) => "'${value.replaceAll("'", r"'\''")}'";

void _listPaths(List<String> paths, StringSink stderr) {
  for (final path in paths.take(_listedPathLimit)) {
    stderr.writeln('  $path');
  }
  if (paths.length > _listedPathLimit) {
    stderr.writeln('  and ${paths.length - _listedPathLimit} more');
  }
}

Future<ProcessResult> _runGenerator(Directory projectRoot) => Process.run(
  'dart',
  const ['run', 'build_runner', 'build'],
  workingDirectory: projectRoot.path,
  runInShell: false,
);

String _text(Object? stream) => switch (stream) {
  String value => value,
  List<int> bytes => String.fromCharCodes(bytes),
  _ => '',
};
