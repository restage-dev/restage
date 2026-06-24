import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/src/user_catalog_emitter.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kUserCatalogAllocationTimestamp = '2026-05-26T00:00:00.000Z';
const String _kUserCatalogAllocationActor =
    'restage-codegen-user-catalog-allocator';

/// The result of allocating stable wire IDs for a generated user catalog.
final class UserCatalogAllocation {
  /// Creates an allocation result.
  const UserCatalogAllocation({
    required this.catalog,
    required this.newEvents,
  });

  /// The catalog with real widget/property wire IDs.
  final Catalog catalog;

  /// Events minted during this allocation pass.
  final List<WireIdEvent> newEvents;
}

/// Allocates stable package-root wire IDs for generated customer widgets.
///
/// The package-root `wire_ids.events.jsonl` is treated as one append-only
/// source of truth for the generated `user_catalog.g.dart` surface. Entries
/// replay by exact source/name match; a rename or source move therefore mints
/// a new ID unless the log is explicitly edited with a rename event.
UserCatalogAllocation allocateUserCatalogFromWidgets({
  required String package,
  required List<WidgetEntry> widgets,
  Iterable<WireIdEvent> existingEvents = const [],
}) {
  final baseCatalog = userCatalogFromWidgets(widgets);
  final allocator = WireIdAllocator(
    library: package,
    at: _kUserCatalogAllocationTimestamp,
    by: _kUserCatalogAllocationActor,
    existingEvents: existingEvents,
  );
  final seeded = allocator.currentState;
  final seededWidgets = _indexBy(
    seeded.widgets.values,
    (entry) => (entry.name!, entry.source!),
    (key) => 'widget name=${key.$1} source=${key.$2}',
  );
  final seededProperties = _indexBy(
    seeded.properties.values,
    (entry) => (entry.owner!, entry.name!, entry.source!),
    (key) => 'property owner=${key.$1.value} name=${key.$2} source=${key.$3}',
  );

  final newEvents = <WireIdEvent>[];
  final allocatedWidgets = <WidgetEntry>[];
  for (final widget in baseCatalog.widgets) {
    final widgetId = _resolveOrAllocateWidget(
      allocator: allocator,
      seededWidgets: seededWidgets,
      widget: widget,
      newEvents: newEvents,
    );
    allocatedWidgets.add(
      _copyWidget(
        widget,
        wireId: widgetId,
        properties: [
          for (final property in widget.properties)
            _copyProperty(
              property,
              wireId: _resolveOrAllocateProperty(
                allocator: allocator,
                seededProperties: seededProperties,
                widget: widget,
                property: property,
                owner: widgetId,
                newEvents: newEvents,
              ),
            ),
        ],
      ),
    );
  }

  return UserCatalogAllocation(
    catalog: Catalog(
      schemaVersion: baseCatalog.schemaVersion,
      generatedAt: baseCatalog.generatedAt,
      libraries: baseCatalog.libraries,
      widgets: allocatedWidgets,
      structuredTypes: baseCatalog.structuredTypes,
      unions: baseCatalog.unions,
      designTokens: baseCatalog.designTokens,
      flutterVersion: baseCatalog.flutterVersion,
      compatRules: baseCatalog.compatRules,
    ),
    newEvents: List.unmodifiable(newEvents),
  );
}

/// Reads a package-root `wire_ids.events.jsonl` event log for [package].
Future<RootEventLogContents?> readRootEventLog(
  BuildStep buildStep,
  String package,
) async {
  final eventLog = AssetId(package, 'wire_ids.events.jsonl');
  if (await buildStep.canRead(eventLog)) {
    return RootEventLogContents(
      contents: await buildStep.readAsString(eventLog),
      sourceDescription: '${eventLog.package}|${eventLog.path}',
    );
  }

  final root = await _packageRoot(package);
  if (root == null) return null;
  final file = File.fromUri(root.resolve('wire_ids.events.jsonl'));
  if (!file.existsSync()) return null;
  return RootEventLogContents(
    contents: file.readAsStringSync(),
    sourceDescription: file.path,
  );
}

/// Appends generated customer catalog allocation [events] to the package root.
Future<void> appendEventsToRootEventLog({
  required String package,
  required Iterable<WireIdEvent> events,
  bool createIfMissing = false,
}) async {
  final root = await _packageRoot(package);
  if (root == null) return;
  final file = File.fromUri(root.resolve('wire_ids.events.jsonl'));
  if (file.existsSync()) {
    appendWireIdEventsSync(file, events);
    return;
  }
  if (createIfMissing) {
    writeWireIdEventLogSync(file, events);
  }
}

