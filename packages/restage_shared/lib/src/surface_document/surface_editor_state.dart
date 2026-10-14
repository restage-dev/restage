import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Editor-only state saved with a draft in `SurfacePayload.editorState`.
///
/// [meta] holds the editor's document metadata (canvas geometry, slot
/// defaults, presentation style). A flow keeps one such map per screen in
/// [screens] instead. [catalog] is the custom widget catalog the surface was
/// built against, in the generated catalog JSON shape, or null.
@immutable
final class SurfaceEditorState {
  /// Creates editor state; both maps are deep-copied and frozen.
  SurfaceEditorState({
    Map<String, Object?> meta = const <String, Object?>{},
    Map<String, Object?>? catalog,
    Map<String, Map<String, Object?>>? screens,
  })  : meta = _freezeMap(meta, 'meta'),
        catalog = catalog == null ? null : _freezeMap(catalog, 'catalog'),
        screens = screens == null
            ? null
            : Map<String, Map<String, Object?>>.unmodifiable({
                for (final entry in screens.entries)
                  entry.key: _freezeMap(entry.value, 'screens.${entry.key}'),
              });

  /// Decodes [bytes] written by [encode].
  ///
  /// Throws [FormatException] when the bytes are not editor state.
  factory SurfaceEditorState.decode(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw FormatException('Editor state is not JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Editor state must be a JSON object.');
    }
    for (final key in decoded.keys) {
      if (key != _metaKey && key != _catalogKey && key != _screensKey) {
        throw FormatException('Unknown editor state field "$key".');
      }
    }
    final meta = decoded[_metaKey];
    final catalog = decoded[_catalogKey];
    if (meta is! Map<String, Object?>) {
      throw const FormatException('Editor state "meta" must be an object.');
    }
    if (catalog != null && catalog is! Map<String, Object?>) {
      throw const FormatException('Editor state "catalog" must be an object.');
    }
    final screens = decoded[_screensKey];
    if (screens != null &&
        (screens is! Map<String, Object?> ||
            screens.values.any((meta) => meta is! Map<String, Object?>))) {
      throw const FormatException(
        'Editor state "screens" must map each screen to an object.',
      );
    }
    return SurfaceEditorState(
      meta: meta,
      catalog: catalog as Map<String, Object?>?,
      screens: (screens as Map<String, Object?>?)?.map(
        (id, meta) => MapEntry(id, meta! as Map<String, Object?>),
      ),
    );
  }

  /// The editor's document metadata.
  final Map<String, Object?> meta;

  /// The custom widget catalog, or null when the surface uses none.
  final Map<String, Object?>? catalog;

  /// A flow's document metadata keyed by screen id, or null for a single
  /// screen.
  final Map<String, Map<String, Object?>>? screens;

  /// Canonical UTF-8 JSON: map keys sorted at every depth, no whitespace.
  Uint8List encode() => Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            _canonical(<String, Object?>{
              _metaKey: meta,
              if (catalog != null) _catalogKey: catalog,
              if (screens != null) _screensKey: screens,
            }),
          ),
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is SurfaceEditorState && _bytesEqual(encode(), other.encode());

  @override
  int get hashCode => Object.hashAll(encode());
}

const String _metaKey = 'meta';
const String _catalogKey = 'catalog';
const String _screensKey = 'screens';

Map<String, Object?> _freezeMap(Map<String, Object?> map, String path) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in map.entries)
        entry.key: _freeze(entry.value, '$path.${entry.key}'),
    });

Object? _freeze(Object? value, String path) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, path, 'must be finite');
    }
    return value;
  }
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, path, 'map keys must be text');
      }
      frozen[key] = _freeze(entry.value, '$path.$key');
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(<Object?>[
      for (var i = 0; i < value.length; i++) _freeze(value[i], '$path[$i]'),
    ]);
  }
  throw ArgumentError.value(value, path, 'is not a JSON value');
}

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List<Object?>) return value.map(_canonical).toList();
  return value;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
