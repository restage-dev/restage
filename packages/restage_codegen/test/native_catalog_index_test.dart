import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

WireIdRef _ref(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

void main() {
  test('indexes native catalog entries by library-qualified identity', () {
    final index = NativeCatalogIndex(_nativeCatalog());

    final widgetRef = _ref('restage.core', 'w0001');
    final boxRef = _ref('restage.core', 's0001');
    final borderRadiusRef = _ref('restage.core', 's0002');
    final gradientUnionRef = _ref('restage.core', 'u0001');

    expect(index.widgetByRef(widgetRef)?.name, 'Container');
    expect(
      index.widgetByName(WidgetLibrary.core, 'Container')?.wireId,
      WireId('w0001'),
    );
    expect(index.widgetProperty(widgetRef, WireId('p0001'))?.name, 'radius');

    expect(index.structuredByRef(boxRef)?.name, 'BoxDecoration');
    expect(
      index.structuredByDartType(_boxDecorationType)?.wireId,
      WireId('s0001'),
    );
    expect(
      index.structuredField(boxRef, WireId('p0002'))?.name,
      'borderRadius',
    );

    expect(
      index.variantByRef(_ref('restage.core', 'v0001'))?.wireId,
      WireId('v0001'),
    );
    expect(index.variantFor(boxRef, WireId('v0001'))?.wireId, WireId('v0001'));
    expect(
      index
          .variantParameter(_ref('restage.core', 'v0002'), WireId('a0003'))
          ?.name,
      'radius',
    );

    expect(index.unionByRef(gradientUnionRef)?.name, 'Gradient');
    expect(
      index.unionMember(gradientUnionRef, _ref('restage.core', 's0003'))?.name,
      'LinearGradient',
    );
    expect(index.unionMember(gradientUnionRef, borderRadiusRef), isNull);
  });

  test('resolves construction receivers from native receiver metadata', () {
    final index = NativeCatalogIndex(_nativeCatalog());
    final widget = index.widgetByRef(_ref('restage.core', 'w0001'))!;
    final structured = index.structuredByRef(_ref('restage.core', 's0001'))!;

    expect(
      index.receiverDartType(
        const ResultStructuredTypeReceiver(),
        owningWidget: widget,
        resultStructured: structured,
      ),
      _boxDecorationType,
    );
    expect(
      index.receiverDartType(
        const OwningWidgetTypeReceiver(),
        owningWidget: widget,
        resultStructured: structured,
      ),
      _containerType,
    );
    expect(
      index.receiverDartType(
        const ExplicitDartTypeReceiver(_linearGradientType),
        owningWidget: widget,
        resultStructured: structured,
      ),
      _linearGradientType,
    );
  });
}

const _containerType = DartTypeRef(
  libraryUri: 'package:flutter/widgets.dart',
  symbolName: 'Container',
);
const _boxDecorationType = DartTypeRef(
  libraryUri: 'package:flutter/painting.dart',
  symbolName: 'BoxDecoration',
);
const _linearGradientType = DartTypeRef(
  libraryUri: 'package:flutter/painting.dart',
  symbolName: 'LinearGradient',
);

Catalog _nativeCatalog() {
  final boxRef = _ref('restage.core', 's0001');
  final borderRadiusRef = _ref('restage.core', 's0002');
  final linearGradientRef = _ref('restage.core', 's0003');
  final boxCtorRef = _ref('restage.core', 'v0001');
  final borderRadiusCircularRef = _ref('restage.core', 'v0002');

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Container',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'Container.',
        flutterType: 'package:flutter/widgets.dart#Container',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'radius',
            type: PropertyType.real,
            description: 'Uniform radius.',
            valueShape: const ScalarShape(propertyType: PropertyType.real),
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: boxRef,
            flatProperties: {WireId('p0002'): WireId('p0001')},
            targetArg: 'decoration',
            construction: FactoryInvocation(
              variantRef: boxCtorRef,
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: WireId('p0002'),
                propertyRef: WireId('p0001'),
                transform: ConstructVariantTransform(
                  resultStructuredRef: borderRadiusRef,
                  invocation: FactoryInvocation(
                    variantRef: borderRadiusCircularRef,
                    receiver: const ResultStructuredTypeReceiver(),
                    memberName: 'circular',
                  ),
                  argumentBindings: [
                    PropertyValueArgumentBinding(
                      parameterRef: WireId('a0003'),
                      nullPolicy: TransformNullPolicy.nullResult,
                      missingPolicy: TransformMissingPolicy.nullResult,
                    ),
                  ],
                ),
              ),
            ],
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
            wireId: WireId('p0002'),
            name: 'borderRadius',
            type: PropertyType.structured,
            description: 'Border radius.',
            structuredRef: borderRadiusRef,
            valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: borderRadiusRef,
            ),
          ),
          StructuredField(
            wireId: WireId('p0003'),
            name: 'gradient',
            type: PropertyType.gradient,
            description: 'Gradient.',
            unionRef: _ref('restage.core', 'u0001'),
            valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef: _ref('restage.core', 'u0001'),
              wireCodec: CatalogWireCodec.rfwGradient,
            ),
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
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
              FactoryParameter(
                wireId: WireId('a0002'),
                name: 'gradient',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: true,
                defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                valueShape: UnionShape(
                  propertyType: PropertyType.gradient,
                  unionRef: _ref('restage.core', 'u0001'),
                  wireCodec: CatalogWireCodec.rfwGradient,
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
        fields: [
          StructuredField(
            wireId: WireId('p0004'),
            name: 'radius',
            type: PropertyType.real,
            description: 'Radius.',
            valueShape: const ScalarShape(propertyType: PropertyType.real),
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0002'),
            namedConstructor: 'circular',
            parameters: [
              FactoryParameter(
                wireId: WireId('a0003'),
                name: 'radius',
                kind: FactoryParameterKind.named,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: const ScalarShape(propertyType: PropertyType.real),
              ),
            ],
          ),
        ],
      ),
      StructuredEntry(
        wireId: WireId('s0003'),
        name: 'LinearGradient',
        library: WidgetLibrary.core,
        description: 'Linear gradient.',
        sourceType: 'package:flutter/painting.dart#LinearGradient',
        fields: const [],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0003'),
          ),
        ],
      ),
    ],
    unions: [
      UnionEntry(
        wireId: WireId('u0001'),
        name: 'Gradient',
        library: WidgetLibrary.core,
        description: 'Gradient union.',
        sourceType: 'package:flutter/painting.dart#Gradient',
        memberSourceTypes: const [
          'package:flutter/painting.dart#LinearGradient',
        ],
        discriminator: DiscriminatorSpec(
          field: 'kind',
          values: [linearGradientRef],
        ),
        members: [linearGradientRef],
      ),
    ],
  );
}
