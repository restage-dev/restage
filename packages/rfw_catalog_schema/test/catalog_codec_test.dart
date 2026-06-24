import 'dart:convert';
import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('v4 native decompose codec', () {
    test('round-trips value shapes, parameters, construction, and transforms',
        () {
      const boxShapeType = DartTypeRef(
        libraryUri: 'package:flutter/painting.dart',
        symbolName: 'BoxShape',
      );
      final boxDecorationRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('s0001'),
      );
      final shapeUnionRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('u0001'),
      );
      final shapeBorderUnionRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('u0002'),
      );
      final borderRadiusRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('s0002'),
      );
      final circularVariantRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('v0002'),
      );

      final input = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-23T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Container',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'Box model widget.',
            flutterType: 'package:flutter/widgets.dart#Container',
            childrenSlot: ChildrenSlot.single,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'decoration',
                type: PropertyType.structured,
                description: 'Decoration.',
                structuredRef: boxDecorationRef,
                valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: boxDecorationRef,
                ),
              ),
              PropertyEntry(
                wireId: WireId('p0002'),
                name: 'shape',
                type: PropertyType.enumValue,
                description: 'Decoration shape.',
                valueShape: const EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: boxShapeType,
                ),
              ),
              PropertyEntry(
                wireId: WireId('p0003'),
                name: 'gradient',
                type: PropertyType.gradient,
                description: 'Gradient.',
                valueShape: UnionShape(
                  propertyType: PropertyType.gradient,
                  unionRef: shapeUnionRef,
                  wireCodec: CatalogWireCodec.rfwGradient,
                ),
              ),
              PropertyEntry(
                wireId: WireId('p0004'),
                name: 'boxShadow',
                type: PropertyType.boxShadowList,
                description: 'Shadow list.',
                valueShape: ListShape(
                  propertyType: PropertyType.boxShadowList,
                  itemShape: StructuredShape(
                    propertyType: PropertyType.structured,
                    structuredRef: borderRadiusRef,
                  ),
                  wireCodec: CatalogWireCodec.rfwBoxShadowList,
                ),
              ),
              PropertyEntry(
                wireId: WireId('p0005'),
                name: 'shapeBorder',
                type: PropertyType.shapeBorder,
                description: 'Shape border.',
                valueShape: UnionShape(
                  propertyType: PropertyType.shapeBorder,
                  unionRef: shapeBorderUnionRef,
                  wireCodec: CatalogWireCodec.rfwShapeBorder,
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
                    wireId: WireId('v0001'),
                  ),
                  receiver: const ResultStructuredTypeReceiver(),
                ),
                fieldMappings: [
                  DecompositionFieldMapping(
                    fieldRef: WireId('p0501'),
                    propertyRef: WireId('p0004'),
                    transform: ConstructVariantTransform(
                      resultStructuredRef: borderRadiusRef,
                      invocation: FactoryInvocation(
                        variantRef: circularVariantRef,
                        receiver: const ResultStructuredTypeReceiver(),
                        memberName: 'circular',
                      ),
                      argumentBindings: [
                        PropertyValueArgumentBinding(
                          parameterRef: WireId('a0001'),
                          nullPolicy: TransformNullPolicy.nullResult,
                          missingPolicy: TransformMissingPolicy.nullResult,
                        ),
                      ],
                    ),
                  ),
                ],
                flatProperties: {
                  WireId('p0501'): WireId('p0004'),
                },
              ),
            ],
          ),
        ],
        structuredTypes: [
          StructuredEntry(
            wireId: WireId('s0001'),
            name: 'BoxDecoration',
            library: WidgetLibrary.core,
            description: 'Box decoration.',
            sourceType: 'package:flutter/painting.dart#BoxDecoration',
            fields: [
              StructuredField(
                wireId: WireId('p0501'),
                name: 'borderRadius',
                type: PropertyType.structured,
                description: 'Border radius.',
                structuredRef: borderRadiusRef,
                valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: borderRadiusRef,
                ),
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
                    valueShape: StructuredShape(
                      propertyType: PropertyType.structured,
                      structuredRef: borderRadiusRef,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StructuredEntry(
            wireId: WireId('s0002'),
            name: 'BorderRadius',
            library: WidgetLibrary.core,
            description: 'Border radius.',
            sourceType: 'package:flutter/painting.dart#BorderRadius',
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
        unions: [
          UnionEntry(
            wireId: WireId('u0001'),
            name: 'ShapeDecoration',
            library: WidgetLibrary.core,
            description: 'Shape decoration.',
            sourceType: 'package:flutter/painting.dart#ShapeDecoration',
            memberSourceTypes: const [
              'package:flutter/painting.dart#BoxDecoration',
            ],
            discriminator: DiscriminatorSpec(
              field: '_s',
              values: [boxDecorationRef],
            ),
            members: [boxDecorationRef],
          ),
          UnionEntry(
            wireId: WireId('u0002'),
            name: 'ShapeBorder',
            library: WidgetLibrary.core,
            description: 'Shape border.',
            sourceType: 'package:flutter/painting.dart#ShapeBorder',
            memberSourceTypes: const [
              'package:flutter/painting.dart#RoundedRectangleBorder',
            ],
            discriminator: DiscriminatorSpec(
              field: '_s',
              values: [boxDecorationRef],
            ),
            members: [boxDecorationRef],
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(input));
      final widget = decoded.widgets.single;
      final recipe = widget.decomposes.single;
      final mapping = recipe.fieldMappings.single;
      final borderRadiusVariant = decoded.structuredTypes
          .singleWhere((entry) => entry.name == 'BorderRadius')
          .variants
          .single;

      expect(decoded.schemaVersion, 4);
      expect(
        (widget.properties[1].valueShape! as EnumShape).enumRef,
        boxShapeType,
      );
      expect(
        widget.properties[2].valueShape!.wireCodec,
        CatalogWireCodec.rfwGradient,
      );
      expect(
        ((widget.properties[3].valueShape! as ListShape).itemShape
                as StructuredShape)
            .structuredRef,
        borderRadiusRef,
      );
      expect(widget.properties[4].type, PropertyType.shapeBorder);
      expect(
        widget.properties[4].valueShape!.wireCodec,
        CatalogWireCodec.rfwShapeBorder,
      );
      expect(recipe.targetArg, 'decoration');
      expect(
        recipe.construction!.receiver,
        isA<ResultStructuredTypeReceiver>(),
      );
      expect(
        mapping.transform,
        isA<ConstructVariantTransform>(),
      );
      expect(
        (mapping.transform as ConstructVariantTransform)
            .argumentBindings
            .single
            .parameterRef,
        WireId('a0001'),
      );
      expect(
        (borderRadiusVariant as ConstructorVariant).parameters.single.position,
        0,
      );
    });

    test('round-trips parameter mappings and typed parameter defaults', () {
      final catalog = _nativeCatalog(
        recipe: DecompositionRecipe(
          structuredRef: _boxDecorationRef,
          targetArg: 'decoration',
          construction: FactoryInvocation(
            variantRef: WireIdRef(
              library: 'restage.core',
              wireId: WireId('v0001'),
            ),
            receiver: const ResultStructuredTypeReceiver(),
          ),
          fieldMappings: [
            _borderRadiusMapping(),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0003'),
              propertyRef: WireId('p0002'),
              transform: const IdentityTransform(),
            ),
          ],
          flatProperties: {
            WireId('p0501'): WireId('p0001'),
          },
        ),
        extraProperties: [
          PropertyEntry(
            wireId: WireId('p0002'),
            name: 'packageName',
            type: PropertyType.string,
            description: 'Font package.',
            valueShape: const ScalarShape(
              propertyType: PropertyType.string,
            ),
          ),
        ],
        boxDecorationParameters: [
          _boxDecorationParameter(
            name: 'borderRadius',
            valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: _borderRadiusRef,
            ),
          ),
          FactoryParameter(
            wireId: WireId('a0003'),
            name: 'package',
            kind: FactoryParameterKind.named,
            required: false,
            nullable: true,
            defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
            valueShape: const ScalarShape(
              propertyType: PropertyType.string,
            ),
          ),
          FactoryParameter(
            wireId: WireId('a0004'),
            name: 'inherit',
            kind: FactoryParameterKind.named,
            required: false,
            nullable: false,
            defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
            defaultValue: const LiteralParameterDefault(true),
            valueShape: const ScalarShape(
              propertyType: PropertyType.boolean,
            ),
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(catalog));
      final recipe = decoded.widgets.single.decomposes.single;
      final parameters = (decoded.structuredTypes
              .singleWhere((entry) => entry.name == 'BoxDecoration')
              .variants
              .single as ConstructorVariant)
          .parameters;

      expect(recipe.parameterMappings.single.parameterRef, WireId('a0003'));
      expect(recipe.parameterMappings.single.propertyRef, WireId('p0002'));
      expect(
        parameters.singleWhere((p) => p.name == 'inherit').defaultValue,
        const LiteralParameterDefault(true),
      );
    });

    test('decodeCatalog is current-only and gives no compat escape hatch', () {
      const v3Json =
          '{"schemaVersion":3,"generatedAt":"x","libraries":{"restage.core":'
          '{"version":"0.1.0","widgetCount":0,"structuredCount":0,'
          '"unionCount":0,"designTokenCount":0}},"widgets":[]}';

      expect(
        () => decodeCatalog(v3Json),
        throwsA(
          isA<CatalogSchemaException>()
              .having(
                (error) => error.message,
                'message',
                contains('Unsupported catalog schemaVersion 3'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('decodeCatalogCompat')),
              ),
        ),
      );
    });

    test('catalog codec production source has no compat decoder', () {
      final source = File('lib/src/catalog_codec.dart').readAsStringSync();

      expect(source, isNot(contains('decodeCatalogCompat')));
      expect(source, isNot(contains('CompatibilityMode.legacyV3')));
    });

    test('production package has no legacy schema export or codec', () {
      expect(File('lib/legacy.dart').existsSync(), isFalse);
      expect(File('lib/src/legacy_codec.dart').existsSync(), isFalse);
    });

    test('production schema model has no bridge sidecar fields', () {
      final schemaSources = [
        File('lib/rfw_catalog_schema.dart'),
        File('lib/src/catalog_codec.dart'),
        File('lib/src/decomposition_recipe.dart'),
      ].map((file) => file.readAsStringSync()).join('\n');

      expect(schemaSources, isNot(contains('factory_convention.dart')));
      expect(schemaSources, isNot(contains('FactoryConvention')));
      expect(schemaSources, isNot(contains('factoryConvention')));
      expect(schemaSources, isNot(contains('legacyStructuredType')));
      expect(schemaSources, isNot(contains('legacyFlatProperties')));
    });

    test('decodeCatalog rejects v4 bridge fields', () {
      final raw =
          jsonDecode(encodeCatalog(_nativeCatalog())) as Map<String, dynamic>;
      final widgets = raw['widgets'] as List<Object?>;
      final widget = widgets.single! as Map<String, dynamic>;
      final decomposes = widget['decomposes'] as List<Object?>;
      final recipe = decomposes.single! as Map<String, dynamic>;
      recipe['factoryConvention'] = 'styleFrom';
      recipe['legacyStructuredType'] = 'BoxDecoration';
      recipe['legacyFlatProperties'] = {'borderRadius': 'borderRadius'};
      final json = jsonEncode(raw);

      expect(
        () => decodeCatalog(json),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('unexpected field'),
          ),
        ),
      );
    });

    test(
        'decodeCatalog surfaces a non-string discriminator as a '
        'CatalogSchemaException, not a raw TypeError', () {
      final raw =
          jsonDecode(encodeCatalog(_nativeCatalog())) as Map<String, dynamic>;
      final widget =
          (raw['widgets'] as List<Object?>).single! as Map<String, dynamic>;
      final recipe = (widget['decomposes'] as List<Object?>).single!
          as Map<String, dynamic>;
      final construction = recipe['construction'] as Map<String, dynamic>;
      final receiver = construction['receiver'] as Map<String, dynamic>;
      // A non-string `kind` previously reached a raw `as String` cast,
      // leaking a TypeError past the codec's `CatalogSchemaException`
      // contract (defeating the consumer's `on CatalogSchemaException`).
      receiver['kind'] = 123;

      expect(
        () => decodeCatalog(jsonEncode(raw)),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('v4 encode rejects unallocated parameter IDs', () {
      final catalog = _nativeCatalog(
        borderRadiusParameter: const FactoryParameter(
          wireId: WireId.unallocatedParameter,
          position: 0,
          kind: FactoryParameterKind.positional,
          required: true,
          nullable: false,
          defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
          valueShape: _realShape,
        ),
      );

      expect(
        () => encodeCatalog(catalog),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('a0000'),
          ),
        ),
      );
    });

    test('requireNativeCatalog rejects duplicate parameter IDs per library',
        () {
      final duplicateAcrossVariants = _nativeCatalog(
        bindingParameterRef: WireId('a0002'),
        borderRadiusParameter: FactoryParameter(
          wireId: WireId('a0002'),
          position: 0,
          kind: FactoryParameterKind.positional,
          required: true,
          nullable: false,
          defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
          valueShape: _realShape,
        ),
      );

      expect(
        () => requireNativeCatalog(duplicateAcrossVariants),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('duplicate parameter'), contains('a0002')),
          ),
        ),
      );

      final duplicateWithinVariant = _nativeCatalog(
        boxDecorationParameters: [
          _boxDecorationParameter(name: 'borderRadius'),
          _boxDecorationParameter(name: 'radiusAlias'),
        ],
      );

      expect(
        () => requireNativeCatalog(duplicateWithinVariant),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('duplicate parameter'), contains('a0002')),
          ),
        ),
      );
    });

    test('requireNativeCatalog rejects non-native and incoherent catalogs', () {
      final current = _nativeCatalog();
      expect(requireNativeCatalog(current), same(current));

      expect(
        () => requireNativeCatalog(_nativeCatalog(schemaVersion: 3)),
        throwsA(isA<CatalogSchemaException>()),
      );
      expect(
        () => requireNativeCatalog(
          _nativeCatalog(
            recipe: DecompositionRecipe(
              structuredRef: _boxDecorationRef,
              targetArg: 'decoration',
              construction: FactoryInvocation(
                variantRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('v0001'),
                ),
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [_borderRadiusMapping()],
              parameterMappings: [
                DecompositionParameterMapping(
                  parameterRef: WireId('a9999'),
                  propertyRef: WireId('p0001'),
                  transform: const IdentityTransform(),
                ),
              ],
              flatProperties: {WireId('p0501'): WireId('p0001')},
            ),
          ),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('parameterMappings'), contains('a9999')),
          ),
        ),
      );
      expect(
        () => requireNativeCatalog(
          _nativeCatalog(recipeVariantRef: WireId('v9999')),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('variant'),
          ),
        ),
      );
      expect(
        () => requireNativeCatalog(
          _nativeCatalog(bindingParameterRef: WireId('a0002')),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('parameter'),
          ),
        ),
      );
      expect(
        () => requireNativeCatalog(
          _nativeCatalog(valueShapeStructuredRef: WireId('s9999')),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('valueShape'), contains('s9999')),
          ),
        ),
      );
    });

    test(
        'requireNativeCatalog resolves parameterMapping refs against the '
        'construction variant', () {
      DecompositionRecipe recipeWithParameterMapping(WireId parameterRef) =>
          DecompositionRecipe(
            structuredRef: _boxDecorationRef,
            targetArg: 'decoration',
            construction: FactoryInvocation(
              variantRef: WireIdRef(
                library: 'restage.core',
                wireId: WireId('v0001'),
              ),
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [_borderRadiusMapping()],
            parameterMappings: [
              DecompositionParameterMapping(
                parameterRef: parameterRef,
                propertyRef: WireId('p0001'),
                transform: const IdentityTransform(),
              ),
            ],
            flatProperties: {WireId('p0501'): WireId('p0001')},
          );

      // Positive: a0002 IS a parameter of the construction variant v0001, so
      // the mapping resolves cleanly.
      final valid =
          _nativeCatalog(recipe: recipeWithParameterMapping(WireId('a0002')));
      expect(requireNativeCatalog(valid), same(valid));

      // Owner mismatch: a0001 exists, but on variant v0002 (BorderRadius), not
      // the construction variant v0001 (BoxDecoration). The check must resolve
      // against the CONSTRUCTION variant specifically — a real parameter on the
      // wrong variant is still rejected (distinct from the wholly-absent case).
      expect(
        () => requireNativeCatalog(
          _nativeCatalog(recipe: recipeWithParameterMapping(WireId('a0001'))),
        ),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(contains('construction parameter'), contains('a0001')),
          ),
        ),
      );
    });

    // Negative coverage for the CatalogSchemaException validator branches that
    // throw on malformed input but had no test feeding the violating input.
    // Each pins a specific guard so a mutation (`if (…) → if (false)`, or
    // dropping the referential check) is caught.
    group('CatalogSchemaException validator negatives', () {
      Matcher throwsSchemaMessage(Matcher message) => throwsA(
            isA<CatalogSchemaException>()
                .having((e) => e.message, 'message', message),
          );

      test('a named factory parameter with a null or empty name is rejected',
          () {
        Catalog catalogWithName(String? name) => _nativeCatalog(
              borderRadiusParameter: FactoryParameter(
                wireId: WireId('a0001'),
                kind: FactoryParameterKind.named,
                name: name,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: _realShape,
              ),
            );
        final matcher =
            throwsSchemaMessage(contains('named parameter requires name'));
        // Both the null and the empty branch of the `name == null ||
        // name!.isEmpty` guard fail closed.
        expect(() => encodeCatalog(catalogWithName(null)), matcher);
        expect(() => encodeCatalog(catalogWithName('')), matcher);
      });

      test('a structured field whose structuredRef dangles is rejected', () {
        // The structured-types referential-integrity check
        // (_requireOptionalStructuredRef on field.structuredRef), distinct from
        // the value-shape structuredRef check covered above.
        expect(
          () => requireNativeCatalog(
            _nativeCatalog(fieldStructuredRef: WireId('s9999')),
          ),
          throwsSchemaMessage(
            allOf(contains('missing structured entry'), contains('s9999')),
          ),
        );
      });

      test('a native recipe missing targetArg and construction is rejected',
          () {
        final catalog = _nativeCatalog(
          recipe: DecompositionRecipe(
            structuredRef: _boxDecorationRef,
            flatProperties: {WireId('p0501'): WireId('p0001')},
            // targetArg and construction both omitted — the required native
            // pair.
          ),
        );
        expect(
          () => requireNativeCatalog(catalog),
          throwsSchemaMessage(
            contains('native recipe requires targetArg and construction'),
          ),
        );
      });

      test('encoding a non-canonical schemaVersion is rejected', () {
        // The encode-side schemaVersion guard (the decode-side and the
        // requireNativeCatalog guard are covered elsewhere).
        expect(
          () => encodeCatalog(_nativeCatalog(schemaVersion: 3)),
          throwsSchemaMessage(
            contains('Cannot encode catalog schemaVersion 3'),
          ),
        );
      });
    });

    test('static-member parameter default round-trips through the codec', () {
      final catalog = _nativeCatalog(
        borderRadiusParameter: FactoryParameter(
          wireId: WireId('a0001'),
          position: 0,
          kind: FactoryParameterKind.positional,
          required: false,
          nullable: false,
          defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
          defaultValue: const StaticMemberParameterDefault(
            staticType: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BorderSide',
            ),
            memberName: 'none',
          ),
          valueShape: _realShape,
        ),
      );

      final decoded = decodeCatalog(encodeCatalog(catalog));
      final parameter = (decoded.structuredTypes
              .singleWhere((entry) => entry.name == 'BorderRadius')
              .variants
              .single as ConstructorVariant)
          .parameters
          .single;

      expect(
        parameter.defaultValue,
        const StaticMemberParameterDefault(
          staticType: DartTypeRef(
            libraryUri: 'package:flutter/painting.dart',
            symbolName: 'BorderSide',
          ),
          memberName: 'none',
        ),
      );
    });

    test('static-member default with empty memberName is rejected', () {
      final catalog = _nativeCatalog(
        borderRadiusParameter: FactoryParameter(
          wireId: WireId('a0001'),
          position: 0,
          kind: FactoryParameterKind.positional,
          required: false,
          nullable: false,
          defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
          defaultValue: const StaticMemberParameterDefault(
            staticType: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BorderSide',
            ),
            memberName: '',
          ),
          valueShape: _realShape,
        ),
      );

      expect(
        () => encodeCatalog(catalog),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('memberName'),
          ),
        ),
      );
    });

    test('static-member default JSON missing staticType is rejected', () {
      final catalog = _nativeCatalog(
        borderRadiusParameter: FactoryParameter(
          wireId: WireId('a0001'),
          position: 0,
          kind: FactoryParameterKind.positional,
          required: false,
          nullable: false,
          defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
          defaultValue: const StaticMemberParameterDefault(
            staticType: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BorderSide',
            ),
            memberName: 'none',
          ),
          valueShape: _realShape,
        ),
      );

      // Strip the staticType from the encoded default and confirm the
      // decoder rejects the malformed static-member shape.
      final raw = jsonDecode(encodeCatalog(catalog)) as Map<String, dynamic>;
      final structuredTypes = raw['structuredTypes'] as List<Object?>;
      final borderRadius = structuredTypes
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['name'] == 'BorderRadius');
      final variant = (borderRadius['variants'] as List<Object?>).single!
          as Map<String, dynamic>;
      final parameter = (variant['parameters'] as List<Object?>).single!
          as Map<String, dynamic>;
      (parameter['defaultValue'] as Map<String, dynamic>).remove('staticType');

      expect(
        () => decodeCatalog(jsonEncode(raw)),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            contains('staticType'),
          ),
        ),
      );
    });

    test('a literal argument binding with a null literal round-trips', () {
      final catalog = _nativeCatalog(
        recipe: DecompositionRecipe(
          structuredRef: _boxDecorationRef,
          targetArg: 'decoration',
          construction: FactoryInvocation(
            variantRef: WireIdRef(
              library: 'restage.core',
              wireId: WireId('v0001'),
            ),
            receiver: const ResultStructuredTypeReceiver(),
          ),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0501'),
              propertyRef: WireId('p0001'),
              transform: ConstructVariantTransform(
                resultStructuredRef: _borderRadiusRef,
                invocation: FactoryInvocation(
                  variantRef: WireIdRef(
                    library: 'restage.core',
                    wireId: WireId('v0002'),
                  ),
                  receiver: const ResultStructuredTypeReceiver(),
                  memberName: 'circular',
                ),
                argumentBindings: [
                  // A `literal` source with no literal value encodes the
                  // intentional Dart `null` — a valid binding, not a
                  // missing field.
                  LiteralArgumentBinding(
                    literal: null,
                    parameterRef: WireId('a0001'),
                    nullPolicy: TransformNullPolicy.nullResult,
                    missingPolicy: TransformMissingPolicy.nullResult,
                  ),
                ],
              ),
            ),
          ],
          flatProperties: {WireId('p0501'): WireId('p0001')},
        ),
      );

      final decoded = decodeCatalog(encodeCatalog(catalog));
      final transform = decoded
          .widgets.single.decomposes.single.fieldMappings.single.transform;
      final binding =
          (transform as ConstructVariantTransform).argumentBindings.single;

      expect(binding, isA<LiteralArgumentBinding>());
      expect((binding as LiteralArgumentBinding).literal, isNull);
    });

    group('literal default / value-shape compatibility', () {
      // `_literalDefaultMatchesShape`: a literal default that is type-legal
      // (bool/int/double/String) but incompatible with the parameter's
      // value-shape `PropertyType` is rejected by the canonical encoder. The
      // type-reject (non-primitive literal) and empty-memberName cases are
      // covered elsewhere; this exercises the shape-mismatch arm.
      Catalog catalogWithDefault(
        Object? literal,
        PropertyType propertyType,
      ) =>
          _nativeCatalog(
            borderRadiusParameter: FactoryParameter(
              wireId: WireId('a0001'),
              position: 0,
              kind: FactoryParameterKind.positional,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: LiteralParameterDefault(literal),
              valueShape: ScalarShape(propertyType: propertyType),
            ),
          );

      void expectIncompatible(Object? literal, PropertyType propertyType) {
        expect(
          () => encodeCatalog(catalogWithDefault(literal, propertyType)),
          throwsA(
            isA<CatalogSchemaException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('is not compatible with PropertyType.'),
                contains('PropertyType.${propertyType.name}'),
              ),
            ),
          ),
        );
      }

      test('String literal against an integer shape is rejected', () {
        expectIncompatible('hello', PropertyType.integer);
      });

      test('int literal against a boolean shape is rejected', () {
        expectIncompatible(42, PropertyType.boolean);
      });

      test('bool literal against a string shape is rejected', () {
        expectIncompatible(true, PropertyType.string);
      });

      test('a compatible literal (int against integer) is accepted', () {
        final catalog = catalogWithDefault(42, PropertyType.integer);
        // Encodes without throwing and round-trips the default.
        final decoded = decodeCatalog(encodeCatalog(catalog));
        final parameter = (decoded.structuredTypes
                .singleWhere((entry) => entry.name == 'BorderRadius')
                .variants
                .single as ConstructorVariant)
            .parameters
            .single;
        expect(parameter.defaultValue, const LiteralParameterDefault(42));
      });
    });

    group('wireCodec placement', () {
      // wireCodec sits on the base shape, so it is constructible on any
      // subtype, but it is only meaningful on scalar/union/list shapes. The
      // encoder / native-coherence guard rejects it on enum and structured
      // shapes, where it can never carry meaning.
      Catalog catalogWithParameterShape(CatalogValueShape shape) =>
          _nativeCatalog(
            borderRadiusParameter: FactoryParameter(
              wireId: WireId('a0001'),
              position: 0,
              kind: FactoryParameterKind.positional,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              valueShape: shape,
            ),
          );

      test('enumValue shape carrying a wireCodec is rejected', () {
        expect(
          () => encodeCatalog(
            catalogWithParameterShape(
              const EnumShape(
                propertyType: PropertyType.enumValue,
                enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/painting.dart',
                  symbolName: 'BoxShape',
                ),
                wireCodec: CatalogWireCodec.rfwGradient,
              ),
            ),
          ),
          throwsA(
            isA<CatalogSchemaException>().having(
              (error) => error.message,
              'message',
              contains('wireCodec'),
            ),
          ),
        );
      });

      test('structured shape carrying a wireCodec is rejected', () {
        expect(
          () => encodeCatalog(
            catalogWithParameterShape(
              StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0002'),
                ),
                wireCodec: CatalogWireCodec.rfwBorder,
              ),
            ),
          ),
          throwsA(
            isA<CatalogSchemaException>().having(
              (error) => error.message,
              'message',
              contains('wireCodec'),
            ),
          ),
        );
      });

      test('union shape carrying a wireCodec is still accepted', () {
        expect(
          () => encodeCatalog(
            catalogWithParameterShape(
              UnionShape(
                propertyType: PropertyType.gradient,
                unionRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('u0001'),
                ),
                wireCodec: CatalogWireCodec.rfwGradient,
              ),
            ),
          ),
          returnsNormally,
        );
      });
    });
  });

  group('enumValue property enum-identity (encode/validate guard)', () {
    const boxFitRef = DartTypeRef(
      libraryUri: 'package:flutter/painting.dart',
      symbolName: 'BoxFit',
    );

    // Inject one enumValue property carrying the given identity carriers.
    Catalog catalogWithEnumProperty({
      String? enumType,
      bool withEnumShape = false,
      bool withEmptyEnumRefShape = false,
    }) =>
        _nativeCatalog(
          extraProperties: [
            PropertyEntry(
              wireId: WireId('p0002'),
              name: 'fit',
              type: PropertyType.enumValue,
              description: 'How to fit.',
              enumType: enumType,
              valueShape: switch ((withEmptyEnumRefShape, withEnumShape)) {
                (true, _) => const EnumShape(
                    propertyType: PropertyType.enumValue,
                    enumRef: DartTypeRef(libraryUri: '', symbolName: ''),
                  ),
                (_, true) => const EnumShape(
                    propertyType: PropertyType.enumValue,
                    enumRef: boxFitRef,
                  ),
                _ => null,
              },
            ),
          ],
        );

    test('rejects an enumValue property carrying neither carrier', () {
      expect(
        () => encodeCatalog(catalogWithEnumProperty()),
        throwsA(
          isA<CatalogSchemaException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('enumValue property'),
              contains('enumType or an EnumShape'),
            ),
          ),
        ),
      );
    });

    test('accepts an enumValue property carrying only enumType', () {
      expect(
        () => encodeCatalog(catalogWithEnumProperty(enumType: 'BoxFit')),
        returnsNormally,
      );
    });

    test('accepts an enumValue property carrying only an EnumShape (enumRef)',
        () {
      // The OR form: identity may live solely in the EnumShape (enumRef) with
      // no enumType — the shape committed catalogs actually use.
      expect(
        () => encodeCatalog(catalogWithEnumProperty(withEnumShape: true)),
        returnsNormally,
      );
    });

    test('an empty enumType does not count as identity', () {
      expect(
        () => encodeCatalog(catalogWithEnumProperty(enumType: '')),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('an EnumShape with an empty enumRef does not count as identity', () {
      // The EnumShape satisfies the OR-branch by type, but an empty enumRef
      // pins the slot to nothing; _validateValueShape must still reject it.
      expect(
        () => encodeCatalog(
          catalogWithEnumProperty(withEmptyEnumRefShape: true),
        ),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('committed built-in catalogs still validate/encode under the guard',
        () {
      // The real data exercises both carriers (many enumValue props pin
      // identity only via an EnumShape, no enumType) and must pass.
      const catalogPaths = [
        '../restage_core/lib/src/widget_catalog/catalog.json',
        '../restage_material/lib/src/widget_catalog/catalog.json',
        '../restage_cupertino/lib/src/widget_catalog/catalog.json',
      ];
      for (final path in catalogPaths) {
        final source = File(path).readAsStringSync();
        final catalog = decodeCatalog(source);
        expect(
          () => encodeCatalog(catalog),
          returnsNormally,
          reason: '$path must round-trip clean under the enum-identity guard',
        );
        // The native-coherence validation runs the same guard.
        expect(() => requireNativeCatalog(catalog), returnsNormally);
      }
    });
  });

  group('decoded catalog collections are unmodifiable (wire->catalog)', () {
    test('top-level + nested collections from _nativeCatalog reject mutation',
        () {
      final decoded = decodeCatalog(encodeCatalog(_nativeCatalog()));
      final widget = decoded.widgets.single;
      final recipe = widget.decomposes.single;
      final boxDecoration = decoded.structuredTypes
          .singleWhere((entry) => entry.name == 'BoxDecoration');
      final variant = boxDecoration.variants.single;

      // Top-level collections.
      expect(decoded.libraries.clear, throwsUnsupportedError);
      expect(() => decoded.widgets.add(widget), throwsUnsupportedError);
      expect(decoded.structuredTypes.clear, throwsUnsupportedError);
      // Nested widget collections.
      expect(widget.fires.clear, throwsUnsupportedError);
      expect(
        () => widget.properties.add(widget.properties.first),
        throwsUnsupportedError,
      );
      expect(widget.decomposes.clear, throwsUnsupportedError);
      // Nested recipe collections (list + map).
      expect(recipe.fieldMappings.clear, throwsUnsupportedError);
      expect(recipe.flatProperties.clear, throwsUnsupportedError);
      // Collection nested inside a decode-built transform.
      final transform =
          recipe.fieldMappings.single.transform as ConstructVariantTransform;
      expect(transform.argumentBindings.clear, throwsUnsupportedError);
      // Nested structured-entry collections.
      expect(boxDecoration.fields.clear, throwsUnsupportedError);
      expect(boxDecoration.variants.clear, throwsUnsupportedError);
      expect(
        (variant as ConstructorVariant).parameters.clear,
        throwsUnsupportedError,
      );
    });

    test('union, designToken, and mutex collections reject mutation', () {
      final decoded = decodeCatalog(encodeCatalog(_catalogWithUnion()));
      final union = decoded.unions.single;
      final mutexProp = decoded.widgets.single.properties
          .firstWhere((p) => p.mutuallyExclusiveWith != null);

      expect(decoded.unions.clear, throwsUnsupportedError);
      expect(decoded.designTokens.clear, throwsUnsupportedError);
      expect(union.members.clear, throwsUnsupportedError);
      expect(union.memberSourceTypes.clear, throwsUnsupportedError);
      expect(union.discriminator.values.clear, throwsUnsupportedError);
      expect(mutexProp.mutuallyExclusiveWith!.clear, throwsUnsupportedError);
    });
  });

  group('union member/source/discriminator length agreement', () {
    Map<String, dynamic> unionJsonWith(
      void Function(Map<String, dynamic> union) mutate,
    ) {
      final raw = jsonDecode(encodeCatalog(_catalogWithUnion()))
          as Map<String, dynamic>;
      final union = (raw['unions'] as List).single as Map<String, dynamic>;
      mutate(union);
      return raw;
    }

    test('a valid union (equal lengths) still round-trips', () {
      final json = encodeCatalog(_catalogWithUnion());
      expect(() => requireNativeCatalog(decodeCatalog(json)), returnsNormally);
    });

    test('encode rejects memberSourceTypes length != members length', () {
      // decodeCatalog does not validate, so the mismatch decodes; encodeCatalog
      // (via _validateUnion) is the encode-side guard.
      final raw = unionJsonWith(
        (u) => (u['memberSourceTypes'] as List).add('dart:core#String'),
      );
      final catalog = decodeCatalog(jsonEncode(raw));
      expect(
        () => encodeCatalog(catalog),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            allOf(contains('memberSourceTypes'), contains('members')),
          ),
        ),
      );
    });

    test('decode-validation rejects discriminator.values length != members',
        () {
      final raw = unionJsonWith((u) {
        final values = (u['discriminator'] as Map)['values'] as List;
        values.add(Map<String, dynamic>.from(values.single as Map));
      });
      expect(
        () => requireNativeCatalog(decodeCatalog(jsonEncode(raw))),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('discriminator.values'),
          ),
        ),
      );
    });
  });

  group('StructuredField ref/type-shape contract (decoder)', () {
    // Mutate the single structured field (BoxDecoration.fields[0]) of
    // _nativeCatalog and re-encode for plain decodeCatalog — the decoder is the
    // durable, all-entrypoints fix (covers the customer-import path).
    String jsonWithFieldMutated(
      void Function(Map<String, dynamic> field) mutate,
    ) {
      final raw =
          jsonDecode(encodeCatalog(_nativeCatalog())) as Map<String, dynamic>;
      final boxDecoration = (raw['structuredTypes'] as List)
          .map((e) => e as Map<String, dynamic>)
          .firstWhere((s) => s['name'] == 'BoxDecoration');
      final field =
          (boxDecoration['fields'] as List).single as Map<String, dynamic>;
      mutate(field);
      return jsonEncode(raw);
    }

    const unionRefJson = {'library': 'restage.core', 'wireId': 'u0001'};

    test('rejects a structured-typed field carrying neither ref', () {
      final json = jsonWithFieldMutated((f) {
        f
          ..remove('structuredRef')
          ..remove('unionRef')
          ..remove('valueShape');
      });
      expect(
        () => decodeCatalog(json),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('structured-typed field must carry'),
          ),
        ),
      );
    });

    test('rejects a structuredRef on a non-structured (scalar) field', () {
      final json = jsonWithFieldMutated((f) {
        f
          ..['type'] = 'color'
          ..remove('valueShape'); // keeps the existing structuredRef
      });
      expect(
        () => decodeCatalog(json),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('only valid on a structured-typed'),
          ),
        ),
      );
    });

    test('rejects both structuredRef and unionRef set', () {
      final json = jsonWithFieldMutated(
        (f) => f['unionRef'] = unionRefJson, // structuredRef already present
      );
      expect(
        () => decodeCatalog(json),
        throwsA(
          isA<CatalogSchemaException>().having(
            (e) => e.message,
            'message',
            contains('mutually exclusive'),
          ),
        ),
      );
    });

    test('accepts a unionRef on a union-category (gradient) field', () {
      final json = jsonWithFieldMutated((f) {
        f
          ..['type'] = 'gradient'
          ..remove('structuredRef')
          ..remove('valueShape')
          ..['unionRef'] = unionRefJson;
      });
      expect(() => decodeCatalog(json), returnsNormally);
    });

    test('accepts a structuredRef on a union-category (gradient) field', () {
      // A widget accepting a single concrete gradient (e.g. LinearGradient)
      // produces a gradient-typed field bound to one concrete structured
      // entry via structuredRef rather than the Gradient union.
      final json = jsonWithFieldMutated((f) {
        f
          ..['type'] = 'gradient'
          ..remove('valueShape'); // keeps the existing structuredRef
      });
      expect(() => decodeCatalog(json), returnsNormally);
    });

    test('accepts a unionRef on a structured-typed field', () {
      final json = jsonWithFieldMutated((f) {
        f
          ..remove('structuredRef')
          ..remove('valueShape')
          ..['unionRef'] = unionRefJson;
      });
      expect(() => decodeCatalog(json), returnsNormally);
    });

    test('accepts a ref on an unknown (forward-compat) typed field', () {
      final json = jsonWithFieldMutated((f) {
        f
          ..['type'] = 'someFutureScalarType' // unrecognized -> unknown
          ..remove('valueShape'); // keeps the existing structuredRef
      });
      expect(() => decodeCatalog(json), returnsNormally);
    });
  });
}

