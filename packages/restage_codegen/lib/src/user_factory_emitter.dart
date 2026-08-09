import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_preview_reservation.dart';
import 'package:restage_codegen/src/customer_record_plan.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Emits a `user_factories.g.dart` source string containing one
/// `LocalWidgetBuilder` per emittable `@RestageWidget` class, plus a
/// top-level `registerRestageCustomerWidgets()` helper the customer calls
/// once at startup. Output is `dart format`-clean.
///
/// Returns `null` when no entries are emittable so the builder can skip
/// writing the output file rather than emit an empty registration helper.
///
/// Reuses [emitFactoryFunction] for the per-widget body — built-in
/// libraries and customer libraries share the same emission rules, so the
/// generated factories handle scalar properties, structured-type
/// decomposition, the canonical child / children slots, and event slots
/// uniformly.
///
/// [onSkip] fires once per entry the factory emitter can't produce
/// mechanically (e.g. `childrenSlot` declared without a canonical child
/// property, unsupported `synthetic` strategy, malformed decomposition
/// recipe — see `emitFactoryFunction`'s eligibility rules). The catalog
/// emitter accepts the same entries unconditionally, so a customer who
/// annotates a non-emittable widget would otherwise see the widget in
/// `user_catalog.g.dart` but not in `user_factories.g.dart`, with no
/// signal at build time — and an unhelpful "widget not found" at render
/// time when a blob references it. Builders pass a `log.warning`-emitting
/// callback so the gap surfaces in the build output.
String? emitUserFactoriesDart(
  List<WidgetEntry> widgets, {
  void Function(WidgetEntry skipped)? onSkip,
  List<StructuredEntry> structuredTypes = const [],
  Map<String, String> slotTargets = const {},
  Set<String> nullableStructuredSlots = const {},
  Map<String, ReconstructionPlan> reconstructionPlans = const {},
  Map<String, MapPlan> mapPlans = const {},
  Map<String, RecordPlan> recordPlans = const {},
  Map<String, int> stampedCapabilityVersions = const {},
}) {
  validateCustomerPreviewReservations(widgets);
  final plannedUris = _referencedLibraryUris(
    widgets,
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    mapPlans: mapPlans,
    recordPlans: recordPlans,
  )..add('package:flutter/widgets.dart');
  final imports = DartImportPlanner(
    libraryUris: plannedUris,
    prefixStem: 's',
    unprefixedLibraryUris: const {'package:flutter/widgets.dart'},
  );
  final aliasByUri = imports.prefixesBySourceUri;

  // The build-time context for inline customer reconstruction: admitted
  // structured types, slot-keyed map and record plans, nominal slot targets,
  // and import aliases. No allocated wire IDs are needed.
  final customer =
      structuredTypes.isEmpty && mapPlans.isEmpty && recordPlans.isEmpty
          ? null
          : (
              structuredBySourceType: {
                for (final structured in structuredTypes)
                  structured.sourceType: structured,
              },
              plansBySourceType: reconstructionPlans,
              mapPlans: mapPlans,
              recordPlans: recordPlans,
              slotTargets: slotTargets,
              nullableStructuredSlots: nullableStructuredSlots,
              aliases: aliasByUri,
            );

  final emittable = <(WidgetEntry, String)>[];
  for (final entry in widgets) {
    final body =
        emitFactoryFunction(entry, customer: customer, aliases: aliasByUri);
    if (body == null) {
      onSkip?.call(entry);
      continue;
    }
    emittable.add((entry, body));
  }
  if (emittable.isEmpty) return null;

  // One import per referenced customer library: the source file of each
  // emittable `@RestageWidget`, the referenced structured types the inline
  // reconstructor NAMES, and every referenced enum's library (an
  // `RestageDecoders.enumByName<Tone>(...)` needs `Tone`'s library). Derived
  // from the `<uri>#<name>` FQNs + enum shapes; the nameability predicate
  // already excluded any unnameable (private) referenced type, so every URI
  // here is importable. Emitted WITH the uniform-prefix alias, sorted for
  // byte-deterministic emit.
  final referencedUris = _referencedLibraryUris(
    [for (final (entry, _) in emittable) entry],
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    mapPlans: mapPlans,
    recordPlans: recordPlans,
  )..add('package:flutter/widgets.dart');

  // Group emittable entries by library so each
  // `Restage.registerWidgetLibrary` call passes exactly one library's
  // widgets. Sorted by namespace for stable emit.
  final byLibrary = <WidgetLibrary, List<(WidgetEntry, String)>>{};
  for (final pair in emittable) {
    byLibrary.putIfAbsent(pair.$1.library, () => []).add(pair);
  }
  final orderedLibraries = byLibrary.keys.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace));

  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln('//')
    ..writeln(
      '// Per-widget LocalWidgetBuilder closures for every admitted',
    )
    ..writeln('// @RestageWidget class in this package, plus a one-call helper')
    ..writeln('// that registers them with Restage at startup.')
    ..writeln('//')
    ..writeln('// Inputs come from public unnamed generative constructors;')
    ..writeln('// edit the ordinary Flutter constructor, fields, Dartdoc, or')
    ..writeln('// optional Restage overlays, then re-run build_runner.')
    ..writeln()
    // `widgets.dart` supplies `Widget` / `BuildContext` for the generated
    // factory closures. Every identity used by customer constructors and
    // reconstruction is imported separately by the shared planner below.
    // The SDK re-exports `DataSource`, `ArgumentDecoders`, and
    // `LocalWidgetBuilder` from rfw, plus `RestageDecoders` for
    // property types not covered by rfw's helpers (e.g. `Duration`),
    // so no direct rfw import is needed (and the customer package
    // isn't required to depend on rfw).
    ..writeln();
  imports.importDirectivesFor(referencedUris).forEach(buf.writeln);
  buf
    ..writeln("import 'package:restage/restage.dart';")
    ..writeln()
    ..writeln('/// Registers every emittable @RestageWidget-annotated class')
    ..writeln("/// in this package with Restage. Call once at the app's")
    ..writeln('/// startup, before any `RestagePaywall` mounts. Idempotent')
    ..writeln('/// after `Restage.debugReset`, so test setUps may call it')
    ..writeln('/// again between cases.')
    ..writeln('void registerRestageCustomerWidgets() {');
  for (final library in orderedLibraries) {
    final entries = byLibrary[library]!;
    // A structured-admitting library carries its declared capabilityVersion so
    // the runtime floor (`LibraryRuntimeRegistry.satisfies`) fail-closes an
    // under-capable client; other libraries register unversioned (byte-stable).
    final capabilityVersion = stampedCapabilityVersions[library.namespace];
    buf
      ..writeln('  Restage.registerWidgetLibrary(')
      ..writeln('    ${_libraryFieldRef(library)},');
    if (capabilityVersion != null) {
      buf.writeln('    capabilityVersion: $capabilityVersion,');
    }
    buf.writeln('    widgets: const <RestageWidgetFactory>[');
    for (final (entry, _) in entries) {
      buf.writeln(
        "      RestageWidgetFactory(name: '${entry.name}', "
        'builder: ${functionNameFor(entry)}),',
      );
    }
    buf
      ..writeln('    ],')
      ..writeln('  );');
  }
  buf.writeln('}');
  for (final (_, body) in emittable) {
    buf
      ..writeln()
      ..write(body);
  }

  return formatGeneratedDart(buf.toString());
}

