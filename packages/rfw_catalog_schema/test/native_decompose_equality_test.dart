// These tests deliberately construct value-equal instances as *distinct*
// objects to prove value-`==` (not identity). `const` would canonicalize the
// pairs into a single instance and defeat that, so const-promotion is opted
// out for this file.
// ignore_for_file: prefer_const_constructors

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Value-equality across the native-decompose sealed hierarchies.
///
/// These are `@immutable` value types in a public package; the
/// `FactoryParameterDefaultValue` doc promises value-equality and consumers
/// compare them by value. This pins value-`==`/`hashCode` for a representative
/// of every concrete subtype — including the recursive cases (`ListShape`
/// item, `ProjectListTransform` item, `NestedTransformArgumentBinding` nested,
/// `ConstructVariantTransform` invocation) and the `List` field
/// (`ConstructVariantTransform.argumentBindings`).
///
/// Each pair is constructed **non-`const`** so the two instances are distinct
/// objects (`identical` is false) — identity-equality would fail these, so a
/// pass proves value-equality.
void main() {
  // Shared, distinct building blocks.
  DartTypeRef colorRef() =>
      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color');
  WireIdRef structuredRef() =>
      WireIdRef(library: 'restage.core', wireId: WireId('s0001'));
  WireIdRef unionRef() =>
      WireIdRef(library: 'restage.core', wireId: WireId('u0001'));
  WireIdRef variantRef() =>
      WireIdRef(library: 'restage.core', wireId: WireId('v0001'));

  /// Asserts two distinct instances are value-equal with equal hashCodes.
  void expectValueEqual(Object a, Object b) {
    expect(identical(a, b), isFalse, reason: 'instances must be distinct');
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  }

  group('CatalogValueShape', () {
    test('ScalarShape value-equals on all fields', () {
      expectValueEqual(
        ScalarShape(
          propertyType: PropertyType.color,
          dartTypeRef: colorRef(),
          wireCodec: CatalogWireCodec.rfwGradient,
        ),
        ScalarShape(
          propertyType: PropertyType.color,
          dartTypeRef: colorRef(),
          wireCodec: CatalogWireCodec.rfwGradient,
        ),
      );
    });

    test('ScalarShape differs on propertyType / dartTypeRef / wireCodec', () {
      const base = ScalarShape(propertyType: PropertyType.string);
      expect(base, isNot(const ScalarShape(propertyType: PropertyType.color)));
      expect(
        const ScalarShape(propertyType: PropertyType.gradient),
        isNot(
          const ScalarShape(
            propertyType: PropertyType.gradient,
            wireCodec: CatalogWireCodec.rfwGradient,
          ),
        ),
      );
      expect(
        ScalarShape(propertyType: PropertyType.color, dartTypeRef: colorRef()),
        isNot(const ScalarShape(propertyType: PropertyType.color)),
      );
    });

    test('EnumShape value-equals on enumRef', () {
      expectValueEqual(
        EnumShape(propertyType: PropertyType.enumValue, enumRef: colorRef()),
        EnumShape(propertyType: PropertyType.enumValue, enumRef: colorRef()),
      );
      expect(
        EnumShape(
          propertyType: PropertyType.enumValue,
          enumRef: DartTypeRef(libraryUri: 'a', symbolName: 'A'),
        ),
        isNot(
          EnumShape(
            propertyType: PropertyType.enumValue,
            enumRef: DartTypeRef(libraryUri: 'b', symbolName: 'B'),
          ),
        ),
      );
    });

    test('StructuredShape value-equals on structuredRef', () {
      expectValueEqual(
        StructuredShape(
          propertyType: PropertyType.structured,
          structuredRef: structuredRef(),
        ),
        StructuredShape(
          propertyType: PropertyType.structured,
          structuredRef: structuredRef(),
        ),
      );
    });

    test('UnionShape value-equals on unionRef', () {
      expectValueEqual(
        UnionShape(propertyType: PropertyType.gradient, unionRef: unionRef()),
        UnionShape(propertyType: PropertyType.gradient, unionRef: unionRef()),
      );
    });

    test('ListShape value-equals recursively on itemShape', () {
      expectValueEqual(
        ListShape(
          propertyType: PropertyType.stringList,
          itemShape: ListShape(
            propertyType: PropertyType.stringList,
            itemShape: const ScalarShape(propertyType: PropertyType.string),
          ),
        ),
        ListShape(
          propertyType: PropertyType.stringList,
          itemShape: ListShape(
            propertyType: PropertyType.stringList,
            itemShape: const ScalarShape(propertyType: PropertyType.string),
          ),
        ),
      );
      // A difference deep in the nested itemShape breaks equality.
      expect(
        const ListShape(
          propertyType: PropertyType.stringList,
          itemShape: ScalarShape(propertyType: PropertyType.string),
        ),
        isNot(
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: ScalarShape(propertyType: PropertyType.integer),
          ),
        ),
      );
    });

    test('different shape subtypes are never equal (even sharing base)', () {
      // Both carry propertyType.unknown + null wireCodec; only the subtype
      // differs. A base-only == would wrongly call these equal.
      expect(
        const ScalarShape(propertyType: PropertyType.unknown),
        isNot(
          EnumShape(propertyType: PropertyType.unknown, enumRef: colorRef()),
        ),
      );
    });
  });

  group('DecompositionValueTransform', () {
    test('IdentityTransform instances are equal', () {
      expect(IdentityTransform(), equals(IdentityTransform()));
      expect(
        IdentityTransform().hashCode,
        equals(IdentityTransform().hashCode),
      );
    });

    FactoryInvocation invocation() => FactoryInvocation(
          variantRef: variantRef(),
          receiver: const ResultStructuredTypeReceiver(),
          memberName: 'circular',
        );

    TransformArgumentBinding binding(WireId param) =>
        PropertyValueArgumentBinding(
          parameterRef: param,
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        );

    test('ConstructVariantTransform value-equals incl. invocation + bindings',
        () {
      expectValueEqual(
        ConstructVariantTransform(
          resultStructuredRef: structuredRef(),
          invocation: invocation(),
          argumentBindings: [
            binding(WireId('a0001')),
            binding(WireId('a0002')),
          ],
        ),
        ConstructVariantTransform(
          resultStructuredRef: structuredRef(),
          invocation: invocation(),
          argumentBindings: [
            binding(WireId('a0001')),
            binding(WireId('a0002')),
          ],
        ),
      );
    });

    test('ConstructVariantTransform is order-sensitive on argumentBindings',
        () {
      expect(
        ConstructVariantTransform(
          resultStructuredRef: structuredRef(),
          invocation: invocation(),
          argumentBindings: [
            binding(WireId('a0001')),
            binding(WireId('a0002')),
          ],
        ),
        isNot(
          ConstructVariantTransform(
            resultStructuredRef: structuredRef(),
            invocation: invocation(),
            argumentBindings: [
              binding(WireId('a0002')),
              binding(WireId('a0001')),
            ],
          ),
        ),
      );
    });

    test('ProjectListTransform value-equals recursively', () {
      // Outer constructions are non-`const` so the two are distinct objects
      // (the inner const leaves canonicalize, but the outer wrappers do not).
      expectValueEqual(
        ProjectListTransform(
          itemTransform: const ProjectListTransform(
            itemTransform: IdentityTransform(),
          ),
        ),
        ProjectListTransform(
          itemTransform: const ProjectListTransform(
            itemTransform: IdentityTransform(),
          ),
        ),
      );
    });

    test('CoerceScalarTransform value-equals on scalarCoercion', () {
      expect(
        const CoerceScalarTransform(scalarCoercion: 'toDouble'),
        equals(const CoerceScalarTransform(scalarCoercion: 'toDouble')),
      );
      expect(
        const CoerceScalarTransform(scalarCoercion: 'toDouble'),
        isNot(const CoerceScalarTransform(scalarCoercion: 'toInt')),
      );
    });
  });

  group('FactoryReceiver', () {
    test('fieldless receivers are equal to their own kind only', () {
      expect(
        ResultStructuredTypeReceiver(),
        equals(ResultStructuredTypeReceiver()),
      );
      expect(OwningWidgetTypeReceiver(), equals(OwningWidgetTypeReceiver()));
      expect(
        const ResultStructuredTypeReceiver(),
        isNot(const OwningWidgetTypeReceiver()),
      );
    });

    test('ExplicitDartTypeReceiver value-equals on dartTypeRef', () {
      expectValueEqual(
        ExplicitDartTypeReceiver(colorRef()),
        ExplicitDartTypeReceiver(colorRef()),
      );
      expect(
        ExplicitDartTypeReceiver(
          DartTypeRef(libraryUri: 'a', symbolName: 'A'),
        ),
        isNot(
          ExplicitDartTypeReceiver(
            DartTypeRef(libraryUri: 'b', symbolName: 'B'),
          ),
        ),
      );
    });
  });

  group('TransformArgumentBinding', () {
    test('PropertyValueArgumentBinding value-equals on base fields', () {
      expectValueEqual(
        PropertyValueArgumentBinding(
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
        PropertyValueArgumentBinding(
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
      );
    });

    test('LiteralArgumentBinding value-equals on literal + base', () {
      expectValueEqual(
        LiteralArgumentBinding(
          literal: 42,
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
        LiteralArgumentBinding(
          literal: 42,
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
      );
      expect(
        LiteralArgumentBinding(
          literal: 42,
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
        isNot(
          LiteralArgumentBinding(
            literal: 43,
            parameterRef: WireId('a0001'),
            nullPolicy: TransformNullPolicy.nullResult,
            missingPolicy: TransformMissingPolicy.nullResult,
          ),
        ),
      );
    });

    test('NestedTransformArgumentBinding value-equals recursively', () {
      expectValueEqual(
        NestedTransformArgumentBinding(
          nestedTransform: const ProjectListTransform(
            itemTransform: IdentityTransform(),
          ),
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
        NestedTransformArgumentBinding(
          nestedTransform: const ProjectListTransform(
            itemTransform: IdentityTransform(),
          ),
          parameterRef: WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
      );
    });

    test('different binding subtypes are never equal (even sharing base)', () {
      final base = (
        param: WireId('a0001'),
        nullP: TransformNullPolicy.nullResult,
        missP: TransformMissingPolicy.nullResult,
      );
      expect(
        PropertyValueArgumentBinding(
          parameterRef: base.param,
          nullPolicy: base.nullP,
          missingPolicy: base.missP,
        ),
        isNot(
          LiteralArgumentBinding(
            literal: null,
            parameterRef: base.param,
            nullPolicy: base.nullP,
            missingPolicy: base.missP,
          ),
        ),
      );
    });
  });

  group('FactoryInvocation', () {
    test('value-equals on variantRef + receiver + memberName', () {
      expectValueEqual(
        FactoryInvocation(
          variantRef: variantRef(),
          receiver: const ResultStructuredTypeReceiver(),
          memberName: 'circular',
        ),
        FactoryInvocation(
          variantRef: variantRef(),
          receiver: const ResultStructuredTypeReceiver(),
          memberName: 'circular',
        ),
      );
    });

    test('differs on memberName and on receiver value', () {
      expect(
        FactoryInvocation(
          variantRef: variantRef(),
          receiver: const ResultStructuredTypeReceiver(),
          memberName: 'circular',
        ),
        isNot(
          FactoryInvocation(
            variantRef: variantRef(),
            receiver: const ResultStructuredTypeReceiver(),
            memberName: 'all',
          ),
        ),
      );
      expect(
        FactoryInvocation(
          variantRef: variantRef(),
          receiver: const ResultStructuredTypeReceiver(),
        ),
        isNot(
          FactoryInvocation(
            variantRef: variantRef(),
            receiver: const OwningWidgetTypeReceiver(),
          ),
        ),
      );
    });
  });
}
