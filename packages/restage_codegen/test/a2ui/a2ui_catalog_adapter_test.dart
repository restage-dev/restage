import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart'
    show classifyA2uiCatalogDart;
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A catalog mixing built-in widgets with a custom library that declares a
/// capability version.
Catalog _mixedCatalog({int? acmeCapabilityVersion = 3}) {
  const acme = WidgetLibrary.custom('acme.widgets');
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      acme: LibraryInfo(
        version: '1.0.0',
        capabilityVersion: acmeCapabilityVersion,
      ),
    },
    widgets: [
      entry(name: 'Text', properties: []),
      entry(name: 'FilledButton', properties: [], sinceVersion: 2),
      // A custom widget whose sinceVersion (5) must NOT raise the built-in
      // floor — its capability lives in the custom-library axis.
      entry(
        name: 'AcmeBanner',
        properties: [],
        library: acme,
        sinceVersion: 5,
      ),
    ],
  );
}

void main() {
  group('emitA2uiCatalog — components', () {
    test('injects the discriminator into the per-property data schema', () {
      // emitA2uiCatalog emits over the A2UI-emittable set, so the fixtures use
      // emittable widgets (scalar/enum/child-with-field), never an unrealistic
      // children-slot-without-a-children-field (which scopes out of both arts).
      // The component schema replicates genui's `CatalogItem.dataSchema`
      // getter: the data properties plus a `component` const-enum, `component`
      // ahead of the data's required set, and NO `additionalProperties`.
      final catalog = catalogWith([
        entry(
          name: 'Text',
          properties: [prop('text', PropertyType.string, required: true)],
        ),
        entry(name: 'Column', properties: [prop('spacing', PropertyType.real)]),
      ]);

      final result = emitA2uiCatalog(catalog);

      expect(
        result.components.map((c) => c.name).toSet(),
        {'Text', 'Column'},
      );

      // A REQUIRED scalar property: carried in `properties` alongside the
      // `component` discriminator AND added to `required`.
      final text = result.components.firstWhere((c) => c.name == 'Text');
      expect(text.dataSchema, {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'component': {
            'type': 'string',
            'enum': ['Text'],
          },
        },
        'required': ['component', 'text'],
      });

      // An OPTIONAL property: carried in `properties` but NOT in `required`.
      final column = result.components.firstWhere((c) => c.name == 'Column');
      expect(column.dataSchema, {
        'type': 'object',
        'properties': {
          'spacing': {'type': 'number'},
          'component': {
            'type': 'string',
            'enum': ['Column'],
          },
        },
        'required': ['component'],
      });
    });

    test('a component with no data fields is the bare discriminator', () {
      final result = emitA2uiCatalog(
        catalogWith([entry(name: 'Spacer', properties: [])]),
      );
      expect(result.components.single.dataSchema, {
        'type': 'object',
        'properties': {
          'component': {
            'type': 'string',
            'enum': ['Spacer'],
          },
        },
        'required': ['component'],
      });
    });

    test('manifest component set == the Dart CatalogItem set (no divergence)',
        () {
      // The manifest (catalog.json) and the Dart CatalogItem set must agree by
      // construction: a widget scoped out of one is scoped out of the other.
      final catalog = catalogWith([
        entry(
          name: 'Emittable',
          properties: [prop('label', PropertyType.string)],
        ),
        // A children slot with no children field is A2UI-unemittable — it must
        // be absent from BOTH artifacts.
        entry(name: 'Dropped', childrenSlot: ChildrenSlot.list, properties: []),
      ]);

      final manifestNames =
          emitA2uiCatalog(catalog).components.map((c) => c.name).toSet();
      final dartItemNames = classifyA2uiCatalogDart(catalog)
          .widgets
          .map((plan) => plan.entry.name)
          .toSet();

      expect(manifestNames, dartItemNames);
      expect(manifestNames, {'Emittable'});
      expect(manifestNames, isNot(contains('Dropped')));
    });
  });

  group('emitA2uiCatalog — the built-in content-version axis', () {
    test('is the max sinceVersion over BUILT-IN widgets only', () {
      final result = emitA2uiCatalog(_mixedCatalog());
      // Text@1, FilledButton@2 are built-in; AcmeBanner@5 is custom and must
      // NOT raise the built-in floor.
      expect(result.stamp.catalogContentVersion, 2);
    });

    test('a built-in-only catalog matches Catalog.contentVersion', () {
      final catalog = catalogWith([
        entry(name: 'A', properties: []),
        entry(name: 'B', properties: [], sinceVersion: 3),
      ]);
      expect(
        emitA2uiCatalog(catalog).stamp.catalogContentVersion,
        catalog.contentVersion,
      );
    });

    test('an empty catalog floors at the baseline with no libraries', () {
      final result = emitA2uiCatalog(catalogWith([]));
      expect(result.components, isEmpty);
      expect(result.stamp.catalogContentVersion, 1);
      expect(result.stamp.availableLibraries, isEmpty);
    });
  });

  group('emitA2uiCatalog — the custom-library axis', () {
    test('carries present custom libraries with their capability version', () {
      final result = emitA2uiCatalog(_mixedCatalog());
      expect(result.stamp.availableLibraries, [
        const A2uiLibraryCapability(namespace: 'acme.widgets', version: 3),
      ]);
      // The custom component is still emitted into the flat catalog.
      expect(
        result.components.map((c) => c.name),
        containsAll(<String>['Text', 'FilledButton', 'AcmeBanner']),
      );
    });

    test('throws when a present custom library declares no capability version',
        () {
      expect(
        () => emitA2uiCatalog(_mixedCatalog(acmeCapabilityVersion: null)),
        throwsArgumentError,
      );
    });
  });

  group('emitA2uiCatalog — duplicate component names fail loud', () {
    test('throws on a same-library duplicate name', () {
      final catalog = catalogWith([
        entry(name: 'Dup', properties: []),
        entry(name: 'Dup', properties: [], sinceVersion: 2),
      ]);
      expect(() => emitA2uiCatalog(catalog), throwsArgumentError);
    });

    test('throws on a cross-library duplicate name', () {
      final catalog = catalogWith([
        entry(name: 'Button', properties: []),
        entry(name: 'Button', properties: [], library: WidgetLibrary.material),
      ]);
      expect(() => emitA2uiCatalog(catalog), throwsArgumentError);
    });
  });

  group('emitA2uiCatalog — interactive parity with the Dart emitter', () {
    test('an interactive widget the Dart path keeps is in the manifest too',
        () {
      // The manifest and the Dart CatalogItem set must agree by construction. A
      // required interactive callback is LOWERED on the Dart path (the widget
      // is emitted); the manifest must see the SAME eventSeam so it keeps the
      // widget too — not drop it via the catalog-fed required-`eventProperty`
      // path. Without threading the seam, the two artifacts diverge.
      final catalog = catalogWith([
        entry(
          name: 'IconButton',
          flutterType: 'package:fixture/fixture.dart#IconButton',
          properties: [
            prop('icon', PropertyType.string, required: true),
            prop('onPressed', PropertyType.event, required: true),
          ],
        ),
      ]);
      final seam = <(String, String), A2uiCallbackSignature>{
        ('IconButton', 'onPressed'): const A2uiCallbackDispatch(),
      };

      final dartSet = classifyA2uiCatalogDart(catalog, eventSeam: seam)
          .widgets
          .map((w) => w.entry.name)
          .toSet();
      expect(dartSet, contains('IconButton'));

      final manifestSet = emitA2uiCatalog(catalog, eventSeam: seam)
          .components
          .map((c) => c.name)
          .toSet();
      expect(manifestSet, dartSet);
    });

    test('a built-in catalog (no seam) is byte-neutral on the manifest path',
        () {
      // No seam → identical to before the parameter existed.
      final catalog = catalogWith([
        entry(name: 'Text', properties: [prop('text', PropertyType.string)]),
      ]);
      expect(
        emitA2uiCatalog(catalog).components.map((c) => c.name).toSet(),
        {'Text'},
      );
    });
  });
}