/// A compact, encode-valid catalog exercising the union / designToken /
/// mutuallyExclusiveWith collection slots that [_nativeCatalog] omits.
Catalog _catalogWithUnion() {
  final boxDecorationRef = WireIdRef(
    library: 'restage.core',
    wireId: WireId('s0001'),
  );
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '2026-05-23T12:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Container',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'Box model widget.',
        flutterType: 'package:flutter/widgets.dart#Container',
        childrenSlot: ChildrenSlot.single,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'color',
            type: PropertyType.color,
            description: 'Background color.',
            mutuallyExclusiveWith: [WireId('p0002')],
          ),
          PropertyEntry(
            wireId: WireId('p0002'),
            name: 'decoration',
            type: PropertyType.structured,
            description: 'Decoration.',
            structuredRef: boxDecorationRef,
            valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: boxDecorationRef,
            ),
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: WireId('s0001'),
        name: 'BoxDecoration',
        library: WidgetLibrary.core,
        description: 'Box decoration.',
        sourceType: 'package:flutter/painting.dart#BoxDecoration',
        fields: const [],
        variants: const [],
      ),
    ],
    unions: [
      UnionEntry(
        wireId: WireId('u0001'),
        name: 'Decoration',
        library: WidgetLibrary.core,
        description: 'Decoration union.',
        sourceType: 'package:flutter/painting.dart#Decoration',
        memberSourceTypes: const [
          'package:flutter/painting.dart#BoxDecoration',
        ],
        discriminator: DiscriminatorSpec(
          field: '_t',
          values: [boxDecorationRef],
        ),
        members: [boxDecorationRef],
      ),
    ],
    designTokens: [
      DesignTokenEntry(
        wireId: WireId('t0001'),
        name: 'primaryColor',
        library: WidgetLibrary.core,
        type: DesignTokenType.color,
        resolver: const ThemeBindingPath.path('colorScheme.primary'),
      ),
    ],
  );
}

