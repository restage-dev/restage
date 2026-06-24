import 'dart:async';

import 'package:build/build.dart';
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
/// `lib/src/registration.g.dart` declaring a const
/// `Map<String, LocalWidgetBuilder> kXxxLibraryFactories` keyed by widget
/// name.
///
/// Scaffold: the emitted map is empty regardless of catalog content.
/// Per-widget closures land in follow-up work that decodes flat
/// `DataSource` arguments and constructs the canonical Flutter widget.
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

    if (catalog.libraries.length != 1) {
      throw StateError(
        'Expected exactly one library in ${input.path}; '
        'found ${catalog.libraries.length} '
        '(${catalog.libraries.keys.map((l) => l.namespace).join(", ")}).',
      );
    }

    final library = catalog.libraries.keys.first;
    final source = _emitRegistrationFile(
      library: library,
      widgets: catalog.widgetsIn(library),
      nativeIndex: NativeCatalogIndex(catalog),
    );

    await buildStep.writeAsString(
      AssetId(input.package, _outputAsset),
      source,
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
/// Customer libraries register through the `@RestageWidget` flow
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
        'built-in libraries (restage.{core,material,cupertino}); customer '
        'libraries flow through the @RestageWidget aggregator instead.',
      );
  }
}

String _emitRegistrationFile({
  required WidgetLibrary library,
  required List<WidgetEntry> widgets,
  required NativeCatalogIndex nativeIndex,
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
    final emitted = emitFactoryFunction(entry, nativeIndex: nativeIndex);
    if (emitted == null) continue;
    factoryDefinitions.add(emitted);
    mapEntries.add("  '${entry.name}': ${functionNameFor(entry)},");
    emittedEntries.add(entry);
  }

  // An icon factory constructs `IconData` from a runtime codepoint (the
  // `--no-tree-shake-icons` RFW pattern). Newer analyzers flag the non-const
  // codePoint argument, and pub's analyzer scoring does not honour an
  // `analysis_options` exclude — only an in-file ignore. Emit it for the whole
  // generated file, but only when an icon factory actually lands here (so
  // icon-free libraries don't carry a would-be-unnecessary directive).
  final needsIconDataIgnore =
      factoryDefinitions.any((body) => body.contains('IconData('));

  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln('//')
    ..writeln(
      "// Per-widget LocalWidgetBuilder map for the '$namespace' library.",
    )
    ..writeln('// To change this map: edit lib/registry_curation.dart, then')
    ..writeln('// re-run build_runner (it regenerates the registry, the')
    ..writeln('// catalog, and this file).');
  if (needsIconDataIgnore) {
    buf
      ..writeln('//')
      ..writeln('// ignore_for_file: non_const_argument_for_const_parameter')
      ..writeln('// (icon factories build IconData from a runtime codepoint,')
      ..writeln('// which newer analyzers flag because the codePoint is not')
      ..writeln('// const).');
  }
  buf.writeln();
  // Flutter import is only needed when at least one factory function
  // body lands in the file; an empty map references no Flutter types
  // and the unused import would trigger an analyzer warning.
  if (factoryDefinitions.isNotEmpty) {
    buf.writeln("import '${_flutterImportFor(library)}';");
  }
  // Cross-package widget imports — emitted whenever a curated entry's
  // class lives outside the primary Flutter import (e.g. a widget
  // authored inside `restage_material` itself, whose `flutterType`
  // resolves to `package:restage_material/...`). Mirrors the pattern
  // in `user_factory_emitter.dart`: dedupe by source URI, drop
  // `package:flutter/...` URIs (covered by the primary import), sort
  // for byte-deterministic emit. Without this, the emitted factory
  // body references a class the file doesn't import and analyze fails.
  // `restage_core` carries `RestageDecoders` (helpers for property
  // types not covered by rfw's `ArgumentDecoders`, e.g. `Duration`)
  // and `resolveThemeBinding` (the runtime resolver for theme-binding
  // defaults). Emit the barrel import only when at least one factory body
  // references one of them — keeps unused-import warnings out of
  // libraries whose curation reaches neither. Self-imports via
  // `package:` URI resolve fine for the core library itself.
  final referencesCoreRuntime = factoryDefinitions.any(
    (d) => d.contains('RestageDecoders.') || d.contains('resolveThemeBinding('),
  );
  final primaryFlutterImport = _flutterImportFor(library);
  final extraWidgetImports = <String>{
    for (final entry in emittedEntries)
      entry.flutterType.substring(0, entry.flutterType.indexOf('#')),
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
        'built-in libraries; customer libraries flow through the '
        '@RestageWidget aggregator.',
      );
  }
}
