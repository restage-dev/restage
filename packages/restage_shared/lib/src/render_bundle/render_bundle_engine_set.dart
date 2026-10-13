import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// Directory inside a render bundle that holds the Flutter engine files.
///
/// A bundle file whose path starts with this prefix is an engine file, and the
/// remainder of the path is its [RenderBundleEngineFile.path].
const renderBundleEnginePathPrefix = 'canvaskit/';

const _canonicalHeader = 'restage.render-bundle-engine-set.v1';

final _pathPattern = RegExp(
  r'^[a-z0-9][a-z0-9_.-]*(?:/[a-z0-9][a-z0-9_.-]*)*$',
);
final _hashPattern = RegExp(r'^sha256:[0-9a-f]{64}$');
final _flutterVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');

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
    if (byteLength <= 0) {
      throw FormatException('Engine file length must be positive.', path);
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

/// The engine files every bundle built on one Flutter version loads.
///
/// Sets are pinned per Flutter version and never change once published, so a
/// bundle built on an older version still resolves the engine it was built
/// against.
final class RenderBundleEngineSet {
  /// Creates one pinned set from files sorted by path.
  RenderBundleEngineSet({
    required this.flutterVersion,
    required List<RenderBundleEngineFile> files,
  }) : files = List<RenderBundleEngineFile>.unmodifiable(files) {
    if (!_flutterVersionPattern.hasMatch(flutterVersion)) {
      throw FormatException('Invalid Flutter version.', flutterVersion);
    }
    if (this.files.isEmpty) {
      throw const FormatException('An engine set holds at least one file.');
    }
    for (var index = 1; index < this.files.length; index++) {
      if (this.files[index - 1].path.compareTo(this.files[index].path) >= 0) {
        throw FormatException(
          'Engine files are sorted by path and each path appears once.',
          this.files[index].path,
        );
      }
    }
  }

  /// The Flutter version this set was derived from.
  final String flutterVersion;

  /// Every file in the set, sorted by path.
  final List<RenderBundleEngineFile> files;

  late final Map<String, RenderBundleEngineFile> _byPath = {
    for (final file in files) file.path: file,
  };

  /// The exact text [id] is taken over.
  late final String canonicalForm = (StringBuffer()
        ..writeln(_canonicalHeader)
        ..writeln('flutter $flutterVersion')
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

/// Every pinned engine set, oldest Flutter version first.
final List<RenderBundleEngineSet> renderBundleEngineSets =
    List<RenderBundleEngineSet>.unmodifiable(<RenderBundleEngineSet>[
  _flutter3470,
  // Append a newer pinned set above this line.
]);

/// The set the current pinned Flutter version builds against.
RenderBundleEngineSet get newestRenderBundleEngineSet =>
    renderBundleEngineSets.last;

/// The set derived from [flutterVersion], or `null` when none is pinned.
RenderBundleEngineSet? renderBundleEngineSetForFlutterVersion(
  String flutterVersion,
) {
  for (final set in renderBundleEngineSets) {
    if (set.flutterVersion == flutterVersion) return set;
  }
  return null;
}

/// The set identified by [id], or `null` when no pinned set matches.
RenderBundleEngineSet? renderBundleEngineSetById(String id) {
  for (final set in renderBundleEngineSets) {
    if (set.id == id) return set;
  }
  return null;
}

/// One entry, taking the digest without its algorithm prefix.
RenderBundleEngineFile _file(String path, String digest, int byteLength) =>
    RenderBundleEngineFile(
      path: path,
      contentHash: 'sha256:$digest',
      byteLength: byteLength,
    );

/// Produced by `tool/derive_render_bundle_engine_set.dart` from an installed
/// Flutter SDK; the accompanying test checks it back against that SDK.
final _flutter3470 = RenderBundleEngineSet(
  flutterVersion: '3.47.0',
  files: <RenderBundleEngineFile>[
    _file(
      'canvaskit.js',
      'bb559f6080c7d312ac2a912b4abec9f68ff3d3022d4a603c7796b9b31460642b',
      86987,
    ),
    _file(
      'canvaskit.wasm',
      '2898c0795cf4a694e86ee3445c7414c2503fbcb46967154762f50ebde988da04',
      7284349,
    ),
    _file(
      'chromium/canvaskit.js',
      '6018b12bd8ed37e6952eee72d59c1cf7ad707ccdb74a0a45190010f77edd9068',
      86226,
    ),
    _file(
      'chromium/canvaskit.wasm',
      'ba4024133403777f41c709b9e76e9f4bdb76c73d33adba8645527a59d815d824',
      5428553,
    ),
    _file(
      'skwasm.js',
      '71d7d3e34bf71b52bdba3b588b103bba8148ba28de5754083e01b3398e7a6e1c',
      63537,
    ),
    _file(
      'skwasm.wasm',
      'a957befea55cf597eeebcf3286f1b88f463f3ad8bfc13e55aa8f5d34cd2ade4d',
      3593521,
    ),
    _file(
      'skwasm_heavy.js',
      'cec554b46ddcf4c0e63d799e0556d546f42d2c3f69316fb4f67ed776f6104558',
      63650,
    ),
    _file(
      'skwasm_heavy.wasm',
      '781a14fc7e9cd387ee6df4a056f62af7e940c60cc42ce04571cc2e810042c588',
      5216023,
    ),
    _file(
      'webparagraph/canvaskit.js',
      '3110e3e4d9b7b5657d336f253aaca8acca5777cde9319fb69ac302d6ff5a8b23',
      76114,
    ),
    _file(
      'webparagraph/canvaskit.wasm',
      '7a61c4ad71781875a80bbfc5ee6e49686dd190d629e0fe986d3ecc05ada58856',
      3729073,
    ),
    _file(
      'wimp.js',
      '8fd8a47480c6eb0a374d159912d0b3fb15661b41f5c113ecdd39c2f01f2bee46',
      59127,
    ),
    _file(
      'wimp.wasm',
      '7474f6074c42c4be503c9059c9b5058e468a68a8917ac6c3607f0da4922f7e5a',
      3581483,
    ),
  ],
);
