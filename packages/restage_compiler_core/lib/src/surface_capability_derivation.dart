import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kLocalValueSetEventName, kMeasurementPublicationItemArgumentKeyV1;
import 'package:restage_shared/restage_shared.dart'
    show
        LibraryRequirement,
        WidgetVocabulary,
        kGroupedWidgetListClientFloor,
        kJoinedStringClientFloor,
        kSurfaceFeatureClientFloor;
import 'package:restage_shared/rfw_formats.dart' hide WidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show
        Catalog,
        PropertyEntry,
        PropertyType,
        WidgetEntry,
        WidgetLibrary,
        kBaselineCatalogVersion;

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
  var joinsStrings = false;
  var propertyFloor = kBaselineCatalogVersion;
  for (final widget in library.widgets) {
    _collectReferences(
      widget.root,
      catalog,
      localNames,
      referenced,
      ambiguous,
      onJoinedString: () => joinsStrings = true,
      onPropertyVersion: (version) {
        if (version > propertyFloor) propertyFloor = version;
      },
    );
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
  if (joinsStrings && builtInFloor < kJoinedStringClientFloor) {
    builtInFloor = kJoinedStringClientFloor;
  }
  if (builtInFloor < propertyFloor) builtInFloor = propertyFloor;
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
/// [out]; a name found in more than one library goes to [ambiguous]. A string
/// slot given a list of parts calls [onJoinedString], and each property set
/// reports its [PropertyEntry.sinceVersion] to [onPropertyVersion].
void _collectReferences(
  Object? node,
  Catalog catalog,
  Set<String> localNames,
  List<WidgetEntry> out,
  Set<String> ambiguous, {
  required void Function() onJoinedString,
  required void Function(int version) onPropertyVersion,
}) {
  void visit(Object? child) => _collectReferences(
        child,
        catalog,
        localNames,
        out,
        ambiguous,
        onJoinedString: onJoinedString,
        onPropertyVersion: onPropertyVersion,
      );
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
          final entry = candidates.first;
          out.add(entry);
          final builtIn =
              WidgetLibrary.builtInByNamespace(entry.library.namespace) != null;
          for (final property in entry.properties) {
            if (!arguments.containsKey(property.name)) continue;
            if (builtIn) onPropertyVersion(property.sinceVersion);
            if (property.type == PropertyType.string &&
                _carriesList(arguments[property.name])) {
              onJoinedString();
            }
          }
        }
      }
      arguments.values.forEach(visit);
    case List<Object?>():
      node.forEach(visit);
    case Switch(:final outputs):
      outputs.values.forEach(visit);
    case Loop(:final output):
      visit(output);
    case WidgetBuilderDeclaration(:final widget):
      visit(widget);
    case Map<Object?, Object?>():
      node.values.forEach(visit);
  }
}

bool _carriesList(Object? value) => switch (value) {
      List<Object?>() => true,
      Switch(:final outputs) => outputs.values.any(_carriesList),
      _ => false,
    };

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
