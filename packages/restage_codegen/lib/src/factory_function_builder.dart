import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _catalogAsset = 'lib/src/widget_catalog/catalog.json';
const String _outputAsset = 'lib/src/registration.g.dart';

/// build_runner builder that emits each curated library's per-widget
/// factory map, consumed by the SDK runtime to register a
/// `LocalWidgetLibrary` per namespace.
///
/// One builder run per consuming package. Reads the package's
/// `lib/src/widget_catalog/catalog.json` (emitted by the workspace
/// catalog tool from each library's `kRegistry`) and writes
/// `lib/src/registration.g.dart`, which declares one public builder
/// function per widget plus a const
/// `Map<String, LocalWidgetBuilder> kXxxLibraryFactories` keyed by widget
/// name.
final class FactoryFunctionBuilder implements Builder {
  /// Const constructor used by the `factoryFunctionBuilder` factory.
  const FactoryFunctionBuilder(this.options);

  /// `BuilderOptions` injected by build_runner; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        _catalogAsset: [_outputAsset],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final json = await buildStep.readAsString(input);
    final catalog = requireNativeCatalog(decodeCatalog(json));

    // A pure-custom catalog (no built-in library) registers through the
    // @RestageWidget factory aggregator, not this builder. Since a custom
    // package may carry an authored custom catalog at the same path.
    // Custom factories come from the annotation-driven builder.
    final hasBuiltInLibrary = catalog.libraries.keys.any(
      (l) => WidgetLibrary.builtInByNamespace(l.namespace) != null,
    );
    if (!hasBuiltInLibrary) return;

    if (catalog.libraries.length != 1) {
      throw StateError(
        'Expected exactly one library in ${input.path}; '
        'found ${catalog.libraries.length} '
        '(${catalog.libraries.keys.map((l) => l.namespace).join(", ")}).',
      );
    }

    final library = catalog.libraries.keys.first;
    final widgets = catalog.widgetsIn(library);
    final source = _emitRegistrationFile(
      library: library,
      widgets: widgets,
      nativeIndex: NativeCatalogIndex(catalog),
      reachableEnums: await _enumsExportedBy(
        buildStep,
        _flutterImportFor(library),
        widgets.expand(_sdkEnumRefs),
      ),
    );

    await buildStep.writeAsString(
      AssetId(input.package, _outputAsset),
      formatGeneratedDart(
        source,
        languageVersion: await packageLanguageVersion(buildStep),
      ),
    );
  }
}

/// Returns the const-map identifier used in the emitted file for [library].
///
/// Recognized built-in namespaces map to:
///   * `restage.core` → `kCoreLibraryFactories`
///   * `restage.material` → `kMaterialLibraryFactories`
///   * `restage.cupertino` → `kCupertinoLibraryFactories`
///
/// Custom libraries register through the `@RestageWidget` flow
/// (which emits `lib/user_catalog.g.dart`), not this builder, so any
/// non-built-in namespace reaching this point is a configuration bug
/// and surfaces as a [StateError].
String constMapNameFor(WidgetLibrary library) {
  switch (library.namespace) {
    case 'restage.core':
      return 'kCoreLibraryFactories';
    case 'restage.material':
      return 'kMaterialLibraryFactories';
    case 'restage.cupertino':
      return 'kCupertinoLibraryFactories';
    default:
      throw StateError(
        'Unsupported library namespace for factory function emission: '
        "'${library.namespace}'. The factory builder runs only against "
        'built-in libraries (restage.{core,material,cupertino}); custom '
        'libraries flow through the @RestageWidget aggregator instead.',
      );
  }
}

