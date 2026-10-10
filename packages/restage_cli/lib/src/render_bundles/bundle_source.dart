import 'dart:io';

import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';

/// The source a bundle was built from, as the repository reports it.
final class BundleSource {
  const BundleSource({
    required this.inRepository,
    this.commit,
    this.dirty = false,
  });

  /// A project that sits in no repository at all.
  const BundleSource.outsideRepository()
    : inRepository = false,
      commit = null,
      dirty = false;

  /// Whether the project sits in a repository.
  final bool inRepository;

  /// Commit `HEAD` resolved to, or null when there is none to read.
  final String? commit;

  /// Whether the project tree carried uncommitted content at build time.
  final bool dirty;

  /// The first seven characters, the way Git abbreviates a hash.
  String? get shortCommit {
    final full = commit;
    if (full == null) return null;
    return full.length <= 7 ? full : full.substring(0, 7);
  }
}

/// Reads the source a bundle is built from.
typedef BundleSourceReader =
    Future<BundleSource> Function(Directory projectRoot, {bool recordGit});

/// Reads the commit and the dirty state of the repository [projectRoot] is in.
///
/// A project outside a repository, one before its first commit, and one whose
/// status cannot be read all answer with no commit. Only [recordGit] refuses
/// dependencies whose state cannot be recorded.
Future<BundleSource> readBundleSource(
  Directory projectRoot, {
  bool recordGit = false,
  GitProcessRunner? processRunner,
}) async {
  final GitRepository? repository;
  try {
    repository = await GitRepository.open(
      projectRoot,
      processRunner: processRunner,
    );
  } on Object {
    return const BundleSource.outsideRepository();
  }
  if (repository == null) return const BundleSource.outsideRepository();
  final GitHead? head;
  try {
    head = await repository.head();
  } on Object {
    return const BundleSource(inRepository: true);
  }
  if (head == null) return const BundleSource(inRepository: true);
  // Under recordGit a SourceBoundaryException reaches the caller: it names
  // what to fix. Otherwise the app package alone decides the dirty state.
  List<String> paths;
  try {
    paths = await _sourcePaths(projectRoot, repository, recordGit: recordGit);
  } on SourceBoundaryException {
    if (recordGit) rethrow;
    paths = <String>[projectRoot.path];
  }
  try {
    final changed = await repository.uncommitted(paths: paths);
    return BundleSource(
      inRepository: true,
      commit: head.commit,
      dirty: changed.isNotEmpty,
    );
  } on Object {
    return const BundleSource(inRepository: true);
  }
}

/// The app package and the packages it depends on inside the repository.
///
/// A narrower set would call a dirty dependency clean, and the push prints
/// that answer, so a boundary that will not resolve is the caller's to refuse.
Future<List<String>> _sourcePaths(
  Directory projectRoot,
  GitRepository repository, {
  required bool recordGit,
}) async {
  final boundary = await resolveSourceBoundary(
    projectRoot: projectRoot,
    repository: repository,
    allowUnpinned: !recordGit,
  );
  return boundary.packages.isEmpty
      ? <String>[projectRoot.path]
      : boundary.packages;
}

/// One sentence naming the source a bundle was built from.
String describeBundleSource(BundleSource source) {
  final short = source.shortCommit;
  if (short == null) {
    return source.inRepository
        ? 'No source commit was recorded.'
        : 'Built outside a repository, so no source commit was recorded.';
  }
  return source.dirty
      ? 'Built from $short with local changes.'
      : 'Built from $short.';
}
