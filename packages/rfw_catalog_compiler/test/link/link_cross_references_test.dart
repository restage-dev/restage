import 'package:rfw_catalog_compiler/src/link/cross_ref_resolution_index.dart';
import 'package:rfw_catalog_compiler/src/link/link_cross_references.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('linkCrossReferences', () {
    test('preserves an above-baseline widget sinceVersion', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-23T00:00:00.000Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Banner',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: '',
            flutterType: 'package:test/banner.dart#Banner',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: const [],
            sinceVersion: 2,
          ),
        ],
      );

      final linked = linkCrossReferences(catalog, _fullIndex);

      expect(linked.widgets.single.sinceVersion, 2);
    });

    test('R1 resolves union member refs by memberSourceTypes', () {
      final linked = linkCrossReferences(_catalog(), _fullIndex);

      expect(
        linked.unions.single.members.map((ref) => ref.wireId),
        [WireId('s0001'), WireId('s0002')],
      );
    });

    test('R2 resolves discriminator values from aligned members', () {
      final linked = linkCrossReferences(_catalog(), _fullIndex);

      expect(
        linked.unions.single.discriminator.values.map((ref) => ref.wireId),
        [WireId('s0001'), WireId('s0002')],
      );
    });

    test('R3 resolves structured field unionRef from source key index', () {
      final linked = linkCrossReferences(
        _catalog(),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
          unionSourceKeyByField: {
            ('package:test/host.dart#Host', 'unionSlot'):
                'restage.core#package:test/shape.dart#Shape',
          },
          argTargetFieldNames: {
            ('package:test/host.dart#Host', 'constructor|only|', 'left'): [
              'left',
            ],
          },
        ),
      );

      final field = _fieldByName(linked, 'unionSlot');
      expect(field.unionRef!.wireId, WireId('u0001'));
    });

    test('R4 resolves structured field structuredRef from FQN index', () {
      final linked = linkCrossReferences(
        _catalog(),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
          unionSourceKeyByField: {
            ('package:test/host.dart#Host', 'unionSlot'):
                'restage.core#package:test/shape.dart#Shape',
          },
          argTargetFieldNames: {
            ('package:test/host.dart#Host', 'constructor|only|', 'left'): [
              'left',
            ],
          },
        ),
      );

      final field = _fieldByName(linked, 'child');
      expect(field.structuredRef!.wireId, WireId('s0003'));
    });

    test('resolves structured field valueShape refs from FQN index', () {
      final linked = linkCrossReferences(
        _catalog(
          variants: const [],
          hostFields: [
            StructuredField(
              wireId: WireId('p0003'),
              name: 'child',
              type: PropertyType.structured,
              description: '',
              valueShape: const StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId.unallocatedStructured,
                ),
              ),
            ),
          ],
        ),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
        ),
      );

      final field = _fieldByName(linked, 'child');
      expect(
        (field.valueShape! as StructuredShape).structuredRef.wireId,
        WireId('s0003'),
      );
    });

    test('resolves factory parameter valueShape refs from source index', () {
      final linked = linkCrossReferences(
        _catalog(
          variants: [
            ConstructorVariant(
              wireId: WireId('v0001'),
              parameters: [
                FactoryParameter(
                  wireId: WireId('a0001'),
                  name: 'child',
                  kind: FactoryParameterKind.named,
                  required: false,
                  nullable: true,
                  defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                  valueShape: const StructuredShape(
                    propertyType: PropertyType.structured,
                    structuredRef: WireIdRef(
                      library: 'restage.core',
                      wireId: WireId.unallocatedStructured,
                    ),
                  ),
                ),
                FactoryParameter(
                  wireId: WireId('a0002'),
                  name: 'unionSlot',
                  kind: FactoryParameterKind.named,
                  required: false,
                  nullable: true,
                  defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                  valueShape: const UnionShape(
                    propertyType: PropertyType.gradient,
                    unionRef: WireIdRef(
                      library: 'restage.core',
                      wireId: WireId.unallocatedUnion,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
          unionSourceKeyByField: {
            ('package:test/host.dart#Host', 'unionSlot'):
                'restage.core#package:test/shape.dart#Shape',
          },
        ),
      );

      final parameters = (linked.structuredTypes
              .firstWhere((entry) => entry.name == 'Host')
              .variants
              .single as ConstructorVariant)
          .parameters;
      expect(
        (parameters[0].valueShape as StructuredShape).structuredRef.wireId,
        WireId('s0003'),
      );
      expect(
        (parameters[1].valueShape as UnionShape).unionRef.wireId,
        WireId('u0001'),
      );
    });

    test('R5 resolves variant arg mappings by target field names', () {
      final linked = linkCrossReferences(
        _catalog(),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
          unionSourceKeyByField: {
            ('package:test/host.dart#Host', 'unionSlot'):
                'restage.core#package:test/shape.dart#Shape',
          },
          argTargetFieldNames: {
            ('package:test/host.dart#Host', 'constructor|only|', 'left'): [
              'left',
            ],
          },
        ),
      );

      final variant = linked.structuredTypes
          .firstWhere((entry) => entry.name == 'Host')
          .variants
          .single as ConstructorVariant;
      expect(variant.argMappings['left']!.targetFields, [WireId('p0001')]);
    });

    test('resolves one-to-one and splat arg mappings uniformly', () {
      final linked = linkCrossReferences(
        _catalog(
          variants: [
            ConstructorVariant(
              wireId: WireId('v0001'),
              namedConstructor: 'fromSide',
              argMappings: const {
                'left': ArgMapping(targetFields: [WireId.unallocatedProperty]),
                'side': ArgMapping(
                  targetFields: [
                    WireId.unallocatedProperty,
                    WireId.unallocatedProperty,
                  ],
                ),
              },
            ),
          ],
        ),
        const CrossRefResolutionIndex(
          structuredRefFqnByField: {
            ('package:test/host.dart#Host', 'child'):
                'package:test/child.dart#Child',
          },
          unionSourceKeyByField: {
            ('package:test/host.dart#Host', 'unionSlot'):
                'restage.core#package:test/shape.dart#Shape',
          },
          argTargetFieldNames: {
            ('package:test/host.dart#Host', 'constructor|fromSide|', 'left'): [
              'left',
            ],
            ('package:test/host.dart#Host', 'constructor|fromSide|', 'side'): [
              'left',
              'right',
            ],
          },
        ),
      );

      final mappings = (linked.structuredTypes
              .firstWhere((entry) => entry.name == 'Host')
              .variants
              .single as ConstructorVariant)
          .argMappings;
      expect(mappings['left']!.targetFields, [WireId('p0001')]);
      expect(
        mappings['side']!.targetFields,
        [WireId('p0001'), WireId('p0002')],
      );
    });

    test('already allocated cross refs pass through without index entries', () {
      final catalog = _catalog(
        hostFields: [
          StructuredField(
            wireId: WireId('p0001'),
            name: 'left',
            type: PropertyType.real,
            description: '',
          ),
          StructuredField(
            wireId: WireId('p0003'),
            name: 'child',
            type: PropertyType.structured,
            description: '',
            structuredRef: WireIdRef(
              library: 'restage.core',
              wireId: WireId('s0003'),
            ),
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            namedConstructor: 'only',
            argMappings: {
              'left': ArgMapping(targetFields: [WireId('p0001')]),
            },
          ),
        ],
        unionMembers: [
          WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
          WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
        ],
        discriminatorValues: [
          WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
          WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
        ],
      );

      final linked =
          linkCrossReferences(catalog, const CrossRefResolutionIndex());

      expect(
        _fieldByName(linked, 'child').structuredRef!.wireId,
        WireId('s0003'),
      );
      expect(
        (linked.structuredTypes
                .firstWhere((entry) => entry.name == 'Host')
                .variants
                .single as ConstructorVariant)
            .argMappings['left']!
            .targetFields,
        [WireId('p0001')],
      );
      expect(
        linked.unions.single.members.map((ref) => ref.wireId),
        [WireId('s0001'), WireId('s0002')],
      );
    });

    test('missing target throws CrossRefLinkException with site coordinates',
        () {
      expect(
        () => linkCrossReferences(
          _catalog(),
          const CrossRefResolutionIndex(
            structuredRefFqnByField: {
              ('package:test/host.dart#Host', 'child'):
                  'package:test/missing.dart#Missing',
            },
          ),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('structuredIdBySourceType'),
              contains('package:test/missing.dart#Missing'),
              contains('package:test/host.dart#Host.child'),
            ),
          ),
        ),
      );
    });

    test('preserves valid native decompose refs and metadata', () {
      final linked = linkCrossReferences(
        _nativeCatalog(),
        const CrossRefResolutionIndex(),
      );

      final recipe = linked.widgets.single.decomposes.single;
      final mapping = recipe.fieldMappings.single;
      final borderRadius = linked.structuredTypes
          .singleWhere((entry) => entry.name == 'BorderRadius');

      final transform = mapping.transform as ConstructVariantTransform;
      expect(recipe.construction!.variantRef.wireId, WireId('v0001'));
      expect(transform.invocation.variantRef.wireId, WireId('v0002'));
      expect(
        transform.argumentBindings.single.parameterRef,
        WireId('a0001'),
      );
      final borderRadiusVariant =
          borderRadius.variants.single as ConstructorVariant;
      expect(
        borderRadiusVariant.parameters.single.wireId,
        WireId('a0001'),
      );
      expect(linked.widgets.single.properties.single.valueShape, isNotNull);
      expect(
        borderRadiusVariant.parameters.single.valueShape,
        isNotNull,
      );
    });

    test('resolves native decompose refs from source-aware index', () {
      final linked = linkCrossReferences(
        _nativeCatalog(unallocatedRecipeRefs: true),
        CrossRefResolutionIndex(
          decompositionStructuredSourceByWidget: const {
            ('package:test/container.dart#Container', 0):
                'package:test/decoration.dart#BoxDecoration',
          },
          decompositionConstructionVariantByWidget: {
            ('package:test/container.dart#Container', 0): variantIdentity(
              const ConstructorVariant(
                wireId: WireId.unallocatedVariant,
              ),
            ),
          },
          decompositionFieldMappingNames: const {
            ('package:test/container.dart#Container', 0, 0): (
              'borderRadius',
              'radius',
            ),
          },
          decompositionTransformStructuredSourceByMapping: const {
            ('package:test/container.dart#Container', 0, 0):
                'package:test/border_radius.dart#BorderRadius',
          },
          decompositionTransformVariantByMapping: {
            ('package:test/container.dart#Container', 0, 0): variantIdentity(
              const ConstructorVariant(
                wireId: WireId.unallocatedVariant,
                namedConstructor: 'circular',
              ),
            ),
          },
          decompositionTransformParameterLabels: const {
            ('package:test/container.dart#Container', 0, 0, 0): '0',
          },
        ),
      );

      final recipe = linked.widgets.single.decomposes.single;
      final mapping = recipe.fieldMappings.single;
      expect(recipe.structuredRef.wireId, WireId('s0001'));
      expect(recipe.construction!.variantRef.wireId, WireId('v0001'));
      final transform = mapping.transform as ConstructVariantTransform;
      expect(mapping.fieldRef, WireId('p0501'));
      expect(mapping.propertyRef, WireId('p0001'));
      expect(transform.resultStructuredRef.wireId, WireId('s0002'));
      expect(transform.invocation.variantRef.wireId, WireId('v0002'));
      expect(
        transform.argumentBindings.single.parameterRef,
        WireId('a0001'),
      );
    });

    test('rejects native construction variants that do not resolve', () {
      expect(
        () => linkCrossReferences(
          _nativeCatalog(constructionVariantRef: WireId('v9999')),
          const CrossRefResolutionIndex(),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(contains('construction.variantRef'), contains('v9999')),
          ),
        ),
      );
    });

    test('rejects transform parameter refs not owned by the invoked variant',
        () {
      expect(
        () => linkCrossReferences(
          _nativeCatalog(bindingParameterRef: WireId('a0002')),
          const CrossRefResolutionIndex(),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(contains('parameterRef'), contains('a0002')),
          ),
        ),
      );
    });

    test('rejects identity mappings with incompatible value shapes', () {
      expect(
        () => linkCrossReferences(
          _nativeCatalog(
            mappingTransform: const IdentityTransform(),
          ),
          const CrossRefResolutionIndex(),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(contains('identity'), contains('valueShape')),
          ),
        ),
      );
    });

    test('backfills identity-mapped property value shapes when missing', () {
      final linked = linkCrossReferences(
        _nativeCatalog(
          mappingTransform: const IdentityTransform(),
          omitPropertyValueShape: true,
        ),
        const CrossRefResolutionIndex(),
      );
      expect(
        (linked.widgets.single.properties.single.valueShape! as StructuredShape)
            .structuredRef,
        WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
      );
    });

    test('rejects valueShape refs that do not resolve', () {
      expect(
        () => linkCrossReferences(
          _nativeCatalog(valueShapeStructuredRef: WireId('s9999')),
          const CrossRefResolutionIndex(),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(contains('valueShape'), contains('s9999')),
          ),
        ),
      );
    });

    test('rejects unallocated property valueShape refs with site diagnostics',
        () {
      expect(
        () => linkCrossReferences(
          _nativeCatalog(
            propertyValueShapeStructuredRef: WireId.unallocatedStructured,
          ),
          const CrossRefResolutionIndex(),
        ),
        throwsA(
          isA<CrossRefLinkException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('valueShape'),
              contains('does not resolve'),
              contains('s0000'),
            ),
          ),
        ),
      );
    });
  });
}

