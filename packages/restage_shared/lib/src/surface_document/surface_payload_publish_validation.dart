import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        MeasurementOrderedCaptureDeclarationV1,
        kHostListItemPositionKey,
        kLocalValueSetEventName,
        kMeasurementPublicationItemArgumentKeyV1,
        kMeasurementPublicationReservedArgumentPrefixV1,
        kMeasurementPublicationRouteArgumentKeyV1;
import 'package:restage_shared/src/capability/capability_manifest.dart'
    show LibraryRequirement;
import 'package:restage_shared/src/capability/widget_vocabulary.dart';
import 'package:restage_shared/src/fonts/literal_icon_code_points.dart';
import 'package:restage_shared/src/fonts/sfnt_cmap.dart';
import 'package:restage_shared/src/rfw_formats.dart' hide WidgetLibrary;
import 'package:restage_shared/src/surface_contract/screen_event_names.dart'
    show kReservedCommerceEventNames;
import 'package:restage_shared/src/surface_document/surface_document.dart';
import 'package:restage_shared/src/surface_feature_client_floor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show Catalog, WidgetEntry, WidgetLibrary, kBaselineCatalogVersion;

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
/// widgets the blob declares. No payload may carry editor state. Throws a
/// [FormatException] on any refusal.
void validatePayloadSectionsForPublish(SurfacePayload payload) {
  if (payload.editorState != null) {
    throw const FormatException('A published payload carries no editor state.');
  }
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

/// Refuses a reserved commerce event, a reserved measurement argument other
/// than the route and item
/// keys, and a tap item bound to anything but a literal string or its loop
/// element's index, so host context never reaches a measurement. Returns
/// whether [library] writes a screen-local value.
bool _validateEvents(RemoteWidgetLibrary library) {
  var writesLocalValues = false;
  void walk(Object? node) {
    switch (node) {
      case EventHandler(:final eventName, :final eventArguments):
        if (kReservedCommerceEventNames.contains(eventName)) {
          throw FormatException(
            'The event name "$eventName" is reserved. Choose another name.',
          );
        }
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

/// What a surface library needs from a client, read against a catalog.
@immutable
final class SurfaceCapabilityDerivation {
  /// Creates a derivation result.
  const SurfaceCapabilityDerivation({
    required this.builtInFloor,
    required this.requiredLibraries,
    required this.referencedWidgets,
    required this.ambiguousNames,
    required this.unversionedLibraries,
  });

  /// The highest `sinceVersion` over the built-in widgets referenced, and the
  /// surface feature floor, never below [kBaselineCatalogVersion].
  final int builtInFloor;

  /// One requirement per referenced custom library that declares a capability
  /// version, by namespace.
  final List<LibraryRequirement> requiredLibraries;

  /// Every catalog widget referenced, deduplicated, by qualified name.
  final List<WidgetEntry> referencedWidgets;

  /// Widget names that resolve to more than one library, sorted.
  final List<String> ambiguousNames;

  /// Referenced custom libraries without a capability version, by namespace.
  final List<WidgetLibrary> unversionedLibraries;
}

/// Derives what [library] needs from a client, resolving each widget by name
/// against [catalog]. Library-local declarations are not catalog references.
/// [requiresSurfaceFeatureFloor] raises the floor to
/// [kSurfaceFeatureClientFloor].
SurfaceCapabilityDerivation deriveSurfaceCapability(
  RemoteWidgetLibrary library,
  Catalog catalog, {
  bool requiresSurfaceFeatureFloor = false,
}) {
  final referenced = <WidgetEntry>[];
  final ambiguous = <String>{};
  final localNames = {for (final widget in library.widgets) widget.name};
  for (final widget in library.widgets) {
    _collectReferences(widget.root, catalog, localNames, referenced, ambiguous);
  }

  var builtInFloor = kBaselineCatalogVersion;
  final customLibraries = <WidgetLibrary>{};
  for (final entry in referenced) {
    if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null) {
      if (entry.sinceVersion > builtInFloor) builtInFloor = entry.sinceVersion;
    } else {
      customLibraries.add(entry.library);
    }
  }
  final featureFloor = surfaceFeatureClientFloor(library);
  if (builtInFloor < featureFloor) builtInFloor = featureFloor;
  if (requiresSurfaceFeatureFloor &&
      builtInFloor < kSurfaceFeatureClientFloor) {
    builtInFloor = kSurfaceFeatureClientFloor;
  }

  final requiredLibraries = <LibraryRequirement>[];
  final unversioned = <WidgetLibrary>[];
  for (final custom in customLibraries.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace))) {
    final version = catalog.libraries[custom]?.capabilityVersion;
    if (version == null) {
      unversioned.add(custom);
    } else {
      requiredLibraries.add(
        LibraryRequirement(namespace: custom.namespace, minVersion: version),
      );
    }
  }

  final byQualifiedName = <String, WidgetEntry>{};
  for (final entry in referenced) {
    byQualifiedName.putIfAbsent(
      WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
      () => entry,
    );
  }
  final names = byQualifiedName.keys.toList()..sort();
  return SurfaceCapabilityDerivation(
    builtInFloor: builtInFloor,
    requiredLibraries: List.unmodifiable(requiredLibraries),
    referencedWidgets: List.unmodifiable([
      for (final name in names) byQualifiedName[name]!,
    ]),
    ambiguousNames: List.unmodifiable(ambiguous.toList()..sort()),
    unversionedLibraries: List.unmodifiable(unversioned),
  );
}

/// Appends the catalog entry of every non-local constructor under [node] to
/// [out]; a name found in more than one library goes to [ambiguous].
void _collectReferences(
  Object? node,
  Catalog catalog,
  Set<String> localNames,
  List<WidgetEntry> out,
  Set<String> ambiguous,
) {
  switch (node) {
    case ConstructorCall(:final name, :final arguments):
      if (!localNames.contains(name)) {
        final candidates = [
          for (final widget in catalog.widgets)
            if (widget.name == name) widget,
        ];
        if (candidates.map((c) => c.library).toSet().length > 1) {
          ambiguous.add(name);
        } else if (candidates.isNotEmpty) {
          out.add(candidates.first);
        }
      }
      for (final argument in arguments.values) {
        _collectReferences(argument, catalog, localNames, out, ambiguous);
      }
    case List<Object?>():
      for (final child in node) {
        _collectReferences(child, catalog, localNames, out, ambiguous);
      }
    case Switch(:final outputs):
      for (final output in outputs.values) {
        _collectReferences(output, catalog, localNames, out, ambiguous);
      }
    case Loop(:final output):
      _collectReferences(output, catalog, localNames, out, ambiguous);
    case WidgetBuilderDeclaration(:final widget):
      _collectReferences(widget, catalog, localNames, out, ambiguous);
    case Map<Object?, Object?>():
      for (final value in node.values) {
        _collectReferences(value, catalog, localNames, out, ambiguous);
      }
  }
}

/// The client floor [library]'s surface features need: icon literals,
/// screen-local value writes and counted tap items need
/// [kSurfaceFeatureClientFloor], a loop that emits a widget list needs
/// [kGroupedWidgetListClientFloor]. [kBaselineCatalogVersion] otherwise.
int surfaceFeatureClientFloor(RemoteWidgetLibrary library) {
  var floor = literalIconCodePoints(library).isNotEmpty
      ? kSurfaceFeatureClientFloor
      : kBaselineCatalogVersion;
  void require(int version) {
    if (floor < version) floor = version;
  }

  void visit(Object? node) {
    switch (node) {
      case EventHandler():
        if (node.eventName == kLocalValueSetEventName ||
            node.eventArguments
                .containsKey(kMeasurementPublicationItemArgumentKeyV1)) {
          require(kSurfaceFeatureClientFloor);
        }
        visit(node.eventArguments);
      case ConstructorCall():
        visit(node.arguments);
      case WidgetBuilderDeclaration():
        visit(node.widget);
      case Loop():
        if (node.output is List) require(kGroupedWidgetListClientFloor);
        visit(node.input);
        visit(node.output);
      case Switch():
        visit(node.input);
        node.outputs.values.forEach(visit);
      case Map():
        node.values.forEach(visit);
      case List():
        node.forEach(visit);
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return floor;
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
