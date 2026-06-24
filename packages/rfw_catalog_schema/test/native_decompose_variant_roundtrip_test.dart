import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Per-variant **byte-goldens** for the five native-decompose schema types.
///
/// Each fixture embeds one variant in the smallest valid catalog and asserts
/// two things through the production codec:
///
///  1. **Byte-golden:** `encodeCatalog(fixture)` equals an exact committed
///     golden file (`test/fixtures/native_decompose/<name>.json`) captured
///     from today's encoder. This pins every byte — discriminator strings,
///     field keys, key *order*, and null emission — for that variant,
///     independent of whether any built-in catalog happens to exercise it.
///  2. **Round-trip:** `encodeCatalog(decodeCatalog(encodeCatalog(fixture)))`
///     equals `encodeCatalog(fixture)`. Cheap, and catches an asymmetric
///     decode that drops a field.
///
/// Why a full byte-golden and not just a discriminator substring: a future
/// per-subclass encode rewrite (the sealed-types swap) can move the wire in
/// ways self-consistency and a discriminator-substring both miss — a
/// field-key rename, or a key *reorder* (decode reads keys order-independently,
/// so both sides still agree). The frozen golden file is the only thing that
/// makes "the wire didn't move" falsifiable for variants absent from the
/// committed catalogs. The goldens live in a separate, frozen directory
/// precisely so a representation change to the builders below cannot silently
/// relax them.
///
/// Regenerate goldens (only when the wire is *intended* to change) with:
///   `REGEN_GOLDENS=1 dart test test/native_decompose_variant_roundtrip_test.dart`
///
/// The one checklist item that is NOT a representable wire state — a
/// null-literal *parameter default* — is locked by a negative test asserting
/// `encodeCatalog` rejects it (a null-literal *argument binding* IS valid; see
/// that fixture).
void main() {
  group('CatalogValueShape byte-goldens', () {
    test('scalar', () {
      _expectWireGolden(
        _shapeCatalog(
          const ScalarShape(propertyType: PropertyType.string),
        ),
        'shape_scalar',
      );
    });

    test('scalar carrying wireCodec + dartTypeRef', () {
      _expectWireGolden(
        _shapeCatalog(
          const ScalarShape(
            propertyType: PropertyType.gradient,
            dartTypeRef: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'Gradient',
            ),
            wireCodec: CatalogWireCodec.rfwGradient,
          ),
        ),
        'shape_scalar_wirecodec_darttyperef',
      );
    });

    test('enumValue', () {
      _expectWireGolden(
        _shapeCatalog(
          const EnumShape(
            propertyType: PropertyType.enumValue,
            enumRef: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BoxShape',
            ),
          ),
        ),
        'shape_enum',
      );
    });

    test('structured', () {
      _expectWireGolden(
        _shapeCatalog(
          StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: _structuredRef,
          ),
        ),
        'shape_structured',
      );
    });

    test('union', () {
      _expectWireGolden(
        _shapeCatalog(
          UnionShape(
            propertyType: PropertyType.gradient,
            unionRef: _unionRef,
          ),
        ),
        'shape_union',
      );
    });

    test('list (item scalar)', () {
      _expectWireGolden(
        _shapeCatalog(
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: ScalarShape(propertyType: PropertyType.string),
          ),
        ),
        'shape_list_scalar',
      );
    });

    test('list (item structured)', () {
      _expectWireGolden(
        _shapeCatalog(
          ListShape(
            propertyType: PropertyType.boxShadowList,
            itemShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: _structuredRef,
            ),
          ),
        ),
        'shape_list_structured',
      );
    });

    test('nested list (list whose itemShape is itself a list)', () {
      _expectWireGolden(
        _shapeCatalog(
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(propertyType: PropertyType.string),
            ),
          ),
        ),
        'shape_nested_list',
      );
    });

    // The `union` golden above anchors only `gradient`; pin the other two
    // discriminated-union propertyTypes so the union encode is falsifiable for
    // each.
    test('union (border)', () {
      _expectWireGolden(
        _shapeCatalog(
          UnionShape(
            propertyType: PropertyType.border,
            unionRef: _unionRef,
          ),
        ),
        'shape_union_border',
      );
    });

    test('union (shapeBorder)', () {
      _expectWireGolden(
        _shapeCatalog(
          UnionShape(
            propertyType: PropertyType.shapeBorder,
            unionRef: _unionRef,
          ),
        ),
        'shape_union_shapeborder',
      );
    });

    // Close the recursive-emission matrix: a list whose item is a union, and
    // one whose item is an enum (the scalar/structured/list item cases are
    // already anchored above).
    test('list (item union)', () {
      _expectWireGolden(
        _shapeCatalog(
          ListShape(
            propertyType: PropertyType.boxShadowList,
            itemShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef: _unionRef,
            ),
          ),
        ),
        'shape_list_union',
      );
    });

    test('list (item enum)', () {
      _expectWireGolden(
        _shapeCatalog(
          const ListShape(
            propertyType: PropertyType.stringList,
            itemShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                libraryUri: 'package:flutter/painting.dart',
                symbolName: 'BoxShape',
              ),
            ),
          ),
        ),
        'shape_list_enum',
      );
    });
  });

  group('DecompositionValueTransform byte-goldens', () {
    test('identity', () {
      _expectWireGolden(
        _recipeCatalog(const IdentityTransform()),
        'transform_identity',
      );
    });

    test('constructVariant (with argument bindings)', () {
      _expectWireGolden(
        _recipeCatalog(_constructVariant()),
        'transform_construct_variant',
      );
    });

    test('projectList', () {
      _expectWireGolden(
        _recipeCatalog(
          const ProjectListTransform(itemTransform: IdentityTransform()),
        ),
        'transform_project_list',
      );
    });

    test('projectList recursive (itemTransform is itself a projectList)', () {
      _expectWireGolden(
        _recipeCatalog(
          const ProjectListTransform(
            itemTransform: ProjectListTransform(
              itemTransform: IdentityTransform(),
            ),
          ),
        ),
        'transform_project_list_recursive',
      );
    });

    test('coerceScalar', () {
      _expectWireGolden(
        _recipeCatalog(
          const CoerceScalarTransform(scalarCoercion: 'toDouble'),
        ),
        'transform_coerce_scalar',
      );
    });
  });

  group('FactoryParameterDefaultValue byte-goldens', () {
    test('literal (non-null)', () {
      _expectWireGolden(
        _defaultCatalog(
          const LiteralParameterDefault(true),
          const ScalarShape(propertyType: PropertyType.boolean),
        ),
        'default_literal',
      );
    });

    test('staticMember', () {
      _expectWireGolden(
        _defaultCatalog(
          const StaticMemberParameterDefault(
            staticType: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BorderSide',
            ),
            memberName: 'none',
          ),
          const ScalarShape(propertyType: PropertyType.string),
        ),
        'default_static_member',
      );
    });

    // Negative lock (per coordinator answer): a null-literal *parameter
    // default* is NOT a representable v4 wire state. `encodeCatalog`'s
    // canonical validator rejects a literal whose value is not
    // bool/int/double/String; null-default semantics are carried by the
    // `defaultPolicy` enum (omitWhenNull/emitNull/useFlutterDefault), so a
    // null literal default would be redundant/ambiguous. This locks the
    // boundary so the sealed LiteralParameterDefault cannot silently start
    // round-tripping a state the wire rejects. Contrast: a null-literal
    // *argument binding* IS valid (see the TransformArgumentBinding group).
    test('literal null is rejected by the canonical encoder (negative lock)',
        () {
      final catalog = _defaultCatalog(
        const LiteralParameterDefault(null),
        const ScalarShape(propertyType: PropertyType.string),
      );
      expect(
        () => encodeCatalog(catalog),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('literal default must be bool, int, double, or String'),
          ),
        ),
      );
    });
  });

  group('FactoryReceiver byte-goldens', () {
    test('resultStructuredType', () {
      _expectWireGolden(
        _recipeCatalog(
          const IdentityTransform(),
          constructionReceiver: const ResultStructuredTypeReceiver(),
        ),
        'receiver_result_structured_type',
      );
    });

    test('owningWidgetType', () {
      _expectWireGolden(
        _recipeCatalog(
          const IdentityTransform(),
          constructionReceiver: const OwningWidgetTypeReceiver(),
        ),
        'receiver_owning_widget_type',
      );
    });

    test('explicitDartType', () {
      _expectWireGolden(
        _recipeCatalog(
          const IdentityTransform(),
          constructionReceiver: const ExplicitDartTypeReceiver(
            DartTypeRef(
              libraryUri: 'package:flutter/material.dart',
              symbolName: 'ButtonStyle',
            ),
          ),
        ),
        'receiver_explicit_dart_type',
      );
    });
  });

  group('TransformArgumentBinding byte-goldens', () {
    test('source propertyValue', () {
      _expectWireGolden(
        _recipeCatalog(_constructVariant(bindings: [_binding()])),
        'binding_source_property_value',
      );
    });

    test('source literal (non-null)', () {
      _expectWireGolden(
        _recipeCatalog(
          _constructVariant(
            bindings: [
              _binding(source: TransformArgumentSource.literal, literal: 42),
            ],
          ),
        ),
        'binding_source_literal_nonnull',
      );
    });

    test('source literal (null literal — intentional Dart null)', () {
      _expectWireGolden(
        _recipeCatalog(
          _constructVariant(
            bindings: [_binding(source: TransformArgumentSource.literal)],
          ),
        ),
        'binding_source_literal_null',
      );
    });

    test('source nestedTransform (recursive)', () {
      _expectWireGolden(
        _recipeCatalog(
          _constructVariant(
            bindings: [
              _binding(
                source: TransformArgumentSource.nestedTransform,
                nestedTransform: _constructVariant(),
              ),
            ],
          ),
        ),
        'binding_source_nested_transform',
      );
    });

    test('every nullPolicy value is pinned byte-for-byte', () {
      for (final policy in TransformNullPolicy.values) {
        _expectWireGolden(
          _recipeCatalog(
            _constructVariant(bindings: [_binding(nullPolicy: policy)]),
          ),
          'binding_null_policy_${policy.name}',
        );
      }
    });

    test('every missingPolicy value is pinned byte-for-byte', () {
      for (final policy in TransformMissingPolicy.values) {
        _expectWireGolden(
          _recipeCatalog(
            _constructVariant(bindings: [_binding(missingPolicy: policy)]),
          ),
          'binding_missing_policy_${policy.name}',
        );
      }
    });
  });
}

