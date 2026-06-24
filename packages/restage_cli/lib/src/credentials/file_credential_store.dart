import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:path/path.dart' as p;

/// Thrown when the credential file exists but cannot be decoded safely.
///
/// The message deliberately includes only the path and a generic reason. Dart's
/// raw JSON [FormatException] can include the source text, which may contain
/// the persisted auth token.
@experimental
class MalformedCredentialFileException implements Exception {
  /// Construct with the credential file [path].
  const MalformedCredentialFileException(this.path);

  /// Path of the malformed credentials file.
  final String path;

  @override
  String toString() =>
      'MalformedCredentialFileException: credentials file is malformed at '
      '$path. Run `restage login` again to replace it.';
}

/// Returns the platform-default location of the credentials file.
///
/// On POSIX: respects `$XDG_CONFIG_HOME` when set, otherwise falls back
/// to `$HOME/.config/restage/credentials`.
///
/// On Windows: writes under `%APPDATA%\restage\credentials`.
///
/// Throws [StateError] when neither `$HOME` nor `%APPDATA%` is set.
@experimental
String defaultCredentialPath({
  Map<String, String>? environment,
  bool? isWindows,
}) {
  final env = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  if (windows) {
    final appData = env['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError(
        '%APPDATA% is not set — cannot locate the credentials file.',
      );
    }
    return p.join(appData, 'restage', 'credentials');
  }
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return p.join(xdg, 'restage', 'credentials');
  }
  final home = env['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError(r'$HOME is not set — cannot locate the credentials file.');
  }
  return p.join(home, '.config', 'restage', 'credentials');
}

/// On-disk credential store backed by a single JSON file.
///
/// On POSIX, the file is permissioned `0600` (owner read/write only)
/// after every write. Parent directories are created on demand.
@experimental
class FileCredentialStore {
  /// Construct a store rooted at [path].
  FileCredentialStore(this.path);

  /// Construct a store at the platform-default location.
  factory FileCredentialStore.atDefaultLocation() =>
      FileCredentialStore(defaultCredentialPath());

  /// Absolute path the store reads from and writes to.
  final String path;

  /// Read the persisted credential, or `null` when the file does not
  /// exist. Throws if the file is malformed.
  ///
  /// Reads the file directly and treats a "no such file" error as
  /// absence, rather than pre-checking with [File.exists] — the
  /// pre-check would race with concurrent deletion.
  Future<Credential?> read() async {
    final file = File(path);
    final String raw;
    try {
      raw = await file.readAsString();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (e) {
      // Older Dart SDKs report missing files as a generic FileSystemException
      // with errno 2 (ENOENT) rather than PathNotFoundException.
      if (e.osError?.errorCode == 2) return null;
      rethrow;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('credentials JSON must be an object');
      }
      return Credential.fromJson(json);
    } on FormatException {
      throw MalformedCredentialFileException(path);
    } on TypeError {
      throw MalformedCredentialFileException(path);
    }
  }

  /// Persist [credential] to [path], creating parent directories as
  /// needed and tightening permissions to `0600` on POSIX.
  Future<void> write(Credential credential) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(credential.toJson()));
    if (!Platform.isWindows) {
      await _chmodOwnerOnly(file.path);
    }
  }

  /// Remove the credentials file. A no-op when no file exists.
  ///
  /// Deletes directly and tolerates "no such file" errors, rather than
  /// pre-checking — the pre-check would race with concurrent deletion.
  Future<void> delete() async {
    final file = File(path);
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone — desired terminal state reached.
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 2) return;
      rethrow;
    }
  }

  /// Tighten POSIX file permissions to `0600` (owner read/write only).
  ///
  /// Invokes `chmod` by absolute path so a malicious entry earlier on `PATH`
  /// cannot shadow the system binary. Falls back to the bare name only when
  /// the standard locations are absent (unusual POSIX layouts).
  Future<void> _chmodOwnerOnly(String filePath) async {
    final result = await Process.run(_chmodExecutable(), <String>[
      '600',
      filePath,
    ]);
    if (result.exitCode != 0) {
      throw StateError('chmod 600 failed on $filePath: ${result.stderr}');
    }
  }

  /// Resolve a trusted absolute path to the `chmod` binary.
  ///
  /// `/bin/chmod` (Linux, macOS) and `/usr/bin/chmod` cover every supported
  /// POSIX target; the bare name is a last resort.
  static String _chmodExecutable() {
    for (final candidate in const ['/bin/chmod', '/usr/bin/chmod']) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'chmod';
  }
}
