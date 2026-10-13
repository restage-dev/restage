import 'dart:convert';

import 'package:restage/restage.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;

import 'wire_json.dart';

/// Immutable wrapper around one canonical generated catalog.
///
/// The catalog graph is retained exactly instead of being projected through a
/// second schema model. Unknown catalog fields therefore survive round-trips.
final class RenderBundleManifest {
  RenderBundleManifest({
    required this.formatVersion,
    required Map<String, Object?> catalog,
  }) : catalog = snapshotWireMap(catalog, argumentName: 'catalog') {
    if (formatVersion != 1) {
      throw ArgumentError.value(
        formatVersion,
        'formatVersion',
        'only manifest format version 1 is supported',
      );
    }
    _validateCatalogIndexes(this.catalog);
  }

  factory RenderBundleManifest.fromJson(Map<String, Object?> json) {
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int) {
      throw const FormatException('formatVersion must be an integer.');
    }
    return RenderBundleManifest(
      formatVersion: formatVersion,
      catalog: _requiredMap(json, 'catalog'),
    );
  }

  factory RenderBundleManifest.fromCatalogJson(String source) {
    final decoded = jsonDecode(source);
    final catalog = _asStringMap(decoded, 'catalog');
    return RenderBundleManifest(formatVersion: 1, catalog: catalog);
  }

  final int formatVersion;
  final Map<String, Object?> catalog;

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(
        <String, Object?>{
          'formatVersion': formatVersion,
          'catalog': catalog,
        },
      );
}

/// Flutter engine facts advertised separately from the opaque catalog.
final class RenderEngine {
  RenderEngine({required this.flutterVersion, required this.renderer}) {
    if (flutterVersion.trim().isEmpty) {
      throw ArgumentError.value(
        flutterVersion,
        'flutterVersion',
        'must not be empty',
      );
    }
    if (renderer.trim().isEmpty) {
      throw ArgumentError.value(renderer, 'renderer', 'must not be empty');
    }
  }

  factory RenderEngine.fromJson(Map<String, Object?> json) => RenderEngine(
        flutterVersion: _requiredString(json, 'flutterVersion'),
        renderer: _requiredString(json, 'renderer'),
      );

  final String flutterVersion;
  final String renderer;

  Map<String, Object?> toJson() => <String, Object?>{
        'flutterVersion': flutterVersion,
        'renderer': renderer,
      };
}

void _validateCatalogIndexes(Map<String, Object?> catalog) {
  final libraries = _requiredMap(catalog, 'libraries');
  for (final entry in libraries.entries) {
    if (entry.key.trim().isEmpty) {
      throw const FormatException('library names must not be empty.');
    }
    if (entry.key == kReservedPreviewLibraryName) {
      throw FormatException(
        'library "$kReservedPreviewLibraryName" is reserved for internal '
        'preview instrumentation.',
      );
    }
    final library = _asStringMap(entry.value, 'library ${entry.key}');
    final capabilityVersion = library['capabilityVersion'];
    if (capabilityVersion != null &&
        (capabilityVersion is! int || capabilityVersion < 1)) {
      throw FormatException(
        'library ${entry.key} capabilityVersion must be a positive integer.',
      );
    }
  }

  final widgets = catalog['widgets'];
  if (widgets is! List<Object?>) {
    throw const FormatException('widgets must be a list.');
  }
  final identities = <String>{};
  for (final value in widgets) {
    final widget = _asStringMap(value, 'widget');
    final library = _requiredNonEmptyString(widget, 'library');
    final name = _requiredNonEmptyString(widget, 'name');
    if (name == kReservedPreviewConstructorName) {
      throw FormatException(
        'widget "$kReservedPreviewConstructorName" is reserved for internal '
        'preview instrumentation.',
      );
    }
    if (!libraries.containsKey(library)) {
      throw FormatException('widget $library.$name has no indexed library.');
    }
    final wireId = widget['wireId'];
    if (wireId != null && (wireId is! String || wireId.trim().isEmpty)) {
      throw FormatException('widget $library.$name has a malformed wireId.');
    }
    final identity = '$library\u0000$name';
    if (!identities.add(identity)) {
      throw FormatException('duplicate widget identity $library.$name.');
    }
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) =>
    _asStringMap(map[key], key);

Map<String, Object?> _asStringMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label keys must be strings.');
    }
    result[key] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

String _requiredNonEmptyString(Map<String, Object?> map, String key) {
  final value = _requiredString(map, key);
  if (value.trim().isEmpty) {
    throw FormatException('$key must not be empty.');
  }
  return value;
}
