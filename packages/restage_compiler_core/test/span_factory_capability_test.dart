import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.spans');
Catalog _catalog({WidgetLibrary library = _custom, int spanVersion = 1}) =>
    Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          library: const LibraryInfo(version: '1', capabilityVersion: 1),
        },
        widgets: [
          WidgetEntry(
              wireId: WireId('w0001'),
              name: 'CustomSpan',
              library: library,
              category: WidgetCategory.decoration,
              description: 'Native inline span',
              flutterType: 'package:example/span.dart#CustomSpan',
              childrenSlot: ChildrenSlot.none,
              properties: [
                PropertyEntry(
                    wireId: WireId('p0001'),
                    name: 'span',
                    sinceVersion: spanVersion,
                    type: PropertyType.inlineSpan,
                    description: 'Span')
              ])
        ]);
SurfaceCapabilityDerivation _derive(String source) =>
    deriveSurfaceCapability(rfw.parseLibraryFile(source), _catalog());
bool _accepted(SurfaceCapabilityDerivation result,
        {required int sdk, required int generated}) =>
    BlobRenderCapabilityGate.evaluate(
        required: CapabilityManifest(
            builtInFloor: result.builtInFloor,
            requiredLibraries: result.requiredLibraries),
        installed: InstalledCapability(
            builtInCatalogVersion: sdk,
            installedLibraries: [
              InstalledLibrary(
                  namespace: _custom.namespace,
                  version: 1,
                  generated: generated)
            ])).accepted;

