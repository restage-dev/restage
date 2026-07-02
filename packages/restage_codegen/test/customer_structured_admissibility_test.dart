import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// The recursive renderable-closure predicate + `computeAdmission` decide
/// whether a customer structured widget can render on the RFW path. A widget
/// survives IFF every `structuredRef` in its transitive closure resolves to an
/// allocated, fully-renderable structured entry (resolve-or-exclude-loud). The
/// predicate reasons over `slotTargets` (slot -> target sourceType FQN) and
/// `localUnrenderable` (types whose walk dropped an unsupported inner field),
/// never over the bare sentinel ref (which does not identify the target).

const _lib = 'acme.design_system';
const _library = WidgetLibrary.custom(_lib);
const _sentinelRef = WireIdRef(
  library: _lib,
  wireId: WireId.unallocatedStructured,
);

StructuredField _scalarField(String name, PropertyType type) => StructuredField(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: '',
      valueShape: ScalarShape(propertyType: type),
    );

StructuredField _structuredField(String name) => StructuredField(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: PropertyType.structured,
      description: '',
      structuredRef: _sentinelRef,
      valueShape: const StructuredShape(
        propertyType: PropertyType.structured,
        structuredRef: _sentinelRef,
      ),
    );

/// A canonical unnamed ctor variant whose required named parameters mirror the
/// fields 1:1 (param name == field name) — the shape a real data class lowers
/// to and the reconstructor sources by name.
ConstructorVariant _canonicalVariant(List<StructuredField> fields) =>
    ConstructorVariant(
      wireId: WireId.unallocatedVariant,
      parameters: [
        for (final field in fields)
          FactoryParameter(
            wireId: WireId.unallocatedParameter,
            name: field.name,
            kind: FactoryParameterKind.named,
            required: true,
            nullable: false,
            defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
            valueShape: field.valueShape!,
          ),
      ],
    );

StructuredEntry _structured(
  String name,
  String sourceType,
  List<StructuredField> fields, {
  List<FactoryVariant>? variants,
}) =>
    StructuredEntry(
      wireId: WireId.unallocatedStructured,
      name: name,
      library: _library,
      description: '',
      sourceType: sourceType,
      fields: fields,
      variants: variants ?? [_canonicalVariant(fields)],
    );

WidgetEntry _widget(
  String name,
  String flutterType,
  List<PropertyEntry> props,
) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: _library,
      category: WidgetCategory.decoration,
      description: '',
      flutterType: flutterType,
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: props,
    );

PropertyEntry _structuredProp(String name) => PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: PropertyType.structured,
      description: '',
      structuredRef: _sentinelRef,
    );

// Closure: Outer{title:String, inner:Inner}, Inner{value:int}.
const _outerFqn = 'package:acme/foo.dart#Outer';
const _innerFqn = 'package:acme/foo.dart#Inner';
const _cardFqn = 'package:acme/foo.dart#OuterCard';

final StructuredEntry _inner = _structured('Inner', _innerFqn, [
  _scalarField('value', PropertyType.integer),
]);
final StructuredEntry _outer = _structured('Outer', _outerFqn, [
  _scalarField('title', PropertyType.string),
  _structuredField('inner'),
]);
final WidgetEntry _card =
    _widget('OuterCard', _cardFqn, [_structuredProp('config')]);

Map<String, StructuredEntry> get _bySourceType => {
      _innerFqn: _inner,
      _outerFqn: _outer,
    };
Map<String, String> get _slotTargets => {
      '$_outerFqn.inner': _innerFqn,
      '$_cardFqn.config': _outerFqn,
    };