/// Holds the raw JSONL text and a human-readable parse source label.
final class RootEventLogContents {
  /// Creates root event-log contents.
  const RootEventLogContents({
    required this.contents,
    required this.sourceDescription,
  });

  /// Raw JSONL text.
  final String contents;

  /// Parse source label used in error messages.
  final String sourceDescription;
}

WireId _resolveOrAllocateWidget({
  required WireIdAllocator allocator,
  required Map<(String, String), WireIdEntryState> seededWidgets,
  required WidgetEntry widget,
  required List<WireIdEvent> newEvents,
}) {
  if (!widget.wireId.isUnallocated) {
    _requireSeeded(allocator, widget.wireId);
    return widget.wireId;
  }
  final seeded = seededWidgets[(widget.name, widget.flutterType)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.widget(
      name: widget.name,
      source: widget.flutterType,
    ),
  );
  newEvents.add(event);
  return event.id;
}

WireId _resolveOrAllocateProperty({
  required WireIdAllocator allocator,
  required Map<(WireId, String, String), WireIdEntryState> seededProperties,
  required WidgetEntry widget,
  required PropertyEntry property,
  required WireId owner,
  required List<WireIdEvent> newEvents,
}) {
  if (!property.wireId.isUnallocated) {
    _requireSeeded(allocator, property.wireId);
    return property.wireId;
  }
  final source = '${widget.flutterType}.${property.name}';
  final seeded = seededProperties[(owner, property.name, source)];
  if (seeded != null) return seeded.id;
  final event = allocator.allocate(
    WireIdAllocationCandidate.property(
      owner: owner,
      name: property.name,
      source: source,
    ),
  );
  newEvents.add(event);
  return event.id;
}

void _requireSeeded(WireIdAllocator allocator, WireId id) {
  if (!allocator.currentState.contains(id)) {
    throw WireIdReplayException(
      'catalog entry ${id.value} is already allocated but is missing from '
      'the seeded event log',
    );
  }
}

Map<K, WireIdEntryState> _indexBy<K>(
  Iterable<WireIdEntryState> entries,
  K Function(WireIdEntryState entry) keyOf,
  String Function(K key) describeDuplicate,
) {
  final result = <K, WireIdEntryState>{};
  for (final entry in entries) {
    final key = keyOf(entry);
    if (result.containsKey(key)) {
      throw WireIdReplayException(
        'event log contains multiple matches for ${describeDuplicate(key)}',
      );
    }
    result[key] = entry;
  }
  return result;
}

WidgetEntry _copyWidget(
  WidgetEntry widget, {
  required WireId wireId,
  required List<PropertyEntry> properties,
}) {
  return WidgetEntry(
    wireId: wireId,
    name: widget.name,
    library: widget.library,
    category: widget.category,
    description: widget.description,
    flutterType: widget.flutterType,
    childrenSlot: widget.childrenSlot,
    fires: widget.fires,
    properties: properties,
    decomposes: widget.decomposes,
    sinceVersion: widget.sinceVersion,
    deprecatedSince: widget.deprecatedSince,
    stability: widget.stability,
    deprecated: widget.deprecated,
  );
}

PropertyEntry _copyProperty(PropertyEntry property, {required WireId wireId}) {
  return PropertyEntry(
    wireId: wireId,
    name: property.name,
    type: property.type,
    description: property.description,
    required: property.required,
    defaultBrandToken: property.defaultBrandToken,
    synthetic: property.synthetic,
    positional: property.positional,
    enumType: property.enumType,
    widgetType: property.widgetType,
    callbackSignature: property.callbackSignature,
    firesAs: property.firesAs,
    defaultSource: property.defaultSource,
    mutuallyExclusiveWith: property.mutuallyExclusiveWith,
    requiresAncestor: property.requiresAncestor,
    category: property.category,
    priority: property.priority,
    validationRule: property.validationRule,
    deprecated: property.deprecated,
    structuredRef: property.structuredRef,
    valueShape: property.valueShape,
  );
}

Future<Uri?> _packageRoot(String package) async {
  final packageConfigUri = await Isolate.packageConfig;
  if (packageConfigUri == null) return null;
  final config = await loadPackageConfigUri(packageConfigUri);
  final packageConfig = config[package];
  if (packageConfig == null || !packageConfig.root.isScheme('file')) {
    return null;
  }
  return packageConfig.root;
}
