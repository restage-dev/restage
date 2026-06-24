// Phase 11 proof slice — diffs constructed canonical Catalog pairs end to
// end through computeCatalogDiff and asserts both the classification and
// the emitted CompatRule for every constructible compatibility-taxonomy
// row, across all six wire-ID kinds plus a customer namespace.
//
// Not exercised, by design: "type widening" (a property/field whose Dart
// type widens, e.g. EdgeInsets → EdgeInsetsGeometry). Widening is
// sub-PropertyType — both sides map to the same flat PropertyType enum
// value — so it produces no observable PropertyTypeChanged and is
// correctly additive-and-invisible. Every observable PropertyType change
// is a narrowing-equivalent and classifies breaking.
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Asserts a one-change diff: the single change has [classification], and
/// either emits one CompatRule of kind [rule] or — when [rule] is null —
/// emits none.
void expectSingleChange(
  CatalogDiffReport report, {
  required CompatClassification classification,
  CompatKind? rule,
}) {
  expect(report.changes, hasLength(1));
  expect(report.changes.single.classification, classification);
  if (rule == null) {
    expect(report.compatRules, isEmpty);
  } else {
    expect(report.compatRules, hasLength(1));
    expect(report.compatRules.single.kind, rule);
  }
}

void main() {
  group('proof slice — widgets', () {
    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(),
          catalog(widgets: [widgetEntry(wireId: 'w0001')]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(widgets: [widgetEntry(wireId: 'w0001')]),
          catalog(),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(widgets: [widgetEntry(wireId: 'w0001', name: 'A')]),
          catalog(widgets: [widgetEntry(wireId: 'w0001', name: 'B')]),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(widgets: [widgetEntry(wireId: 'w0001')]),
          catalog(
            widgets: [
              widgetEntry(wireId: 'w0001', deprecated: catalogDeprecation()),
            ],
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('replace → forwarding, removal rule with successor + transition', () {
      final report = computeCatalogDiff(
        catalog(widgets: [widgetEntry(wireId: 'w0001')]),
        catalog(
          widgets: [
            widgetEntry(
              wireId: 'w0001',
              deprecated: catalogDeprecation(
                replaceWith: ref('w0002'),
                transitionId: 'tx0001',
              ),
            ),
          ],
        ),
      );
      expect(
        report.changes.single.classification,
        CompatClassification.forwarding,
      );
      expect(report.compatRules, hasLength(1));
      final rule = report.compatRules.single;
      expect(rule.kind, CompatKind.removal);
      expect(rule.successorRef, ref('w0002'));
      expect(rule.transitionId, 'tx0001');
    });

    test('children-slot change → breaking, structuralShift', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(widgets: [widgetEntry(wireId: 'w0001')]),
          catalog(
            widgets: [
              widgetEntry(wireId: 'w0001', childrenSlot: ChildrenSlot.single),
            ],
          ),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.structuralShift,
      );
    });
  });

  group('proof slice — properties', () {
    Catalog widgetWith(List<PropertyEntry> properties) => catalog(
          widgets: [widgetEntry(wireId: 'w0001', properties: properties)],
        );

    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([]),
          widgetWith([propertyEntry(wireId: 'p0001')]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001', name: 'a')]),
          widgetWith([propertyEntry(wireId: 'p0001', name: 'b')]),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', deprecated: catalogDeprecation()),
          ]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('type change → breaking, typeChange', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([
            propertyEntry(wireId: 'p0001', type: PropertyType.color),
          ]),
          widgetWith([
            propertyEntry(wireId: 'p0001', type: PropertyType.integer),
          ]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.typeChange,
      );
    });

    test('required false→true → breaking, structuralShift', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([propertyEntry(wireId: 'p0001', required: true)]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.structuralShift,
      );
    });

    test('required true→false → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001', required: true)]),
          widgetWith([propertyEntry(wireId: 'p0001')]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('defaultSource change → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(
              wireId: 'p0001',
              defaultSource: const LiteralDefault('x'),
            ),
          ]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('category/priority change → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', category: PropertyCategory.style),
          ]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('synthetic strategy change → breaking, structuralShift', () {
      expectSingleChange(
        computeCatalogDiff(
          widgetWith([propertyEntry(wireId: 'p0001')]),
          widgetWith([
            propertyEntry(wireId: 'p0001', synthetic: 'iconData'),
          ]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.structuralShift,
      );
    });
  });

  group('proof slice — structured types', () {
    Catalog structuredOf(StructuredEntry entry) =>
        catalog(structuredTypes: [entry]);

    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(),
          structuredOf(structuredEntry(wireId: 's0001')),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(
          structuredOf(structuredEntry(wireId: 's0001')),
          catalog(),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          structuredOf(structuredEntry(wireId: 's0001', name: 'A')),
          structuredOf(structuredEntry(wireId: 's0001', name: 'B')),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          structuredOf(structuredEntry(wireId: 's0001')),
          structuredOf(
            structuredEntry(wireId: 's0001', deprecated: catalogDeprecation()),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('add field → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          structuredOf(structuredEntry(wireId: 's0001')),
          structuredOf(
            structuredEntry(
              wireId: 's0001',
              fields: [structuredField(wireId: 'p0010')],
            ),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove field → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(
          structuredOf(
            structuredEntry(
              wireId: 's0001',
              fields: [structuredField(wireId: 'p0010')],
            ),
          ),
          structuredOf(structuredEntry(wireId: 's0001')),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('field type change → breaking, typeChange', () {
      Catalog fieldTyped(PropertyType type) => structuredOf(
            structuredEntry(
              wireId: 's0001',
              fields: [structuredField(wireId: 'p0010', type: type)],
            ),
          );
      expectSingleChange(
        computeCatalogDiff(
          fieldTyped(PropertyType.color),
          fieldTyped(PropertyType.integer),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.typeChange,
      );
    });
  });

  group('proof slice — factory variants', () {
    Catalog variantsOf(List<FactoryVariant> variants) => catalog(
          structuredTypes: [
            structuredEntry(wireId: 's0001', variants: variants),
          ],
        );

    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          variantsOf([]),
          variantsOf([factoryVariant(wireId: 'v0001')]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, factoryVariantChange', () {
      expectSingleChange(
        computeCatalogDiff(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.factoryVariantChange,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          variantsOf([
            factoryVariant(wireId: 'v0001', namedConstructor: 'circular'),
          ]),
          variantsOf([
            factoryVariant(wireId: 'v0001', namedConstructor: 'rounded'),
          ]),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([
            factoryVariant(wireId: 'v0001', deprecated: catalogDeprecation()),
          ]),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('argument-shape change → breaking, factoryVariantChange', () {
      expectSingleChange(
        computeCatalogDiff(
          variantsOf([factoryVariant(wireId: 'v0001')]),
          variantsOf([
            factoryVariant(
              wireId: 'v0001',
              sourceKind: VariantSourceKind.staticGetter,
              staticAccessor: 'zero',
            ),
          ]),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.factoryVariantChange,
      );
    });

    test('argument-type change → breaking, factoryVariantChange', () {
      expectSingleChange(
        computeCatalogDiff(
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
        classification: CompatClassification.breaking,
        rule: CompatKind.factoryVariantChange,
      );
    });
  });

  group('proof slice — unions', () {
    Catalog unionOf(UnionEntry entry) => catalog(unions: [entry]);

    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(catalog(), unionOf(unionEntry(wireId: 'u0001'))),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(unionOf(unionEntry(wireId: 'u0001')), catalog()),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          unionOf(unionEntry(wireId: 'u0001', name: 'A')),
          unionOf(unionEntry(wireId: 'u0001', name: 'B')),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          unionOf(unionEntry(wireId: 'u0001')),
          unionOf(
            unionEntry(wireId: 'u0001', deprecated: catalogDeprecation()),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('member added → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          unionOf(unionEntry(wireId: 'u0001', members: [ref('s0001')])),
          unionOf(
            unionEntry(wireId: 'u0001', members: [ref('s0001'), ref('s0002')]),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('member removed → breaking, unionMembershipChange', () {
      expectSingleChange(
        computeCatalogDiff(
          unionOf(
            unionEntry(wireId: 'u0001', members: [ref('s0001'), ref('s0002')]),
          ),
          unionOf(unionEntry(wireId: 'u0001', members: [ref('s0001')])),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.unionMembershipChange,
      );
    });

    test('discriminator-field change → breaking, structuralShift', () {
      expectSingleChange(
        computeCatalogDiff(
          unionOf(unionEntry(wireId: 'u0001')),
          unionOf(
            unionEntry(
              wireId: 'u0001',
              discriminator: const DiscriminatorSpec(field: '_t', values: []),
            ),
          ),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.structuralShift,
      );
    });
  });

  group('proof slice — design tokens', () {
    Catalog tokenOf(DesignTokenEntry entry) => catalog(designTokens: [entry]);

    test('add → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          catalog(),
          tokenOf(designTokenEntry(wireId: 't0001')),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('remove → breaking, removal', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(designTokenEntry(wireId: 't0001')),
          catalog(),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.removal,
      );
    });

    test('rename → free', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(designTokenEntry(wireId: 't0001', name: 'a')),
          tokenOf(designTokenEntry(wireId: 't0001', name: 'b')),
        ),
        classification: CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(designTokenEntry(wireId: 't0001')),
          tokenOf(
            designTokenEntry(wireId: 't0001', deprecated: catalogDeprecation()),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('resolver-path change → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(designTokenEntry(wireId: 't0001')),
          tokenOf(
            designTokenEntry(
              wireId: 't0001',
              resolver: const ThemeBindingPath.path('colorScheme.primary'),
            ),
          ),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('literal-fallback change → additive', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(designTokenEntry(wireId: 't0001', literalFallback: 1)),
          tokenOf(designTokenEntry(wireId: 't0001', literalFallback: 2)),
        ),
        classification: CompatClassification.additive,
      );
    });

    test('token-type change → breaking, typeChange', () {
      expectSingleChange(
        computeCatalogDiff(
          tokenOf(
            designTokenEntry(wireId: 't0001', type: DesignTokenType.length),
          ),
          tokenOf(
            designTokenEntry(wireId: 't0001', type: DesignTokenType.duration),
          ),
        ),
        classification: CompatClassification.breaking,
        rule: CompatKind.typeChange,
      );
    });
  });

  group('proof slice — library-agnostic', () {
    test('a customer-namespace widget diffs identically to a built-in one', () {
      const acme = WidgetLibrary.custom('acme.design_system');
      final report = computeCatalogDiff(
        catalog(widgets: [widgetEntry(wireId: 'w0001', library: acme)]),
        catalog(),
      );
      expect(report.changes, hasLength(1));
      final change = report.changes.single.change;
      expect(change, isA<EntryRemoved>());
      expect(change.affected.library, 'acme.design_system');
      expect(
        report.changes.single.classification,
        CompatClassification.breaking,
      );
      expect(report.compatRules.single.kind, CompatKind.removal);
      expect(
        report.compatRules.single.affectedRef.library,
        'acme.design_system',
      );
    });
  });

  group('proof slice — mixed report', () {
    test('several simultaneous changes classify and rule independently', () {
      final before = catalog(
        widgets: [
          widgetEntry(wireId: 'w0001', name: 'Old'),
          widgetEntry(wireId: 'w0002'),
        ],
      );
      final after = catalog(
        widgets: [
          widgetEntry(wireId: 'w0001', name: 'New'),
          widgetEntry(wireId: 'w0003'),
        ],
      );
      final report = computeCatalogDiff(before, after);
      // Deterministic order by wireId: w0001 renamed, w0002 removed,
      // w0003 added.
      expect(
        report.changes.map((c) => c.classification).toList(),
        [
          CompatClassification.free,
          CompatClassification.breaking,
          CompatClassification.additive,
        ],
      );
      expect(report.compatRules, hasLength(1));
      expect(report.compatRules.single.affectedRef, ref('w0002'));
      expect(report.compatRules.single.kind, CompatKind.removal);
    });
  });
}
