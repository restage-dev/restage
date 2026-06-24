import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = 'restage.core';
const _at = '2026-05-11T12:00:00Z';
const _by = 'rfw_catalog_compiler@0.1.0';

void main() {
  group('WireIdAllocator structured + variant allocation', () {
    test(
        'fresh allocation emits one s* event, one p* per field, one v* per '
        'variant in declaration order', () {
      final catalog = _catalog(
        structuredTypes: [
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'BoxDecoration',
            fields: [
              _field('color'),
              _field('image'),
              _field('border'),
              _field('borderRadius'),
              _field('boxShadow'),
            ],
            variants: [
              _variant(
                sourceKind: VariantSourceKind.constructor,
              ),
              _variant(
                sourceKind: VariantSourceKind.staticGetter,
                staticAccessor: 'zero',
              ),
              _variant(
                sourceKind: VariantSourceKind.staticMethod,
                staticAccessor: 'lerp',
              ),
            ],
          ),
        ],
      );

      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);
      final events = allocator.allocateCatalog(catalog, WidgetLibrary.core);

      final allocEvents = events.whereType<AllocWireIdEvent>().toList();
      expect(events, hasLength(allocEvents.length));

      final structured = allocEvents
          .where((event) => event.type == WireIdKind.structured)
          .toList();
      final properties = allocEvents
          .where((event) => event.type == WireIdKind.property)
          .toList();
      final variants = allocEvents
          .where((event) => event.type == WireIdKind.variant)
          .toList();

      expect(structured, hasLength(1));
      expect(properties, hasLength(5));
      expect(variants, hasLength(3));

      expect(structured.single.id, WireId('s0001'));
      expect(structured.single.name, 'BoxDecoration');

      expect(
        properties.map((event) => event.name).toList(),
        ['color', 'image', 'border', 'borderRadius', 'boxShadow'],
      );
      expect(
        properties.map((event) => event.id.value).toList(),
        ['p0001', 'p0002', 'p0003', 'p0004', 'p0005'],
      );
      expect(
        properties.every((event) => event.owner == WireId('s0001')),
        isTrue,
      );

      expect(
        variants.map((event) => event.id.value).toList(),
        ['v0001', 'v0002', 'v0003'],
      );
      expect(
        variants.map((event) => event.sourceKind).toList(),
        [
          VariantSourceKind.constructor,
          VariantSourceKind.staticGetter,
          VariantSourceKind.staticMethod,
        ],
      );
      expect(
        variants.map((event) => event.staticAccessor).toList(),
        [null, 'zero', 'lerp'],
      );
      expect(
        variants.every((event) => event.owner == WireId('s0001')),
        isTrue,
      );
    });

    test(
        're-running the allocator against the now-allocated catalog produces '
        'zero new events', () {
      final initial = _catalog(
        structuredTypes: [
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'EdgeInsets',
            fields: [_field('left'), _field('top')],
            variants: [
              _variant(
                sourceKind: VariantSourceKind.constructor,
              ),
              _variant(
                sourceKind: VariantSourceKind.staticGetter,
                staticAccessor: 'zero',
              ),
            ],
          ),
        ],
      );

      final first = WireIdAllocator(library: _library, at: _at, by: _by);
      final firstPass = first.allocateCatalog(initial, WidgetLibrary.core);
      expect(firstPass, isNotEmpty);

      // Replace the unallocated sentinels with the freshly-assigned IDs from
      // the first pass and re-run a fresh allocator seeded with the events.
      final allocatedStructured = first.currentState.structuredTypes.values
          .firstWhere((entry) => entry.name == 'EdgeInsets');
      final propsByName = {
        for (final entry in first.currentState.properties.values)
          entry.name!: entry.id,
      };
      final variantIds = first.currentState.variants.values
          .map((entry) => entry.id)
          .toList(growable: false);

      final allocated = _catalog(
        structuredTypes: [
          _structured(
            wireId: allocatedStructured.id,
            name: 'EdgeInsets',
            fields: [
              _field('left', wireId: propsByName['left']),
              _field('top', wireId: propsByName['top']),
            ],
            variants: [
              _variant(
                wireId: variantIds[0],
                sourceKind: VariantSourceKind.constructor,
              ),
              _variant(
                wireId: variantIds[1],
                sourceKind: VariantSourceKind.staticGetter,
                staticAccessor: 'zero',
              ),
            ],
          ),
        ],
      );

      final second = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: first.events,
      );
      final secondPass = second.allocateCatalog(allocated, WidgetLibrary.core);

      expect(secondPass, isEmpty);
      expect(second.events, first.events);
    });

    test('multi-structured allocation preserves catalog declaration order', () {
      final catalog = _catalog(
        structuredTypes: [
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'Alpha',
            fields: [_field('a')],
          ),
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'Beta',
            fields: [_field('b1'), _field('b2')],
            variants: [
              _variant(sourceKind: VariantSourceKind.constructor),
            ],
          ),
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'Gamma',
            fields: [_field('g')],
            variants: [
              _variant(sourceKind: VariantSourceKind.constructor),
              _variant(
                sourceKind: VariantSourceKind.staticGetter,
                staticAccessor: 'zero',
              ),
            ],
          ),
        ],
      );

      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);
      final events = allocator
          .allocateCatalog(catalog, WidgetLibrary.core)
          .whereType<AllocWireIdEvent>()
          .toList();

      final structured =
          events.where((event) => event.type == WireIdKind.structured).toList();
      expect(
        structured.map((event) => event.id.value).toList(),
        ['s0001', 's0002', 's0003'],
      );
      expect(
        structured.map((event) => event.name).toList(),
        ['Alpha', 'Beta', 'Gamma'],
      );

      final properties =
          events.where((event) => event.type == WireIdKind.property).toList();
      // Properties are interleaved with their owning structured in the
      // emission order: Alpha.a → Beta.b1 → Beta.b2 → Gamma.g.
      expect(
        properties.map((event) => event.name).toList(),
        ['a', 'b1', 'b2', 'g'],
      );
      expect(
        properties.map((event) => event.owner!.value).toList(),
        ['s0001', 's0002', 's0002', 's0003'],
      );
      expect(
        properties.map((event) => event.id.value).toList(),
        ['p0001', 'p0002', 'p0003', 'p0004'],
      );

      final variants =
          events.where((event) => event.type == WireIdKind.variant).toList();
      // Beta has one variant, Gamma has two; allocator interleaves variants
      // with their owning structured.
      expect(
        variants.map((event) => event.owner!.value).toList(),
        ['s0002', 's0003', 's0003'],
      );
      expect(
        variants.map((event) => event.id.value).toList(),
        ['v0001', 'v0002', 'v0003'],
      );
    });
  });
}

