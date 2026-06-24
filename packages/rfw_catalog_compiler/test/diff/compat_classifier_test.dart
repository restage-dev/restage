import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// One test per classification rule. `classifyCatalogChange` switches
/// exhaustively over the sealed `CatalogChange` hierarchy, so these tests
/// plus the compiler's exhaustiveness check together cover every rule.
void main() {
  group('classifyCatalogChange', () {
    test('add entry → additive', () {
      expect(
        classifyCatalogChange(
          EntryAdded(kind: WireIdKind.widget, affected: ref('w0001')),
        ),
        CompatClassification.additive,
      );
    });

    test('remove entry → breaking', () {
      expect(
        classifyCatalogChange(
          EntryRemoved(kind: WireIdKind.widget, affected: ref('w0001')),
        ),
        CompatClassification.breaking,
      );
    });

    test('rename → free', () {
      expect(
        classifyCatalogChange(
          EntryRenamed(kind: WireIdKind.widget, affected: ref('w0001')),
        ),
        CompatClassification.free,
      );
    });

    test('deprecate → additive', () {
      expect(
        classifyCatalogChange(
          EntryDeprecated(kind: WireIdKind.widget, affected: ref('w0001')),
        ),
        CompatClassification.additive,
      );
    });

    test('replace with successor → forwarding', () {
      expect(
        classifyCatalogChange(
          EntryReplaced(
            kind: WireIdKind.widget,
            affected: ref('w0001'),
            successor: ref('w0002'),
          ),
        ),
        CompatClassification.forwarding,
      );
    });

    test('children-slot change → breaking', () {
      expect(
        classifyCatalogChange(
          WidgetChildrenSlotChanged(
            affected: ref('w0001'),
            from: ChildrenSlot.none,
            to: ChildrenSlot.single,
          ),
        ),
        CompatClassification.breaking,
      );
    });

    test('property type change → breaking', () {
      expect(
        classifyCatalogChange(
          PropertyTypeChanged(
            affected: ref('p0001'),
            from: PropertyType.color,
            to: PropertyType.string,
          ),
        ),
        CompatClassification.breaking,
      );
    });

    test('required false→true (tightened) → breaking', () {
      expect(
        classifyCatalogChange(
          RequiredFlagChanged(
            affected: ref('p0001'),
            direction: RequiredFlagDirection.tightened,
          ),
        ),
        CompatClassification.breaking,
      );
    });

    test('required true→false (loosened) → additive', () {
      expect(
        classifyCatalogChange(
          RequiredFlagChanged(
            affected: ref('p0001'),
            direction: RequiredFlagDirection.loosened,
          ),
        ),
        CompatClassification.additive,
      );
    });

    test('DefaultValueSource change → additive', () {
      expect(
        classifyCatalogChange(PropertyDefaultChanged(affected: ref('p0001'))),
        CompatClassification.additive,
      );
    });

    test('category/priority change → additive', () {
      expect(
        classifyCatalogChange(PropertyMetadataChanged(affected: ref('p0001'))),
        CompatClassification.additive,
      );
    });

    test('synthetic strategy change → breaking', () {
      expect(
        classifyCatalogChange(SyntheticStrategyChanged(affected: ref('p0001'))),
        CompatClassification.breaking,
      );
    });

    test('variant argument change → breaking', () {
      expect(
        classifyCatalogChange(VariantArgumentsChanged(affected: ref('v0001'))),
        CompatClassification.breaking,
      );
    });

    test('add union member → additive', () {
      expect(
        classifyCatalogChange(
          UnionMemberAdded(affected: ref('u0001'), member: ref('s0002')),
        ),
        CompatClassification.additive,
      );
    });

    test('remove union member → breaking', () {
      expect(
        classifyCatalogChange(
          UnionMemberRemoved(affected: ref('u0001'), member: ref('s0002')),
        ),
        CompatClassification.breaking,
      );
    });

    test('discriminator-field change → breaking', () {
      expect(
        classifyCatalogChange(
          UnionDiscriminatorChanged(affected: ref('u0001')),
        ),
        CompatClassification.breaking,
      );
    });

    test('resolver path change → additive', () {
      expect(
        classifyCatalogChange(TokenResolverChanged(affected: ref('t0001'))),
        CompatClassification.additive,
      );
    });

    test('literal fallback change → additive', () {
      expect(
        classifyCatalogChange(TokenFallbackChanged(affected: ref('t0001'))),
        CompatClassification.additive,
      );
    });

    test('token type change → breaking', () {
      expect(
        classifyCatalogChange(
          TokenTypeChanged(
            affected: ref('t0001'),
            from: DesignTokenType.color,
            to: DesignTokenType.length,
          ),
        ),
        CompatClassification.breaking,
      );
    });
  });
}
