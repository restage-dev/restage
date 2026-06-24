import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'example_registry.dart';

void main() {
  group('example registry — schema-lock smoke', () {
    test('exercises decomposes, flutterType, and per-library lookup', () {
      expect(kExampleRegistry.schemaVersion, kSupportedSchemaVersion);
      expect(kExampleRegistry.widgets.length, 3);
      final byName = {
        for (final w in kExampleRegistry.widgets) w.name: w,
      };
      expect(byName['SizedBox']!.decomposes, isEmpty);
      expect(
        byName['SizedBox']!.flutterType,
        'package:flutter/widgets.dart#SizedBox',
      );
      expect(byName['Text']!.decomposes, hasLength(1));
      final textRecipe = byName['Text']!.decomposes.first;
      expect(textRecipe.structuredRef.wireId, WireId('s0001'));
      expect(
        textRecipe.flatProperties[WireId('p0501')],
        WireId('p0004'),
      );
      expect(byName['Container']!.decomposes, hasLength(2));
      final structured = byName['Container']!
          .decomposes
          .map((r) => r.structuredRef.wireId.value)
          .toSet();
      expect(structured, {'s0002', 's0003'});
    });

    test('round-trips through encodeCatalog / decodeCatalog (v4 canonical)',
        () {
      final encoded = encodeCatalog(kExampleRegistry);
      final decoded = decodeCatalog(encoded);
      expect(decoded.schemaVersion, kSupportedSchemaVersion);
      expect(decoded.widgets.length, kExampleRegistry.widgets.length);
      for (var i = 0; i < decoded.widgets.length; i++) {
        final original = kExampleRegistry.widgets[i];
        final reborn = decoded.widgets[i];
        expect(reborn.wireId, original.wireId);
        expect(reborn.name, original.name);
        expect(reborn.flutterType, original.flutterType);
        expect(reborn.decomposes.length, original.decomposes.length);
        for (var j = 0; j < reborn.decomposes.length; j++) {
          expect(
            reborn.decomposes[j].structuredRef,
            original.decomposes[j].structuredRef,
          );
          expect(
            reborn.decomposes[j].flatProperties,
            equals(original.decomposes[j].flatProperties),
          );
        }
      }
    });

    test('per-library entry counts are computed off the catalog', () {
      // Counts are derived from the entry lists, not a stored denormalized
      // value. This fixture lists three core widgets and no structured /
      // union / token *entries* (the widgets reference structured types via
      // decompose recipes, but the catalog declares no StructuredEntry list).
      expect(kExampleRegistry.widgetsIn(WidgetLibrary.core).length, 3);
      expect(kExampleRegistry.structuredTypesIn(WidgetLibrary.core), isEmpty);
      expect(kExampleRegistry.unionsIn(WidgetLibrary.core), isEmpty);
      expect(kExampleRegistry.designTokensIn(WidgetLibrary.core), isEmpty);
    });

    test('lookup by name and library works across decomposed entries', () {
      final w = kExampleRegistry.findByName('Text', WidgetLibrary.core);
      expect(w, isNotNull);
      expect(w!.flutterType, 'package:flutter/widgets.dart#Text');
    });
  });
}
