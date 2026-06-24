import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'canonicalize.dart';
import 'project.dart';

void main() {
  group('projectCatalogToLegacyJson', () {
    test('drops additive fields and projects supported default sources', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [
          WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'Button',
            library: WidgetLibrary.core,
            category: WidgetCategory.input,
            description: 'A button.',
            flutterType: 'package:flutter/widgets.dart#Button',
            childrenSlot: ChildrenSlot.none,
            fires: [WidgetEventName.onTap],
            stability: Stability.stable,
            properties: [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'label',
                type: PropertyType.string,
                description: 'Text.',
                defaultSource: LiteralDefault('Continue'),
                category: PropertyCategory.data,
                priority: PropertyPriority.primary,
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'color',
                type: PropertyType.color,
                description: 'Color.',
                defaultSource: TokenRefDefault(
                  WireIdRef(
                    library: 'restage.core',
                    wireId: WireId.unallocatedDesignToken,
                  ),
                ),
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'foregroundColor',
                type: PropertyType.color,
                description: 'Foreground color.',
                defaultSource: ThemeBindingDefault(
                  ThemeBindingPath.path('colorScheme.primary'),
                ),
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'height',
                type: PropertyType.length,
                description: 'Height.',
                defaultSource: LiteralDefault(44),
              ),
            ],
          ),
        ],
        structuredTypes: const [
          StructuredEntry(
            wireId: WireId.unallocatedStructured,
            name: 'ButtonStyle',
            library: WidgetLibrary.core,
            description: 'Style.',
            sourceType: 'ButtonStyle',
            fields: [],
            variants: [],
          ),
        ],
        unions: const [
          UnionEntry(
            wireId: WireId.unallocatedUnion,
            name: 'StyleUnion',
            library: WidgetLibrary.core,
            description: 'Style union.',
            sourceType: 'package:test/test.dart#StyleUnion',
            memberSourceTypes: [],
            discriminator: DiscriminatorSpec(field: 'type', values: []),
            members: [],
          ),
        ],
        designTokens: const [
          DesignTokenEntry(
            wireId: WireId.unallocatedDesignToken,
            name: 'brand.primary',
            library: WidgetLibrary.core,
            type: DesignTokenType.color,
            literalFallback: 0xFF000000,
            stability: Stability.stable,
          ),
        ],
      );

      final canonical =
          jsonDecode(canonicalizeJson(projectCatalogToLegacyJson(catalog)))
              as Map<String, dynamic>;
      final widget =
          (canonical['widgets'] as List).single as Map<String, dynamic>;
      final properties = {
        for (final property in widget['properties'] as List)
          (property as Map<String, dynamic>)['name'] as String: property,
      };

      expect(canonical.containsKey('structuredTypes'), isFalse);
      expect(canonical.containsKey('unions'), isFalse);
      expect(canonical.containsKey('designTokens'), isFalse);
      expect(widget.containsKey('wireId'), isFalse);
      expect(widget.containsKey('stability'), isFalse);
      expect(properties['label']!['defaultValue'], 'Continue');
      expect(properties['label']!.containsKey('defaultSource'), isFalse);
      expect(properties['label']!.containsKey('priority'), isFalse);
      expect(properties['color']!['defaultBrandToken'], 'brand.primary');
      expect(
        properties['foregroundColor']!.containsKey('defaultValue'),
        isFalse,
      );
      expect(properties['height']!['defaultValue'], 44);
      expect(
        properties.values.any((property) => property.containsKey('wireId')),
        isFalse,
      );
    });

    test('drops PropertyEntry instances typed as structured', () {
      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [
          WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'Container',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'A container.',
            flutterType: 'package:flutter/widgets.dart#Container',
            childrenSlot: ChildrenSlot.single,
            fires: [],
            stability: Stability.stable,
            properties: [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'width',
                type: PropertyType.length,
                description: 'Width.',
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'decoration',
                type: PropertyType.structured,
                description: 'BoxDecoration value.',
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId.unallocatedStructured,
                ),
              ),
            ],
          ),
        ],
        structuredTypes: const [
          StructuredEntry(
            wireId: WireId.unallocatedStructured,
            name: 'BoxDecoration',
            library: WidgetLibrary.core,
            description: 'BoxDecoration.',
            sourceType: 'BoxDecoration',
            fields: [],
            variants: [],
          ),
        ],
      );

      final canonical =
          jsonDecode(canonicalizeJson(projectCatalogToLegacyJson(catalog)))
              as Map<String, dynamic>;
      final widget =
          (canonical['widgets'] as List).single as Map<String, dynamic>;
      final propertyNames = [
        for (final property in widget['properties'] as List)
          (property as Map<String, dynamic>)['name'] as String,
      ];

      // Structured-typed properties drop from the projection — they are
      // an additive surface the legacy baselines never carried.
      expect(propertyNames, equals(['width']));
      expect(canonical.containsKey('structuredTypes'), isFalse);
    });
  });
}
