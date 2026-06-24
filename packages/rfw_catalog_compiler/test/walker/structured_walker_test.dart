import 'package:analyzer/dart/element/element.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_compiler/src/ir/ir_lower.dart'
    show lowerStructuredField;
import 'package:rfw_catalog_compiler/src/ir/type_ir.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  const policy = PolicyLedger.builtIn();

  group('walkStructuredType', () {
    test('walks a concrete BoxDecoration-like type', () {
      final borderRadius = fakes.fakeClassElement(
        'BorderRadius',
        libraryIdentifier: 'package:flutter/src/painting/border_radius.dart',
      );
      final boxBorder = fakes.fakeClassElement(
        'BoxBorder',
        libraryIdentifier: 'package:flutter/src/painting/box_border.dart',
      );
      final gradient = fakes.fakeClassElement(
        'Gradient',
        libraryIdentifier: 'package:flutter/src/painting/gradient.dart',
      );
      final boxDecoration = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
        fields: [
          fakes.fakeFieldElement(
            'color',
            fakes.fakeInterfaceType(
              'Color',
              libraryIdentifier: 'dart:ui',
            ),
          ),
          fakes.fakeFieldElement('border', boxBorder.thisType),
          fakes.fakeFieldElement('borderRadius', borderRadius.thisType),
          fakes.fakeFieldElement('gradient', gradient.thisType),
        ],
      );

      final result = walkStructuredType(
        element: boxDecoration,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#BoxDecoration',
        visited: <String>{},
        depth: 0,
      );

      final ir = result.ir!;
      expect(ir.name, 'BoxDecoration');
      expect(
        ir.fields.map((field) => field.name),
        ['color', 'border', 'borderRadius', 'gradient'],
      );
      expect(ir.fields[0].type.kind, ResolvedTypeKind.color);
      // Abstract-base fields whose Flutter type maps to a legacy
      // PropertyType (BoxBorder -> border, Gradient -> gradient) lower
      // to that kind directly. Without this projection the wire shape
      // would carry `type: structured` with no structuredRef, which
      // violates the schema codec's structuredRef-when-structured
      // invariant. The diagnostic still surfaces the abstract-base
      // condition for the eventual union-resolver pass.
      expect(ir.fields[1].type.kind, ResolvedTypeKind.border);
      expect(
        ir.fields[1].diagnostics.single.code,
        issue_codes.abstractTypeAwaitingUnion,
      );
      expect(ir.fields[2].type.kind, ResolvedTypeKind.structured);
      // Concrete structured field carries a placeholder structuredRef
      // until the allocator pass resolves the descendant's wire ID.
      expect(ir.fields[2].type.structuredRef, isNotNull);
      expect(
        ir.fields[2].type.structuredRef!.library,
        WidgetLibrary.core.namespace,
      );
      expect(
        ir.fields[2].type.structuredRef!.wireId,
        WireId.unallocatedStructured,
      );
      // structuredRef stays null on the abstract-base branch in either
      // sub-case: the legacy-fallback kinds are inherently anonymous,
      // and the unresolved-fallback case has no descendant entry yet.
      expect(ir.fields[1].type.structuredRef, isNull);
      expect(ir.fields[3].type.kind, ResolvedTypeKind.gradient);
      expect(ir.fields[3].type.structuredRef, isNull);
      expect(
        ir.fields[3].diagnostics.single.code,
        issue_codes.abstractTypeAwaitingUnion,
      );
      expect(result.descendants.map((entry) => entry.name), ['BorderRadius']);
    });

    test(
        'concrete structured field lowers to PropertyType.structured + '
        'preserves structuredRef', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {
            'package:test/types.dart#Host',
            'package:test/types.dart#Inner',
          },
          abstractTypes: {},
        ),
      );
      final inner = fakes.fakeClassElement('Inner');
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement('inner', inner.thisType),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      final fieldIr = result.ir!.fields.single;
      expect(fieldIr.type.kind, ResolvedTypeKind.structured);
      expect(fieldIr.type.structuredRef, isNotNull);
      expect(
        fieldIr.type.structuredRef!.library,
        WidgetLibrary.core.namespace,
      );
      expect(fieldIr.structuredRefFqn, 'package:test/types.dart#Inner');

      final lowered = lowerStructuredField(fieldIr);
      expect(lowered.type, PropertyType.structured);
      expect(lowered.structuredRef, isNotNull);
      expect(lowered.structuredRef!.library, WidgetLibrary.core.namespace);
      expect(lowered.structuredRef!.wireId, WireId.unallocatedStructured);
    });

    test(
        'flags a descendant that carries an unresolved union reference with '
        'an info diagnostic', () {
      // Chain: Host (concrete) -> Mid (concrete) -> Gradient (abstract union
      // base). The walker materializes Mid as a shallow descendant stub
      // WITHOUT re-walking Mid's own fields, so Mid's Gradient field is not
      // resolved into a union here. The stub should carry an info diagnostic
      // marking the unfollowed reference, never an error.
      const hostFqn = 'package:test/types.dart#Host';
      const midFqn = 'package:test/types.dart#Mid';
      final ledger = policy.extend(
        structuredWalk: StructuredWalkPolicy(
          concreteTypes: {
            ...policy.structuredWalk.concreteTypes,
            hostFqn,
            midFqn,
          },
          abstractTypes: policy.structuredWalk.abstractTypes,
          maxDepth: policy.structuredWalk.maxDepth,
        ),
      );
      final gradient = fakes.fakeClassElement(
        'Gradient',
        libraryIdentifier: 'package:flutter/src/painting/gradient.dart',
      );
      final mid = fakes.fakeClassElement(
        'Mid',
        fields: [
          fakes.fakeFieldElement('gradient', gradient.thisType),
        ],
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement('mid', mid.thisType),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      // The host's own field resolves to the concrete descendant ref.
      expect(result.ir!.fields.single.name, 'mid');
      expect(result.ir!.fields.single.type.kind, ResolvedTypeKind.structured);

      // The descendant stub for Mid carries the info diagnostic for the
      // unresolved Gradient union reference.
      final midStub =
          result.descendants.singleWhere((entry) => entry.name == 'Mid');
      final diagnostic = midStub.diagnostics.singleWhere(
        (d) => d.code == issue_codes.descendantUnionReferenceUndiscovered,
      );
      expect(diagnostic.severity, DiagnosticSeverity.info);
      expect(diagnostic.target, 'Mid');

      // No error-severity diagnostic appears anywhere in the result.
      final allDiagnostics = <DiagnosticIR>[
        ...result.ir!.diagnostics,
        for (final field in result.ir!.fields) ...field.diagnostics,
        for (final descendant in result.descendants) ...descendant.diagnostics,
      ];
      expect(
        allDiagnostics.where((d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('does not flag a descendant whose fields are all scalar / non-union',
        () {
      // Chain: Host (concrete) -> Plain (concrete) with only a scalar field.
      // The shallow descendant walk leaves no abstract-base reference
      // unfollowed, so no descendant-union diagnostic is emitted.
      const hostFqn = 'package:test/types.dart#Host';
      const plainFqn = 'package:test/types.dart#Plain';
      final ledger = policy.extend(
        structuredWalk: StructuredWalkPolicy(
          concreteTypes: {
            ...policy.structuredWalk.concreteTypes,
            hostFqn,
            plainFqn,
          },
          abstractTypes: policy.structuredWalk.abstractTypes,
          maxDepth: policy.structuredWalk.maxDepth,
        ),
      );
      final plain = fakes.fakeClassElement(
        'Plain',
        fields: [
          fakes.fakeFieldElement(
            'label',
            fakes.fakeInterfaceType(
              'String',
              libraryIdentifier: 'dart:core',
            ),
          ),
        ],
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement('plain', plain.thisType),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      final plainStub =
          result.descendants.singleWhere((entry) => entry.name == 'Plain');
      expect(
        plainStub.diagnostics
            .where(
              (d) => d.code == issue_codes.descendantUnionReferenceUndiscovered,
            )
            .isEmpty,
        isTrue,
      );
    });

    test('short-circuits an abstract base type', () {
      final gradient = fakes.fakeClassElement(
        'Gradient',
        libraryIdentifier: 'package:flutter/src/painting/gradient.dart',
      );

      final result = walkStructuredType(
        element: gradient,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        visited: <String>{},
        depth: 0,
      );

      final ir = result.ir!;
      expect(ir.fields, isEmpty);
      expect(ir.variants, isEmpty);
      expect(ir.diagnostics.single.code, issue_codes.abstractTypeAwaitingUnion);
      expect(result.descendants, isEmpty);
    });

    test('shape union-base field lowers to shapeBorder + carries a union ref',
        () {
      // ShapeDecoration is not on the built-in concrete allowlist, so the
      // entry point is added to the walk policy while the built-in
      // abstract bases (including ShapeBorder) are preserved.
      const shapeDecorationFqn =
          'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration';
      final ledger = policy.extend(
        structuredWalk: StructuredWalkPolicy(
          concreteTypes: {
            ...policy.structuredWalk.concreteTypes,
            shapeDecorationFqn,
          },
          abstractTypes: policy.structuredWalk.abstractTypes,
          maxDepth: policy.structuredWalk.maxDepth,
        ),
      );
      final shapeBorder = fakes.fakeClassElement(
        'ShapeBorder',
        libraryIdentifier: 'package:flutter/src/painting/borders.dart',
      );
      final host = fakes.fakeClassElement(
        'ShapeDecoration',
        libraryIdentifier: 'package:flutter/src/painting/shape_decoration.dart',
        fields: [
          fakes.fakeFieldElement('shape', shapeBorder.thisType),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#ShapeDecoration',
        visited: <String>{},
        depth: 0,
      );

      final fieldIr = result.ir!.fields.single;
      // ShapeBorder has a dedicated value type, and because it is also a
      // registered union base, the field carries the union reference that
      // later resolves to its concrete shape variants.
      expect(fieldIr.type.kind, ResolvedTypeKind.shapeBorder);
      expect(fieldIr.type.structuredRef, isNull);
      expect(fieldIr.type.unionRef, isNotNull);
      expect(fieldIr.type.unionRef!.library, WidgetLibrary.core.namespace);
      expect(fieldIr.type.unionRef!.wireId, WireId.unallocatedUnion);
      expect(fieldIr.type.valueShape, isNotNull);
      expect(fieldIr.type.valueShape!.propertyType, PropertyType.shapeBorder);
      expect(
        fieldIr.type.valueShape!.wireCodec,
        CatalogWireCodec.rfwShapeBorder,
      );
      expect(
        fieldIr.unionSourceKey,
        'restage.core#package:flutter/src/painting/borders.dart#ShapeBorder',
      );

      final lowered = lowerStructuredField(fieldIr);
      expect(lowered.type, PropertyType.shapeBorder);
      expect(lowered.unionRef, isNotNull);
      expect(lowered.unionRef!.wireId, WireId.unallocatedUnion);
    });

    test('legacy-fallback union-base field carries a union ref too', () {
      final gradient = fakes.fakeClassElement(
        'Gradient',
        libraryIdentifier: 'package:flutter/src/painting/gradient.dart',
      );
      final host = fakes.fakeClassElement(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
        fields: [
          fakes.fakeFieldElement('gradient', gradient.thisType),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#BoxDecoration',
        visited: <String>{},
        depth: 0,
      );

      final fieldIr = result.ir!.fields.single;
      // The legacy fallback kind is preserved AND the union reference is
      // attached, since Gradient is a registered union base.
      expect(fieldIr.type.kind, ResolvedTypeKind.gradient);
      expect(fieldIr.type.structuredRef, isNull);
      expect(fieldIr.type.unionRef, isNotNull);
      expect(fieldIr.type.unionRef!.wireId, WireId.unallocatedUnion);
      expect(
        fieldIr.unionSourceKey,
        'restage.core#package:flutter/src/painting/gradient.dart#Gradient',
      );
    });

    test('records and skips a denylisted field', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'controller',
            fakes.fakeInterfaceType('TextEditingController'),
          ),
          fakes.fakeFieldElement(
            'label',
            fakes.fakeInterfaceType(
              'String',
              libraryIdentifier: 'dart:core',
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      final ir = result.ir!;
      expect(ir.fields.map((field) => field.name), ['label']);
      expect(ir.policyTrace.single, isA<PolicyDecisionIR>());
      expect(ir.policyTrace.single.target, 'controller');
      expect(ir.diagnostics.single.code, issue_codes.denylistedPropertyType);
    });

    test('classifies inline scalar fields', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Scalars'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Scalars',
        fields: [
          fakes.fakeFieldElement(
            'color',
            fakes.fakeInterfaceType('Color'),
          ),
          fakes.fakeFieldElement(
            'opacity',
            fakes.fakeInterfaceType(
              'double',
              libraryIdentifier: 'dart:core',
            ),
          ),
          fakes.fakeFieldElement(
            'label',
            fakes.fakeInterfaceType(
              'String',
              libraryIdentifier: 'dart:core',
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Scalars',
        visited: <String>{},
        depth: 0,
      );

      expect(
        result.ir!.fields.map((field) => field.type.kind),
        [
          ResolvedTypeKind.color,
          ResolvedTypeKind.real,
          ResolvedTypeKind.string,
        ],
      );
    });

    test('materializes enum fields with enum value shapes', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final axisElement = fakes.fakeEnumElement(
        'Axis',
        libraryIdentifier: 'package:flutter/src/painting/basic_types.dart',
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'axis',
            fakes.fakeInterfaceTypeForElement(axisElement),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['axis']);
      final field = result.ir!.fields.single;
      expect(field.name, 'axis');
      expect(field.type.kind, ResolvedTypeKind.enumValue);
      expect(field.type.valueShape, isA<EnumShape>());
      final shape = field.type.valueShape! as EnumShape;
      expect(shape.propertyType, PropertyType.enumValue);
      expect(
        shape.enumRef,
        const DartTypeRef(
          libraryUri: 'package:flutter/src/painting/basic_types.dart',
          symbolName: 'Axis',
        ),
      );
      expect(result.ir!.diagnostics, isEmpty);
    });

    test('materializes list fields with list value shapes', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'tags',
            fakes.fakeInterfaceType(
              'List',
              libraryIdentifier: 'dart:core',
              typeArguments: [
                fakes.fakeInterfaceType(
                  'String',
                  libraryIdentifier: 'dart:core',
                ),
              ],
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['tags']);
      final field = result.ir!.fields.single;
      expect(field.name, 'tags');
      expect(field.type.kind, ResolvedTypeKind.stringList);
      expect(field.type.valueShape, isA<ListShape>());
      final shape = field.type.valueShape! as ListShape;
      expect(shape.propertyType, PropertyType.stringList);
      expect(shape.itemShape, isA<ScalarShape>());
      expect(shape.itemShape.propertyType, PropertyType.string);
      expect(result.ir!.diagnostics, isEmpty);
    });

    test('unwraps WidgetStateProperty fields to their value shapes', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'overlayColor',
            fakes.fakeInterfaceType(
              'WidgetStateProperty',
              libraryIdentifier:
                  'package:flutter/src/widgets/widget_state.dart',
              typeArguments: [
                fakes.fakeInterfaceType(
                  'Color',
                  libraryIdentifier: 'dart:ui',
                ),
              ],
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['overlayColor']);
      final field = result.ir!.fields.single;
      expect(field.name, 'overlayColor');
      expect(field.type.kind, ResolvedTypeKind.color);
      expect(field.type.valueShape, isA<ScalarShape>());
      expect(field.type.valueShape!.propertyType, PropertyType.color);
      expect(result.ir!.diagnostics, isEmpty);
    });

    test('materializes typed scalar fields with scalar value shapes', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'weight',
            fakes.fakeInterfaceType(
              'FontWeight',
              libraryIdentifier: 'package:flutter/src/painting/text_style.dart',
            ),
          ),
          fakes.fakeFieldElement(
            'curve',
            fakes.fakeInterfaceType(
              'Curve',
              libraryIdentifier: 'package:flutter/src/animation/curves.dart',
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), [
        'weight',
        'curve',
      ]);
      final weight = result.ir!.fields[0];
      expect(weight.name, 'weight');
      expect(weight.type.kind, ResolvedTypeKind.fontWeight);
      expect(weight.type.valueShape, isA<ScalarShape>());
      final weightShape = weight.type.valueShape! as ScalarShape;
      expect(weightShape.propertyType, PropertyType.fontWeight);
      expect(
        weightShape.dartTypeRef,
        const DartTypeRef(
          libraryUri: 'package:flutter/src/painting/text_style.dart',
          symbolName: 'FontWeight',
        ),
      );
      final curve = result.ir!.fields[1];
      expect(curve.name, 'curve');
      expect(curve.type.kind, ResolvedTypeKind.curve);
      expect(curve.type.valueShape, isA<ScalarShape>());
      final curveShape = curve.type.valueShape! as ScalarShape;
      expect(curveShape.propertyType, PropertyType.curve);
      expect(
        curveShape.dartTypeRef,
        const DartTypeRef(
          libraryUri: 'package:flutter/src/animation/curves.dart',
          symbolName: 'Curve',
        ),
      );
      expect(result.ir!.diagnostics, isEmpty);
    });

    test('skips private and static fields', () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            '_private',
            fakes.fakeInterfaceType(
              'String',
              libraryIdentifier: 'dart:core',
            ),
          ),
          fakes.fakeFieldElement(
            'staticField',
            fakes.fakeInterfaceType(
              'String',
              libraryIdentifier: 'dart:core',
            ),
            isStatic: true,
          ),
          fakes.fakeFieldElement(
            'visible',
            fakes.fakeInterfaceType(
              'bool',
              libraryIdentifier: 'dart:core',
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['visible']);
    });

    test(
        'skips getter-backed synthetic fields without deprecated analyzer APIs',
        () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:test/types.dart#Host'},
          abstractTypes: {},
        ),
      );
      final host = fakes.fakeClassElement(
        'Host',
        fields: [
          fakes.fakeFieldElement(
            'hashCode',
            fakes.fakeInterfaceType(
              'int',
              libraryIdentifier: 'dart:core',
            ),
            isOriginGetterSetter: true,
          ),
          fakes.fakeFieldElement(
            'runtimeType',
            fakes.fakeInterfaceType(
              'Type',
              libraryIdentifier: 'dart:core',
            ),
            isOriginGetterSetter: true,
          ),
          fakes.fakeFieldElement(
            'isComplex',
            fakes.fakeInterfaceType(
              'bool',
              libraryIdentifier: 'dart:core',
            ),
            isOriginGetterSetter: true,
          ),
          fakes.fakeFieldElement(
            'visible',
            fakes.fakeInterfaceType(
              'bool',
              libraryIdentifier: 'dart:core',
            ),
          ),
        ],
      );

      final result = walkStructuredType(
        element: host,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Host',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['visible']);
    });

    test('keeps value getters that are part of structured value shape', () {
      // A value type like Offset exposes its constructible state (dx, dy) as
      // getters over private fields, so they are getter-backed
      // (isOriginGetterSetter) yet must be KEPT. The discriminator keeps them
      // because they are parameters of the generative constructor; the Object
      // getter hashCode reaches no generative constructor and is dropped.
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'dart:ui#Offset'},
          abstractTypes: {},
        ),
      );
      final doubleType = fakes.fakeInterfaceType(
        'double',
        libraryIdentifier: 'dart:core',
      );
      final constructors = <ConstructorElement>[];
      final fields = <FieldElement>[];
      final offset = fakes.fakeClassElement(
        'Offset',
        libraryIdentifier: 'dart:ui',
        fields: fields,
        constructors: constructors,
      );
      fields.addAll([
        fakes.fakeFieldElement('dx', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement('dy', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement(
          'hashCode',
          fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
          isOriginGetterSetter: true,
        ),
      ]);
      constructors.add(
        fakes.fakeConstructorElement(
          '',
          returnType: offset.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('dx', doubleType),
            fakes.fakeFormalParameterElement('dy', doubleType),
          ],
        ),
      );

      final result = walkStructuredType(
        element: offset,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Offset',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['dx', 'dy']);
    });

    test(
        'drops computed getters not reachable via a generative constructor '
        '(factory-only params and getter-only members)', () {
      // The discriminator for getter-backed fields is "is this a parameter of
      // some public GENERATIVE (non-factory) constructor?". A type's
      // constructible state is what a generative constructor accepts; a
      // value reachable only through a FACTORY constructor is a conversion
      // (e.g. Offset.fromDirection computes dx/dy from polar inputs), not
      // stored state, so its parameters do NOT rescue the matching getters.
      // Getter-backed members reachable by no constructor at all (isUniform)
      // are computed and dropped too.
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'dart:ui#Offset'},
          abstractTypes: {},
        ),
      );
      final doubleType = fakes.fakeInterfaceType(
        'double',
        libraryIdentifier: 'dart:core',
      );
      final boolType = fakes.fakeInterfaceType(
        'bool',
        libraryIdentifier: 'dart:core',
      );
      final constructors = <ConstructorElement>[];
      final fields = <FieldElement>[];
      final offset = fakes.fakeClassElement(
        'Offset',
        libraryIdentifier: 'dart:ui',
        fields: fields,
        constructors: constructors,
      );
      fields.addAll([
        // Real constructible state — getter-backed (Offset exposes dx/dy as
        // getters over private fields) but accepted by the generative ctor.
        fakes.fakeFieldElement('dx', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement('dy', doubleType, isOriginGetterSetter: true),
        // Computed getters reachable only via the FACTORY fromDirection.
        fakes.fakeFieldElement(
          'distance',
          doubleType,
          isOriginGetterSetter: true,
        ),
        fakes.fakeFieldElement(
          'direction',
          doubleType,
          isOriginGetterSetter: true,
        ),
        // Computed getter reachable by no constructor at all.
        fakes.fakeFieldElement(
          'isFinite',
          boolType,
          isOriginGetterSetter: true,
        ),
      ]);
      constructors.addAll([
        // Generative (non-factory) ctor: dx/dy are constructible state.
        fakes.fakeConstructorElement(
          '',
          returnType: offset.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('dx', doubleType),
            fakes.fakeFormalParameterElement('dy', doubleType),
          ],
        ),
        // Factory ctor: a conversion. Its direction/distance params must NOT
        // rescue the computed getters of the same name.
        fakes.fakeConstructorElement(
          'fromDirection',
          isFactory: true,
          returnType: offset.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('direction', doubleType),
            fakes.fakeFormalParameterElement('distance', doubleType),
          ],
        ),
      ]);

      final result = walkStructuredType(
        element: offset,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Offset',
        visited: <String>{},
        depth: 0,
      );

      expect(result.ir!.fields.map((field) => field.name), ['dx', 'dy']);
    });

    test('fills stable dart:ui Offset descriptions when dartdocs are absent',
        () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'dart:ui#Offset'},
          abstractTypes: {},
        ),
      );
      final doubleType = fakes.fakeInterfaceType(
        'double',
        libraryIdentifier: 'dart:core',
      );
      final constructors = <ConstructorElement>[];
      final methods = <MethodElement>[];
      final fields = <FieldElement>[];
      final offset = fakes.fakeClassElement(
        'Offset',
        libraryIdentifier: 'dart:ui',
        fields: fields,
        constructors: constructors,
        methods: methods,
      );
      fields.addAll([
        fakes.fakeFieldElement('dx', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement('dy', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement(
          'distance',
          doubleType,
          isOriginGetterSetter: true,
        ),
        fakes.fakeFieldElement(
          'direction',
          doubleType,
          isOriginGetterSetter: true,
        ),
        fakes.fakeStaticConstField('infinite', offset.thisType),
        fakes.fakeStaticConstField('zero', offset.thisType),
      ]);
      constructors.addAll([
        fakes.fakeConstructorElement(
          '',
          returnType: offset.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('dx', doubleType),
            fakes.fakeFormalParameterElement('dy', doubleType),
          ],
        ),
        fakes.fakeConstructorElement(
          'fromDirection',
          isFactory: true,
          returnType: offset.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('direction', doubleType),
            fakes.fakeFormalParameterElement('distance', doubleType),
          ],
        ),
      ]);
      methods.add(
        fakes.fakeMethodElement('lerp', returnType: offset.thisType),
      );

      final result = walkStructuredType(
        element: offset,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Offset',
        visited: <String>{},
        depth: 0,
      );

      final ir = result.ir!;
      expect(ir.description, 'An immutable 2D floating-point offset.');
      expect(
        ir.variants
            .singleWhere(
              (variant) =>
                  variant.sourceKind == VariantSourceKind.constructor &&
                  variant.namedConstructor == null,
            )
            .description,
        'Creates an offset. The first argument sets [dx], the horizontal '
        'component, and the second sets [dy], the vertical component.',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) => variant.namedConstructor == 'fromDirection',
            )
            .description,
        'Creates an offset from its [direction] and [distance].',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) =>
                  variant.sourceKind == VariantSourceKind.staticMethod &&
                  variant.staticAccessor == 'lerp',
            )
            .description,
        'Linearly interpolate between two offsets.',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) =>
                  variant.sourceKind == VariantSourceKind.constValue &&
                  variant.staticAccessor == 'zero',
            )
            .description,
        'An offset with zero magnitude.',
      );
    });

    test('fills stable dart:ui Radius descriptions when dartdocs are absent',
        () {
      final ledger = policy.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'dart:ui#Radius'},
          abstractTypes: {},
        ),
      );
      final doubleType = fakes.fakeInterfaceType(
        'double',
        libraryIdentifier: 'dart:core',
      );
      final constructors = <ConstructorElement>[];
      final methods = <MethodElement>[];
      final fields = <FieldElement>[];
      final radius = fakes.fakeClassElement(
        'Radius',
        libraryIdentifier: 'dart:ui',
        fields: fields,
        constructors: constructors,
        methods: methods,
      );
      fields.addAll([
        fakes.fakeFieldElement('x', doubleType, isOriginGetterSetter: true),
        fakes.fakeFieldElement('y', doubleType, isOriginGetterSetter: true),
        fakes.fakeStaticConstField('zero', radius.thisType),
      ]);
      constructors.add(
        fakes.fakeConstructorElement(
          'elliptical',
          returnType: radius.thisType,
          parameters: [
            fakes.fakeFormalParameterElement('x', doubleType),
            fakes.fakeFormalParameterElement('y', doubleType),
          ],
        ),
      );
      methods.add(
        fakes.fakeMethodElement('lerp', returnType: radius.thisType),
      );

      final result = walkStructuredType(
        element: radius,
        library: WidgetLibrary.core,
        policy: ledger,
        location: 'test#Radius',
        visited: <String>{},
        depth: 0,
      );

      final ir = result.ir!;
      expect(
        ir.description,
        'A radius for either circular or elliptical shapes.',
      );
      expect(
        ir.fields.singleWhere((field) => field.name == 'x').description,
        'The radius value on the horizontal axis.',
      );
      expect(
        ir.fields.singleWhere((field) => field.name == 'y').description,
        'The radius value on the vertical axis.',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) => variant.namedConstructor == 'elliptical',
            )
            .description,
        'Constructs an elliptical radius with the given radii.',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) =>
                  variant.sourceKind == VariantSourceKind.staticMethod &&
                  variant.staticAccessor == 'lerp',
            )
            .description,
        'Linearly interpolate between two radii.',
      );
      expect(
        ir.variants
            .singleWhere(
              (variant) =>
                  variant.sourceKind == VariantSourceKind.constValue &&
                  variant.staticAccessor == 'zero',
            )
            .description,
        'A radius with [x] and [y] values set to zero.',
      );
    });
  });
}
