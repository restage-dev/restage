import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_discovery.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_loader.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_validator.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

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
  List<LoadedA2uiExample> examples,
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
  final examples = <LoadedA2uiExample>[];
  for (final path in dartFiles) {
    final abs = File(path).resolveSymbolicLinksSync();
    final collection = AnalysisContextCollection(includedPaths: [abs]);
    final resolved =
        await collection.contextFor(abs).currentSession.getResolvedLibrary(abs);
    if (resolved is! ResolvedLibraryResult) continue;
    final assetId =
        AssetId('restage_a2ui_example', 'lib/${abs.split('/').last}');
    final entries = visitRestageWidgets(
      resolved.element,
      assetId,
      target: WidgetVisitorTarget.a2ui,
    ).widgets;
    final widgetNamesByClass = <ClassElement, String>{};
    for (final entry in entries) {
      final element = resolved.element.classes.firstWhere(
        (c) => c.name == entry.flutterType.split('#').last,
        orElse: () => throw StateError('no class for ${entry.name}'),
      );
      widgets.add((entry: entry, element: element));
      widgetNamesByClass[element] = entry.name;

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
    for (final anchor in discoverA2uiExampleAnchors(
      resolvedLibrary: resolved,
      widgetNamesByClass: widgetNamesByClass,
    )) {
      final sidecar = File.fromUri(
        libDir.parent.uri.resolve(anchor.asset),
      );
      examples.add(
        LoadedA2uiExample(
          anchor: anchor,
          assetId: AssetId('restage_a2ui_example', anchor.asset),
          components: decodeA2uiExampleComponents(
            sidecar.readAsStringSync(),
            anchor,
          ),
        ),
      );
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
    examples: examples,
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

Catalog _visitorCatalog(WidgetVisitorResult result) {
  final libraries = <WidgetLibrary>{
    for (final widget in result.widgets) widget.library,
  };
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      for (final library in libraries)
        library: const LibraryInfo(
          version: '0.0.0',
          capabilityVersion: 1,
        ),
    },
    widgets: result.widgets,
  );
}

List<int> _encodedA2uiCatalog(Catalog catalog) {
  final registration = emitA2uiCatalog(catalog);
  return utf8.encode(
    const JsonEncoder.withIndent('  ').convert(registration.toJson()),
  );
}

String _recordPackageSource({required bool includeRecord}) {
  final constructor = includeRecord
      ? "const RecordCard({this.heading = (step: 0, title: 'Untitled')});"
      : 'const RecordCard();';
  final property = includeRecord
      ? '''
    @RestageProperty(description: 'The heading.')
    final ({String title, int step}) heading;
  '''
      : '';
  return '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

    @RestageLibrary(
      library: WidgetLibrary.custom('acme.widgets'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;

    @RestageWidget(
      name: 'RecordCard',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A card.',
    )
    class RecordCard {
      $constructor
      $property
    }
  ''';
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

void _expectOccurrenceDescription(
  A2uiSchemaNode node,
  String description, {
  String? reason,
}) {
  expect(node.occurrenceDescription, description, reason: reason);
}

void main() {
  test(
    'the committed example artifacts regenerate from one production '
    'registration (binding-tie)',
    () async {
      final sources = await _discoverExampleSources();
      expect(
        sources.widgets,
        isNotEmpty,
        reason: 'the example must declare at least one @RestageWidget',
      );
      final catalog = _customerCatalog(sources);
      final seams = assembleA2uiSeams(sources.widgets);
      final product = seams.richShapes[('ProductCard', 'product')];
      expect(product, isA<ObjectNode>());
      final productObject = product! as ObjectNode;
      expect(
        productObject.definitionDescription,
        'A product with pricing, feature, attribute, and display metadata.',
      );
      _expectOccurrenceDescription(
        productObject.fields['name']!,
        'The customer-facing product name.',
        reason: 'the field-formal annotation must override member Dartdoc',
      );
      _expectOccurrenceDescription(
        productObject.fields['price']!,
        'The price — a nested data class.',
      );
      final price = productObject.fields['price']! as ObjectNode;
      expect(
        price.definitionDescription,
        'A monetary amount in a specific currency.',
      );
      _expectOccurrenceDescription(
        price.fields['amount']!,
        'The numeric amount.',
      );
      _expectOccurrenceDescription(
        price.fields['currency']!,
        "The ISO currency code (e.g. `'USD'`).",
      );
      _expectOccurrenceDescription(
        productObject.fields['tags']!,
        'Marketing tags — a scalar list.',
      );
      final features = productObject.fields['features']! as ListNode;
      _expectOccurrenceDescription(
        features,
        'Feature rows — a list of objects.',
      );
      final feature = features.element as ObjectNode;
      expect(
        feature.definitionDescription,
        'One feature included in or excluded from a product.',
      );
      _expectOccurrenceDescription(
        feature.fields['label']!,
        'The feature label.',
      );
      _expectOccurrenceDescription(
        feature.fields['included']!,
        'Whether this plan includes the feature.',
      );
      _expectOccurrenceDescription(
        productObject.fields['attributes']!,
        'Arbitrary attributes — a String-keyed map.',
      );
      final size = productObject.fields['size']! as ObjectNode;
      _expectOccurrenceDescription(
        size,
        'The display size — a named record.',
      );
      expect(
        size.fields.values
            .every((field) => field.occurrenceDescription == null),
        isTrue,
        reason: 'record labels do not invent member descriptions',
      );
      final registration = emitA2uiCatalog(
        catalog,
        richShapes: seams.richShapes,
        eventSeam: seams.eventSeam,
        pairingSeam: seams.pairingSeam,
        usageByWidget: sources.usageByWidget,
      );
      final plan = classifyA2uiCatalogDart(
        catalog,
        richShapes: seams.richShapes,
        eventSeam: seams.eventSeam,
        pairingSeam: seams.pairingSeam,
      );
      final exampleRegistry = buildA2uiExampleRegistry(
        validateA2uiExamples(plan: plan, examples: sources.examples),
      );

      final emittedDart = formatGeneratedDart(
        emitA2uiCatalogDartWithExampleRegistry(
          catalog,
          exampleRegistry: exampleRegistry,
          registration: registration,
          richShapes: seams.richShapes,
          eventSeam: seams.eventSeam,
          pairingSeam: seams.pairingSeam,
          usageByWidget: sources.usageByWidget,
        ),
      );

      final exampleLibDir = await _exampleLibDirUri();
      final committedDart = File.fromUri(
        exampleLibDir.resolve('restage_a2ui_catalog.g.dart'),
      ).readAsStringSync();

      expect(
        _body(emittedDart),
        _body(committedDart),
        reason: 'the committed example catalog body must regenerate '
            'byte-for-byte from the example @RestageWidget source through the '
            'production emit path — the shipped lowering is traceable',
      );
      final stamp = registration.toJson();
      // The builder's exact serialization of the stamp document.
      final emittedStamp = const JsonEncoder.withIndent('  ').convert(stamp);

      final committedStamp = File.fromUri(
        exampleLibDir.resolve('restage_a2ui_catalog.a2ui.json'),
      ).readAsStringSync();

      expect(
        emittedStamp,
        committedStamp,
        reason: 'the committed example capability stamp must regenerate '
            'byte-for-byte from the example @RestageWidget source through the '
            'production emit path — the shipped capability surface is '
            'traceable',
      );
    },
  );

  test(
    'an RFW-admitted record property leaves A2UI catalog bytes unchanged',
    () async {
      final recordSource = _recordPackageSource(includeRecord: true);
      final removedSource = _recordPackageSource(includeRecord: false);

      final rfwRecord = await runWidgetVisitorOn(
        {'lib/record_card.dart': recordSource},
      );
      expect(
        rfwRecord.widgets.single.properties.map((property) => property.name),
        ['heading'],
        reason: 'the control package must carry an RFW-admitted record',
      );

      final a2uiRecord = await runWidgetVisitorOn(
        {'lib/record_card.dart': recordSource},
        target: WidgetVisitorTarget.a2ui,
      );
      final a2uiRemoved = await runWidgetVisitorOn(
        {'lib/record_card.dart': removedSource},
        target: WidgetVisitorTarget.a2ui,
      );

      // The current A2UI catalog property path rejects records before
      // projection, while a String control would intentionally add `heading`
      // and change the catalog. Removing the record is therefore the
      // byte-neutral comparison for this harness.
      expect(a2uiRecord.widgets.single.properties, isEmpty);
      expect(
        _encodedA2uiCatalog(_visitorCatalog(a2uiRecord)),
        orderedEquals(_encodedA2uiCatalog(_visitorCatalog(a2uiRemoved))),
        reason: 'omitting the record must be the only A2UI projection effect',
      );
    },
  );
}
