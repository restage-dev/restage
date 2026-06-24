import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/property_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/union_ir.dart';
import 'package:rfw_catalog_compiler/src/link/cross_ref_resolution_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  group('CrossRefResolutionIndex', () {
    test('captures structured refs, union refs, and arg target names', () {
      final hostElement = fakes.fakeClassElement('Host');
      final ir = _structuredIr(
        sourceType: 'package:test/host.dart#Host',
        fields: [
          _field(
            'child',
            structuredRefFqn: 'package:test/child.dart#Child',
          ),
          _field(
            'shape',
            unionSourceKey: 'restage.core#package:test/shape.dart#Shape',
          ),
        ],
        variants: [
          FactoryVariantIR(
            wireId: WireId.unallocatedVariant,
            sourceKind: VariantSourceKind.constructor,
            source: fakes.fakeConstructorElement(
              'only',
              returnType: fakes.fakeInterfaceTypeForElement(hostElement),
            ),
            namedConstructor: 'only',
            argTargetFieldNames: const {
              'side': ['left', 'right'],
            },
          ),
        ],
      );

      final index = crossRefIndexForStructured(ir);

      expect(index.structuredRefFqnByField, {
        ('package:test/host.dart#Host', 'child'):
            'package:test/child.dart#Child',
      });
      expect(index.unionSourceKeyByField, {
        ('package:test/host.dart#Host', 'shape'):
            'restage.core#package:test/shape.dart#Shape',
      });
      expect(index.argTargetFieldNames, {
        ('package:test/host.dart#Host', 'constructor|only|', 'side'): [
          'left',
          'right',
        ],
      });
    });

    test('merges partial indexes', () {
      const first = CrossRefResolutionIndex(
        structuredRefFqnByField: {
          ('package:test/host.dart#Host', 'child'):
              'package:test/child.dart#Child',
        },
      );
      const second = CrossRefResolutionIndex(
        unionSourceKeyByField: {
          ('package:test/host.dart#Host', 'shape'):
              'restage.core#package:test/shape.dart#Shape',
        },
        argTargetFieldNames: {
          ('package:test/host.dart#Host', 'constructor||', 'child'): ['child'],
        },
      );

      final merged = first.merge(second);

      expect(merged.structuredRefFqnByField, first.structuredRefFqnByField);
      expect(merged.unionSourceKeyByField, second.unionSourceKeyByField);
      expect(merged.argTargetFieldNames, second.argTargetFieldNames);
    });

    test('union IR contributes no index entries', () {
      final union = UnionIR(
        wireId: WireId.unallocatedUnion,
        source: fakes.fakeClassElement('Shape'),
        name: 'Shape',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/shape.dart#Shape',
        memberSourceTypes: const ['package:test/circle.dart#Circle'],
        discriminator: const DiscriminatorSpec(
          field: '_s',
          values: [
            WireIdRef(
              library: 'restage.core',
              wireId: WireId.unallocatedStructured,
            ),
          ],
        ),
        members: const [
          WireIdRef(
            library: 'restage.core',
            wireId: WireId.unallocatedStructured,
          ),
        ],
        stability: Stability.volatile,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:test/shape.dart#Shape',
          curationSource: null,
          derivationTrace: ['test'],
        ),
        policyTrace: const [],
      );

      final index = crossRefIndexForUnion(union);

      expect(index.structuredRefFqnByField, isEmpty);
      expect(index.unionSourceKeyByField, isEmpty);
      expect(index.argTargetFieldNames, isEmpty);
    });

    test('variant identity is shared between IR and schema variants', () {
      final ir = FactoryVariantIR(
        wireId: WireId.unallocatedVariant,
        sourceKind: VariantSourceKind.staticMethod,
        source: fakes.fakeMethodElement(
          'lerp',
          returnType: fakes.fakeInterfaceType('Host'),
        ),
        staticAccessor: 'lerp',
      );
      const schema = StaticMethodVariant(
        wireId: WireId.unallocatedVariant,
        staticAccessor: 'lerp',
      );

      expect(variantIdentityIr(ir), 'staticMethod||lerp');
      expect(variantIdentity(schema), variantIdentityIr(ir));
    });
  });
}

StructuredIR _structuredIr({
  required String sourceType,
  List<StructuredFieldIR> fields = const [],
  List<FactoryVariantIR> variants = const [],
}) {
  return StructuredIR(
    wireId: WireId.unallocatedStructured,
    source: fakes.fakeClassElement('Host'),
    name: 'Host',
    library: WidgetLibrary.core,
    description: '',
    fields: fields,
    variants: variants,
    stability: Stability.volatile,
    diagnostics: const [],
    provenance: ProvenanceIR(
      flutterType: sourceType,
      curationSource: null,
      derivationTrace: const ['test'],
    ),
    policyTrace: const [],
  );
}

StructuredFieldIR _field(
  String name, {
  String? structuredRefFqn,
  String? unionSourceKey,
}) {
  return StructuredFieldIR(
    wireId: WireId.unallocatedProperty,
    source: fakes.fakeFieldElement(name, fakes.fakeInterfaceType('Object')),
    name: name,
    type: const ResolvedType(kind: ResolvedTypeKind.string),
    description: '',
    defaultSource: null,
    metadata: const PropertyMetadataIR(),
    diagnostics: const [],
    structuredRefFqn: structuredRefFqn,
    unionSourceKey: unionSourceKey,
  );
}
