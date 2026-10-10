import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// Directory inside a render bundle that holds the Flutter engine files.
///
/// A bundle file whose path starts with this prefix is an engine file, and the
/// remainder of the path is its [RenderBundleEngineFile.path].
const renderBundleEnginePathPrefix = 'canvaskit/';

const _canonicalHeader = 'restage.render-bundle-engine-set.v2';

final _pathPattern = RegExp(
  r'^[a-z0-9][a-z0-9_.-]*(?:/[a-z0-9][a-z0-9_.-]*)*$',
);
final _hashPattern = RegExp(r'^sha256:[0-9a-f]{64}$');
final _engineRevisionPattern = RegExp(r'^[0-9a-f]{40}$');
final _flutterVersionPattern = RegExp(
  r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$',
);

/// Most files one engine set may list.
const renderBundleEngineSetMaxFiles = 64;

/// Largest engine file a set may list, about twice the largest real one.
const int renderBundleEngineFileMaxBytes = 16 * 1024 * 1024;

/// Largest total a set's files may add up to, about twice a real set.
const int renderBundleEngineSetMaxBytes = 64 * 1024 * 1024;

/// One file the Flutter loader fetches from a bundle's engine base.
@immutable
final class RenderBundleEngineFile {
  /// Creates one entry and rejects a shape the loader could not ask for.
  RenderBundleEngineFile({
    required this.path,
    required this.contentHash,
    required this.byteLength,
  }) {
    if (!_pathPattern.hasMatch(path)) {
      throw FormatException('Invalid engine file path.', path);
    }
    if (!_hashPattern.hasMatch(contentHash)) {
      throw FormatException('Invalid engine file content hash.', contentHash);
    }
    if (byteLength <= 0 || byteLength > renderBundleEngineFileMaxBytes) {
      throw FormatException(
        'Engine file length must be between 1 and '
        '$renderBundleEngineFileMaxBytes bytes.',
        path,
      );
    }
  }

  /// Path relative to the bundle's engine base, such as `skwasm.wasm`.
  final String path;

  /// `sha256:` followed by 64 lowercase hex characters.
  final String contentHash;

  /// Exact length of the file in bytes.
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is RenderBundleEngineFile &&
      other.path == path &&
      other.contentHash == contentHash &&
      other.byteLength == byteLength;

  @override
  int get hashCode => Object.hash(path, contentHash, byteLength);

  @override
  String toString() => '$path $contentHash $byteLength';
}

/// The engine files a bundle loads, as one Flutter SDK produced them.
///
/// A set is identified by the hash of its canonical form, so the same SDK
/// yields the same set for every app and organization.
final class RenderBundleEngineSet {
  /// Creates one set from files sorted by path.
  RenderBundleEngineSet({
    required this.flutterVersion,
    required this.engineRevision,
    required List<RenderBundleEngineFile> files,
  }) : files = List<RenderBundleEngineFile>.unmodifiable(files) {
    if (!_flutterVersionPattern.hasMatch(flutterVersion)) {
      throw FormatException('Invalid Flutter version.', flutterVersion);
    }
    if (!_engineRevisionPattern.hasMatch(engineRevision)) {
      throw FormatException('Invalid engine revision.', engineRevision);
    }
    if (this.files.isEmpty ||
        this.files.length > renderBundleEngineSetMaxFiles) {
      throw const FormatException(
        'An engine set holds between one and '
        '$renderBundleEngineSetMaxFiles files.',
      );
    }
    for (var index = 1; index < this.files.length; index++) {
      if (this.files[index - 1].path.compareTo(this.files[index].path) >= 0) {
        throw FormatException(
          'Engine files are sorted by path and each path appears once.',
          this.files[index].path,
        );
      }
    }
    if (byteLength > renderBundleEngineSetMaxBytes) {
      throw const FormatException(
        'An engine set holds at most $renderBundleEngineSetMaxBytes bytes.',
      );
    }
  }

  /// Reads the set whose [canonicalForm] is exactly [text].
  ///
  /// Anything that does not serialize back to the same text is refused, so a
  /// parsed set always hashes to the identifier its text does.
  factory RenderBundleEngineSet.parse(String text) {
    final lines = text.split('\n');
    if (lines.length < 5 ||
        lines.first != _canonicalHeader ||
        !lines[1].startsWith('flutter ') ||
        !lines[2].startsWith('engine ') ||
        lines.last.isNotEmpty) {
      throw const FormatException('Not an engine set.');
    }
    final files = <RenderBundleEngineFile>[];
    for (final line in lines.sublist(3, lines.length - 1)) {
      final fields = line.split(' ');
      final length = fields.length == 3 ? int.tryParse(fields[2]) : null;
      if (length == null) throw FormatException('Bad engine file line.', line);
      files.add(
        RenderBundleEngineFile(
          path: fields[0],
          contentHash: fields[1],
          byteLength: length,
        ),
      );
    }
    final set = RenderBundleEngineSet(
      flutterVersion: lines[1].substring('flutter '.length),
      engineRevision: lines[2].substring('engine '.length),
      files: files,
    );
    if (set.canonicalForm != text) {
      throw const FormatException('Engine set text is not canonical.');
    }
    return set;
  }

  /// Derives the set from the engine files one build produced.
  ///
  /// [files] is keyed by path relative to the engine directory.
  factory RenderBundleEngineSet.fromFiles({
    required String flutterVersion,
    required String engineRevision,
    required Map<String, List<int>> files,
  }) =>
      RenderBundleEngineSet(
        flutterVersion: flutterVersion,
        engineRevision: engineRevision,
        files: [
          for (final path in files.keys.toList()..sort())
            RenderBundleEngineFile(
              path: path,
              contentHash: 'sha256:${crypto.sha256.convert(files[path]!)}',
              byteLength: files[path]!.length,
            ),
        ],
      );

  /// The Flutter version this set was derived from.
  final String flutterVersion;

  /// The Flutter engine revision whose release published these files.
  final String engineRevision;

  /// Every file in the set, sorted by path.
  final List<RenderBundleEngineFile> files;

  late final Map<String, RenderBundleEngineFile> _byPath = {
    for (final file in files) file.path: file,
  };

  /// The exact text [id] is taken over.
  late final String canonicalForm = (StringBuffer()
        ..writeln(_canonicalHeader)
        ..writeln('flutter $flutterVersion')
        ..writeln('engine $engineRevision')
        ..writeAll(
          files.map(
            (file) => '${file.path} ${file.contentHash} '
                '${file.byteLength}\n',
          ),
        ))
      .toString();

  /// SHA-256 of [canonicalForm], as 64 lowercase hex characters.
  ///
  /// This is the identifier the engine files serve under, so it appears in a
  /// URL path segment and carries no prefix.
  late final String id =
      crypto.sha256.convert(utf8.encode(canonicalForm)).toString();

  /// Sum of every file's length.
  late final int byteLength = files.fold(
    0,
    (total, file) => total + file.byteLength,
  );

  /// The entry at [path], or `null` when this set has none.
  RenderBundleEngineFile? fileForPath(String path) => _byPath[path];

  /// Whether [contentHash] belongs to the file this set holds at [path].
  bool holds({required String path, required String contentHash}) =>
      _byPath[path]?.contentHash == contentHash;
}