final _boxDecorationRef = WireIdRef(
  library: 'restage.core',
  wireId: WireId('s0001'),
);
final _borderRadiusRef = WireIdRef(
  library: 'restage.core',
  wireId: WireId('s0002'),
);
const _realShape = ScalarShape(
  propertyType: PropertyType.real,
  dartTypeRef: DartTypeRef(
    libraryUri: 'dart:core',
    symbolName: 'double',
  ),
);

DecompositionFieldMapping _borderRadiusMapping({
  WireId? bindingParameterRef,
}) {
  return DecompositionFieldMapping(
    fieldRef: WireId('p0501'),
    propertyRef: WireId('p0001'),
    transform: ConstructVariantTransform(
      resultStructuredRef: _borderRadiusRef,
      invocation: FactoryInvocation(
        variantRef: WireIdRef(library: 'restage.core', wireId: WireId('v0002')),
        receiver: const ResultStructuredTypeReceiver(),
        memberName: 'circular',
      ),
      argumentBindings: [
        PropertyValueArgumentBinding(
          parameterRef: bindingParameterRef ?? WireId('a0001'),
          nullPolicy: TransformNullPolicy.nullResult,
          missingPolicy: TransformMissingPolicy.nullResult,
        ),
      ],
    ),
  );
}

Catalog _nativeCatalog({
  int schemaVersion = 4,
  DecompositionRecipe? recipe,
  WireId? recipeVariantRef,
  WireId? bindingParameterRef,
  FactoryParameter? borderRadiusParameter,
  WireId? valueShapeStructuredRef,
  WireId? fieldStructuredRef,
  List<PropertyEntry> extraProperties = const [],
  List<FactoryParameter>? boxDecorationParameters,
}) {
  final effectiveBorderRadiusShape = StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.core',
      wireId: valueShapeStructuredRef ?? _borderRadiusRef.wireId,
    ),
  );
  final effectiveRecipe = recipe ??
      DecompositionRecipe(
        structuredRef: _boxDecorationRef,
        targetArg: 'decoration',
        construction: FactoryInvocation(
          variantRef: WireIdRef(
            library: 'restage.core',
            wireId: recipeVariantRef ?? WireId('v0001'),
          ),
          receiver: const ResultStructuredTypeReceiver(),
        ),
        fieldMappings: [
          _borderRadiusMapping(bindingParameterRef: bindingParameterRef),
        ],
        flatProperties: {WireId('p0501'): WireId('p0001')},
      );

  return Catalog(
    schemaVersion: schemaVersion,
    generatedAt: '2026-05-23T12:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Container',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'Box model widget.',
        flutterType: 'package:flutter/widgets.dart#Container',
        childrenSlot: ChildrenSlot.single,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'borderRadius',
            type: PropertyType.real,
            description: 'Radius.',
            valueShape: _realShape,
          ),
          ...extraProperties,
        ],
        decomposes: [effectiveRecipe],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: WireId('s0001'),
        name: 'BoxDecoration',
        library: WidgetLibrary.core,
        description: 'Box decoration.',
        sourceType: 'package:flutter/painting.dart#BoxDecoration',
        fields: [
          StructuredField(
            wireId: WireId('p0501'),
            name: 'borderRadius',
            type: PropertyType.structured,
            description: 'Border radius.',
            structuredRef: fieldStructuredRef != null
                ? WireIdRef(library: 'restage.core', wireId: fieldStructuredRef)
                : _borderRadiusRef,
            valueShape: effectiveBorderRadiusShape,
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: boxDecorationParameters ??
                [
                  _boxDecorationParameter(
                    name: 'borderRadius',
                    valueShape: effectiveBorderRadiusShape,
                  ),
                ],
          ),
        ],
      ),
      StructuredEntry(
        wireId: WireId('s0002'),
        name: 'BorderRadius',
        library: WidgetLibrary.core,
        description: 'Border radius.',
        sourceType: 'package:flutter/painting.dart#BorderRadius',
        fields: const [],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0002'),
            namedConstructor: 'circular',
            parameters: [
              borderRadiusParameter ??
                  FactoryParameter(
                    wireId: WireId('a0001'),
                    position: 0,
                    kind: FactoryParameterKind.positional,
                    required: true,
                    nullable: false,
                    defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                    valueShape: _realShape,
                  ),
            ],
          ),
        ],
      ),
    ],
  );
}

FactoryParameter _boxDecorationParameter({
  required String name,
  CatalogValueShape? valueShape,
}) {
  return FactoryParameter(
    wireId: WireId('a0002'),
    name: name,
    kind: FactoryParameterKind.named,
    required: false,
    nullable: true,
    defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
    valueShape: valueShape ??
        StructuredShape(
          propertyType: PropertyType.structured,
          structuredRef: _borderRadiusRef,
        ),
  );
}