void main() {
  group('isRenderableStructuredType', () {
    test('a fully-renderable nested closure is renderable', () {
      expect(
        isRenderableStructuredType(
          _outer,
          bySourceType: _bySourceType,
          slotTargets: _slotTargets,
          localUnrenderable: const {},
        ),
        isTrue,
      );
    });

    test(
        'a type whose nested target has a dropped inner field is NOT '
        'renderable (recursion sees the target localUnrenderable)', () {
      expect(
        isRenderableStructuredType(
          _outer,
          bySourceType: _bySourceType,
          slotTargets: _slotTargets,
          localUnrenderable: const {_innerFqn: 'Inner.data (Map) unsupported'},
        ),
        isFalse,
      );
    });

    test('a dangling structured field (target absent) is NOT renderable', () {
      expect(
        isRenderableStructuredType(
          _outer,
          bySourceType: const {},
          slotTargets: _slotTargets,
          localUnrenderable: const {},
        ),
        isFalse,
      );
    });

    test(
        'a non-canonical shape — a required ctor param that name-matches no '
        'field — is NOT renderable (reconstructor-soundness invariant)', () {
      // Badge(int c) : count = c — the ctor param `c` has no field named `c`,
      // so the by-name reconstructor could not source it. Exclude, never
      // mis-source.
      const badgeFqn = 'package:acme/foo.dart#Badge';
      final badge = _structured(
        'Badge',
        badgeFqn,
        [_scalarField('count', PropertyType.integer)],
        variants: const [
          ConstructorVariant(
            wireId: WireId.unallocatedVariant,
            parameters: [
              FactoryParameter(
                wireId: WireId.unallocatedParameter,
                name: 'c',
                kind: FactoryParameterKind.named,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: ScalarShape(propertyType: PropertyType.integer),
              ),
            ],
          ),
        ],
      );
      expect(
        isRenderableStructuredType(
          badge,
          bySourceType: {badgeFqn: badge},
          slotTargets: const {},
          localUnrenderable: const {},
        ),
        isFalse,
      );
    });

    test(
        'a data class with no constructor variant (const-value-only) is NOT '
        'renderable (nothing to reconstruct with)', () {
      const fqn = 'package:acme/foo.dart#Token';
      final token = _structured(
        'Token',
        fqn,
        [_scalarField('value', PropertyType.integer)],
        variants: const [],
      );
      expect(
        isRenderableStructuredType(
          token,
          bySourceType: {fqn: token},
          slotTargets: const {},
          localUnrenderable: const {},
        ),
        isFalse,
      );
    });

    test(
        'a self-referential (cyclic) data class is NOT renderable (a cycle '
        'cannot be finitely reconstructed by inline emission)', () {
      // The check terminates (cycle-safe via the visiting set), but a cyclic
      // type is excluded-loud: the inline reconstructor would expand
      // `next: Node(next: Node(...))` forever. (Cyclic types render in A2UI via
      // `$ref`, not RFW inline — see the render-leg cyclic-exclude fix.)
      const nodeFqn = 'package:acme/foo.dart#Node';
      final node = _structured('Node', nodeFqn, [
        _scalarField('value', PropertyType.integer),
        _structuredField('next'),
      ]);
      expect(
        isRenderableStructuredType(
          node,
          bySourceType: {nodeFqn: node},
          slotTargets: {'$nodeFqn.next': nodeFqn},
          localUnrenderable: const {},
        ),
        isFalse,
      );
    });
  });

  group('computeAdmission', () {
    test(
        'admits a widget whose closure is fully renderable, and returns the '
        'reachable structured closure', () {
      final admission = computeAdmission(
        widgets: [_card],
        structuredTypes: [_outer, _inner],
        slotTargets: _slotTargets,
        localUnrenderable: const {},
      );
      expect(admission.admitted, [_card]);
      expect(admission.excluded, isEmpty);
      expect(admission.admittedSourceTypes, {_outerFqn, _innerFqn});
    });

    test(
        'excludes-loud a widget whose closure contains an unsupported inner '
        'field, naming the offending target', () {
      final admission = computeAdmission(
        widgets: [_card],
        structuredTypes: [_outer, _inner],
        slotTargets: _slotTargets,
        localUnrenderable: const {_innerFqn: 'Inner.data (Map) unsupported'},
      );
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.widget, _card);
      // The reason names the offending property and/or the non-renderable
      // target so the log is actionable.
      expect(
        admission.excluded.single.reason,
        anyOf(contains('config'), contains('Inner'), contains(_innerFqn)),
      );
    });

    test(
        'excludes-loud a widget whose structured property target is absent '
        '(dangling ref)', () {
      final admission = computeAdmission(
        widgets: [_card],
        structuredTypes: const [],
        slotTargets: const {
          '$_cardFqn.config': 'package:acme/foo.dart#Missing',
        },
        localUnrenderable: const {},
      );
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.reason, contains('Missing'));
    });
  });
}
