import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_preview_reservation.dart';
import 'package:restage_codegen/src/customer_record_plan.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
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
  // Uniform-prefix import aliases: every referenced CUSTOMER library (a widget
  // class, a nested structured type, or a referenced enum) gets a unique alias
  // (`s0`, `s1`, ...), assigned over the sorted URIs for byte-deterministic
  // emit. The reconstruction then names every customer type QUALIFIED
  // (`s0.Badge`, `s0.Tone`), so two same-name types from different libraries
  // can never collide by construction — the aliased-import scheme keeps both,
  // both render.
  // Built-in libraries (`dart:` / `package:flutter/`) are NOT aliased; their
  // types come bare through the `widgets.dart` re-exports.
  final aliasByUri = <String, String>{};
  {
    final customerUris = <String>{
      for (final entry in widgets) _libraryUriOf(entry.flutterType),
      for (final structured in structuredTypes)
        _libraryUriOf(structured.sourceType),
      for (final entry in widgets)
        for (final prop in entry.properties)
          if (_enumLibOf(prop.valueShape) case final uri?) uri,
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
    }.where(_isCustomerLibUri).toList()
      ..sort();
    for (var i = 0; i < customerUris.length; i++) {
      aliasByUri[customerUris[i]] = 's$i';
    }
  }

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
  final referencedUris = <String>{
    for (final (entry, _) in emittable) _libraryUriOf(entry.flutterType),
    for (final structured in structuredTypes)
      _libraryUriOf(structured.sourceType),
    for (final (entry, _) in emittable)
      for (final prop in entry.properties)
        if (_enumLibOf(prop.valueShape) case final uri?) uri,
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
  }.where(_isCustomerLibUri).toList()
    ..sort();

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
      '// Per-widget LocalWidgetBuilder closures for every @RestageWidget-',
    )
    ..writeln('// annotated class in this package, plus a one-call helper')
    ..writeln('// that registers them with Restage at startup.')
    ..writeln('//')
    ..writeln('// To change this file: edit the @RestageWidget /')
    ..writeln('// @RestageProperty annotations on the underlying classes,')
    ..writeln('// then re-run build_runner.')
    ..writeln()
    // `widgets.dart` supplies `Widget` / `BuildContext` for the generated
    // factory closures. Customer widgets pull their own Material /
    // Cupertino imports through `widgets.dart`'s re-exports if needed.
    // The SDK re-exports `DataSource`, `ArgumentDecoders`, and
    // `LocalWidgetBuilder` from rfw, plus `RestageDecoders` for
    // property types not covered by rfw's helpers (e.g. `Duration`),
    // so no direct rfw import is needed (and the customer package
    // isn't required to depend on rfw).
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import 'package:restage/restage.dart';");
  for (final import in referencedUris) {
    buf.writeln("import '$import' as ${aliasByUri[import]};");
  }
  buf
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

/// Whether [uri] is a CUSTOMER library (aliased) rather than a built-in one
/// (`dart:` / `package:flutter/`, which come bare through the `widgets.dart`
/// re-exports and must not be aliased).
bool _isCustomerLibUri(String uri) =>
    !uri.startsWith('dart:') && !uri.startsWith('package:flutter/');

/// The defining library URI of [shape]'s enum type, or `null` when [shape] is
/// not an [EnumShape] (so it names no source-qualified enum to import).
String? _enumLibOf(CatalogValueShape? shape) =>
    shape is EnumShape ? shape.enumRef.libraryUri : null;

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
