import 'dart:convert';

import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Customer structured wire-ID allocation extends the codegen replay-match
/// model with structured/field/variant/parameter kinds. The load-bearing
/// invariant: structured allocation runs STRICTLY AFTER widget/property
/// allocation, so structured fields (which share the `p*` counter) append past
/// the existing `p*` without shifting any existing `w*`/`p*` id (byte-neutral).

const _pkg = 'acme';
const _at = '2026-05-26T00:00:00.000Z';
const _by = 'restage-codegen-user-catalog-allocator';

/// A seed event log with two widgets + their properties already allocated
/// (`w0001` AcmeBorder{child,color} -> p0001/p0002), and ZERO structured
/// entries — the shape of the real committed customer log before this feature.
String _seedJsonl() => [
      {
        'at': _at,
        'by': _by,
        'id': 'w0001',
        'kind': 'alloc',
        'name': 'AcmeBorder',
        'source': 'package:acme/a.dart#AcmeBorder',
        'type': 'widget',
      },
      {
        'at': _at,
        'by': _by,
        'id': 'p0001',
        'kind': 'alloc',
        'name': 'child',
        'owner': 'w0001',
        'source': 'package:acme/a.dart#AcmeBorder.child',
        'type': 'property',
      },
      {
        'at': _at,
        'by': _by,
        'id': 'p0002',
        'kind': 'alloc',
        'name': 'color',
        'owner': 'w0001',
        'source': 'package:acme/a.dart#AcmeBorder.color',
        'type': 'property',
      },
    ].map(jsonEncode).join('\n');

WidgetEntry _acmeBorder() => const WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'AcmeBorder',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.decoration,
      description: '',
      flutterType: 'package:acme/a.dart#AcmeBorder',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'color',
          type: PropertyType.color,
          description: '',
        ),
      ],
    );

StructuredField _field(String name, PropertyType type) => StructuredField(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: '',
      valueShape: ScalarShape(propertyType: type),
    );

FactoryParameter _param(String name, PropertyType type) => FactoryParameter(
      wireId: WireId.unallocatedParameter,
      name: name,
      kind: FactoryParameterKind.named,
      required: true,
      nullable: false,
      defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
      valueShape: ScalarShape(propertyType: type),
    );

const _sentinelStructuredRef = WireIdRef(
  library: 'acme.design_system',
  wireId: WireId.unallocatedStructured,
);

/// A widget with a single structured property `badge` whose `structuredRef`
/// (top-level AND on its `StructuredShape` valueShape) is the bare sentinel,
/// targeting `Badge` via `slotTargets`.
WidgetEntry _badgeCard() => const WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'BadgeCard',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.decoration,
      description: '',
      flutterType: 'package:acme/c.dart#BadgeCard',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'badge',
          type: PropertyType.structured,
          description: '',
          structuredRef: _sentinelStructuredRef,
          valueShape: StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: _sentinelStructuredRef,
          ),
        ),
      ],
    );

/// Badge{label:String, count:int} with the canonical unnamed ctor variant.
StructuredEntry _badge() => StructuredEntry(
      wireId: WireId.unallocatedStructured,
      name: 'Badge',
      library: const WidgetLibrary.custom('acme.design_system'),
      description: '',
      sourceType: 'package:acme/b.dart#Badge',
      fields: [
        _field('label', PropertyType.string),
        _field('count', PropertyType.integer),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId.unallocatedVariant,
          argMappings: const {
            'label': ArgMapping(targetFields: [WireId.unallocatedProperty]),
            'count': ArgMapping(targetFields: [WireId.unallocatedProperty]),
          },
          parameters: [
            _param('label', PropertyType.string),
            _param('count', PropertyType.integer),
          ],
        ),
      ],
    );

