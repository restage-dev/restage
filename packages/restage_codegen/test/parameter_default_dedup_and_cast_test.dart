import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// D3 — locks `_applyParameterDefaultFallback`'s dedup skip branch, and
/// D4 — covers the `OutlinedBorder` nullable-cast gap in
/// `_coerceNativeArgumentForParameter`. Both exercise the native-decompose
/// outer-recipe argument path through `emitFactoryFunction`.

WireIdRef _ref(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

NativeCatalogIndex _index(WidgetEntry widget, StructuredEntry structured) {
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.material: const LibraryInfo(version: '1.0.0'),
    },
    widgets: [widget],
    structuredTypes: [structured],
  );
  return NativeCatalogIndex(catalog);
}

void main() {
  group('D3 — parameter-default dedup skip branch', () {
    // A widget whose single property is decomposed (identity transform) into a
    // one-parameter construction whose parameter carries its own default.
    // Whether the parameter default is appended depends on the property's
    // default source.
    ({WidgetEntry widget, StructuredEntry structured}) fixture({
      required String name,
      required PropertyType type,
      required DefaultValueSource propertyDefault,
      required FactoryParameterDefaultValue parameterDefault,
    }) {
      final shape = ScalarShape(propertyType: type);
      final widget = WidgetEntry(
        wireId: WireId('w0001'),
        name: 'Styled',
        library: WidgetLibrary.material,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/material.dart#Styled',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: name,
            type: type,
            description: '',
            defaultSource: propertyDefault,
            valueShape: shape,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: _ref('restage.material', 's0001'),
            targetArg: 'style',
            flatProperties: {WireId('p0501'): WireId('p0001')},
            construction: FactoryInvocation(
              variantRef: _ref('restage.material', 'v0001'),
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              DecompositionFieldMapping(
                fieldRef: WireId('p0501'),
                propertyRef: WireId('p0001'),
                transform: const IdentityTransform(),
              ),
            ],
          ),
        ],
      );
      final structured = StructuredEntry(
        wireId: WireId('s0001'),
        name: 'Style',
        library: WidgetLibrary.material,
        description: '',
        sourceType: 'package:flutter/painting.dart#Style',
        fields: [
          StructuredField(
            wireId: WireId('p0501'),
            name: name,
            type: type,
            description: '',
            valueShape: shape,
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            argMappings: {
              name: ArgMapping(targetFields: [WireId('p0501')]),
            },
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                name: name,
                kind: FactoryParameterKind.named,
                required: false,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
                defaultValue: parameterDefault,
                valueShape: shape,
              ),
            ],
          ),
        ],
      );
      return (widget: widget, structured: structured);
    }

    test(
        'a non-theme literal property default skips the parameter default '
        '(single ??)', () {
      final f = fixture(
        name: 'inherit',
        type: PropertyType.boolean,
        propertyDefault: const LiteralDefault(false),
        parameterDefault: const LiteralParameterDefault(true),
      );
      final source = emitFactoryFunction(
        f.widget,
        nativeIndex: _index(f.widget, f.structured),
      );

      expect(source, isNotNull);
      // The property literal default is present...
      expect(source, contains('?? false'));
      // ...and the parameter default (true) is NOT appended on top of it.
      expect(source, isNot(contains('?? true')));
    });

    test('a ThemeBindingDefault property default keeps the parameter default',
        () {
      final f = fixture(
        name: 'color',
        type: PropertyType.color,
        propertyDefault: const ThemeBindingDefault(
          ThemeBindingPath.path('colorScheme.primary'),
        ),
        parameterDefault: const StaticMemberParameterDefault(
          staticType: DartTypeRef(
            libraryUri: 'package:flutter/material.dart',
            symbolName: 'Colors',
          ),
          memberName: 'transparent',
        ),
      );
      final source = emitFactoryFunction(
        f.widget,
        nativeIndex: _index(f.widget, f.structured),
      );

      expect(source, isNotNull);
      // The theme binding resolves to a nullable value at render time, so the
      // parameter default stays a reachable fallback.
      expect(source, contains('resolveThemeBinding'));
      expect(source, contains('?? Colors.transparent'));
    });
  });

  group('D4 — OutlinedBorder cast nullability follows the parameter', () {
    const outlinedBorderType = DartTypeRef(
      libraryUri: 'package:flutter/painting.dart',
      symbolName: 'OutlinedBorder',
    );

    WidgetEntry borderedWidget() => WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Bordered',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/material.dart#Bordered',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'shape',
              type: PropertyType.shapeBorder,
              description: '',
              valueShape: const ScalarShape(
                propertyType: PropertyType.shapeBorder,
                dartTypeRef: outlinedBorderType,
                wireCodec: CatalogWireCodec.rfwShapeBorder,
              ),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: _ref('restage.material', 's0001'),
              targetArg: 'decoration',
              flatProperties: {WireId('p0501'): WireId('p0001')},
              construction: FactoryInvocation(
                variantRef: _ref('restage.material', 'v0001'),
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: WireId('p0501'),
                  propertyRef: WireId('p0001'),
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );

    StructuredEntry borderStructured({required bool nonNullableParameter}) =>
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'ShapeDecoration',
          library: WidgetLibrary.material,
          description: '',
          sourceType: 'package:flutter/painting.dart#ShapeDecoration',
          fields: [
            StructuredField(
              wireId: WireId('p0501'),
              name: 'shape',
              type: PropertyType.shapeBorder,
              description: '',
              valueShape: const ScalarShape(
                propertyType: PropertyType.shapeBorder,
                dartTypeRef: outlinedBorderType,
                wireCodec: CatalogWireCodec.rfwShapeBorder,
              ),
            ),
          ],
          variants: [
            ConstructorVariant(
              wireId: WireId('v0001'),
              argMappings: {
                'shape': ArgMapping(targetFields: [WireId('p0501')]),
              },
              parameters: [
                FactoryParameter(
                  wireId: WireId('a0001'),
                  name: 'shape',
                  kind: FactoryParameterKind.named,
                  required: false,
                  nullable: !nonNullableParameter,
                  defaultPolicy:
                      FactoryParameterDefaultPolicy.useFlutterDefault,
                  valueShape: const ScalarShape(
                    propertyType: PropertyType.shapeBorder,
                    dartTypeRef: outlinedBorderType,
                    wireCodec: CatalogWireCodec.rfwShapeBorder,
                  ),
                ),
              ],
            ),
          ],
        );

    test('a non-nullable OutlinedBorder parameter casts to OutlinedBorder', () {
      final widget = borderedWidget();
      final source = emitFactoryFunction(
        widget,
        nativeIndex: _index(
          widget,
          borderStructured(nonNullableParameter: true),
        ),
      );

      expect(source, isNotNull);
      expect(source, contains('as OutlinedBorder)'));
      expect(source, isNot(contains('as OutlinedBorder?)')));
    });

    test('a nullable OutlinedBorder parameter casts to OutlinedBorder?', () {
      final widget = borderedWidget();
      final source = emitFactoryFunction(
        widget,
        nativeIndex: _index(
          widget,
          borderStructured(nonNullableParameter: false),
        ),
      );

      expect(source, isNotNull);
      expect(source, contains('as OutlinedBorder?)'));
      // ...and not the non-nullable form, so the pair pins the mapping in
      // both directions.
      expect(source, isNot(contains('as OutlinedBorder)')));
    });
  });
}
