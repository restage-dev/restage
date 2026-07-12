import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The binding-tie: the shipped example artifacts' customer-widget lowering is
/// byte-traceable to the production emit path.
///
/// The example (`packages/restage_a2ui/example/`) commits its generated A2UI
/// catalog AND its capability stamp, produced by `dart run build_runner build`.
/// This drift-guard re-derives BOTH from the example's committed
/// `@RestageWidget` source through the SAME production functions the builder
/// runs — `visitRestageWidgets` (the catalog projection), `walkRestageLibrary`
/// (the `@RestageLibrary` capability versions), `assembleA2uiSeams` (the
/// analyzer-fed read legs), and the unchanged `emitA2uiCatalogDart` /
/// `emitA2uiCatalog` — with built-ins explicitly EMPTY (so it reproduces the
/// example's customer-only build, which depends on no built-in catalog), and
/// asserts byte-identity to the committed artifacts. So the shipped lowering
/// cannot silently rot.
///
/// For the generated Dart, only the import BLOCK is excluded from the
/// comparison — the resolved source URIs differ at the test boundary
/// (`file://` vs the build's `package:restage_a2ui_example/…`), exactly the
/// benign scope/URI artifact the seam-parity proof already accounts for. The
/// bodies reference widgets through the emitter's import aliases (assigned in
/// the same sorted order under both URI schemes), so the lowering itself
/// compares byte-for-byte. The capability stamp carries no source URIs, so it
/// ties whole-file.
///
/// The widget set is DISCOVERED by walking the example `lib/` for every
/// `@RestageWidget` (not a hardcoded list), so an added or dropped widget that
/// did not get the artifacts regenerated is caught by the mismatch.

/// The example package's `lib/` directory, resolved from the `restage_codegen`
/// package location so the proof is cwd-independent (runs from repo root and
/// inside broad verification gates, not only from `packages/restage_codegen`).
/// Returned as a `Uri` so each call site resolves child paths explicitly rather
/// than depending on a trailing separator.
Future<Uri> _exampleLibDirUri() async {
  final barrel = await Isolate.resolvePackageUri(
    Uri.parse('package:restage_codegen/restage_codegen.dart'),
  );
  if (barrel == null) {
    throw StateError('cannot resolve package:restage_codegen');
  }
  // barrel = .../packages/restage_codegen/lib/restage_codegen.dart
  return barrel.resolve('../../restage_a2ui/example/lib/');
}

/// The discovered example sources: every `@RestageWidget` paired with its
/// resolved class element, plus each `@RestageLibrary` declaration's
/// capability version — the same two walks the production builder runs.
typedef _ExampleSources = ({
  List<A2uiWidgetElement> widgets,
  Map<WidgetLibrary, int?> capabilityVersions,
  Map<String, String> usageByWidget,
});

/// Walks the example `lib/` for every `@RestageWidget`, resolved off the real
/// SDK, returning the `(WidgetEntry, ClassElement)` pairs in the SAME
/// `(library namespace, name)` order the production builder emits, and each
/// contributing library's declared `@RestageLibrary(capabilityVersion:)`. The
/// generated `*.g.dart` is excluded (it imports the genui runtime, unresolvable
/// here, and is the artifact under test, not a source).
Future<_ExampleSources> _discoverExampleSources() async {
  final libDir = Directory.fromUri(await _exampleLibDirUri());
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
      .toList()
    ..sort();

  final widgets = <A2uiWidgetElement>[];
  final capabilityVersions = <WidgetLibrary, int?>{};
  final usageByWidget = <String, String>{};
  for (final path in dartFiles) {
    final abs = File(path).resolveSymbolicLinksSync();
    final collection = AnalysisContextCollection(includedPaths: [abs]);
    final resolved =
        await collection.contextFor(abs).currentSession.getResolvedLibrary(abs);
    if (resolved is! ResolvedLibraryResult) continue;
    final assetId =
        AssetId('restage_a2ui_example', 'lib/${abs.split('/').last}');
    final entries = visitRestageWidgets(resolved.element, assetId).widgets;
    for (final entry in entries) {
      final element = resolved.element.classes.firstWhere(
        (c) => c.name == entry.flutterType.split('#').last,
        orElse: () => throw StateError('no class for ${entry.name}'),
      );
      widgets.add((entry: entry, element: element));

      // Read the `usage` producer note the same way the production builder
      // does — straight off the annotation, since it is not part of the
      // `WidgetEntry` projection.
      final annotationValue =
          firstAnnotation(element, 'RestageWidget')?.computeConstantValue();
      final usage = annotationValue?.getField('usage')?.toStringValue()?.trim();
      if (usage != null && usage.isNotEmpty) {
        usageByWidget[entry.name] = usage;
      }
    }
    final declaration =
        walkRestageLibrary(barrel: resolved.element, barrelAssetId: assetId)
            .declaration;
    if (declaration != null) {
      capabilityVersions[declaration.library] = declaration.capabilityVersion;
    }
  }

  widgets.sort((a, b) {
    final byLib =
        a.entry.library.namespace.compareTo(b.entry.library.namespace);
    return byLib != 0 ? byLib : a.entry.name.compareTo(b.entry.name);
  });
  return (
    widgets: widgets,
    capabilityVersions: capabilityVersions,
    usageByWidget: usageByWidget,
  );
}

