import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// A minimal valid widget entry. [sinceVersion] defaults to the schema
/// default so a caller only sets it when exercising a non-baseline widget.
WidgetEntry _widget({
  String wireId = 'w0001',
  String name = 'Foo',
  int? sinceVersion,
}) =>
    WidgetEntry(
      wireId: WireId(wireId),
      name: name,
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A $name.',
      flutterType: 'package:flutter/widgets.dart#$name',
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: const [],
      sinceVersion: sinceVersion ?? kBaselineCatalogVersion,
    );

Catalog _catalog(List<WidgetEntry> widgets) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-06-19T00:00:00Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: widgets,
    );

/// The first widget's JSON object out of an encoded catalog string.
Map<String, dynamic> _firstWidgetJson(String encoded) {
  final decoded = jsonDecode(encoded) as Map<String, dynamic>;
  final widgets = decoded['widgets'] as List<dynamic>;
  return widgets.first as Map<String, dynamic>;
}

void main() {
  group('WidgetEntry.sinceVersion', () {
    test('defaults to the baseline catalog content version', () {
      final entry = WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Foo',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'A foo.',
        flutterType: 'package:flutter/widgets.dart#Foo',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: const [],
      );

      expect(entry.sinceVersion, kBaselineCatalogVersion);
      expect(kBaselineCatalogVersion, 1);
    });

    test('carries an explicit above-baseline version', () {
      final entry = _widget(sinceVersion: 4);

      expect(entry.sinceVersion, 4);
    });
  });

  group('Catalog.contentVersion', () {
    test('is the baseline for a catalog of only baseline widgets', () {
      final catalog = _catalog([
        _widget(),
        _widget(wireId: 'w0002', name: 'Bar'),
      ]);

      expect(catalog.contentVersion, kBaselineCatalogVersion);
    });

    test('is the baseline for an empty catalog', () {
      final catalog = _catalog(const []);

      expect(catalog.contentVersion, kBaselineCatalogVersion);
    });

    test('is the max sinceVersion across widgets', () {
      final catalog = _catalog([
        _widget(),
        _widget(wireId: 'w0002', name: 'Bar', sinceVersion: 3),
        _widget(wireId: 'w0003', name: 'Baz', sinceVersion: 2),
      ]);

      expect(catalog.contentVersion, 3);
    });
  });

  group('contentVersionOf (the single canonical formula)', () {
    test('is the baseline for an empty widget set', () {
      expect(contentVersionOf(const []), kBaselineCatalogVersion);
    });

    test('is the max sinceVersion across the widgets', () {
      expect(
        contentVersionOf([
          _widget(),
          _widget(wireId: 'w0002', name: 'Bar', sinceVersion: 3),
          _widget(wireId: 'w0003', name: 'Baz', sinceVersion: 2),
        ]),
        3,
      );
    });

    test('Catalog.contentVersion delegates to it', () {
      final catalog = _catalog([
        _widget(sinceVersion: 5),
        _widget(wireId: 'w0002', name: 'Bar', sinceVersion: 2),
      ]);

      expect(catalog.contentVersion, contentVersionOf(catalog.widgets));
    });

    test('max over a union equals the max of per-subset maxes', () {
      // The property the A2UI built-in-floor relies on: the merged built-in
      // catalog's content version equals the max of the per-library content
      // versions (max-over-union == max-of-maxes), so a per-library-derived
      // SDK constant and a merged-catalog derivation cannot disagree.
      final core = [_widget(sinceVersion: 2)];
      final material = [_widget(wireId: 'w0002', name: 'Bar', sinceVersion: 4)];
      expect(
        contentVersionOf([...core, ...material]),
        [contentVersionOf(core), contentVersionOf(material)]
            .reduce((a, b) => a > b ? a : b),
      );
    });
  });

  group('sinceVersion through the catalog codec', () {
    test('omits sinceVersion at the baseline (byte-neutral)', () {
      final encoded = encodeCatalog(_catalog([_widget()]));

      expect(_firstWidgetJson(encoded).containsKey('sinceVersion'), isFalse);
    });

    test('emits sinceVersion when above the baseline', () {
      final encoded = encodeCatalog(_catalog([_widget(sinceVersion: 5)]));

      expect(_firstWidgetJson(encoded)['sinceVersion'], 5);
    });

    test('round-trips an above-baseline sinceVersion', () {
      final decoded = decodeCatalog(
        encodeCatalog(_catalog([_widget(sinceVersion: 7)])),
      );

      expect(decoded.widgets.single.sinceVersion, 7);
      expect(decoded.contentVersion, 7);
    });

    test('decodes an absent sinceVersion as the baseline', () {
      // A catalog whose widget JSON has no `sinceVersion` key (the baseline
      // emission) decodes to the baseline — the existing committed catalogs
      // remain decodable unchanged.
      final encoded = encodeCatalog(_catalog([_widget()]));
      expect(encoded.contains('sinceVersion'), isFalse);

      final decoded = decodeCatalog(encoded);

      expect(decoded.widgets.single.sinceVersion, kBaselineCatalogVersion);
    });

    test('rejects a sinceVersion below the baseline', () {
      final encoded = encodeCatalog(_catalog([_widget(sinceVersion: 3)]));
      final tampered =
          encoded.replaceFirst('"sinceVersion": 3', '"sinceVersion": 0');

      expect(
        () => decodeCatalog(tampered),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('rejects a non-integer sinceVersion', () {
      final encoded = encodeCatalog(_catalog([_widget(sinceVersion: 3)]));
      final tampered =
          encoded.replaceFirst('"sinceVersion": 3', '"sinceVersion": "three"');

      expect(
        () => decodeCatalog(tampered),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('rejects an explicit null sinceVersion (not treated as absent)', () {
      // Absent ⇒ baseline, but a present explicit `null` is malformed and must
      // fail loud rather than silently normalize to the baseline.
      final encoded = encodeCatalog(_catalog([_widget(sinceVersion: 3)]));
      final tampered =
          encoded.replaceFirst('"sinceVersion": 3', '"sinceVersion": null');

      expect(
        () => decodeCatalog(tampered),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('sinceVersion must be an integer'),
          ),
        ),
      );
    });
  });
}
