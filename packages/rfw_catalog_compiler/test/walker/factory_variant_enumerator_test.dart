import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/factory_variant_enumerator.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  const policy = PolicyLedger.builtIn();

  group('enumerateFactoryVariants', () {
    test('Color constructor variants map fromARGB args by field name', () {
      final intType = _coreType('int');
      final constructors = <ConstructorElement>[];
      final color = fakes.fakeClassElement(
        'Color',
        constructors: constructors,
      );
      constructors.addAll([
        fakes.fakeConstructorElement(
          'fromRGBO',
          returnType: color.thisType,
        ),
        fakes.fakeConstructorElement(
          '',
          returnType: color.thisType,
        ),
        fakes.fakeConstructorElement(
          'fromARGB',
          returnType: color.thisType,
          parameters: _params({
            'a': intType,
            'r': intType,
            'g': intType,
            'b': intType,
          }),
        ),
      ]);

      final result = enumerateFactoryVariants(
        element: color,
        fields: [
          _field('a', intType, wireId: WireId('p0001')),
          _field('r', intType, wireId: WireId('p0002')),
          _field('g', intType, wireId: WireId('p0003')),
          _field('b', intType, wireId: WireId('p0004')),
        ],
        policy: policy,
      );

      expect(
        result.variants.map((variant) => variant.namedConstructor),
        [null, 'fromARGB', 'fromRGBO'],
      );
      final fromArgb = result.variants[1];
      expect(fromArgb.sourceKind, VariantSourceKind.constructor);
      expect(
        fromArgb.argMappings.map(
          (name, mapping) => MapEntry(name, mapping.targetFields.single),
        ),
        {
          'a': WireId('p0001'),
          'r': WireId('p0002'),
          'g': WireId('p0003'),
          'b': WireId('p0004'),
        },
      );
    });

    test('Color static method variants allow nullable self return type', () {
      final methods = <MethodElement>[];
      final color = fakes.fakeClassElement('Color', methods: methods);
      methods.add(
        fakes.fakeMethodElement(
          'lerp',
          returnType: fakes.fakeInterfaceTypeForElement(
            color,
            isNullable: true,
          ),
          parameters: _params({
            'a': fakes.fakeInterfaceTypeForElement(color, isNullable: true),
            'b': fakes.fakeInterfaceTypeForElement(color, isNullable: true),
            't': _coreType('double'),
          }),
        ),
      );

      final result = enumerateFactoryVariants(
        element: color,
        fields: const [],
        policy: policy,
      );

      expect(result.variants, hasLength(1));
      expect(result.variants.single.sourceKind, VariantSourceKind.staticMethod);
      expect(result.variants.single.staticAccessor, 'lerp');
    });

    test('EdgeInsets lists named constructors before zero const value', () {
      final doubleType = _coreType('double');
      final constructors = <ConstructorElement>[];
      final classFields = <FieldElement>[];
      final edgeInsets = fakes.fakeClassElement(
        'EdgeInsets',
        fields: classFields,
        constructors: constructors,
      );
      constructors.addAll([
        fakes.fakeConstructorElement(
          'symmetric',
          returnType: edgeInsets.thisType,
        ),
        fakes.fakeConstructorElement(
          'fromLTRB',
          returnType: edgeInsets.thisType,
        ),
        fakes.fakeConstructorElement('only', returnType: edgeInsets.thisType),
        fakes.fakeConstructorElement('all', returnType: edgeInsets.thisType),
      ]);
      classFields.add(
        fakes.fakeStaticConstField(
          'zero',
          fakes.fakeInterfaceTypeForElement(edgeInsets),
        ),
      );

      final result = enumerateFactoryVariants(
        element: edgeInsets,
        fields: [
          _field('left', doubleType),
          _field('top', doubleType),
          _field('right', doubleType),
          _field('bottom', doubleType),
        ],
        policy: policy,
      );

      expect(
        result.variants.map(_label),
        [
          'constructor:all',
          'constructor:fromLTRB',
          'constructor:only',
          'constructor:symmetric',
          'constValue:zero',
        ],
      );
    });

    test('Alignment const values are sorted alphabetically', () {
      final classFields = <FieldElement>[];
      final alignment = fakes.fakeClassElement(
        'Alignment',
        fields: classFields,
      );
      for (final name in [
        'topLeft',
        'topCenter',
        'topRight',
        'centerLeft',
        'center',
        'centerRight',
        'bottomLeft',
        'bottomCenter',
        'bottomRight',
      ]) {
        classFields.add(
          fakes.fakeStaticConstField(
            name,
            fakes.fakeInterfaceTypeForElement(alignment),
          ),
        );
      }

      final result = enumerateFactoryVariants(
        element: alignment,
        fields: const [],
        policy: policy,
      );

      expect(
        result.variants.map((variant) => variant.staticAccessor),
        [
          'bottomCenter',
          'bottomLeft',
          'bottomRight',
          'center',
          'centerLeft',
          'centerRight',
          'topCenter',
          'topLeft',
          'topRight',
        ],
      );
      expect(
        result.variants.map((variant) => variant.sourceKind).toSet(),
        {VariantSourceKind.constValue},
      );
    });

    test('BorderRadius includes constructors and zero const value', () {
      final radiusType = fakes.fakeInterfaceType('Radius');
      final constructors = <ConstructorElement>[];
      final classFields = <FieldElement>[];
      final borderRadius = fakes.fakeClassElement(
        'BorderRadius',
        fields: classFields,
        constructors: constructors,
      );
      constructors.addAll([
        fakes.fakeConstructorElement(
          'vertical',
          returnType: borderRadius.thisType,
        ),
        fakes.fakeConstructorElement('only', returnType: borderRadius.thisType),
        fakes.fakeConstructorElement('', returnType: borderRadius.thisType),
        fakes.fakeConstructorElement(
          'all',
          returnType: borderRadius.thisType,
          parameters: _params({'radius': radiusType}),
        ),
        fakes.fakeConstructorElement(
          'circular',
          returnType: borderRadius.thisType,
          parameters: _params({'radius': _coreType('double')}),
        ),
        fakes.fakeConstructorElement(
          'horizontal',
          returnType: borderRadius.thisType,
        ),
      ]);
      classFields.add(
        fakes.fakeStaticConstField(
          'zero',
          fakes.fakeInterfaceTypeForElement(borderRadius),
        ),
      );

      final result = enumerateFactoryVariants(
        element: borderRadius,
        fields: [
          _field('topLeft', radiusType),
          _field('topRight', radiusType),
          _field('bottomLeft', radiusType),
          _field('bottomRight', radiusType),
        ],
        policy: policy,
      );

      expect(
        result.variants.map(_label),
        [
          'constructor:<default>',
          'constructor:all',
          'constructor:circular',
          'constructor:horizontal',
          'constructor:only',
          'constructor:vertical',
          'constValue:zero',
        ],
      );
      final all = result.variants.firstWhere(
        (variant) => variant.namedConstructor == 'all',
      );
      expect(
        all.argMappings['radius']!.targetFields,
        List.filled(4, WireId.unallocatedProperty),
      );
      expect(all.argTargetFieldNames['radius'], [
        'topLeft',
        'topRight',
        'bottomLeft',
        'bottomRight',
      ]);
    });

    test('deduplicates a static const value against its implicit getter', () {
      // A static const field (e.g. BorderRadius.zero) is surfaced by the
      // analyzer as BOTH a const-value field AND an implicit synthetic getter,
      // so it lands in element.fields and element.getters alike. The const
      // value is the canonical accessor; the redundant getter variant of the
      // same name must be dropped, or the type carries a duplicate `zero`
      // variant (one staticGetter, one constValue).
      final getters = <GetterElement>[];
      final classFields = <FieldElement>[];
      final borderRadius = fakes.fakeClassElement(
        'BorderRadius',
        getters: getters,
        fields: classFields,
      );
      getters.add(
        fakes.fakePropertyAccessorElement(
          'zero',
          returnType: fakes.fakeInterfaceTypeForElement(borderRadius),
        ),
      );
      classFields.add(
        fakes.fakeStaticConstField(
          'zero',
          fakes.fakeInterfaceTypeForElement(borderRadius),
        ),
      );

      final result = enumerateFactoryVariants(
        element: borderRadius,
        fields: const [],
        policy: policy,
      );

      expect(result.variants.map(_label), ['constValue:zero']);
    });

    test('denylisted constructor parameter excludes the variant', () {
      final constructors = <ConstructorElement>[];
      final host = fakes.fakeClassElement('Host', constructors: constructors);
      constructors.add(
        fakes.fakeConstructorElement(
          'controlled',
          returnType: host.thisType,
          parameters: _params({
            'controller': fakes.fakeInterfaceType('TextEditingController'),
          }),
        ),
      );

      final result = enumerateFactoryVariants(
        element: host,
        fields: const [],
        policy: policy,
      );

      expect(result.variants, isEmpty);
      expect(result.policyTrace, hasLength(1));
      expect(result.policyTrace.single.policy, 'denylist.types');
      expect(result.policyTrace.single.decision, 'excluded');
      expect(result.policyTrace.single.target, contains('Host.controlled'));
    });

    test('sorts source kinds in deterministic groups', () {
      final constructors = <ConstructorElement>[];
      final methods = <MethodElement>[];
      final getters = <GetterElement>[];
      final classFields = <FieldElement>[];
      final host = fakes.fakeClassElement(
        'Host',
        fields: classFields,
        constructors: constructors,
        methods: methods,
        getters: getters,
      );
      constructors.addAll([
        fakes.fakeConstructorElement('beta', returnType: host.thisType),
        fakes.fakeConstructorElement('', returnType: host.thisType),
        fakes.fakeConstructorElement('alpha', returnType: host.thisType),
      ]);
      methods.addAll([
        fakes.fakeMethodElement('zebra', returnType: host.thisType),
        fakes.fakeMethodElement('apple', returnType: host.thisType),
      ]);
      getters.addAll([
        fakes.fakePropertyAccessorElement('second', returnType: host.thisType),
        fakes.fakePropertyAccessorElement('first', returnType: host.thisType),
      ]);
      classFields.addAll([
        fakes.fakeStaticConstField('y', host.thisType),
        fakes.fakeStaticConstField('x', host.thisType),
      ]);

      final result = enumerateFactoryVariants(
        element: host,
        fields: const [],
        policy: policy,
      );

      expect(
        result.variants.map(_label),
        [
          'constructor:<default>',
          'constructor:alpha',
          'constructor:beta',
          'staticMethod:apple',
          'staticMethod:zebra',
          'staticGetter:first',
          'staticGetter:second',
          'constValue:x',
          'constValue:y',
        ],
      );
    });

    test('empty class produces no variants or policy trace', () {
      final host = fakes.fakeClassElement('Host');

      final result = enumerateFactoryVariants(
        element: host,
        fields: const [],
        policy: policy,
      );

      expect(result.variants, isEmpty);
      expect(result.policyTrace, isEmpty);
    });
  });
}

DartType _coreType(String name) =>
    fakes.fakeInterfaceType(name, libraryIdentifier: 'dart:core');

List<FormalParameterElement> _params(Map<String, DartType> entries) => [
      for (final entry in entries.entries)
        fakes.fakeFormalParameterElement(entry.key, entry.value),
    ];

StructuredFieldIR _field(
  String name,
  DartType type, {
  WireId wireId = WireId.unallocatedProperty,
}) {
  return StructuredFieldIR(
    wireId: wireId,
    source: fakes.fakeFieldElement(name, type),
    name: name,
    type: ResolvedType(kind: ResolvedTypeKind.structured, dartType: type),
    description: '',
    defaultSource: null,
    metadata: const PropertyMetadataIR(),
    diagnostics: const [],
  );
}

String _label(FactoryVariantIR variant) {
  return switch (variant.sourceKind) {
    VariantSourceKind.constructor =>
      'constructor:${variant.namedConstructor ?? '<default>'}',
    VariantSourceKind.staticMethod => 'staticMethod:${variant.staticAccessor}',
    VariantSourceKind.staticGetter => 'staticGetter:${variant.staticAccessor}',
    VariantSourceKind.constValue => 'constValue:${variant.staticAccessor}',
  };
}
