import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The binding-tie (proof-b): the shipped example artifact's customer-widget
/// lowering is byte-traceable to the production emit path.
///
/// The example (`packages/restage_a2ui/example/`) commits its generated A2UI
/// catalog, produced by `dart run build_runner build`. This drift-guard
/// re-derives the catalog from the example's committed `@RestageWidget` source
/// through the SAME production functions the builder runs —
/// `visitRestageWidgets` (the catalog projection), `assembleA2uiSeams` (the
/// analyzer-fed read legs), and the unchanged `emitA2uiCatalogDart` — with
/// built-ins explicitly EMPTY (so it reproduces the example's customer-only
/// build, which depends on no built-in catalog), and asserts the
/// customer-widget CatalogItem bodies + helpers are byte-identical to the
/// committed artifact. So the shipped lowering cannot silently rot.
///
/// Only the import BLOCK is excluded from the comparison — the resolved source
/// URIs differ at the test boundary (`file://` vs the build's
/// `package:restage_a2ui_example/…`), exactly the benign scope/URI artifact the
/// seam-parity proof already accounts for. The bodies reference widgets through
/// the emitter's import aliases (assigned in the same sorted order under both
/// URI schemes), so the lowering itself compares byte-for-byte.
///
/// The widget set is DISCOVERED by walking the example `lib/` for every
/// `@RestageWidget` (not a hardcoded list), so an added or dropped widget that
/// did not get the catalog regenerated is caught by the body mismatch.

const _exampleLibDir = '../restage_a2ui/example/lib';

/// Walks the example `lib/` for every `@RestageWidget`, resolved off the real
/// SDK, returning the `(WidgetEntry, ClassElement)` pairs in the SAME
/// `(library namespace, name)` order the production builder emits. The
/// generated `*.g.dart` is excluded (it imports the genui runtime, unresolvable
/// here, and is the artifact under test, not a source).
Future<List<A2uiWidgetElement>> _discoverExampleWidgets() async {
  final libDir = Directory('${Directory.current.path}/$_exampleLibDir');
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
      .toList()
    ..sort();

  final widgets = <A2uiWidgetElement>[];
  for (final path in dartFiles) {
    final abs = File(path).resolveSymbolicLinksSync();
    final collection = AnalysisContextCollection(includedPaths: [abs]);
    final resolved =
        await collection.contextFor(abs).currentSession.getResolvedLibrary(abs);
    if (resolved is! ResolvedLibraryResult) continue;
    final entries = visitRestageWidgets(
      resolved.element,
      AssetId('restage_a2ui_example', 'lib/${abs.split('/').last}'),
    ).widgets;
    for (final entry in entries) {
      final element = resolved.element.classes.firstWhere(
        (c) => c.name == entry.flutterType.split('#').last,
        orElse: () => throw StateError('no class for ${entry.name}'),
      );
      widgets.add((entry: entry, element: element));
    }
  }

  widgets.sort((a, b) {
    final byLib =
        a.entry.library.namespace.compareTo(b.entry.library.namespace);
    return byLib != 0 ? byLib : a.entry.name.compareTo(b.entry.name);
  });
  return widgets;
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
    'production emit path (proof-b binding-tie)',
    () async {
      final widgets = await _discoverExampleWidgets();
      expect(
        widgets,
        isNotEmpty,
        reason: 'the example must declare at least one @RestageWidget',
      );
      final catalog = catalogWith([for (final w in widgets) w.entry]);
      final seams = assembleA2uiSeams(widgets);

      final emitted = formatGeneratedDart(
        emitA2uiCatalogDart(
          catalog,
          richShapes: seams.richShapes,
          eventSeam: seams.eventSeam,
          pairingSeam: seams.pairingSeam,
        ),
      );

      final committed = File(
        '${Directory.current.path}/$_exampleLibDir/restage_a2ui_catalog.g.dart',
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
}
