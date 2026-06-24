import 'package:analyzer/dart/element/element.dart'
    show ClassElement, ConstructorElement, Element;
import 'package:mocktail/mocktail.dart';
import 'package:rfw_catalog_compiler/src/ir/ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

final class _FakeClassElement extends Fake implements ClassElement {}

final class _FakeConstructorElement extends Fake
    implements ConstructorElement {}

final class _FakeElement extends Fake implements Element {}

void main() {
  group('IR lowering', () {
    test('lowers a WidgetIR to WidgetEntry and round-trips JSON', () {
      final widgetIr = WidgetIR(
        wireId: WireId('w0001'),
        source: _FakeClassElement(),
        constructor: _FakeConstructorElement(),
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        properties: [
          PropertyIR(
            wireId: WireId('p0001'),
            source: _FakeElement(),
            name: 'text',
            type: const ResolvedType(kind: ResolvedTypeKind.string),
            description: 'Text to display.',
            defaultSource: null,
            metadata: const PropertyMetadataIR(
              category: PropertyCategory.data,
              priority: PropertyPriority.primary,
            ),
            policyTrace: const [],
            diagnostics: const [],
            required: true,
          ),
        ],
        decomposes: const [],
        fires: const [],
        childrenSlot: ChildrenSlot.none,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Text',
          curationSource: 'test/fixtures/catalog_text.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );

      final widget = lowerWidget(widgetIr);

      expect(widget, isA<WidgetEntry>());
      expect(widget.wireId, WireId('w0001'));
      expect(widget.name, 'CatalogText');
      expect(widget.flutterType, 'package:flutter/widgets.dart#Text');
      expect(widget.properties, hasLength(1));
      expect(widget.properties.single.wireId, WireId('p0001'));
      expect(widget.properties.single.type, PropertyType.string);

      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-11T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: [widget],
      );

      final decoded = decodeCatalog(encodeCatalog(catalog));

      expect(decoded.widgets, hasLength(1));
      expect(decoded.widgets.single.wireId, WireId('w0001'));
      expect(decoded.widgets.single.properties.single.name, 'text');
      expect(decoded.widgets.single.properties.single.required, isTrue);
    });

    test('preserves an above-baseline sinceVersion through lowering', () {
      final widgetIr = WidgetIR(
        wireId: WireId('w0001'),
        source: _FakeClassElement(),
        constructor: _FakeConstructorElement(),
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        properties: const [],
        decomposes: const [],
        fires: const [],
        childrenSlot: ChildrenSlot.none,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Text',
          curationSource: 'test/fixtures/catalog_text.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
        sinceVersion: 2,
      );

      expect(lowerWidget(widgetIr).sinceVersion, 2);
    });

    test('defaults sinceVersion to the baseline when the IR omits it', () {
      final widgetIr = WidgetIR(
        wireId: WireId('w0001'),
        source: _FakeClassElement(),
        constructor: _FakeConstructorElement(),
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        properties: const [],
        decomposes: const [],
        fires: const [],
        childrenSlot: ChildrenSlot.none,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Text',
          curationSource: 'test/fixtures/catalog_text.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );

      expect(lowerWidget(widgetIr).sinceVersion, kBaselineCatalogVersion);
    });

    test('fails when an emitted library has no version metadata', () {
      final widgetIr = WidgetIR(
        wireId: WireId('w0001'),
        source: _FakeClassElement(),
        constructor: _FakeConstructorElement(),
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        properties: const [],
        decomposes: const [],
        fires: const [],
        childrenSlot: ChildrenSlot.none,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Text',
          curationSource: 'test/fixtures/catalog_text.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );

      expect(
        () => lowerCatalog(
          CatalogIR(
            generatedAt: '2026-05-11T12:00:00Z',
            libraryVersions: const {},
            widgets: [widgetIr],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('restage.core'),
          ),
        ),
      );
    });

    test('lowers library versions and entry counts', () {
      final widgetIr = WidgetIR(
        wireId: WireId('w0001'),
        source: _FakeClassElement(),
        constructor: _FakeConstructorElement(),
        name: 'CatalogText',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Displays a text label.',
        properties: const [],
        decomposes: const [],
        fires: const [],
        childrenSlot: ChildrenSlot.none,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Text',
          curationSource: 'test/fixtures/catalog_text.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );
      final structuredIr = StructuredIR(
        wireId: WireId('s0001'),
        source: _FakeClassElement(),
        name: 'CatalogInsets',
        library: WidgetLibrary.core,
        description: 'Insets.',
        fields: const [],
        variants: const [],
        stability: Stability.volatile,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#EdgeInsets',
          curationSource: 'test/fixtures/catalog_insets.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );
      final unionIr = UnionIR(
        wireId: WireId('u0001'),
        source: _FakeClassElement(),
        name: 'CatalogDecoration',
        library: WidgetLibrary.core,
        description: 'Decoration union.',
        sourceType: 'package:flutter/widgets.dart#Decoration',
        memberSourceTypes: const [],
        discriminator: const DiscriminatorSpec(field: '_s', values: []),
        members: const [],
        stability: Stability.volatile,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'package:flutter/widgets.dart#Decoration',
          curationSource: 'test/fixtures/catalog_decoration.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );
      final designTokenIr = DesignTokenIR(
        wireId: WireId('t0001'),
        name: 'primaryColor',
        library: WidgetLibrary.core,
        type: DesignTokenType.color,
        resolver: null,
        literalFallback: 0xFF000000,
        stability: Stability.stable,
        diagnostics: const [],
        provenance: const ProvenanceIR(
          flutterType: 'Color',
          curationSource: 'test/fixtures/tokens.dart:1',
          derivationTrace: ['fixture'],
        ),
        policyTrace: const [],
      );

      final catalog = lowerCatalog(
        CatalogIR(
          generatedAt: '2026-05-11T12:00:00Z',
          libraryVersions: {WidgetLibrary.core: '1.2.3'},
          widgets: [widgetIr],
          structuredTypes: [structuredIr],
          unions: [unionIr],
          designTokens: [designTokenIr],
        ),
      );

      final library = catalog.libraries[WidgetLibrary.core]!;
      expect(library.version, '1.2.3');
      expect(catalog.widgetsIn(WidgetLibrary.core).length, 1);
      expect(catalog.structuredTypesIn(WidgetLibrary.core).length, 1);
      expect(catalog.unionsIn(WidgetLibrary.core).length, 1);
      expect(catalog.designTokensIn(WidgetLibrary.core).length, 1);
    });

    test('preserves structured and union stability', () {
      final structured = lowerStructured(
        StructuredIR(
          wireId: WireId('s0001'),
          source: _FakeClassElement(),
          name: 'CatalogInsets',
          library: WidgetLibrary.core,
          description: 'Insets.',
          fields: const [],
          variants: const [],
          stability: Stability.stable,
          diagnostics: const [],
          provenance: const ProvenanceIR(
            flutterType: 'package:flutter/widgets.dart#EdgeInsets',
            curationSource: 'test/fixtures/catalog_insets.dart:1',
            derivationTrace: ['fixture'],
          ),
          policyTrace: const [],
        ),
      );
      final union = lowerUnion(
        UnionIR(
          wireId: WireId('u0001'),
          source: _FakeClassElement(),
          name: 'CatalogDecoration',
          library: WidgetLibrary.core,
          description: 'Decoration union.',
          sourceType: 'package:flutter/widgets.dart#Decoration',
          memberSourceTypes: const [],
          discriminator: const DiscriminatorSpec(field: '_s', values: []),
          members: const [],
          stability: Stability.stable,
          diagnostics: const [],
          provenance: const ProvenanceIR(
            flutterType: 'package:flutter/widgets.dart#Decoration',
            curationSource: 'test/fixtures/catalog_decoration.dart:1',
            derivationTrace: ['fixture'],
          ),
          policyTrace: const [],
        ),
      );

      expect(structured.stability, Stability.stable);
      expect(union.stability, Stability.stable);
    });

    test(
        'lowerStructuredField maps ResolvedTypeKind.structured to '
        'PropertyType.structured and threads structuredRef', () {
      const ref = WireIdRef(
        library: 'restage.core',
        wireId: WireId.unallocatedStructured,
      );
      final field = StructuredFieldIR(
        wireId: WireId('p0001'),
        source: _FakeElement(),
        name: 'borderRadius',
        type: const ResolvedType(
          kind: ResolvedTypeKind.structured,
          structuredRef: ref,
        ),
        description: 'Corner radii.',
        defaultSource: null,
        metadata: const PropertyMetadataIR(),
        diagnostics: const [],
      );

      final lowered = lowerStructuredField(field);

      expect(lowered.type, PropertyType.structured);
      expect(lowered.structuredRef, ref);
    });

    test(
        'lowerProperty maps ResolvedTypeKind.structured to '
        'PropertyType.structured and threads structuredRef', () {
      const ref = WireIdRef(
        library: 'restage.core',
        wireId: WireId.unallocatedStructured,
      );
      final property = PropertyIR(
        wireId: WireId('p0001'),
        source: _FakeElement(),
        name: 'decoration',
        type: const ResolvedType(
          kind: ResolvedTypeKind.structured,
          structuredRef: ref,
        ),
        description: 'Box decoration.',
        defaultSource: null,
        metadata: const PropertyMetadataIR(),
        policyTrace: const [],
        diagnostics: const [],
      );

      final lowered = lowerProperty(property);

      expect(lowered.type, PropertyType.structured);
      expect(lowered.structuredRef, ref);
    });

    test('lowerProperty preserves concrete alignmentXY kind', () {
      final property = PropertyIR(
        wireId: WireId('p0001'),
        source: _FakeElement(),
        name: 'alignment',
        type: const ResolvedType(kind: ResolvedTypeKind.alignmentXY),
        description: 'Alignment.',
        defaultSource: const ResolvedDefaultSource(
          lowered: LiteralDefault('center'),
          shape: ResolvedDefaultShape.literal,
          origin: ResolvedDefaultOrigin.curationOverride,
        ),
        metadata: const PropertyMetadataIR(),
        policyTrace: const [],
        diagnostics: const [],
      );

      final lowered = lowerProperty(property);

      expect(lowered.type, PropertyType.alignmentXY);
      expect(lowered.defaultSource, const LiteralDefault('center'));
    });

    test('lowers native decompose metadata from IR to schema', () {
      final boxDecorationRef = WireIdRef(
        library: 'restage.core',
        wireId: WireId('s0001'),
      );
      const boxShapeType = DartTypeRef(
        libraryUri: 'package:flutter/painting.dart',
        symbolName: 'BoxShape',
      );
      const propertyShape = EnumShape(
        propertyType: PropertyType.enumValue,
        enumRef: boxShapeType,
      );
      final fieldShape = StructuredShape(
        propertyType: PropertyType.structured,
        structuredRef: boxDecorationRef,
      );

      final property = lowerProperty(
        PropertyIR(
          wireId: WireId('p0001'),
          source: _FakeElement(),
          name: 'shape',
          type: const ResolvedType(
            kind: ResolvedTypeKind.enumValue,
            valueShape: propertyShape,
          ),
          description: 'Shape.',
          defaultSource: null,
          metadata: const PropertyMetadataIR(),
          policyTrace: const [],
          diagnostics: const [],
        ),
      );
      final field = lowerStructuredField(
        StructuredFieldIR(
          wireId: WireId('p0501'),
          source: _FakeElement(),
          name: 'decoration',
          type: ResolvedType(
            kind: ResolvedTypeKind.structured,
            structuredRef: boxDecorationRef,
            valueShape: fieldShape,
          ),
          description: 'Decoration.',
          defaultSource: null,
          metadata: const PropertyMetadataIR(),
          diagnostics: const [],
        ),
      );
      const parameter = FactoryParameter(
        wireId: WireId.unallocatedParameter,
        position: 0,
        kind: FactoryParameterKind.positional,
        required: true,
        nullable: false,
        defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
        valueShape: ScalarShape(
          propertyType: PropertyType.real,
          dartTypeRef: DartTypeRef(
            libraryUri: 'dart:core',
            symbolName: 'double',
          ),
        ),
      );
      final variant = lowerFactoryVariant(
        FactoryVariantIR(
          wireId: WireId('v0001'),
          sourceKind: VariantSourceKind.constructor,
          source: _FakeConstructorElement(),
          namedConstructor: 'circular',
          parameters: const [parameter],
        ),
      );
      final invocation = FactoryInvocation(
        variantRef: WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
        receiver: const ResultStructuredTypeReceiver(),
        memberName: 'circular',
      );
      final mapping = DecompositionFieldMapping(
        fieldRef: WireId('p0501'),
        propertyRef: WireId('p0002'),
        transform: ConstructVariantTransform(
          resultStructuredRef: boxDecorationRef,
          invocation: invocation,
          argumentBindings: [
            PropertyValueArgumentBinding(
              parameterRef: WireId('a0001'),
              nullPolicy: TransformNullPolicy.nullResult,
              missingPolicy: TransformMissingPolicy.useDefault,
            ),
          ],
        ),
      );
      final recipe = lowerDecomposition(
        DecompositionIR(
          structuredRef: boxDecorationRef,
          targetArg: 'decoration',
          construction: invocation,
          fieldMappings: [mapping],
          flatPropertyRefs: {WireId('p0501'): WireId('p0002')},
        ),
      );

      final loweredVariant = variant as ConstructorVariant;
      expect(property.valueShape, same(propertyShape));
      expect(field.valueShape, same(fieldShape));
      expect(loweredVariant.parameters.single, same(parameter));
      expect(
        loweredVariant.parameters.single.wireId,
        WireId.unallocatedParameter,
      );
      expect(recipe.targetArg, 'decoration');
      expect(recipe.construction, same(invocation));
      expect(recipe.fieldMappings.single, same(mapping));
      final loweredTransform =
          recipe.fieldMappings.single.transform as ConstructVariantTransform;
      expect(
        loweredTransform.argumentBindings.single.parameterRef,
        WireId('a0001'),
      );
      expect(
        loweredTransform.argumentBindings.single.missingPolicy,
        TransformMissingPolicy.useDefault,
      );
    });
  });
}