// --- Byte-golden oracle -----------------------------------------------------

/// Assert that `encodeCatalog(catalog)` matches the frozen golden
/// `test/fixtures/native_decompose/<name>.json` byte-for-byte, and that the
/// encoding round-trips. Set `REGEN_GOLDENS=1` to (re)write the golden from
/// the current encoder output instead of asserting against it.
void _expectWireGolden(Catalog catalog, String name) {
  final encoded = encodeCatalog(catalog);
  final file = File('test/fixtures/native_decompose/$name.json');
  if (Platform.environment['REGEN_GOLDENS'] == '1') {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
  }
  expect(
    encoded,
    file.readAsStringSync(),
    reason: 'wire byte-golden "$name" — a difference means the wire moved; '
        'regenerate with REGEN_GOLDENS=1 only if the change is intended.',
  );
  expect(
    encodeCatalog(decodeCatalog(encoded)),
    encoded,
    reason: 'round-trip stability for "$name"',
  );
}

// --- Minimal scaffolds ------------------------------------------------------

const _generatedAt = '2026-05-27T00:00:00Z';

final _structuredRef = WireIdRef(
  library: 'restage.core',
  wireId: WireId('s0001'),
);
final _unionRef = WireIdRef(library: 'restage.core', wireId: WireId('u0001'));
final _variantRef = WireIdRef(library: 'restage.core', wireId: WireId('v0001'));

