import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_catalog_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

WidgetEntry _widgetEntry({
  required String name,
  WidgetLibrary library = const WidgetLibrary.custom('acme.design_system'),
  WidgetCategory category = WidgetCategory.layout,
  String description = 'A widget.',
  String? flutterType,
  ChildrenSlot childrenSlot = ChildrenSlot.none,
  List<WidgetEventName> fires = const [],
  List<PropertyEntry> properties = const [],
  List<DecompositionRecipe> decomposes = const [],
  int sinceVersion = kBaselineCatalogVersion,
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: library,
      category: category,
      description: description,
      flutterType: flutterType ?? 'package:acme/foo.dart#$name',
      childrenSlot: childrenSlot,
      fires: fires,
      properties: properties,
      decomposes: decomposes,
      sinceVersion: sinceVersion,
    );

Catalog _fullGraphCatalog() {
  const library = WidgetLibrary.custom('acme.design_system');
  const structuredRef = WireIdRef(
    library: 'acme.design_system',
    wireId: WireId.unallocatedStructured,
  );
  const variantRef = WireIdRef(
    library: 'acme.design_system',
    wireId: WireId.unallocatedVariant,
  );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      library: const LibraryInfo(version: '1.2.3'),
    },
    widgets: [
      _widgetEntry(
        name: 'AcmeButton',
        properties: const [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'tone',
            type: PropertyType.structured,
            description: 'Tone.',
            structuredRef: structuredRef,
            valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: structuredRef,
            ),
          ),
        ],
      ),
    ],
    structuredTypes: const [
      StructuredEntry(
        wireId: WireId.unallocatedStructured,
        name: 'AcmeTone',
        library: library,
        description: 'Tone value.',
        sourceType: 'package:acme/tone.dart#AcmeTone',
        fields: [
          StructuredField(
            wireId: WireId.unallocatedProperty,
            name: 'label',
            type: PropertyType.string,
            description: 'Label.',
            valueShape: ScalarShape(propertyType: PropertyType.string),
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId.unallocatedVariant,
            parameters: [
              FactoryParameter(
                wireId: WireId.unallocatedParameter,
                name: 'label',
                kind: FactoryParameterKind.named,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: ScalarShape(propertyType: PropertyType.string),
              ),
            ],
          ),
        ],
      ),
    ],
    unions: const [
      UnionEntry(
        wireId: WireId.unallocatedUnion,
        name: 'AcmeToneUnion',
        library: library,
        description: 'Tone union.',
        sourceType: 'package:acme/tone.dart#AcmeToneBase',
        memberSourceTypes: ['package:acme/tone.dart#AcmeTone'],
        discriminator:
            DiscriminatorSpec(field: 'kind', values: [structuredRef]),
        members: [structuredRef],
      ),
    ],
    designTokens: const [
      DesignTokenEntry(
        wireId: WireId.unallocatedDesignToken,
        name: 'brand.primary',
        library: library,
        type: DesignTokenType.color,
        literalFallback: 0xff000000,
      ),
    ],
    compatRules: const [
      CompatRule(
        fromVersion: '1.0.0',
        toVersion: '2.0.0',
        kind: CompatKind.factoryVariantChange,
        affectedRef: variantRef,
        note: 'factory variant changed',
      ),
    ],
  );
}

