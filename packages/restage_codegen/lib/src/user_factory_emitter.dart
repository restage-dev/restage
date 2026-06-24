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
}) {
  final emittable = <(WidgetEntry, String)>[];
  for (final entry in widgets) {
    final body = emitFactoryFunction(entry);
    if (body == null) {
      onSkip?.call(entry);
      continue;
    }
    emittable.add((entry, body));
  }
  if (emittable.isEmpty) return null;

  // One import per source file containing an emittable `@RestageWidget`.
  // Derived from `flutterType` (`<package URI>#<class name>`); the URI
  // before `#` is the import target. Sorted for byte-deterministic emit.
  final widgetImports = <String>{
    for (final (entry, _) in emittable)
      entry.flutterType.substring(0, entry.flutterType.indexOf('#')),
  }.toList()
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
  for (final import in widgetImports) {
    buf.writeln("import '$import';");
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
    buf
      ..writeln('  Restage.registerWidgetLibrary(')
      ..writeln('    ${_libraryFieldRef(library)},')
      ..writeln('    widgets: const <RestageWidgetFactory>[');
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
