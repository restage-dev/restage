import 'package:restage_codegen/src/custom_map_plan.dart';
import 'package:restage_codegen/src/custom_preview_reservation.dart';
import 'package:restage_codegen/src/custom_record_plan.dart';
import 'package:restage_codegen/src/custom_structured_reconstruction.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Emits a `user_factories.g.dart` source string containing one
/// `LocalWidgetBuilder` per emittable `@RestageWidget` class, plus a
/// `kRestageWidgetRegistration` and `registerRestageWidgets()` startup helpers.
/// Output is `dart format`-clean.
///
/// Returns `null` when no entries are emittable so the builder can skip
/// writing the output file rather than emit an empty registration helper.
///
/// Reuses [emitFactoryFunction] for the per-widget body — built-in widget
/// libraries and app widget libraries share scalar, structured, and event
/// lowering. Generated widget factories additionally lower every exact
/// `Widget` and `List<Widget>` constructor property without requiring author
/// metadata.
///
/// [onSkip] fires once per entry the factory emitter can't produce
/// mechanically (e.g. an unsupported `synthetic` strategy or malformed
/// decomposition recipe — see `emitFactoryFunction`'s eligibility rules).
/// Production callers use `emitAdmittedUserFactoriesDart`, which always turns
/// an admit-then-skip result into a hard coherence failure before any output is
/// written. Direct permissive use of this lower-level function is confined to
/// emitter tests and tooling that inspect historical or manually assembled
/// non-emittable catalog shapes.
///
/// [installWholeCatalog] makes the generated registration install the whole
/// built-in catalog and both icon tables by default.
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
  SurfaceVocabularyReferences appVocabulary = SurfaceVocabularyReferences.empty,
  bool installWholeCatalog = false,
}) {
  validateCustomPreviewReservations(widgets);
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

  // The build-time context for inline app-widget reconstruction: admitted
  // structured types, slot-keyed map and record plans, nominal slot targets,
  // and import aliases. No allocated wire IDs are needed.
  final custom =
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
    final body = emitFactoryFunction(
      entry,
      custom: custom,
      aliases: aliasByUri,
      customChildProperties: true,
    );
    if (body == null) {
      onSkip?.call(entry);
      continue;
    }
    emittable.add((entry, body));
  }
  if (emittable.isEmpty) return null;

  // One import per referenced app widget library: the source file of each
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
    // factory closures. Every identity used by app widget constructors and
    // reconstruction is imported separately by the shared planner below.
    // The SDK re-exports `DataSource`, `ArgumentDecoders`, and
    // `LocalWidgetBuilder` from rfw, plus `RestageDecoders` for
    // property types not covered by rfw's helpers (e.g. `Duration`),
    // so no direct rfw import is needed (and the app package
    // isn't required to depend on rfw).
    ..writeln();
  imports.importDirectivesFor(referencedUris).forEach(buf.writeln);
  buf
    ..writeln("import 'package:restage/restage.dart';")
    ..writeln();
  _writeAppVocabulary(buf, appVocabulary);
  _writeRegistrationConstant(buf);
  buf
    ..writeln('/// Registers every emittable @RestageWidget-annotated class')
    ..writeln("/// in this package with Restage. Call once at the app's")
    ..writeln('/// startup, before any `RestagePaywall` mounts. Idempotent')
    ..writeln('/// after `Restage.debugReset`, so test setUps may call it')
    ..writeln('/// again between cases.');
  _writeCatalogConfigurationDoc(buf, installWholeCatalog);
  _writeRegistrationStart(buf);
  _writeWholeCatalogInstall(buf, installWholeCatalog);
  buf.writeln(
    '  kRestageAppVocabulary.addToInstalled(explicitSelection: true);',
  );
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
  buf
    ..writeln('  }')
    ..writeln('}');
  _emitDeprecatedRegistrationAlias(buf);
  for (final (_, body) in emittable) {
    buf
      ..writeln()
      ..write(body);
  }

  return formatGeneratedDart(buf.toString());
}