/// The import URI (the part before `#`) of a `<library-uri>#<name>` reference.
String _libraryUriOf(String qualifiedRef) =>
    qualifiedRef.substring(0, qualifiedRef.indexOf('#'));

/// The defining library URI of [shape]'s enum type, or `null` when [shape] is
/// not an [EnumShape] (so it names no source-qualified enum to import).
String? _enumLibOf(CatalogValueShape? shape) =>
    shape is EnumShape ? shape.enumRef.libraryUri : null;

Set<String> _referencedLibraryUris(
  Iterable<WidgetEntry> widgets, {
  required List<StructuredEntry> structuredTypes,
  required Map<String, String> slotTargets,
  required Map<String, MapPlan> mapPlans,
  required Map<String, RecordPlan> recordPlans,
}) =>
    {
      for (final entry in widgets) _libraryUriOf(entry.flutterType),
      for (final structured in structuredTypes)
        _libraryUriOf(structured.sourceType),
      for (final entry in widgets)
        for (final property in entry.properties)
          if (_enumLibOf(property.valueShape) case final uri?) uri,
      for (final entry in widgets)
        for (final property in entry.properties)
          if (property.constructorDefault case final value?
              when _constructorDefaultIsEmitted(entry, property))
            ...dartConstValueLibraryUris(value),
      for (final structured in structuredTypes)
        for (final field in structured.fields)
          if (_enumLibOf(field.valueShape) case final uri?) uri,
      for (final plan in mapPlans.values)
        for (final key in plan.keys)
          if (key.enumRef?.libraryUri case final uri?) uri,
      for (final plan in mapPlans.values)
        if (_enumLibOf(plan.valueShape) case final uri?) uri,
      for (final plan in recordPlans.values)
        for (final label in plan.labels)
          if (label.enumLibraryUri case final uri?) uri,
    };

bool _constructorDefaultIsEmitted(
  WidgetEntry entry,
  PropertyEntry property,
) {
  if (property.required || property.constructorDefault == null) return false;
  return property.positional && _hasLaterPositionalProperty(entry, property);
}

bool _hasLaterPositionalProperty(
  WidgetEntry entry,
  PropertyEntry property,
) {
  var passedProperty = false;
  for (final candidate in entry.properties) {
    if (passedProperty && candidate.positional) return true;
    if (identical(candidate, property)) passedProperty = true;
  }
  return false;
}

/// Renders a Dart expression resolving to [lib] when read in code that
/// imports the Restage SDK (which re-exports `WidgetLibrary` from
/// `restage_shared`).
///
/// Mirrors the same helper inside `user_catalog_emitter.dart` — duplicated
/// rather than lifted so each emitter stays self-contained. A third caller
/// would justify promoting this to `emit_utils.dart`.
String _libraryFieldRef(WidgetLibrary lib) {
  switch (lib.namespace) {
    case 'restage.core':
      return 'WidgetLibrary.core';
    case 'restage.material':
      return 'WidgetLibrary.material';
    case 'restage.cupertino':
      return 'WidgetLibrary.cupertino';
    default:
      final escaped = lib.namespace
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'")
          .replaceAll(r'$', r'\$');
      return "WidgetLibrary.custom('$escaped')";
  }
}
