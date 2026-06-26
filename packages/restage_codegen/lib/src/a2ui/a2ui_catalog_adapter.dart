import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show A2uiRichShapes, classifyA2uiCatalogDart;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Projects a format-general [catalog] into a versioned A2UI catalog — the
/// Restage **capability/manifest view** of the A2UI catalog.
///
/// **The catalog.json/manifest vs the Dart CatalogItem split.** This produces
/// the capability/manifest artifact: the component name list + the two-axis
/// capability stamp, with **discriminator-only** component schemas. Its job is
/// the app-side pre-render check (walk component names + read the stamp) and
/// versioning/inspection — none of which needs the per-property schema. The
/// **authoritative functional contract** — the full per-property `dataSchema`
/// and the `widgetBuilder` — lives in the generated Dart `CatalogItem` set
/// (`emitA2uiCatalogDart`), from which genui projects the LLM contract at
/// runtime. The manifest deliberately does NOT duplicate that schema (it would
/// be a drift vector with no consumer).
///
/// **One emittable set, both artifacts agree by construction.** This manifest
/// and the Dart `CatalogItem` set are emitted over the SAME A2UI-emittable
/// widget set (via [classifyA2uiCatalogDart]): a widget scoped out of the Dart
/// emitter (e.g. a required-structured field) is also absent here — never a
/// component in one artifact but not the other. For that parity to hold over
/// INTERACTIVE widgets, this path must be given the SAME `eventSeam` +
/// `richShapes` the Dart emitter receives (a required interactive callback
/// lowered on the Dart path must not be dropped here via the catalog-fed
/// required-event path).
///
/// This is the single module that maps the catalog to the A2UI catalog shape —
/// the **shape-isolation surface**. It emits the catalog **as plain maps**: it
/// imports nothing from the genui SDK, so the genui dependency never enters the
/// code generator.
///
/// Each widget becomes one A2UI component keyed by its catalog name, and the
/// returned catalog carries a Restage capability stamp with **both** capability
/// axes (mirroring the format-general `CapabilityManifest`):
///  * `catalogContentVersion` — the built-in content version, derived from the
///    catalog's built-in widgets via the single canonical [contentVersionOf]
///    formula. This equals the runtime SDK's
///    `RestageBuiltInCatalogCapabilities.currentVersion` by construction (both
///    derive from the same committed catalog), but the build-time toolchain
///    **must not** import the runtime SDK to read it (a layering +
///    two-tier-licensing boundary), so it is computed from the catalog here.
///  * `availableLibraries` — the present custom libraries with their declared
///    capability versions. Carrying this second axis is what keeps the app-side
///    check from failing open for custom libraries.
///
/// Each manifest component's schema is the **discriminator-only** object schema
/// (the `component` const) by design — the full per-property schema is the Dart
/// `CatalogItem`'s job, not the manifest's (see the split above).
///
/// Throws an [ArgumentError] when:
///  * two widgets share a component name (the A2UI catalog is a flat name-keyed
///    map; cross-library and same-library duplicates both fail loud), or
///  * a custom library contributes components but declares no
///    `capabilityVersion` (the custom-library axis cannot be stamped — mirrors
///    the build-time fail-when-referenced rule).
RestageStampedA2uiCatalog emitA2uiCatalog(
  Catalog catalog, {
  NativeCatalogIndex? nativeIndex,
  A2uiEventSeam? eventSeam,
  A2uiRichShapes? richShapes,
  A2uiPairingSeam? pairingSeam,
}) {
  // Emit over the A2UI-emittable widget set ONLY (the same set the Dart
  // CatalogItem emitter produces), so the manifest component list and the Dart
  // CatalogItem set agree by construction — a scoped-out widget is in neither.
  // The interactivity seam + rich shapes + the pairing seam are threaded
  // through so an interactive widget the Dart emitter keeps (a lowered
  // callback) is kept here too.
  final emittable = classifyA2uiCatalogDart(
    catalog,
    nativeIndex: nativeIndex,
    eventSeam: eventSeam,
    richShapes: richShapes,
    pairingSeam: pairingSeam,
  ).widgets.map((plan) => plan.entry).toList(growable: false);

  // De-duplicate by name; ANY duplicate name fails loud (the catalog map is
  // flat). Cross-library is called out as the special case in the message.
  final byName = <String, WidgetEntry>{};
  for (final widget in emittable) {
    final existing = byName[widget.name];
    if (existing != null) {
      throw ArgumentError.value(
        widget.name,
        'name',
        _duplicateNameMessage(widget, existing),
      );
    }
    byName[widget.name] = widget;
  }

  final components = [
    for (final widget in byName.values)
      A2uiComponent(
        name: widget.name,
        dataSchema: _discriminatorOnlySchema(widget.name),
      ),
  ];

  // Built-in axis: the single canonical content-version formula over the
  // emittable built-in widgets only (a custom widget's sinceVersion belongs to
  // the custom-library axis, not the built-in floor). Over the emittable set so
  // the floor reflects exactly what the A2UI catalog actually offers.
  final catalogContentVersion = contentVersionOf(
    emittable.where((w) => _isBuiltIn(w.library)),
  );

  // Custom-library axis: each present custom library with its declared
  // capability version, sorted by namespace (the stamp re-sorts too).
  final customLibraries = <WidgetLibrary>{
    for (final widget in emittable)
      if (!_isBuiltIn(widget.library)) widget.library,
  }.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace));
  final availableLibraries = <A2uiLibraryCapability>[];
  for (final library in customLibraries) {
    final version = catalog.libraries[library]?.capabilityVersion;
    if (version == null) {
      throw ArgumentError.value(
        library.namespace,
        'capabilityVersion',
        'Custom library "${library.namespace}" contributes components to the '
            'A2UI catalog but declares no capability version. Add '
            '`capabilityVersion:` to its @RestageLibrary so the catalog can '
            'carry the custom-library capability axis (a monotonic integer, '
            'not the pub package version).',
      );
    }
    availableLibraries.add(
      A2uiLibraryCapability(namespace: library.namespace, version: version),
    );
  }

  final perItemSinceVersion = {
    for (final widget in byName.values) widget.name: widget.sinceVersion,
  };

  return RestageStampedA2uiCatalog(
    stamp: RestageCapabilityStamp(
      catalogContentVersion: catalogContentVersion,
      availableLibraries: availableLibraries,
      perItemSinceVersion: perItemSinceVersion,
    ),
    components: components,
  );
}