/// The customer-only catalog the production builder assembles from the walked
/// sources: `libraries` and `widgets` from the walk alone, each library
/// carrying its declared capability version, with the builder's deterministic
/// metadata (schema-version constant, epoch `generatedAt`, placeholder pub
/// version) so the derived emit is byte-comparable to the committed artifacts.
Catalog _customerCatalog(_ExampleSources sources) {
  final libraries = <WidgetLibrary>{
    for (final w in sources.widgets) w.entry.library,
  };
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      for (final library in libraries)
        library: LibraryInfo(
          version: '0.0.0',
          capabilityVersion: sources.capabilityVersions[library],
        ),
    },
    widgets: [for (final w in sources.widgets) w.entry],
  );
}

/// The body of a generated catalog — everything from the
/// `buildRestageCatalogItems()` declaration onward (the CatalogItem lowerings +
/// the emitter helper set), excluding the import block.
String _body(String source) {
  const marker = 'List<CatalogItem> buildRestageCatalogItems()';
  final index = source.indexOf(marker);
  if (index < 0) throw StateError('no catalog body found');
  return source.substring(index).trimRight();
}

void main() {
  test(
    'the committed example catalog body regenerates byte-identical from the '
    'production emit path (binding-tie)',
    () async {
      final sources = await _discoverExampleSources();
      expect(
        sources.widgets,
        isNotEmpty,
        reason: 'the example must declare at least one @RestageWidget',
      );
      final catalog = _customerCatalog(sources);
      final seams = assembleA2uiSeams(sources.widgets);

      final emitted = formatGeneratedDart(
        emitA2uiCatalogDart(
          catalog,
          richShapes: seams.richShapes,
          eventSeam: seams.eventSeam,
          pairingSeam: seams.pairingSeam,
          usageByWidget: sources.usageByWidget,
        ),
      );

      final committed = File.fromUri(
        (await _exampleLibDirUri()).resolve('restage_a2ui_catalog.g.dart'),
      ).readAsStringSync();

      expect(
        _body(emitted),
        _body(committed),
        reason: 'the committed example catalog body must regenerate '
            'byte-for-byte from the example @RestageWidget source through the '
            'production emit path — the shipped lowering is traceable',
      );
    },
  );

  test(
    'the committed example capability stamp regenerates byte-identical from '
    'the production emit path (binding-tie)',
    () async {
      final sources = await _discoverExampleSources();
      expect(
        sources.widgets,
        isNotEmpty,
        reason: 'the example must declare at least one @RestageWidget',
      );
      final catalog = _customerCatalog(sources);
      final seams = assembleA2uiSeams(sources.widgets);

      final stamp = emitA2uiCatalog(
        catalog,
        richShapes: seams.richShapes,
        eventSeam: seams.eventSeam,
        pairingSeam: seams.pairingSeam,
        usageByWidget: sources.usageByWidget,
      ).toJson();
      // The builder's exact serialization of the stamp document.
      final emitted = const JsonEncoder.withIndent('  ').convert(stamp);

      final committed = File.fromUri(
        (await _exampleLibDirUri()).resolve('restage_a2ui_catalog.a2ui.json'),
      ).readAsStringSync();

      expect(
        emitted,
        committed,
        reason: 'the committed example capability stamp must regenerate '
            'byte-for-byte from the example @RestageWidget source through the '
            'production emit path — the shipped capability surface is '
            'traceable',
      );
    },
  );
}
