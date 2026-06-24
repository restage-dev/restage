import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('diffCatalogs — widgets', () {
    test('detects an added widget', () {
      final before = catalog();
      final after = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      expect(
        diffCatalogs(before, after),
        [EntryAdded(kind: WireIdKind.widget, affected: ref('w0001'))],
      );
    });

    test('detects a removed widget', () {
      final before = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      final after = catalog();
      expect(
        diffCatalogs(before, after),
        [EntryRemoved(kind: WireIdKind.widget, affected: ref('w0001'))],
      );
    });

    test('detects a rename when the display name shifts', () {
      final before =
          catalog(widgets: [widgetEntry(wireId: 'w0001', name: 'A')]);
      final after = catalog(widgets: [widgetEntry(wireId: 'w0001', name: 'B')]);
      expect(
        diffCatalogs(before, after),
        [EntryRenamed(kind: WireIdKind.widget, affected: ref('w0001'))],
      );
    });

    test('detects a rename when only the flutterType shifts', () {
      final before = catalog(
        widgets: [widgetEntry(wireId: 'w0001', flutterType: 'pkg#Old')],
      );
      final after = catalog(
        widgets: [widgetEntry(wireId: 'w0001', flutterType: 'pkg#New')],
      );
      expect(
        diffCatalogs(before, after),
        [EntryRenamed(kind: WireIdKind.widget, affected: ref('w0001'))],
      );
    });

    test('reports no change for an identical widget', () {
      final before = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      final after = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      expect(diffCatalogs(before, after), isEmpty);
    });

    test('detects a standalone catalog deprecation', () {
      final before = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      final after = catalog(
        widgets: [
          widgetEntry(wireId: 'w0001', deprecated: catalogDeprecation()),
        ],
      );
      expect(
        diffCatalogs(before, after),
        [EntryDeprecated(kind: WireIdKind.widget, affected: ref('w0001'))],
      );
    });

    test('detects a replacement and does not double-count the deprecation', () {
      final before = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      final after = catalog(
        widgets: [
          widgetEntry(
            wireId: 'w0001',
            deprecated: catalogDeprecation(
              replaceWith: ref('w0002'),
              transitionId: 'tx0001',
            ),
          ),
        ],
      );
      expect(
        diffCatalogs(before, after),
        [
          EntryReplaced(
            kind: WireIdKind.widget,
            affected: ref('w0001'),
            successor: ref('w0002'),
            transitionId: 'tx0001',
          ),
        ],
      );
    });

    test('detects a children-slot change', () {
      final before = catalog(widgets: [widgetEntry(wireId: 'w0001')]);
      final after = catalog(
        widgets: [
          widgetEntry(wireId: 'w0001', childrenSlot: ChildrenSlot.single),
        ],
      );
      expect(
        diffCatalogs(before, after),
        [
          WidgetChildrenSlotChanged(
            affected: ref('w0001'),
            from: ChildrenSlot.none,
            to: ChildrenSlot.single,
          ),
        ],
      );
    });
  });

  group('diffCatalogs — properties', () {
    Catalog widgetWith(List<PropertyEntry> properties) => catalog(
          widgets: [widgetEntry(wireId: 'w0001', properties: properties)],
        );

    test('detects an added property', () {
      expect(
        diffCatalogs(
          widgetWith([]),
          widgetWith([propertyEntry(wireId: 'p0001')]),
        ),
        [EntryAdded(kind: WireIdKind.property, affected: ref('p0001'))],
      );
    });

    test('detects a removed property', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([]),
        ),
        [EntryRemoved(kind: WireIdKind.property, affected: ref('p0001'))],
      );
    });

    test('detects a property rename', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001', name: 'a')]),
          widgetWith([propertyEntry(wireId: 'p0001', name: 'b')]),
        ),
        [EntryRenamed(kind: WireIdKind.property, affected: ref('p0001'))],
      );
    });

    test('detects a property type change', () {
      expect(
        diffCatalogs(
          widgetWith([
            propertyEntry(wireId: 'p0001', type: PropertyType.color),
          ]),
          widgetWith([
            propertyEntry(wireId: 'p0001', type: PropertyType.integer),
          ]),
        ),
        [
          PropertyTypeChanged(
            affected: ref('p0001'),
            from: PropertyType.color,
            to: PropertyType.integer,
          ),
        ],
      );
    });

    test('detects a required-flag tightening (false to true)', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([propertyEntry(wireId: 'p0001', required: true)]),
        ),
        [
          RequiredFlagChanged(
            affected: ref('p0001'),
            direction: RequiredFlagDirection.tightened,
          ),
        ],
      );
    });

    test('detects a required-flag loosening (true to false)', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001', required: true)]),
          widgetWith([propertyEntry(wireId: 'p0001')]),
        ),
        [
          RequiredFlagChanged(
            affected: ref('p0001'),
            direction: RequiredFlagDirection.loosened,
          ),
        ],
      );
    });

    test('detects a defaultSource change', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(
              wireId: 'p0001',
              defaultSource: const LiteralDefault('x'),
            ),
          ]),
        ),
        [PropertyDefaultChanged(affected: ref('p0001'))],
      );
    });

    test('detects an editor-metadata change', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', category: PropertyCategory.style),
          ]),
        ),
        [PropertyMetadataChanged(affected: ref('p0001'))],
      );
    });

    test('detects a synthetic-strategy change', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', synthetic: 'iconData'),
          ]),
        ),
        [SyntheticStrategyChanged(affected: ref('p0001'))],
      );
    });

    test('detects a property deprecation', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', deprecated: catalogDeprecation()),
          ]),
        ),
        [EntryDeprecated(kind: WireIdKind.property, affected: ref('p0001'))],
      );
    });

    test('detects a property replacement', () {
      expect(
        diffCatalogs(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(
              wireId: 'p0001',
              deprecated: catalogDeprecation(
                replaceWith: ref('p0002'),
                transitionId: 'tx0002',
              ),
            ),
          ]),
        ),
        [
          EntryReplaced(
            kind: WireIdKind.property,
            affected: ref('p0001'),
            successor: ref('p0002'),
            transitionId: 'tx0002',
          ),
        ],
      );
    });

    test('a structured-type field change surfaces as a property change', () {
      Catalog structuredFieldTyped(PropertyType type) => catalog(
            structuredTypes: [
              structuredEntry(
                wireId: 's0001',
                fields: [structuredField(wireId: 'p0010', type: type)],
              ),
            ],
          );
      expect(
        diffCatalogs(
          structuredFieldTyped(PropertyType.color),
          structuredFieldTyped(PropertyType.string),
        ),
        [
          PropertyTypeChanged(
            affected: ref('p0010'),
            from: PropertyType.color,
            to: PropertyType.string,
          ),
        ],
      );
    });
  });

  group('diffCatalogs — structured types', () {
    Catalog structuredOf(StructuredEntry entry) =>
        catalog(structuredTypes: [entry]);

    test('detects an added structured type', () {
      expect(
        diffCatalogs(catalog(), structuredOf(structuredEntry(wireId: 's0001'))),
        [EntryAdded(kind: WireIdKind.structured, affected: ref('s0001'))],
      );
    });

    test('detects a removed structured type', () {
      expect(
        diffCatalogs(structuredOf(structuredEntry(wireId: 's0001')), catalog()),
        [EntryRemoved(kind: WireIdKind.structured, affected: ref('s0001'))],
      );
    });

    test('detects a structured rename when the name shifts', () {
      expect(
        diffCatalogs(
          structuredOf(structuredEntry(wireId: 's0001', name: 'A')),
          structuredOf(structuredEntry(wireId: 's0001', name: 'B')),
        ),
        [EntryRenamed(kind: WireIdKind.structured, affected: ref('s0001'))],
      );
    });

    test('detects a structured rename when only the sourceType shifts', () {
      expect(
        diffCatalogs(
          structuredOf(structuredEntry(wireId: 's0001', sourceType: 'p#Old')),
          structuredOf(structuredEntry(wireId: 's0001', sourceType: 'p#New')),
        ),
        [EntryRenamed(kind: WireIdKind.structured, affected: ref('s0001'))],
      );
    });

    test('detects a structured deprecation', () {
      expect(
        diffCatalogs(
          structuredOf(structuredEntry(wireId: 's0001')),
          structuredOf(
            structuredEntry(wireId: 's0001', deprecated: catalogDeprecation()),
          ),
        ),
        [EntryDeprecated(kind: WireIdKind.structured, affected: ref('s0001'))],
      );
    });

    test('detects a structured replacement', () {
      expect(
        diffCatalogs(
          structuredOf(structuredEntry(wireId: 's0001')),
          structuredOf(
            structuredEntry(
              wireId: 's0001',
              deprecated: catalogDeprecation(replaceWith: ref('s0002')),
            ),
          ),
        ),
        [
          EntryReplaced(
            kind: WireIdKind.structured,
            affected: ref('s0001'),
            successor: ref('s0002'),
          ),
        ],
      );
    });
  });

  group('diffCatalogs — variants', () {
    Catalog variantsOf(List<FactoryVariant> variants) => catalog(
          structuredTypes: [
            structuredEntry(wireId: 's0001', variants: variants),
          ],
        );

    test('detects an added variant', () {
      expect(
        diffCatalogs(
          variantsOf([]),
          variantsOf([factoryVariant(wireId: 'v0001')]),
        ),
        [EntryAdded(kind: WireIdKind.variant, affected: ref('v0001'))],
      );
    });

    test('detects a removed variant', () {
      expect(
        diffCatalogs(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([]),
        ),
        [EntryRemoved(kind: WireIdKind.variant, affected: ref('v0001'))],
      );
    });

    test('detects a variant rename when the accessor label shifts', () {
      expect(
        diffCatalogs(
          variantsOf([
            factoryVariant(wireId: 'v0001', namedConstructor: 'circular'),
          ]),
          variantsOf([
            factoryVariant(wireId: 'v0001', namedConstructor: 'rounded'),
          ]),
        ),
        [EntryRenamed(kind: WireIdKind.variant, affected: ref('v0001'))],
      );
    });

    test('detects a variant deprecation', () {
      expect(
        diffCatalogs(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([
            factoryVariant(wireId: 'v0001', deprecated: catalogDeprecation()),
          ]),
        ),
        [EntryDeprecated(kind: WireIdKind.variant, affected: ref('v0001'))],
      );
    });

    test('detects a variant argument-shape change (sourceKind shift)', () {
      expect(
        diffCatalogs(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([
            factoryVariant(
              wireId: 'v0001',
              sourceKind: VariantSourceKind.staticGetter,
              staticAccessor: 'zero',
            ),
          ]),
        ),
        [VariantArgumentsChanged(affected: ref('v0001'))],
      );
    });

    test('detects a variant argument-type change (argMappings shift)', () {
      expect(
        diffCatalogs(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([
            factoryVariant(
              wireId: 'v0001',
              argMappings: {
                'radius': ArgMapping(targetFields: [WireId('p0010')]),
              },
            ),
          ]),
        ),
        [VariantArgumentsChanged(affected: ref('v0001'))],
      );
    });
  });

  group('diffCatalogs — unions', () {
    Catalog unionOf(UnionEntry entry) => catalog(unions: [entry]);

    test('detects an added union', () {
      expect(
        diffCatalogs(catalog(), unionOf(unionEntry(wireId: 'u0001'))),
        [EntryAdded(kind: WireIdKind.union, affected: ref('u0001'))],
      );
    });

    test('detects a removed union', () {
      expect(
        diffCatalogs(unionOf(unionEntry(wireId: 'u0001')), catalog()),
        [EntryRemoved(kind: WireIdKind.union, affected: ref('u0001'))],
      );
    });

    test('detects a union rename', () {
      expect(
        diffCatalogs(
          unionOf(unionEntry(wireId: 'u0001', name: 'A')),
          unionOf(unionEntry(wireId: 'u0001', name: 'B')),
        ),
        [EntryRenamed(kind: WireIdKind.union, affected: ref('u0001'))],
      );
    });

    test('detects a union deprecation', () {
      expect(
        diffCatalogs(
          unionOf(unionEntry(wireId: 'u0001')),
          unionOf(
            unionEntry(wireId: 'u0001', deprecated: catalogDeprecation()),
          ),
        ),
        [EntryDeprecated(kind: WireIdKind.union, affected: ref('u0001'))],
      );
    });

    test('detects an added union member', () {
      expect(
        diffCatalogs(
          unionOf(unionEntry(wireId: 'u0001', members: [ref('s0001')])),
          unionOf(
            unionEntry(wireId: 'u0001', members: [ref('s0001'), ref('s0002')]),
          ),
        ),
        [UnionMemberAdded(affected: ref('u0001'), member: ref('s0002'))],
      );
    });

    test('detects a removed union member', () {
      expect(
        diffCatalogs(
          unionOf(
            unionEntry(wireId: 'u0001', members: [ref('s0001'), ref('s0002')]),
          ),
          unionOf(unionEntry(wireId: 'u0001', members: [ref('s0001')])),
        ),
        [UnionMemberRemoved(affected: ref('u0001'), member: ref('s0002'))],
      );
    });

    test('detects a discriminator-field change', () {
      expect(
        diffCatalogs(
          unionOf(unionEntry(wireId: 'u0001')),
          unionOf(
            unionEntry(
              wireId: 'u0001',
              discriminator: const DiscriminatorSpec(field: '_t', values: []),
            ),
          ),
        ),
        [UnionDiscriminatorChanged(affected: ref('u0001'))],
      );
    });
  });

  group('diffCatalogs — design tokens', () {
    Catalog tokenOf(DesignTokenEntry entry) => catalog(designTokens: [entry]);

    test('detects an added token', () {
      expect(
        diffCatalogs(catalog(), tokenOf(designTokenEntry(wireId: 't0001'))),
        [EntryAdded(kind: WireIdKind.designToken, affected: ref('t0001'))],
      );
    });

    test('detects a removed token', () {
      expect(
        diffCatalogs(tokenOf(designTokenEntry(wireId: 't0001')), catalog()),
        [EntryRemoved(kind: WireIdKind.designToken, affected: ref('t0001'))],
      );
    });

    test('detects a token rename', () {
      expect(
        diffCatalogs(
          tokenOf(designTokenEntry(wireId: 't0001', name: 'a')),
          tokenOf(designTokenEntry(wireId: 't0001', name: 'b')),
        ),
        [EntryRenamed(kind: WireIdKind.designToken, affected: ref('t0001'))],
      );
    });

    test('detects a token deprecation', () {
      expect(
        diffCatalogs(
          tokenOf(designTokenEntry(wireId: 't0001')),
          tokenOf(
            designTokenEntry(wireId: 't0001', deprecated: catalogDeprecation()),
          ),
        ),
        [EntryDeprecated(kind: WireIdKind.designToken, affected: ref('t0001'))],
      );
    });

    test('detects a token-type change', () {
      expect(
        diffCatalogs(
          tokenOf(
            designTokenEntry(wireId: 't0001', type: DesignTokenType.length),
          ),
          tokenOf(
            designTokenEntry(
              wireId: 't0001',
              type: DesignTokenType.duration,
            ),
          ),
        ),
        [
          TokenTypeChanged(
            affected: ref('t0001'),
            from: DesignTokenType.length,
            to: DesignTokenType.duration,
          ),
        ],
      );
    });

    test('detects a resolver-path change', () {
      expect(
        diffCatalogs(
          tokenOf(designTokenEntry(wireId: 't0001')),
          tokenOf(
            designTokenEntry(
              wireId: 't0001',
              resolver: const ThemeBindingPath.path('colorScheme.primary'),
            ),
          ),
        ),
        [TokenResolverChanged(affected: ref('t0001'))],
      );
    });

    test('detects a literal-fallback change', () {
      expect(
        diffCatalogs(
          tokenOf(designTokenEntry(wireId: 't0001', literalFallback: 1)),
          tokenOf(designTokenEntry(wireId: 't0001', literalFallback: 2)),
        ),
        [TokenFallbackChanged(affected: ref('t0001'))],
      );
    });
  });
}
