import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show
        A2uiDartWidgetPlan,
        A2uiRichShapes,
        a2uiWidgetDataSchemaMapForPlan,
        classifyA2uiCatalogDart;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Projects a format-general [catalog] into a versioned A2UI catalog — the
/// Restage **capability/manifest view** of the A2UI catalog.
///
/// **The catalog.json/manifest vs the Dart CatalogItem split.** This produces
/// the capability/manifest artifact: the component name list, the two-axis
/// capability stamp, and a **self-describing per-component data schema**. Its
/// jobs are the app-side pre-render check (walk component names + read the
/// stamp), versioning/inspection, and — for a producer that generates payloads
/// against the standalone document alone (not the generated `.g.dart`) —
/// advertising each component's fields. The still-**authoritative functional
/// contract** — the per-property `dataSchema` AND the `widgetBuilder` — lives
/// in the generated Dart `CatalogItem` set (`emitA2uiCatalogDart`), from which
/// genui projects the LLM contract at runtime. The document does NOT carry a
/// `widgetBuilder` (build-time only), but its per-component data schema is
/// the SAME schema the `CatalogItem` carries: both are projected from the SAME
/// classified plan fields ([a2uiWidgetDataSchemaMapForPlan] mirrors
/// `emitA2uiCatalogDart`'s schema expression arm-for-arm, emitting the plain
/// map the `.g.dart`'s `S.*` schema serializes to — without depending on
/// json_schema_builder), so a component's document schema equals the runtime
/// `CatalogItem.dataSchema.value`. The `restage_a2ui` artifact-tie test pins
/// that equivalence against the real genui SDK, closing the drift vector that
/// would otherwise come from carrying the schema in two places.
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
/// Each component's schema is the component's data schema with the `component`
/// discriminator injected — replicating genui's `CatalogItem.dataSchema`
/// getter, so the document carries genui's canonical component-schema format
/// (see [_componentSchema]).
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
  final plans = classifyA2uiCatalogDart(
    catalog,
    nativeIndex: nativeIndex,
    eventSeam: eventSeam,
    richShapes: richShapes,
    pairingSeam: pairingSeam,
  ).widgets;
  final emittable = [for (final plan in plans) plan.entry];

  // De-duplicate by name; ANY duplicate name fails loud (the catalog map is
  // flat). Cross-library is called out as the special case in the message.
  // Keyed by the PLAN (not just the entry) so the component schema can be
  // projected from the plan's classified fields.
  final byName = <String, A2uiDartWidgetPlan>{};
  for (final plan in plans) {
    final existing = byName[plan.entry.name];
    if (existing != null) {
      throw ArgumentError.value(
        plan.entry.name,
        'name',
        _duplicateNameMessage(plan.entry, existing.entry),
      );
    }
    byName[plan.entry.name] = plan;
  }

  final components = [
    for (final plan in byName.values)
      A2uiComponent(name: plan.entry.name, dataSchema: _componentSchema(plan)),
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
    for (final plan in byName.values) plan.entry.name: plan.entry.sinceVersion,
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

/// The component schema for [plan]: the component's full data schema (projected
/// from the plan's classified fields via [a2uiWidgetDataSchemaMapForPlan]) with
/// the `component` discriminator injected. A producer can therefore read a
/// component's fields from the standalone document alone — not only from the
/// generated `.g.dart`.
///
/// This REPLICATES genui's `CatalogItem.dataSchema` getter exactly — its
/// canonical component-schema format (the same shape genui's own
/// `Catalog.toCapabilitiesJson()` emits per component): the data schema is
/// spread, then `properties` is overlaid with the existing data properties plus
/// a `component` const-enum discriminator, and `required` is overlaid with
/// `component` ahead of the data's required set. So a component's document
/// schema equals the runtime `CatalogItem.dataSchema.value` by construction
/// (the `restage_a2ui` document-tie pins it against the real genui SDK).
///
/// The spread handles every data-schema shape uniformly: an object-rooted data
/// schema already carries `properties`/`required` (overlaid); a
/// recursion-bearing `$ref`/`$defs` data schema carries neither, so `component`
/// is added as a `$ref` sibling (evaluated under draft 2020-12, exactly as
/// genui does). A component with no data fields yields
/// `{type: object, properties: {component}, required: [component]}`.
///
/// **Recursion ref scope.** For a recursion-bearing component, the schema keeps
/// genui's own `#/$defs/…` pointers, which are component-root-relative — each
/// `components.<Name>` schema is a STANDALONE schema resource (resolve `$ref`
/// within the component schema, not the whole `.a2ui.json` document). This
/// matches genui's `toCapabilitiesJson` schema-for-schema (genui nests the same
/// component `dataSchema.value` under `components`); we deliberately match it
/// rather than rewriting refs.
Map<String, Object?> _componentSchema(A2uiDartWidgetPlan plan) {
  final data = a2uiWidgetDataSchemaMapForPlan(plan);
  final dataProps = (data['properties'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  final dataRequired = (data['required'] as List?) ?? const <Object?>[];
  return <String, Object?>{
    ...data,
    'properties': <String, Object?>{
      ...dataProps,
      'component': <String, Object?>{
        'type': 'string',
        'enum': [plan.entry.name],
      },
    },
    'required': <Object?>['component', ...dataRequired],
  };
}