String _emitRegistrationFile({
  required WidgetLibrary library,
  required List<WidgetEntry> widgets,
  required NativeCatalogIndex nativeIndex,
  required Set<DartTypeRef> reachableEnums,
}) {
  final namespace = library.namespace;
  final mapName = constMapNameFor(library);

  // Build factory functions for every entry the emitter can produce
  // mechanically today. Entries it doesn't yet know how to handle
  // (unsupported structured transforms, generic enums, synthetic
  // catalog-name remappings) are silently skipped — they'll surface as
  // "widget not found" at runtime until follow-up work fills them in.
  final factoryDefinitions = <String>[];
  final mapEntries = <String>[];
  final emittedEntries = <WidgetEntry>[];
  for (final entry in widgets) {
    final emitted = emitFactoryFunction(
      entry,
      nativeIndex: nativeIndex,
      publicName: true,
    );
    if (emitted == null) continue;
    factoryDefinitions.add(emitted);
    mapEntries.add("  '${entry.name}': ${publicFunctionNameFor(entry)},");
    emittedEntries.add(entry);
  }

  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln('//')
    ..writeln(
      "// Per-widget LocalWidgetBuilder map for the '$namespace' library.",
    )
    ..writeln('// To change this map: edit lib/registry_curation.dart, then')
    ..writeln('// re-run build_runner (it regenerates the registry, the')
    ..writeln('// catalog, and this file).')
    ..writeln();
  // Flutter import is only needed when at least one factory function
  // body lands in the file; an empty map references no Flutter types
  // and the unused import would trigger an analyzer warning.
  if (factoryDefinitions.isNotEmpty) {
    buf.writeln("import '${_flutterImportFor(library)}';");
  }
  // Name each Flutter or SDK enum through its public library unless the
  // Flutter import above already exports it.
  final enumImports = <String, Set<String>>{};
  for (final ref in emittedEntries.expand(_sdkEnumRefs)) {
    if (reachableEnums.contains(ref)) continue;
    enumImports
        .putIfAbsent(publicDartImportUri(ref.libraryUri), () => <String>{})
        .add(ref.symbolName);
  }
  for (final uri in enumImports.keys.toList()..sort()) {
    final symbols = enumImports[uri]!.toList()..sort();
    buf.writeln("import '$uri' show ${symbols.join(', ')};");
  }
  // Import non-Flutter widget and enum libraries by sorted, deduplicated
  // source URI. Add the core barrel only when emitted factories use its
  // runtime helpers.
  final referencesCoreRuntime = factoryDefinitions.any(
    (d) =>
        d.contains('RestageDecoders.') ||
        d.contains('RestageRfwConstructorPresence.') ||
        d.contains('resolveThemeBinding(') ||
        d.contains('restageIcon('),
  );
  final primaryFlutterImport = _flutterImportFor(library);
  final extraWidgetImports = <String>{
    for (final entry in emittedEntries)
      entry.flutterType.substring(0, entry.flutterType.indexOf('#')),
    for (final ref in emittedEntries.expand(_enumRefs))
      if (!_isSdkLibrary(ref.libraryUri)) ref.libraryUri,
  }
    ..removeWhere((uri) => uri == primaryFlutterImport)
    ..removeWhere((uri) => uri.startsWith('package:flutter/'));
  // When the `restage_core` barrel is emitted it re-exports the core
  // library's own public widgets, so a direct import of a first-party core
  // widget source is redundant under it (`unnecessary_import`). Drop those;
  // widgets authored in other packages (e.g. `package:restage_material/...`)
  // are not covered by the core barrel and keep their direct import.
  if (referencesCoreRuntime) {
    extraWidgetImports.removeWhere(
      (uri) => uri.startsWith('package:restage_core/'),
    );
  }
  final sortedExtraWidgetImports = extraWidgetImports.toList()..sort();
  for (final uri in sortedExtraWidgetImports) {
    buf.writeln("import '$uri';");
  }
  if (referencesCoreRuntime) {
    buf.writeln("import 'package:restage_core/restage_core.dart';");
  }
  // `ImageFilter` is in `dart:ui`; `package:flutter/widgets.dart`
  // doesn't re-export it. Conditional import keeps libraries that
  // don't curate `BackdropFilter` (or other ImageFilter-consuming
  // widgets) free of an unused-import warning.
  final referencesImageFilter =
      factoryDefinitions.any((d) => d.contains('ImageFilter.'));
  if (referencesImageFilter) {
    buf.writeln("import 'dart:ui' show ImageFilter;");
  }
  // Hide rfw model class names that collide with Flutter widget names.
  // `Switch` is the first concrete collision (Material `Switch` widget
  // vs rfw's `Switch` model class); add others here as they surface.
  buf
    ..writeln("import 'package:rfw/rfw.dart' hide Switch;")
    ..writeln()
    ..writeln(
      '/// One [LocalWidgetBuilder] per widget entry in `lib/registry.dart`,',
    )
    ..writeln('/// keyed by widget name.')
    ..writeln('const Map<String, LocalWidgetBuilder> $mapName =')
    ..writeln('    <String, LocalWidgetBuilder>{');
  mapEntries.forEach(buf.writeln);
  buf.writeln('};');
  for (final definition in factoryDefinitions) {
    buf
      ..writeln()
      ..write(definition);
  }

  return formatGeneratedDart(buf.toString());
}

/// Returns the Flutter library import the emitted file uses for widget
/// constructors. Each curated library targets the corresponding Flutter
/// surface; `material.dart` and `cupertino.dart` re-export `widgets.dart`
/// so cross-library types (e.g. material's `Icon` from `widgets.dart`)
/// resolve transitively.
/// The enums [entry]'s properties name.
Iterable<DartTypeRef> _enumRefs(WidgetEntry entry) sync* {
  for (final property in entry.properties) {
    if (property.valueShape case EnumShape(:final enumRef)) yield enumRef;
  }
}

/// The Flutter and Dart SDK enums [entry]'s properties name.
Iterable<DartTypeRef> _sdkEnumRefs(WidgetEntry entry) =>
    _enumRefs(entry).where((ref) => _isSdkLibrary(ref.libraryUri));

bool _isSdkLibrary(String uri) =>
    uri.startsWith('package:flutter/') || uri.startsWith('dart:');

/// The [enums] that [libraryUri] exports from their declaring library.
///
/// An unresolvable library exports none, so every enum gets its own import.
Future<Set<DartTypeRef>> _enumsExportedBy(
  BuildStep buildStep,
  String libraryUri,
  Iterable<DartTypeRef> enums,
) async {
  final refs = enums.toSet();
  if (refs.isEmpty) return const {};
  final asset = AssetId.resolve(Uri.parse(libraryUri));
  final LibraryElement exporting;
  try {
    if (!await buildStep.resolver.isLibrary(asset)) return const {};
    exporting = await buildStep.resolver.libraryFor(asset);
  } on Object {
    return const {};
  }
  return {
    for (final ref in refs)
      if (exporting.exportNamespace.get2(ref.symbolName)?.library?.identifier ==
          ref.libraryUri)
        ref,
  };
}

String _flutterImportFor(WidgetLibrary library) {
  switch (library.namespace) {
    case 'restage.core':
      return 'package:flutter/widgets.dart';
    case 'restage.material':
      return 'package:flutter/material.dart';
    case 'restage.cupertino':
      return 'package:flutter/cupertino.dart';
    default:
      throw StateError(
        'No Flutter import mapping for namespace '
        "'${library.namespace}'. The factory builder runs only against "
        'built-in libraries; custom libraries flow through the '
        '@RestageWidget aggregator.',
      );
  }
}