/// A widget carrying one property whose `valueShape` is [shape].
Catalog _shapeCatalog(CatalogValueShape shape) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: _generatedAt,
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Probe',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Probe widget.',
          flutterType: 'package:flutter/widgets.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'prop',
              type: shape.propertyType,
              description: 'Probe property.',
              valueShape: shape,
            ),
          ],
        ),
      ],
    );

/// A widget with one decompose recipe whose field mapping carries [transform]
/// and whose construction uses [constructionReceiver].
Catalog _recipeCatalog(
  DecompositionValueTransform transform, {
  FactoryReceiver? constructionReceiver,
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: _generatedAt,
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Probe',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'Probe widget.',
          flutterType: 'package:flutter/widgets.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'prop',
              type: PropertyType.structured,
              description: 'Probe property.',
              valueShape: const ScalarShape(propertyType: PropertyType.string),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: _structuredRef,
              targetArg: 'arg',
              construction: FactoryInvocation(
                variantRef: _variantRef,
                receiver: constructionReceiver ??
                    const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: WireId('p0501'),
                  propertyRef: WireId('p0001'),
                  transform: transform,
                ),
              ],
              flatProperties: {WireId('p0501'): WireId('p0001')},
            ),
          ],
        ),
      ],
    );

/// A structured type whose single variant parameter carries [defaultValue].
Catalog _defaultCatalog(
  FactoryParameterDefaultValue? defaultValue,
  CatalogValueShape parameterShape,
) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: _generatedAt,
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      },
      widgets: const [],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'Probe',
          library: WidgetLibrary.core,
          description: 'Probe structured type.',
          sourceType: 'package:flutter/painting.dart#Probe',
          fields: const [],
          variants: [
            ConstructorVariant(
              wireId: WireId('v0001'),
              parameters: [
                FactoryParameter(
                  wireId: WireId('a0001'),
                  name: 'p',
                  kind: FactoryParameterKind.named,
                  required: false,
                  nullable: false,
                  defaultPolicy:
                      FactoryParameterDefaultPolicy.useFlutterDefault,
                  defaultValue: defaultValue,
                  valueShape: parameterShape,
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// A `constructVariant` transform with the given [bindings] (default: one
/// `propertyValue` binding).
DecompositionValueTransform _constructVariant({
  List<TransformArgumentBinding>? bindings,
}) =>
    ConstructVariantTransform(
      resultStructuredRef: _structuredRef,
      invocation: FactoryInvocation(
        variantRef: _variantRef,
        receiver: const ResultStructuredTypeReceiver(),
      ),
      argumentBindings: bindings ?? [_binding()],
    );

/// A transform argument binding on parameter `a0001`, varying only the fields
/// each fixture cares about. A `literal` source with the default (`null`)
/// `literal` is the intentional Dart-null binding.
TransformArgumentBinding _binding({
  TransformArgumentSource source = TransformArgumentSource.propertyValue,
  Object? literal,
  DecompositionValueTransform? nestedTransform,
  TransformNullPolicy nullPolicy = TransformNullPolicy.nullResult,
  TransformMissingPolicy missingPolicy = TransformMissingPolicy.nullResult,
}) {
  final parameterRef = WireId('a0001');
  switch (source) {
    case TransformArgumentSource.propertyValue:
      return PropertyValueArgumentBinding(
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
    case TransformArgumentSource.literal:
      return LiteralArgumentBinding(
        literal: literal,
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
    case TransformArgumentSource.nestedTransform:
      return NestedTransformArgumentBinding(
        nestedTransform: nestedTransform!,
        parameterRef: parameterRef,
        nullPolicy: nullPolicy,
        missingPolicy: missingPolicy,
      );
  }
}