bool _isBuiltIn(WidgetLibrary library) =>
    WidgetLibrary.builtInByNamespace(library.namespace) != null;

/// The fail-loud message for a duplicate component [widget] colliding with an
/// already-seen [existing] entry of the same name. Cross-library collisions get
/// the fuller explanation (the A2UI catalog is flat / not namespaced).
String _duplicateNameMessage(WidgetEntry widget, WidgetEntry existing) {
  if (existing.library != widget.library) {
    return 'A2UI catalog component names must be unique; "${widget.name}" is '
        'defined in both "${existing.library.namespace}" and '
        '"${widget.library.namespace}". The A2UI catalog is a flat name-keyed '
        'map with no library namespacing, so a cross-library name collision '
        'cannot be emitted.';
  }
  return 'A2UI catalog component names must be unique; "${widget.name}" is '
      'declared more than once in library "${widget.library.namespace}".';
}

/// The minimal-valid component schema: an object whose only constraint is the
/// `component` discriminator (a const equal to the component name). The A2UI
/// renderer selects a component by this discriminator; the per-property body is
/// added in a later milestone.
Map<String, Object?> _discriminatorOnlySchema(String name) => {
      'type': 'object',
      'properties': {
        'component': {
          'type': 'string',
          'enum': [name],
        },
      },
      'required': ['component'],
      'additionalProperties': false,
    };
