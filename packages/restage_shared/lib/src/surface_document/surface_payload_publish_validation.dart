import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        MeasurementOrderedCaptureDeclarationV1,
        kHostListItemPositionKey,
        kLocalValueSetEventName,
        kMeasurementPublicationItemArgumentKeyV1,
        kMeasurementPublicationReservedArgumentPrefixV1,
        kMeasurementPublicationRouteArgumentKeyV1;
import 'package:restage_shared/src/fonts/literal_icon_code_points.dart';
import 'package:restage_shared/src/fonts/sfnt_cmap.dart';
import 'package:restage_shared/src/rfw_formats.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';
import 'package:restage_shared/src/surface_feature_client_floor.dart';

/// The largest delivered icon font a publish accepts, in bytes.
const int kMaxDeliveredIconFontBytes = 64 * 1024;

/// Refusal of a payload whose delivered icon fonts miss literal icons.
final class IconFontCoverageException extends FormatException {
  /// Creates the refusal for [missing] code points, keyed by font family.
  IconFontCoverageException(Map<String, List<int>> missing)
      : missing = Map.unmodifiable({
          for (final family in missing.keys.toList()..sort())
            family: List<int>.unmodifiable(missing[family]!.toList()..sort()),
        }),
        super(_describe(missing));

  /// Uncovered code points, ascending, keyed by font family.
  final Map<String, List<int>> missing;

  static String _describe(Map<String, List<int>> missing) {
    final families = missing.keys.toList()..sort();
    final parts = [
      for (final family in families)
        '$family: ${(missing[family]!.toList()..sort()).map(_hex).join(', ')}',
    ];
    return 'The delivered icon fonts do not cover these icons: '
        '${parts.join('; ')}.';
  }

  static String _hex(int codePoint) =>
      'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

/// Validates the icon-font and local-seed sections of [payload] for publish.
///
/// When icon fonts are present, each must be a well-formed sfnt of at most
/// [kMaxDeliveredIconFontBytes], and every literal icon code point in the
/// payload's blobs must be covered by a font of its family, else an
/// [IconFontCoverageException]. A blob payload's local seeds must name
/// widgets the blob declares. Throws a [FormatException] on any refusal.
void validatePayloadSectionsForPublish(SurfacePayload payload) {
  final blobs = switch (payload) {
    BlobSurfacePayload(:final blob) => {'': blob},
    FlowSurfacePayload(:final screenBlobs) => screenBlobs,
  };
  if (payload is BlobSurfacePayload && payload.localSeeds.isNotEmpty) {
    final declared = {
      for (final widget in decodeLibraryBlob(payload.blob).widgets) widget.name,
    };
    for (final root in payload.localSeeds.keys) {
      if (!declared.contains(root)) {
        throw FormatException(
          'Local seeds name "$root", which the surface does not declare.',
        );
      }
    }
  }
  var writesLocalValues = false;
  for (final blob in blobs.values) {
    if (_validateEvents(decodeLibraryBlob(blob))) writesLocalValues = true;
  }
  if (writesLocalValues && payload.minClient < kSurfaceFeatureClientFloor) {
    throw FormatException(
      'The payload minClient ${payload.minClient} must be at least '
      '$kSurfaceFeatureClientFloor for a surface that writes screen-local '
      'values.',
    );
  }
  if (payload.iconFonts.isEmpty) return;

  final covered = <String, Set<int>>{};
  for (final font in payload.iconFonts) {
    covered
        .putIfAbsent(font.family, () => <int>{})
        .addAll(_fontCodePoints(font));
  }
  final missing = <String, Set<int>>{};
  for (final blob in blobs.values) {
    final used = literalIconCodePoints(decodeLibraryBlob(blob));
    for (final entry in used.entries) {
      final have = covered[entry.key] ?? const <int>{};
      final lacking = entry.value.difference(have);
      if (lacking.isNotEmpty) {
        missing.putIfAbsent(entry.key, () => <int>{}).addAll(lacking);
      }
    }
  }
  if (missing.isNotEmpty) {
    throw IconFontCoverageException({
      for (final entry in missing.entries) entry.key: entry.value.toList(),
    });
  }
}

Set<int> _fontCodePoints(DeliveredIconFont font) {
  final label = font.fontPackage == null
      ? font.family
      : '${font.family} (${font.fontPackage})';
  if (font.bytes.length > kMaxDeliveredIconFontBytes) {
    throw FormatException(
      'The icon font $label is ${font.bytes.length} bytes; the limit is '
      '$kMaxDeliveredIconFontBytes.',
    );
  }
  try {
    return readSfntCoveredCodePoints(Uint8List.fromList(font.bytes));
  } on FormatException catch (error) {
    throw FormatException('The icon font $label is invalid: ${error.message}');
  }
}

/// Refuses a reserved measurement argument other than the route and item
/// keys, and a tap item bound to anything but a literal string or its loop
/// element's index, so host context never reaches a measurement. Returns
/// whether [library] writes a screen-local value.
bool _validateEvents(RemoteWidgetLibrary library) {
  var writesLocalValues = false;
  void walk(Object? node) {
    switch (node) {
      case EventHandler(:final eventName, :final eventArguments):
        if (eventName == kLocalValueSetEventName) writesLocalValues = true;
        for (final key in eventArguments.keys) {
          if (key.startsWith(kMeasurementPublicationReservedArgumentPrefixV1) &&
              key != kMeasurementPublicationRouteArgumentKeyV1 &&
              key != kMeasurementPublicationItemArgumentKeyV1) {
            throw FormatException(
              'The tap argument "$key" is reserved for measurement.',
            );
          }
        }
        if (eventArguments.containsKey(
          kMeasurementPublicationItemArgumentKeyV1,
        )) {
          final item = eventArguments[kMeasurementPublicationItemArgumentKeyV1];
          final admitted = item is String ||
              (item is LoopReference &&
                  item.parts.length == 1 &&
                  item.parts.single == kHostListItemPositionKey);
          if (!admitted) {
            throw const FormatException(
              'A tap item must be a literal string or its list element index.',
            );
          }
        }
      case ConstructorCall(:final arguments):
        arguments.values.forEach(walk);
      case WidgetBuilderDeclaration(:final widget):
        walk(widget);
      case Loop(:final output):
        walk(output);
      case Switch(:final outputs):
        outputs.values.forEach(walk);
      case final List<Object?> list:
        list.forEach(walk);
      case final Map<Object?, Object?> map:
        map.values.forEach(walk);
    }
  }

  for (final declaration in library.widgets) {
    walk(declaration.root);
  }
  return writesLocalValues;
}

/// Refuses a publication whose measurement [routes] count tap items or mark
/// completing taps unless [payload] requires [kSurfaceFeatureClientFloor].
void validateMeasurementRouteFloorForPublish({
  required SurfacePayload payload,
  required Iterable<MeasurementOrderedCaptureDeclarationV1?> routes,
}) {
  final flagged = routes.any(
    (route) =>
        route != null && (route.interactionItemsV1 || route.completesSurfaceV1),
  );
  if (flagged && payload.minClient < kSurfaceFeatureClientFloor) {
    throw FormatException(
      'The payload minClient ${payload.minClient} must be at least '
      '$kSurfaceFeatureClientFloor for taps that count items or complete the '
      'surface.',
    );
  }
}