/// Emits a registration source for a package with no emittable app widget.
///
/// It still carries [appVocabulary]: a package that defines no widget of its
/// own still renders built-in widgets and icons on its surfaces.
///
/// [installWholeCatalog] makes the generated registration install the whole
/// built-in catalog and both icon tables by default.
String emitEmptyUserFactoriesDart({
  SurfaceVocabularyReferences appVocabulary = SurfaceVocabularyReferences.empty,
  bool installWholeCatalog = false,
}) {
  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln()
    ..writeln("import 'package:restage/restage.dart';")
    ..writeln();
  _writeAppVocabulary(buf, appVocabulary);
  _writeRegistrationConstant(buf);
  buf.writeln('/// Registers the currently enabled RFW widgets.');
  _writeCatalogConfigurationDoc(buf, installWholeCatalog);
  _writeRegistrationStart(buf);
  _writeWholeCatalogInstall(buf, installWholeCatalog);
  buf
    ..writeln(
      '  kRestageAppVocabulary.addToInstalled(explicitSelection: true);',
    )
    ..writeln('  }')
    ..writeln('}');
  _emitDeprecatedRegistrationAlias(buf);
  return formatGeneratedDart(buf.toString());
}

/// Documents the matching configuration entrypoint on the registration helper.
void _writeCatalogConfigurationDoc(StringBuffer buf, bool installWholeCatalog) {
  if (!installWholeCatalog) {
    buf
      ..writeln('///')
      ..writeln(
        '/// Call Restage.configureWithInstalledCatalog() after registration',
      )
      ..writeln('/// to keep this selected vocabulary in a release build.')
      ..writeln(
        '/// Family options are accepted without adding full catalogs.',
      );
    return;
  }
  buf
    ..writeln('///')
    ..writeln('/// Includes both complete built-in families by default.')
    ..writeln(
      '/// Family options omit full contributions, keeping app requirements.',
    );
}

void _writeRegistrationConstant(StringBuffer buf) {
  buf
    ..writeln('/// Pass to Restage.configure(registerWidgets: ...) to register')
    ..writeln('/// this package with the configured family options.')
    ..writeln('const RestageWidgetRegistration kRestageWidgetRegistration =')
    ..writeln('    _RestageWidgetRegistration();')
    ..writeln();
}

void _writeRegistrationStart(StringBuffer buf) {
  buf
    ..writeln('void registerRestageWidgets({')
    ..writeln('  bool includeMaterial = true,')
    ..writeln('  bool includeCupertino = true,')
    ..writeln('}) {')
    ..writeln('  kRestageWidgetRegistration(')
    ..writeln('    includeMaterial: includeMaterial,')
    ..writeln('    includeCupertino: includeCupertino,')
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln('final class _RestageWidgetRegistration')
    ..writeln('    implements RestageWidgetRegistration {')
    ..writeln('  const _RestageWidgetRegistration();')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  void call({')
    ..writeln('    bool includeMaterial = true,')
    ..writeln('    bool includeCupertino = true,')
    ..writeln('  }) {');
}

/// Adds selected full catalogs before app requirements.
void _writeWholeCatalogInstall(StringBuffer buf, bool installWholeCatalog) {
  if (!installWholeCatalog) return;
  buf
    ..writeln('  InstalledWidgetLibraries.add(RestageWidgetLibraries.builtIn(')
    ..writeln('    includeMaterial: includeMaterial,')
    ..writeln('    includeCupertino: includeCupertino,')
    ..writeln('  ));')
    ..writeln('  InstalledIconTable.add(builtInIconTable(')
    ..writeln('    includeMaterial: includeMaterial,')
    ..writeln('    includeCupertino: includeCupertino,')
    ..writeln('  ));');
}

/// Writes the whole-app vocabulary constant.
void _writeAppVocabulary(
  StringBuffer buf,
  SurfaceVocabularyReferences appVocabulary,
) {
  final source = emitSurfaceVocabulary(appVocabulary);
  buf
    ..writeln('/// The built-in widgets and icons this package names in its')
    ..writeln('/// own Dart, plus the catalog entries its compiled surfaces')
    ..writeln('/// render, so a delivered surface can render them.')
    ..writeln('///')
    ..writeln("/// The scan covers this package's own `lib/` and not the")
    ..writeln('/// packages it depends on. An icon reached through a variable,')
    ..writeln('/// a function return, or an app-defined wrapper rather than')
    ..writeln('/// named by a compile-time constant is not seen.')
    ..writeln('const SurfaceVocabulary kRestageAppVocabulary = $source;')
    ..writeln();
}

void _emitDeprecatedRegistrationAlias(StringBuffer buf) {
  buf
    ..writeln()
    ..writeln("@Deprecated('Use registerRestageWidgets; removed in 3.0')")
    ..writeln(
      'void registerRestageCustomerWidgets() => registerRestageWidgets();',
    );
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