Catalog _catalog({
  List<StructuredEntry> structuredTypes = const [],
}) {
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: _at,
    libraries: {
      WidgetLibrary.core: LibraryInfo(version: '0.1.0'),
    },
    widgets: const [],
    structuredTypes: structuredTypes,
  );
}

StructuredEntry _structured({
  required WireId wireId,
  required String name,
  List<StructuredField> fields = const [],
  List<FactoryVariant> variants = const [],
}) {
  return StructuredEntry(
    wireId: wireId,
    name: name,
    library: WidgetLibrary.core,
    description: 'A structured type.',
    sourceType: 'src#$name',
    fields: fields,
    variants: variants,
  );
}

StructuredField _field(String name, {WireId? wireId}) {
  return StructuredField(
    wireId: wireId ?? WireId.unallocatedProperty,
    name: name,
    type: PropertyType.real,
    description: '',
  );
}

FactoryVariant _variant({
  required VariantSourceKind sourceKind,
  WireId? wireId,
  String? namedConstructor,
  String? staticAccessor,
}) {
  final id = wireId ?? WireId.unallocatedVariant;
  switch (sourceKind) {
    case VariantSourceKind.constructor:
      return ConstructorVariant(
        wireId: id,
        namedConstructor: namedConstructor,
      );
    case VariantSourceKind.staticMethod:
      return StaticMethodVariant(
        wireId: id,
        staticAccessor: staticAccessor!,
      );
    case VariantSourceKind.staticGetter:
      return StaticGetterVariant(
        wireId: id,
        staticAccessor: staticAccessor!,
      );
    case VariantSourceKind.constValue:
      return ConstValueVariant(
        wireId: id,
        staticAccessor: staticAccessor!,
      );
  }
}
