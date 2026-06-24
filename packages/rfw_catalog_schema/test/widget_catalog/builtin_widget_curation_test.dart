import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('BuiltinWidgetCuration', () {
    test('captures only required fields with schema-safe defaults', () {
      const curation = BuiltinWidgetCuration<_StubWidget>(
        category: WidgetCategory.layout,
      );
      expect(curation.category, WidgetCategory.layout);
      expect(curation.constructorName, isNull);
      expect(curation.nameOverride, isNull);
      expect(curation.descriptionOverride, isNull);
      expect(curation.fires, isEmpty);
      expect(curation.childrenSlot, isNull);
      expect(curation.deprecatedSince, isNull);
      expect(curation.minSchemaVersion, 1);
      expect(curation.excludeParams, isEmpty);
      expect(curation.brandTokens, isEmpty);
      expect(curation.nativeDecomposes, isEmpty);
      expect(curation.synthetics, isEmpty);
      expect(curation.propertyOverrides, isEmpty);
    });

    test('captures the full schema vocabulary surface', () {
      const curation = BuiltinWidgetCuration<_StubWidget>(
        category: WidgetCategory.action,
        constructorName: 'tonal',
        nameOverride: 'FilledButtonTonal',
        descriptionOverride: 'M3 secondary CTA.',
        fires: [WidgetEventName.onPressed],
        childrenSlot: ChildrenSlot.single,
        deprecatedSince: '2.0.0',
        minSchemaVersion: 2,
        excludeParams: ['style'],
        brandTokens: {
          'backgroundColor': 'secondaryContainer',
          'foregroundColor': 'onSecondaryContainer',
        },
        nativeDecomposes: [
          NativeDecompositionCuration(
            structuredType: 'ButtonStyle',
            targetArg: 'style',
            construction: NativeFactoryCuration.owningWidgetStatic('styleFrom'),
            fieldMappings: [
              NativeFieldMappingCuration(
                field: 'backgroundColor',
                property: 'backgroundColor',
              ),
            ],
          ),
        ],
        synthetics: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'disabled',
            type: PropertyType.boolean,
            description: 'Whether the button is disabled.',
            synthetic: 'gateOnPressed',
            defaultSource: LiteralDefault(false),
          ),
        ],
        propertyOverrides: {
          'onPressed': PropertyOverride(
            description: 'Fired when the user taps.',
            callbackSignature: 'VoidCallback',
          ),
        },
      );
      expect(curation.constructorName, 'tonal');
      expect(curation.nameOverride, 'FilledButtonTonal');
      expect(curation.descriptionOverride, 'M3 secondary CTA.');
      expect(curation.fires, [WidgetEventName.onPressed]);
      expect(curation.childrenSlot, ChildrenSlot.single);
      expect(curation.deprecatedSince, '2.0.0');
      expect(curation.minSchemaVersion, 2);
      expect(curation.excludeParams, ['style']);
      expect(curation.brandTokens, hasLength(2));
      expect(curation.nativeDecomposes.single.structuredType, 'ButtonStyle');
      expect(curation.nativeDecomposes.single.targetArg, 'style');
      expect(
        curation.nativeDecomposes.single.construction.receiver,
        isA<OwningWidgetTypeReceiver>(),
      );
      expect(curation.synthetics.single.synthetic, 'gateOnPressed');
      expect(
        curation.propertyOverrides['onPressed']?.callbackSignature,
        'VoidCallback',
      );
    });

    test(
      'curation entries with distinct type arguments compose into a '
      'const list',
      () {
        // The reflector reads each entry's type argument off the
        // `InterfaceType.typeArguments` exposed by the analyzer; verifying
        // the heterogeneous-list shape is const-constructible safeguards
        // the curation-file authoring pattern.
        const list = <BuiltinWidgetCuration<Object>>[
          BuiltinWidgetCuration<_StubWidget>(category: WidgetCategory.layout),
          BuiltinWidgetCuration<_OtherStub>(category: WidgetCategory.input),
        ];
        expect(list, hasLength(2));
        expect(list.first.category, WidgetCategory.layout);
        expect(list.last.category, WidgetCategory.input);
      },
    );
  });

  group('PropertyOverride', () {
    test('all fields nullable; absence preserves inferred surface', () {
      const override = PropertyOverride();
      expect(override.name, isNull);
      expect(override.description, isNull);
      expect(override.required, isNull);
      expect(override.defaultValue, isNull);
      expect(override.defaultBrandToken, isNull);
      expect(override.positional, isNull);
      expect(override.enumType, isNull);
      expect(override.widgetType, isNull);
      expect(override.callbackSignature, isNull);
    });

    test('captures every overrideable PropertyEntry field', () {
      const override = PropertyOverride(
        name: 'url',
        description: 'The displayed text.',
        required: true,
        defaultValue: 'fallback',
        positional: true,
        enumType: 'TextAlign',
        widgetType: 'PreferredSizeWidget',
        callbackSignature: 'ValueChanged<bool>',
      );
      expect(override.name, 'url');
      expect(override.description, 'The displayed text.');
      expect(override.required, isTrue);
      expect(override.defaultValue, 'fallback');
      expect(override.positional, isTrue);
      expect(override.enumType, 'TextAlign');
      expect(override.widgetType, 'PreferredSizeWidget');
      expect(override.callbackSignature, 'ValueChanged<bool>');
    });

    test('rejects co-supplying defaultValue and defaultBrandToken', () {
      expect(
        () => PropertyOverride(
          defaultValue: 'literal',
          defaultBrandToken: 'primary',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('defaultBrandToken alone is allowed', () {
      const override = PropertyOverride(defaultBrandToken: 'primary');
      expect(override.defaultBrandToken, 'primary');
      expect(override.defaultValue, isNull);
    });
  });

  group('synthetic property authoring (via PropertyEntry)', () {
    test('synthetic field carries the codegen translation strategy', () {
      const synthetic = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'iconCodepoint',
        type: PropertyType.integer,
        description: 'Material icon codepoint.',
        synthetic: 'iconData',
        required: true,
        positional: true,
      );
      expect(synthetic.name, 'iconCodepoint');
      expect(synthetic.type, PropertyType.integer);
      expect(synthetic.synthetic, 'iconData');
      expect(synthetic.required, isTrue);
      expect(synthetic.positional, isTrue);
    });
  });

  group('RestageBuiltinLibrary', () {
    test('captures the library namespace and authoring version', () {
      const annotation = RestageBuiltinLibrary(
        library: WidgetLibrary.material,
        version: '0.1.0',
      );
      expect(annotation.library, WidgetLibrary.material);
      expect(annotation.version, '0.1.0');
      expect(annotation.minSchemaVersion, 1);
    });

    test(
        'minSchemaVersion is overridable for parity with sibling '
        'annotations', () {
      const annotation = RestageBuiltinLibrary(
        library: WidgetLibrary.core,
        version: '0.2.0',
        minSchemaVersion: 2,
      );
      expect(annotation.minSchemaVersion, 2);
    });
  });
}

class _StubWidget {
  const _StubWidget();
}

class _OtherStub {
  const _OtherStub();
}
