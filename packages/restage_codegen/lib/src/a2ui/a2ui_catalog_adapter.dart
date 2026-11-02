import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show
        A2uiDartWidgetPlan,
        A2uiRichShapes,
        a2uiCatalogComponentSchemaMapForPlan,
        classifyA2uiCatalogDart,
        composeSystemPromptFragments;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_native_screen.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Projects the same classified component set as the Dart emitter.
///
/// Component property schemas use the centralized UAX31-safe wire mapping. The
/// pure-Dart A2UI core serializes both the standalone document and runtime
/// catalog, including envelope schemas, unions and protocol metadata. Recursive
/// definitions retain per-component scope in this projection and move to
/// catalog-level namespaced definitions during serialization.
///
/// Pass the same rich-shape, event and pairing seams to both emitters.
/// Duplicate component names and unstamped custom libraries fail before
/// registration.
RestageStampedA2uiCatalog emitA2uiCatalog(
  Catalog catalog, {
  NativeCatalogIndex? nativeIndex,
  Iterable<A2uiNativeScreen> nativeScreens = const [],
  A2uiEventSeam? eventSeam,
  A2uiRichShapes? richShapes,
  A2uiPairingSeam? pairingSeam,
  Map<String, String> usageByWidget = const {},
}) {
  // Emit over the A2UI-emittable widget set ONLY (the same set the Dart
  // ComponentImplementation emitter produces), so the manifest component
  // list and the Dart
  // component implementation set agree by construction — a scoped-out
  // widget is in neither.
  // The interactivity seam + rich shapes + the pairing seam are threaded
  // through so an interactive widget the Dart emitter keeps (a lowered
  // callback) is kept here too.
  final catalogPlan = classifyA2uiCatalogDart(
    catalog,
    nativeIndex: nativeIndex,
    nativeScreens: nativeScreens,
    eventSeam: eventSeam,
    richShapes: richShapes,
    pairingSeam: pairingSeam,
  );
  final plans = catalogPlan.widgets;
  final emittable = [
    for (final plan in plans)
      if (plan.nativeScreen == null) plan.entry,
  ];

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
  }.toList()..sort((a, b) => a.namespace.compareTo(b.namespace));
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
      A2uiLibraryCapability(
        namespace: library.namespace,
        version: version,
        compatibleSince: catalog.libraries[library]!.compatibleSince,
      ),
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
    systemPromptFragments: composeSystemPromptFragments(
      catalogPlan,
      usageByWidget,
    ),
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

/// Component property projection, including locally owned rich definitions. The
/// catalog serializer moves these definitions to catalog scope and leaves
/// catalog-relative references in the property schema. Upstream owns the
/// component envelope; this projection does not inject its discriminator.
Map<String, Object?> _componentSchema(A2uiDartWidgetPlan plan) {
  return a2uiCatalogComponentSchemaMapForPlan(plan);
}