void main() {
  test('canonical recursive span artifacts require SDK24; legacy remains22',
      () {
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    for (final (name, floor) in [
      ('span_collections_compiled', 24),
      ('span_collection_builder_compiled', 24),
      ('span_collection_controls_compiled', 24),
      ('span_builder_compiled', 22),
    ]) {
      final source =
          File('../restage_core/test/fixtures/$name.rfwtxt').readAsStringSync();
      final derived =
          deriveSurfaceCapability(rfw.parseLibraryFile(source), catalog);
      expect(derived.builtInFloor, floor, reason: name);
      for (final sdk in [23, 24]) {
        expect(
            BlobRenderCapabilityGate.evaluate(
                required: CapabilityManifest(
                    builtInFloor: derived.builtInFloor,
                    requiredLibraries: derived.requiredLibraries),
                installed: InstalledCapability(
                    builtInCatalogVersion: sdk,
                    installedLibraries: [])).accepted,
            sdk >= floor,
            reason: '$name SDK$sdk');
      }
    }
  });
  test('recursive and possibly empty span children require the new decoder',
      () {
    for (final span in [
      '{children: []}',
      '{children: [[{text: "x"}]]}',
      '{children: [...for row in data.rows: {text: row}]}',
      '{children: [...for row in []: {text: row}]}',
      '{children: [...for row in [0]: [{text: "x"}]]}',
      '{children: switch data.empty {true: [], default: [{text: "x"}]}}',
      '{children: [{text: "x", children: []}]}',
      '{children: [[{recognizer: {kind: "tap"}}]]}',
    ]) {
      final result = _derive('widget Root = CustomSpan(span: $span);');
      expect(result.builtInFloor, 24, reason: span);
      expect(result.requiredLibraries.single.minGenerated,
          span.contains('recognizer') ? 3 : 1,
          reason: span);
      expect(_accepted(result, sdk: 23, generated: 3), isFalse, reason: span);
      expect(_accepted(result, sdk: 24, generated: 3), isTrue, reason: span);
    }
    for (final source in [
      'widget Link = CustomSpan(span: args.wrapper.span); widget Root = Link(wrapper: {span: {children: [[{text: "x"}]]}});',
      'widget Link = switch data.done {true: CustomSpan(span: args.span), default: Link(span: args.next)}; widget Root = Link(span: {text: "plain"}, next: {children: [[{text: "x"}]]});',
    ]) expect(_derive(source).builtInFloor, 24, reason: source);
  });
  test('flat nonempty spans and ordinary widget groups retain old floors', () {
    for (final span in [
      '{text: "x"}',
      '{children: null}',
      '{children: [{text: "x"}]}',
      '{children: [...for row in [0]: {text: "x"}]}',
      '{children: [{text: "anchor"}, ...for row in data.rows: {text: row}]}',
      '{style: {children: [[{recognizer: {kind: "tap"}}]]}}',
    ])
      expect(_derive('widget Root = CustomSpan(span: $span);').builtInFloor, 1,
          reason: span);
    expect(
        _derive('widget Root = CustomSpan(span: {children: [{recognizer: {kind: "tap"}}]});')
            .builtInFloor,
        22);
    expect(
        _derive('widget Link = CustomSpan(span: {text: "plain"}); widget Root = Link(unused: {children: [[{recognizer: {kind: "tap"}}]]});')
            .builtInFloor,
        1);
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final library = rfw.parseLibraryFile(
        'widget Root = Column(children: [...for row in data.rows: [Text(text: row)]]);');
    expect(deriveSurfaceCapability(library, catalog).builtInFloor, 10);
  });
  test('grouped span recognizers retain their catalog property floor', () {
    // A higher catalog floor makes recognizer discovery observable independently
    // of the recursive-child decoder's SDK24 floor.
    final catalog = _catalog(library: WidgetLibrary.core, spanVersion: 25);
    final library = rfw.parseLibraryFile(
        'widget Root = CustomSpan(span: {children: [[{recognizer: {kind: "tap"}}]]});');
    expect(deriveSurfaceCapability(library, catalog).builtInFloor, 25);
  });
  test('nested span fragments retain typed native preview and authority checks',
      () {
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final library = rfw.parseLibraryFile(
        'widget Link = TextRich(textSpan: args.span); widget Root = Link(span: {children: data.context.children});');
    const color = NativeBindingContract(type: 'flutter.Color');
    const recognizer = NativeBindingContract(type: 'flutter.GestureRecognizer');
    for (final leaf in [
      {
        'style': {'color': color.reference('color')}
      },
      {'recognizer': recognizer.reference('recognizer')},
    ]) {
      expect(
          nativeBindingsNeedInstalledHost(library, catalog, context: {
            'children': [
              [leaf]
            ]
          }),
          isTrue);
    }
    expect(
        nativeBindingsNeedInstalledHost(library, catalog, context: {
          'children': [
            [
              {
                'text': 'plain',
                'style': {'color': 4278190080}
              }
            ]
          ]
        }),
        isFalse);
    final invalid = rfw.parseLibraryFile(
        'widget Root = TextRich(textSpan: {children: [[{style: {color: {kind: "nativeLocal", slot: "missing", type: "flutter.Color", nullable: false}}}]]});');
    expect(
        () => deriveSurfaceCapability(invalid, catalog), throwsFormatException);
    // Native-looking fields outside decoder-read paths remain ordinary data.
    expect(
        nativeBindingsNeedInstalledHost(library, catalog, context: {
          'children': [
            [
              {'text': 'plain', 'unused': color.reference('color')}
            ]
          ]
        }),
        isFalse);
  });

  test('custom interactive span use requires SDK22 and owning factory3', () {
    for (final source in [
      'widget Root = CustomSpan(span: {recognizer: {kind: "tap", onTap: event "go" {}}});',
      'widget Link = CustomSpan(span: args.span); widget Root = Link(span: {children: [{recognizer: {kind: "tap"}}]});',
      'widget Link = CustomSpan(span: args.span); widget Forward = Link(span: args.wrapper.span); widget Root = Forward(wrapper: {span: {children: [{recognizer: {kind: "tap"}}]}});',
      'widget Link = switch data.done {true: CustomSpan(span: args.span), default: Link(span: args.next)}; widget Root = Link(span: {text: "plain"}, next: {recognizer: {kind: "tap"}});',
    ]) {
      final result = _derive(source);
      expect([
        result.builtInFloor,
        result.requiredLibraries.single.minGenerated
      ], [
        22,
        3
      ], reason: source);
      expect(_accepted(result, sdk: 21, generated: 3), isFalse);
      expect(_accepted(result, sdk: 22, generated: 2), isFalse);
      expect(_accepted(result, sdk: 22, generated: 3), isTrue);
    }
  });
  test('local typed exact color forwarding retains SDK19 and custom factory3',
      () {
    final core = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    const color = '{a: 0.8, r: 0.2, g: 0.3, b: 0.4, colorSpace: "displayP3"}';
    final builtIn = deriveSurfaceCapability(
        rfw.parseLibraryFile(
            'widget Link = ColoredBox(color: args.color); widget Root = Link(color: $color);'),
        core);
    expect(builtIn.builtInFloor, 19);
    final catalog = _catalog();
    final widget = catalog.widgets.single;
    final customColor = Catalog(
        schemaVersion: catalog.schemaVersion,
        generatedAt: catalog.generatedAt,
        libraries: catalog.libraries,
        widgets: [
          WidgetEntry(
              wireId: widget.wireId,
              name: widget.name,
              library: widget.library,
              category: widget.category,
              description: widget.description,
              flutterType: widget.flutterType,
              childrenSlot: widget.childrenSlot,
              properties: [
                PropertyEntry(
                    wireId: WireId('p0001'),
                    name: 'color',
                    type: PropertyType.color,
                    description: 'Color')
              ])
        ]);
    final custom = deriveSurfaceCapability(
        rfw.parseLibraryFile(
            'widget Link = CustomSpan(color: args.wrapper.color); widget Root = Link(wrapper: {color: $color});'),
        customColor);
    expect([custom.builtInFloor, custom.requiredLibraries.single.minGenerated],
        [19, 3]);
  });
  test('inert custom spans and unrelated maps retain their existing floors',
      () {
    for (final source in [
      'widget Root = CustomSpan(span: {text: "plain"});',
      'widget Link = CustomSpan(span: args.span); widget Root = Link(span: {children: [{text: "plain", recognizer: null}]});',
      'widget Root = CustomSpan(span: {style: {recognizer: {kind: "tap"}}});',
      'widget Link = CustomSpan(span: {text: "plain"}); widget Root = Link(unused: {recognizer: {kind: "tap"}});',
    ]) {
      final result = _derive(source);
      expect(result.builtInFloor, 1, reason: source);
      expect(result.requiredLibraries.single.minGenerated, 1, reason: source);
      expect(_accepted(result, sdk: 1, generated: 1), isTrue);
    }
  });
}
