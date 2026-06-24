// Fetches a published Flutter package from pub.dev into a writable temp copy
// with its own resolved package config, so the real-package coverage scanner
// can point at it exactly like any local on-disk package.
//
// This file is `src`-internal tooling, NOT exported from the package barrel.
// Its consumers are the pub.dev measurement entrypoint and its tests. The
// `locatePackageInCache` / `compareVersionStrings` helpers are pure (no
// network, no process spawn) and are unit-tested directly; the orchestrating
// `fetchPubPackageToTemp` shells out to `dart pub cache add` + `flutter pub
// get` and is exercised only by the network-gated integration test.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the on-disk directory of [package] (optionally pinned to [version])
/// inside a pub cache rooted at [cacheRoot] — `hosted/pub.dev/<package>-<v>`.
///
/// With [version] null, returns the highest cached version (numeric-segment
/// comparison, so `2.0.10` beats `2.0.1`). Returns null when nothing matches —
/// the caller fetches first.
String? locatePackageInCache({
  required String cacheRoot,
  required String package,
  String? version,
}) {
  final hosted = Directory(p.join(cacheRoot, 'hosted', 'pub.dev'));
  if (!hosted.existsSync()) return null;

  if (version != null) {
    final pinned = Directory(p.join(hosted.path, '$package-$version'));
    return pinned.existsSync() ? pinned.path : null;
  }

  final prefix = '$package-';
  final versions = hosted
      .listSync()
      .whereType<Directory>()
      .map((d) => p.basename(d.path))
      .where((name) => name.startsWith(prefix))
      .map((name) => name.substring(prefix.length))
      .toList();
  if (versions.isEmpty) return null;
  versions.sort(compareVersionStrings);
  return p.join(hosted.path, '$package-${versions.last}');
}

/// Splits a version string into its `.`/`+`/`-`-separated segments.
final _versionSeparators = RegExp('[.+-]');

/// Compares two version strings by numeric segments (`2.0.10` > `2.0.1`),
/// falling back to lexicographic ordering for non-numeric / pre-release tails.
int compareVersionStrings(String a, String b) {
  List<int> segments(String v) =>
      v.split(_versionSeparators).map((s) => int.tryParse(s) ?? -1).toList();
  final aSeg = segments(a);
  final bSeg = segments(b);
  for (var i = 0; i < aSeg.length && i < bSeg.length; i++) {
    final c = aSeg[i].compareTo(bSeg[i]);
    if (c != 0) return c;
  }
  final byLength = aSeg.length.compareTo(bSeg.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

/// Runs a child process, returning its result. Injectable so the fetch
/// orchestration can be unit-tested without spawning real processes.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> args, {
  String? workingDirectory,
});

/// A published package fetched to a writable temp directory and pub-got there,
/// ready for the coverage scanner. Call [dispose] to delete the temp copy.
class FetchedPackage {
  /// Creates a fetched-package handle.
  FetchedPackage({
    required this.package,
    required this.version,
    required this.directory,
    required this.dispose,
  });

  /// The package name as fetched.
  final String package;

  /// The resolved version that was fetched (the pinned one, or the highest).
  final String version;

  /// The writable temp directory holding the package copy (pub-got).
  final String directory;

  /// Deletes the temp copy.
  final Future<void> Function() dispose;
}

/// Thrown when a fetch sub-step (cache add, locate, copy, pub get) fails, with
/// an actionable [message].
class PubFetchException implements Exception {
  /// Creates the exception with an actionable [message].
  PubFetchException(this.message);

  /// What went wrong and (where useful) how to fix it.
  final String message;

  @override
  String toString() => 'PubFetchException: $message';
}

/// Fetches [package] (optionally pinned to [version]) from pub.dev and copies
/// it to a fresh temp directory with its own resolved `package_config.json`,
/// so it can be scanned exactly like any local on-disk package.
///
/// Steps: `dart pub cache add` (download the archive) → locate it in the pub
/// cache → copy to a temp dir → `flutter pub get` in the copy. Requires network
/// and a Flutter SDK on `PATH`; gate callers behind an opt-in (see the
/// network-tagged integration test).
///
/// [pubCacheRoot] defaults to `PUB_CACHE` or `~/.pub-cache`. [runProcess] is
/// injectable for testing.
Future<FetchedPackage> fetchPubPackageToTemp({
  required String package,
  String? version,
  String? pubCacheRoot,
  ProcessRunner? runProcess,
}) async {
  final run = runProcess ?? _defaultRun;
  final cacheRoot = pubCacheRoot ??
      Platform.environment['PUB_CACHE'] ??
      p.join(_homeDir(), '.pub-cache');

  final addArgs = <String>[
    'pub',
    'cache',
    'add',
    package,
    if (version != null) ...['--version', version],
  ];
  final added = await run('dart', addArgs);
  if (added.exitCode != 0) {
    throw PubFetchException(
      '`dart ${addArgs.join(' ')}` failed (exit ${added.exitCode}): '
      '${added.stderr}',
    );
  }

  final cached = locatePackageInCache(
    cacheRoot: cacheRoot,
    package: package,
    version: version,
  );
  if (cached == null) {
    throw PubFetchException(
      'Could not locate $package${version == null ? '' : '-$version'} under '
      '"$cacheRoot" after `pub cache add`.',
    );
  }
  // `<package>-<version>` → the version is everything after `<package>-`.
  final resolvedVersion = p.basename(cached).substring(package.length + 1);

  final temp = Directory.systemTemp.createTempSync('b3_pubdev_');
  final destDir = Directory(p.join(temp.path, p.basename(cached)));
  _copyDirectory(Directory(cached), destDir);

  final got = await run(
    'flutter',
    const ['pub', 'get'],
    workingDirectory: destDir.path,
  );
  if (got.exitCode != 0) {
    temp.deleteSync(recursive: true);
    throw PubFetchException(
      '`flutter pub get` in "${destDir.path}" failed (exit ${got.exitCode}): '
      '${got.stderr}',
    );
  }

  return FetchedPackage(
    package: package,
    version: resolvedVersion,
    directory: destDir.path,
    dispose: () async {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    },
  );
}

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) =>
    Process.run(executable, args, workingDirectory: workingDirectory);

String _homeDir() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

/// Recursively copies the files of [src] to [dest], creating each file's parent
/// directory as needed. (Empty directories are not copied — a pub package's
/// resolvable content is all files.)
void _copyDirectory(Directory src, Directory dest) {
  for (final file in src.listSync(recursive: true).whereType<File>()) {
    final target = p.join(dest.path, p.relative(file.path, from: src.path));
    Directory(p.dirname(target)).createSync(recursive: true);
    file.copySync(target);
  }
}