const _fullIndex = CrossRefResolutionIndex(
  structuredRefFqnByField: {
    ('package:test/host.dart#Host', 'child'): 'package:test/child.dart#Child',
  },
  unionSourceKeyByField: {
    ('package:test/host.dart#Host', 'unionSlot'):
        'restage.core#package:test/shape.dart#Shape',
  },
  argTargetFieldNames: {
    ('package:test/host.dart#Host', 'constructor|only|', 'left'): ['left'],
  },
);

Catalog _catalog({
  List<StructuredField>? hostFields,
  List<FactoryVariant>? variants,
  List<WireIdRef> unionMembers = const [
    WireIdRef(library: 'restage.core', wireId: WireId.unallocatedStructured),
    WireIdRef(library: 'restage.core', wireId: WireId.unallocatedStructured),
  ],
  List<WireIdRef> discriminatorValues = const [
    WireIdRef(library: 'restage.core', wireId: WireId.unallocatedStructured),
    WireIdRef(library: 'restage.core', wireId: WireId.unallocatedStructured),
  ],
}) {
  final effectiveHostFields = hostFields ??
      [
        StructuredField(
          wireId: WireId('p0001'),
          name: 'left',
          type: PropertyType.real,
          description: '',
        ),
        StructuredField(
          wireId: WireId('p0002'),
          name: 'right',
          type: PropertyType.real,
          description: '',
        ),
        StructuredField(
          wireId: WireId('p0003'),
          name: 'child',
          type: PropertyType.structured,
          description: '',
          structuredRef: const WireIdRef(
            library: 'restage.core',
            wireId: WireId.unallocatedStructured,
          ),
        ),
        StructuredField(
          wireId: WireId('p0004'),
          name: 'unionSlot',
          type: PropertyType.structured,
          description: '',
          unionRef: const WireIdRef(
            library: 'restage.core',
            wireId: WireId.unallocatedUnion,
          ),
        ),
      ];
  final effectiveVariants = variants ??
      [
        ConstructorVariant(
          wireId: WireId('v0001'),
          namedConstructor: 'only',
          argMappings: const {
            'left': ArgMapping(targetFields: [WireId.unallocatedProperty]),
          },
        ),
      ];

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '2026-05-21T00:00:00.000Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    },
    widgets: const [],
    structuredTypes: [
      StructuredEntry(
        wireId: WireId('s0001'),
        name: 'Circle',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/circle.dart#Circle',
        fields: const [],
        variants: const [],
      ),
      StructuredEntry(
        wireId: WireId('s0002'),
        name: 'Square',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/square.dart#Square',
        fields: const [],
        variants: const [],
      ),
      StructuredEntry(
        wireId: WireId('s0003'),
        name: 'Child',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/child.dart#Child',
        fields: const [],
        variants: const [],
      ),
      StructuredEntry(
        wireId: WireId('s0004'),
        name: 'Host',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/host.dart#Host',
        fields: effectiveHostFields,
        variants: effectiveVariants,
      ),
    ],
    unions: [
      UnionEntry(
        wireId: WireId('u0001'),
        name: 'Shape',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/shape.dart#Shape',
        memberSourceTypes: const [
          'package:test/circle.dart#Circle',
          'package:test/square.dart#Square',
        ],
        discriminator: DiscriminatorSpec(
          field: '_s',
          values: discriminatorValues,
        ),
        members: unionMembers,
      ),
    ],
  );
}

