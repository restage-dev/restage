// Regression guards for the catalog-compiler architecture-hygiene cleanup:
//   * the unimplemented top-level facade is gone from the public surface,
//   * the wire-ID backfill resolver remains reachable after its file move, and
//   * adapter-constructed catalog IR carries no analyzer elements, so lowering
//     a reflected catalog never dereferences the element placeholders.
import 'dart:io';

import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('public barrel surface', () {
    // Read the barrel source directly so the guard does not depend on the
    // removed symbol still existing (referencing it would fail to compile).
    final barrel = File('lib/rfw_catalog_compiler.dart').readAsStringSync();

    test('no longer exports the unimplemented compiler facade', () {
      expect(
        barrel.contains("export 'src/compiler.dart';"),
        isFalse,
        reason: 'The unimplemented facade was removed; the real entry point '
            'is RestageCatalogGenAdapter.lowerCatalog.',
      );
      expect(
        barrel.contains('CatalogCompiler'),
        isFalse,
        reason: 'The throws-everything facade must not be re-introduced.',
      );
    });

    test('re-exports the wire-ID backfill resolver from its moved location',
        () {
      expect(
        barrel.contains("export 'src/wire_ids/wire_id_backfill.dart';"),
        isTrue,
        reason: 'The backfill resolver moved under src/wire_ids/ and must '
            'still be re-exported from the public barrel.',
      );
    });

    test('the wire-ID backfill resolver type resolves through the barrel', () {
      // A compile-time reference: if the moved file were not re-exported, the
      // suite would fail to resolve this type.
      const resolverType = RestageCatalogGenEventLogWireIdResolver;
      expect(resolverType, isNotNull);
    });
  });

  group('adapter-constructed IR is element-free', () {
    test('lowers a reflected catalog without dereferencing element fields', () {
      // The adapter builds compiler IR from an already-reflected catalog. That
      // IR carries placeholder analyzer-element fields that must never be read.
      // A successful end-to-end lowering proves the lowering path never touches
      // them (any access throws StateError by construction).
      const widget = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        flutterType: 'package:flutter/widgets.dart#Text',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'text',
            type: PropertyType.string,
            description: 'Text to display.',
            required: true,
          ),
        ],
      );

      final catalog = const RestageCatalogGenAdapter().lowerCatalog(
        library: WidgetLibrary.core,
        version: '1.0.0',
        generatedAt: '2026-05-12T00:00:00.000Z',
        widgets: [widget],
      );

      expect(catalog.widgetsIn(WidgetLibrary.core), hasLength(1));
      final lowered = catalog.widgets.single;
      expect(lowered.name, 'CatalogText');
      expect(lowered.flutterType, 'package:flutter/widgets.dart#Text');
      expect(lowered.properties.single.name, 'text');
      expect(lowered.library, WidgetLibrary.core);
      expect(lowered.childrenSlot, ChildrenSlot.none);
    });
  });
}