void main() {
  group('emitUserCatalogDart', () {
    test('declares `final Catalog kUserCatalog` and imports schema', () {
      final src = emitUserCatalogDart(userCatalogFromWidgets(const []));
      expect(
        src,
        contains("import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'"),
      );
      expect(src, contains('final Catalog kUserCatalog = Catalog('));
      expect(src, contains('GENERATED CODE - DO NOT MODIFY BY HAND'));
    });

    test('end-to-end: a v2 widget survives allocate -> emit -> JSON decode',
        () {
      // The pipeline-preservation proof: a non-baseline content version must
      // survive the wire-ID allocation copy, the source emit, and the JSON
      // round-trip without silently resetting to the baseline.
      final allocation = allocateUserCatalogFromWidgets(
        package: 'acme.design_system',
        widgets: [_widgetEntry(name: 'Hero', sinceVersion: 2)],
      );

      // The allocation copy site preserved it.
      expect(allocation.catalog.widgets.single.sinceVersion, 2);
      // The emitter wrote it into the generated source.
      expect(
        emitUserCatalogDart(allocation.catalog),
        contains('sinceVersion: 2'),
      );
      // It round-trips through the JSON codec to the derived content version.
      final decoded = decodeCatalog(encodeCatalog(allocation.catalog));
      expect(decoded.contentVersion, 2);
    });

    test('emits sinceVersion for an above-baseline widget, omits at baseline',
        () {
      final above = emitUserCatalogDart(
        userCatalogFromWidgets([_widgetEntry(name: 'Above', sinceVersion: 3)]),
      );
      expect(above, contains('sinceVersion: 3'));

      final baseline = emitUserCatalogDart(
        userCatalogFromWidgets([_widgetEntry(name: 'Baseline')]),
      );
      expect(baseline, isNot(contains('sinceVersion:')));
    });

    test('emits a single widget entry with library + properties', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(
            name: 'AcmeButton',
            category: WidgetCategory.input,
            description: 'CTA.',
            fires: const [WidgetEventName.onPressed],
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'label',
                type: PropertyType.string,
                description: 'Label.',
                required: true,
              ),
            ],
          ),
        ]),
      );
      expect(src, contains("name: 'AcmeButton'"));
      expect(
        src,
        contains("library: WidgetLibrary.custom('acme.design_system')"),
      );
      expect(src, contains('category: WidgetCategory.input'));
      expect(src, contains("description: 'CTA.'"));
      expect(src, contains('wireId: WireId.unallocatedWidget'));
      expect(src, contains('childrenSlot: ChildrenSlot.none'));
      expect(src, contains('fires: [WidgetEventName.onPressed]'));
      expect(src, contains('wireId: WireId.unallocatedProperty'));
      expect(src, contains("name: 'label'"));
      expect(src, contains('type: PropertyType.string'));
      expect(src, contains('required: true'));
    });

    test('output is dart-format clean', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(
            name: 'AcmeButton',
            description:
                'A long description that would otherwise wrap awkwardly across '
                'lines if the emitter did not run output through '
                'DartFormatter.',
          ),
        ]),
      );
      // Re-formatting a formatted source returns the same string; we don't
      // want CI's `dart format --set-exit-if-changed` to fail on regen.
      expect(src.endsWith('\n'), isTrue);
      expect(src, isNot(contains('  );'.padLeft(200))));
    });

    test('escapes single quotes and backslashes in description and name', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(
            name: "It's Fine",
            description: r"Has 'quotes' and \backslashes\.",
          ),
        ]),
      );
      expect(src, contains(r"name: 'It\'s Fine'"));
      expect(
        src,
        contains(r"description: 'Has \'quotes\' and \\backslashes\\.'"),
      );
    });

    test(r'escapes $ to prevent string-interpolation in emitted source', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(name: r'Price $9.99', description: r'Buy ${now}'),
        ]),
      );
      expect(src, contains(r"name: 'Price \$9.99'"));
      expect(src, contains(r"description: 'Buy \${now}'"));
    });

    test('escapes newlines, carriage returns, and tabs', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(name: 'X', description: 'one\ntwo\rthree\tfour'),
        ]),
      );
      expect(src, contains(r"description: 'one\ntwo\rthree\tfour'"));
    });

    test('emits a list literal default through its LiteralDefault source', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(
            name: 'Foo',
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'tags',
                type: PropertyType.string,
                description: 'Tags.',
                defaultSource: LiteralDefault(['a', 'b']),
              ),
            ],
          ),
        ]),
      );
      expect(src, contains("defaultSource: LiteralDefault(['a', 'b'])"));
    });

    test('uses the typed singleton for built-in libraries', () {
      final src = emitUserCatalogDart(
        userCatalogFromWidgets([
          _widgetEntry(name: 'Foo', library: WidgetLibrary.core),
        ]),
      );
      expect(src, contains('library: WidgetLibrary.core'));
      expect(src, isNot(contains("WidgetLibrary.custom('restage.core')")));
    });

    test('preserves full Catalog graph sections', () {
      final src = emitUserCatalogDart(_fullGraphCatalog());
      final collapsed = src.replaceAll(RegExp(r'\s+'), ' ');

      expect(src, contains("version: '1.2.3'"));
      expect(src, contains('structuredTypes: ['));
      expect(src, contains('StructuredEntry('));
      expect(src, contains('ConstructorVariant('));
      expect(src, contains('FactoryParameter('));
      expect(src, contains('unions: ['));
      expect(src, contains('UnionEntry('));
      expect(src, contains('designTokens: ['));
      expect(src, contains('DesignTokenEntry('));
      expect(src, contains('compatRules: ['));
      expect(src, contains('CompatRule('));
      expect(collapsed, contains("note: 'factory variant changed'"));
    });

    test(
        'rejects unsupported widget decompose data in widget-only builder path',
        () {
      expect(
        () => userCatalogFromWidgets([
          _widgetEntry(
            name: 'UnsupportedDecompose',
            decomposes: [
              DecompositionRecipe(
                structuredRef: const WireIdRef(
                  library: 'acme.design_system',
                  wireId: WireId.unallocatedStructured,
                ),
                flatProperties: {
                  WireId.unallocatedProperty: WireId.unallocatedProperty,
                },
              ),
            ],
          ),
        ]),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('UnsupportedDecompose'),
              contains('customer annotation pipeline cannot preserve'),
              contains('decompose graph'),
            ),
          ),
        ),
      );
    });

    test('rejects nested structured value shapes in widget-only builder path',
        () {
      expect(
        () => userCatalogFromWidgets([
          _widgetEntry(
            name: 'UnsupportedNestedShape',
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'shadows',
                type: PropertyType.boxShadowList,
                description: 'Shadows.',
                valueShape: ListShape(
                  propertyType: PropertyType.boxShadowList,
                  itemShape: StructuredShape(
                    propertyType: PropertyType.structured,
                    structuredRef: WireIdRef(
                      library: 'acme.design_system',
                      wireId: WireId.unallocatedStructured,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ]),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('UnsupportedNestedShape'),
              contains('shadows'),
              contains('structured/union graph references'),
            ),
          ),
        ),
      );
    });

    test('rejects nested union value shapes in widget-only builder path', () {
      expect(
        () => userCatalogFromWidgets([
          _widgetEntry(
            name: 'UnsupportedNestedUnion',
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'tones',
                type: PropertyType.boxShadowList,
                description: 'Tones.',
                valueShape: ListShape(
                  propertyType: PropertyType.boxShadowList,
                  itemShape: UnionShape(
                    propertyType: PropertyType.shapeBorder,
                    unionRef: WireIdRef(
                      library: 'acme.design_system',
                      wireId: WireId.unallocatedUnion,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ]),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('UnsupportedNestedUnion'),
              contains('tones'),
              contains('structured/union graph references'),
            ),
          ),
        ),
      );
    });

    test('rejects token defaults in widget-only builder path', () {
      expect(
        () => userCatalogFromWidgets([
          _widgetEntry(
            name: 'UnsupportedTokenDefault',
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'color',
                type: PropertyType.color,
                description: 'Color.',
                defaultSource: TokenRefDefault(
                  WireIdRef(
                    library: 'acme.design_system',
                    wireId: WireId.unallocatedDesignToken,
                  ),
                ),
              ),
            ],
          ),
        ]),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('UnsupportedTokenDefault'),
              contains('color'),
              contains('design-token default'),
            ),
          ),
        ),
      );
    });
  });
}
