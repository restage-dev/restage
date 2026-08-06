import 'dart:convert';

import 'package:build/build.dart';
import 'package:meta/meta.dart';

const _missingAssetMessage =
    'asset does not exist or was deleted before it could be read';

/// Stable source context carried from annotation discovery through example
/// loading and later schema/graph validation.
@immutable
final class A2uiExampleSourceAnchor {
  /// Creates an example source anchor.
  const A2uiExampleSourceAnchor({
    required this.sourceClass,
    required this.widgetName,
    required this.exampleName,
    required this.asset,
  });

  /// Dart class carrying the annotation.
  final String sourceClass;

  /// Catalog component name declared by `@RestageWidget`.
  final String widgetName;

  /// Developer-authored example name.
  final String exampleName;

  /// Developer-authored package-relative sidecar path.
  final String asset;

  /// Returns an anchor with selected fields replaced.
  A2uiExampleSourceAnchor copyWith({
    String? sourceClass,
    String? widgetName,
    String? exampleName,
    String? asset,
  }) =>
      A2uiExampleSourceAnchor(
        sourceClass: sourceClass ?? this.sourceClass,
        widgetName: widgetName ?? this.widgetName,
        exampleName: exampleName ?? this.exampleName,
        asset: asset ?? this.asset,
      );
}

/// An exact JSON component array read through the build graph.
@immutable
final class LoadedA2uiExample {
  /// Creates a loaded example.
  const LoadedA2uiExample({
    required this.anchor,
    required this.assetId,
    required this.components,
  });

  /// Source context for diagnostics and later association.
  final A2uiExampleSourceAnchor anchor;

  /// Normalized same-package build asset.
  final AssetId assetId;

  /// Deeply immutable, order-preserving flattened GenUI component objects.
  final List<Map<String, Object?>> components;
}

/// Stable fail-loud diagnostic for an invalid canonical example.
final class A2uiExampleException implements Exception {
  /// Creates an example diagnostic anchored to its annotation.
  const A2uiExampleException(this.message, this.anchor);

  /// Specific validation failure.
  final String message;

  /// Annotation source context.
  final A2uiExampleSourceAnchor anchor;

  @override
  String toString() =>
      'A2UI example on class "${anchor.sourceClass}" for widget '
      '"${anchor.widgetName}", example "${anchor.exampleName}", asset '
      '"${anchor.asset}": $message';
}

/// Returns the normalized same-package asset for [anchor].
///
/// Canonical example assets are already-normalized forward-slash paths below
/// `lib/`. Normalizing a rejected path on the caller's behalf would hide
/// traversal or platform-dependent authoring, so every non-canonical spelling
/// fails instead.
AssetId a2uiExampleAssetId(
  String package,
  A2uiExampleSourceAnchor anchor,
) {
  final asset = anchor.asset;
  final segments = asset.split('/');
  final hasScheme = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(asset);
  if (asset.isEmpty ||
      asset.startsWith('/') ||
      asset.contains(r'\') ||
      hasScheme ||
      !asset.startsWith('lib/') ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      ) ||
      !asset.endsWith('.json')) {
    throw A2uiExampleException(
      'asset must be an already-normalized same-package `lib/` JSON path '
      'using forward slashes',
      anchor,
    );
  }
  return AssetId(package, asset);
}

/// Decodes an exact flattened GenUI component array once, preserving object
/// and array order plus Dart's integer/double distinction.
///
/// This stage validates only the JSON-safe transport envelope. Component
/// schema and graph semantics belong to the later validator.
List<Map<String, Object?>> decodeA2uiExampleComponents(
  String source,
  A2uiExampleSourceAnchor anchor,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw A2uiExampleException('invalid JSON: ${error.message}', anchor);
  }
  if (decoded is! List<Object?>) {
    throw A2uiExampleException(
      'document root must be a bare JSON component array',
      anchor,
    );
  }

  final components = <Map<String, Object?>>[];
  for (var index = 0; index < decoded.length; index++) {
    final entry = decoded[index];
    if (entry is! Map<String, Object?>) {
      throw A2uiExampleException(
        'component at index $index must be a JSON object',
        anchor,
      );
    }
    if (entry['id'] is! String) {
      throw A2uiExampleException(
        'component at index $index must contain a string `id`',
        anchor,
      );
    }
    if (entry['component'] is! String) {
      throw A2uiExampleException(
        'component at index $index must contain a string `component`; '
        'internal `{type, properties}` objects are not the GenUI wire form',
        anchor,
      );
    }
    components.add(
      _freezeObject(entry, anchor, '\$[$index]')! as Map<String, Object?>,
    );
  }
  return List<Map<String, Object?>>.unmodifiable(components);
}

/// Loads one example through [BuildStep] so sidecar content is a declared
/// dynamic dependency of the generated outputs.
Future<LoadedA2uiExample> loadA2uiExample(
  BuildStep buildStep,
  A2uiExampleSourceAnchor anchor,
) async {
  final assetId = a2uiExampleAssetId(buildStep.inputId.package, anchor);
  if (!await buildStep.canRead(assetId)) {
    throw A2uiExampleException(_missingAssetMessage, anchor);
  }

  final String source;
  try {
    source = await buildStep.readAsString(assetId);
  } on AssetNotFoundException {
    throw A2uiExampleException(_missingAssetMessage, anchor);
  }
  return LoadedA2uiExample(
    anchor: anchor,
    assetId: assetId,
    components: decodeA2uiExampleComponents(source, anchor),
  );
}

Object? _freezeObject(
  Object? value,
  A2uiExampleSourceAnchor anchor,
  String path,
) {
  if (value is num && !value.isFinite) {
    throw A2uiExampleException(
      'non-finite number at $path is not a re-encodable JSON value',
      anchor,
    );
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      [
        for (var index = 0; index < value.length; index++)
          _freezeObject(value[index], anchor, '$path[$index]'),
      ],
    );
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key: _freezeObject(
          entry.value,
          anchor,
          '$path.${entry.key}',
        ),
    });
  }
  return value;
}
