import 'dart:io';

import 'package:path/path.dart' as p;

const _binaryBaseName = 'restage-preview';

/// Locate the desktop preview binary.
///
/// Search order:
///   1. `RESTAGE_PREVIEW_BIN` — full path override. Used when [_existing]
///      reports the file exists.
///   2. `~/.restage/bin/restage-preview[.exe]` — the conventional
///      per-user install location.
///   3. Each `PATH` entry in order, until one contains a matching
///      executable.
///
/// Returns the absolute path on success, or null when none of the above
/// yield a hit.
///
/// All filesystem and environment access is parameterised so unit tests
/// can drive the function without touching real disks.
String? locateRestagePreviewBinary({
  Map<String, String>? environment,
  bool? isWindows,
  bool Function(String path)? existsCheck,
  Iterable<String>? pathOverride,
}) {
  final env = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  final exists = existsCheck ?? _defaultExists;
  final binaryName = windows ? '$_binaryBaseName.exe' : _binaryBaseName;

  // 1. Explicit override.
  final override = env['RESTAGE_PREVIEW_BIN'];
  if (override != null && override.isNotEmpty && exists(override)) {
    return override;
  }

  // 2. Per-user install location.
  final home = _homeDir(env, windows: windows);
  if (home != null) {
    final installed = p.join(home, '.restage', 'bin', binaryName);
    if (exists(installed)) return installed;
  }

  // 3. PATH walk.
  final searchPath =
      pathOverride ?? _pathFromEnvironment(env, windows: windows);
  for (final dir in searchPath) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, binaryName);
    if (exists(candidate)) return candidate;
  }
  return null;
}

bool _defaultExists(String path) => FileSystemEntity.isFileSync(path);

String? _homeDir(Map<String, String> env, {required bool windows}) {
  if (windows) {
    return env['USERPROFILE'] ?? env['HOMEPATH'];
  }
  return env['HOME'];
}

Iterable<String> _pathFromEnvironment(
  Map<String, String> env, {
  required bool windows,
}) {
  final raw = env['PATH'] ?? '';
  if (raw.isEmpty) return const <String>[];
  final separator = windows ? ';' : ':';
  return raw.split(separator);
}