StructuredField _fieldByName(Catalog catalog, String name) {
  return catalog.structuredTypes
      .firstWhere((entry) => entry.name == 'Host')
      .fields
      .firstWhere((field) => field.name == name);
}

Catalog _nativeCatalog({
  WireId? constructionVariantRef,
  WireId? bindingParameterRef,
  DecompositionValueTransform? mappingTransform,
  WireId? valueShapeStructuredRef,
  WireId? propertyValueShapeStructuredRef,
  bool omitPropertyValueShape = false,
  bool unallocatedRecipeRefs = false,
}) {
  final boxDecorationRef = WireIdRef(
    library: 'restage.core',
    wireId:
        unallocatedRecipeRefs ? WireId.unallocatedStructured : WireId('s0001'),
  );
  final borderRadiusRecipeRef = WireIdRef(
    library: 'restage.core',
    wireId:
        unallocatedRecipeRefs ? WireId.unallocatedStructured : WireId('s0002'),
  );
  final borderRadiusRef = WireIdRef(
    library: 'restage.core',
    wireId: WireId('s0002'),
  );
  const realShape = ScalarShape(
    propertyType: PropertyType.real,
    dartTypeRef: DartTypeRef(libraryUri: 'dart:core', symbolName: 'double'),
  );
  final borderRadiusShape = StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.core',
      wireId: valueShapeStructuredRef ?? borderRadiusRef.wireId,
    ),
  );
  final borderRadiusInvocation = FactoryInvocation(
    variantRef: WireIdRef(
      library: 'restage.core',
      wireId:
          unallocatedRecipeRefs ? WireId.unallocatedVariant : WireId('v0002'),
    ),
    receiver: const ResultStructuredTypeReceiver(),
    memberName: 'circular',
  );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '2026-05-23T00:00:00.000Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Container',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test/container.dart#Container',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'radius',
            type: PropertyType.real,
            description: '',
            valueShape: omitPropertyValueShape
                ? null
                : propertyValueShapeStructuredRef == null
                    ? realShape
                    : StructuredShape(
                        propertyType: PropertyType.structured,
                        structuredRef: WireIdRef(
                          library: 'restage.core',
                          wireId: propertyValueShapeStructuredRef,
                        ),
                      ),
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: boxDecorationRef,
            targetArg: 'decoration',
            construction: FactoryInvocation(
              variantRef: WireIdRef(
                library: 'restage.core',
                wireId: unallocatedRecipeRefs
                    ? WireId.unallocatedVariant
                    : constructionVariantRef ?? WireId('v0001'),
              ),
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: unallocatedRecipeRefs
                    ? WireId.unallocatedProperty
                    : WireId('p0501'),
                propertyRef: unallocatedRecipeRefs
                    ? WireId.unallocatedProperty
                    : WireId('p0001'),
                transform: mappingTransform ??
                    ConstructVariantTransform(
                      resultStructuredRef: borderRadiusRecipeRef,
                      invocation: borderRadiusInvocation,
                      argumentBindings: [
                        PropertyValueArgumentBinding(
                          parameterRef: unallocatedRecipeRefs
                              ? WireId.unallocatedParameter
                              : bindingParameterRef ?? WireId('a0001'),
                          nullPolicy: TransformNullPolicy.nullResult,
                          missingPolicy: TransformMissingPolicy.useDefault,
                        ),
                      ],
                    ),
              ),
            ],
            flatProperties: {WireId('p0501'): WireId('p0001')},
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: WireId('s0001'),
        name: 'BoxDecoration',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/decoration.dart#BoxDecoration',
        fields: [
          StructuredField(
            wireId: WireId('p0501'),
            name: 'borderRadius',
            type: PropertyType.structured,
            description: '',
            structuredRef: borderRadiusRef,
            valueShape: borderRadiusShape,
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: [
              FactoryParameter(
                wireId: WireId('a0002'),
                name: 'borderRadius',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: true,
                defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                valueShape: borderRadiusShape,
              ),
            ],
          ),
        ],
      ),
      StructuredEntry(
        wireId: WireId('s0002'),
        name: 'BorderRadius',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:test/border_radius.dart#BorderRadius',
        fields: const [],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0002'),
            namedConstructor: 'circular',
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                position: 0,
                kind: FactoryParameterKind.positional,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: const ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                    libraryUri: 'dart:core',
                    symbolName: 'double',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