void main() {
  group('customer structured allocation — replay-match, after-widgets', () {
    test(
        'appends s*/v*/a* and continues p* past the existing widget props, '
        'leaving every existing w*/p* id byte-stable', () {
      final seed = parseWireIdEventsJsonl(_seedJsonl(), sourceDescription: 'x');
      final allocation = allocateUserCatalogFromWidgets(
        package: _pkg,
        widgets: [_acmeBorder()],
        structuredTypes: [_badge()],
        existingEvents: seed,
      );
      final catalog = allocation.catalog;

      // Existing widget/property ids byte-stable.
      final widget = catalog.widgets.single;
      expect(widget.wireId, WireId('w0001'));
      expect(
        widget.properties.map((p) => p.wireId.value),
        ['p0001', 'p0002'],
      );

      // The structured entry appends s0001; its fields continue the p* counter
      // (past p0002) as p0003/p0004; the variant v0001; the params a0001/a0002.
      final badge = catalog.structuredTypes.single;
      expect(badge.wireId, WireId('s0001'));
      expect(badge.fields.map((f) => f.wireId.value), ['p0003', 'p0004']);
      final variant = badge.variants.single as ConstructorVariant;
      expect(variant.wireId, WireId('v0001'));
      expect(
        variant.parameters.map((p) => p.wireId.value),
        ['a0001', 'a0002'],
      );

      // Only the new structured ids are appended as events (no widget/property
      // re-allocation).
      expect(
        allocation.newEvents
            .whereType<AllocWireIdEvent>()
            .map((e) => e.id.value),
        ['s0001', 'p0003', 'p0004', 'v0001', 'a0001', 'a0002'],
      );
    });

    test(
        'is idempotent: replaying with the appended events as the new seed '
        'reproduces identical ids and mints nothing', () {
      final seed = parseWireIdEventsJsonl(_seedJsonl(), sourceDescription: 'x');
      final first = allocateUserCatalogFromWidgets(
        package: _pkg,
        widgets: [_acmeBorder()],
        structuredTypes: [_badge()],
        existingEvents: seed,
      );

      final second = allocateUserCatalogFromWidgets(
        package: _pkg,
        widgets: [_acmeBorder()],
        structuredTypes: [_badge()],
        existingEvents: [...seed, ...first.newEvents],
      );

      expect(second.newEvents, isEmpty);
      expect(
        second.catalog.structuredTypes.single.wireId,
        WireId('s0001'),
      );
      expect(
        second.catalog.structuredTypes.single.fields.map((f) => f.wireId.value),
        ['p0003', 'p0004'],
      );
    });
  });

  group('customer structured allocation — sentinel resolution', () {
    test(
        'resolves widget-property structuredRef (+ its valueShape ref) from '
        'the bare sentinel to the allocated structured id', () {
      final allocation = allocateUserCatalogFromWidgets(
        package: _pkg,
        widgets: [_badgeCard()],
        structuredTypes: [_badge()],
        slotTargets: const {
          'package:acme/c.dart#BadgeCard.badge': 'package:acme/b.dart#Badge',
        },
      );
      final badge = allocation.catalog.structuredTypes.single;
      final prop = allocation.catalog.widgets.single.properties.single;

      expect(prop.structuredRef, isNotNull);
      expect(prop.structuredRef!.wireId, badge.wireId);
      expect(prop.structuredRef!.wireId.isUnallocated, isFalse);

      final shape = prop.valueShape! as StructuredShape;
      expect(shape.structuredRef.wireId, badge.wireId);
      expect(shape.structuredRef.wireId.isUnallocated, isFalse);
    });

    test(
        'resolves variant argMappings.targetFields from the sentinel to the '
        'allocated field ids (by param==field name)', () {
      final allocation = allocateUserCatalogFromWidgets(
        package: _pkg,
        widgets: [_badgeCard()],
        structuredTypes: [_badge()],
        slotTargets: const {
          'package:acme/c.dart#BadgeCard.badge': 'package:acme/b.dart#Badge',
        },
      );
      final badge = allocation.catalog.structuredTypes.single;
      final fieldIdByName = {for (final f in badge.fields) f.name: f.wireId};
      final variant = badge.variants.single as ConstructorVariant;

      expect(
        variant.argMappings['label']!.targetFields,
        [fieldIdByName['label']],
      );
      expect(
        variant.argMappings['count']!.targetFields,
        [fieldIdByName['count']],
      );
      expect(
        variant.argMappings.values
            .expand((m) => m.targetFields)
            .every((id) => !id.isUnallocated),
        isTrue,
      );
    });

    test(
        'throws loud on a dangling structured ref (target not in the '
        'allocated set) rather than emitting an unresolved ref', () {
      expect(
        () => allocateUserCatalogFromWidgets(
          package: _pkg,
          widgets: [_badgeCard()],
          structuredTypes: [_badge()],
          slotTargets: const {
            'package:acme/c.dart#BadgeCard.badge':
                'package:acme/missing.dart#X',
          },
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
