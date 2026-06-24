import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('emitCompatRules', () {
    CompatRule onlyRuleFor(CatalogChange change) {
      final rules = emitCompatRules(
        [change],
        fromVersion: 'v1',
        toVersion: 'v2',
      );
      expect(rules, hasLength(1));
      return rules.single;
    }

    test('a removed widget emits a removal rule with no successor', () {
      final rule = onlyRuleFor(
        EntryRemoved(kind: WireIdKind.widget, affected: ref('w0017')),
      );
      expect(rule.kind, CompatKind.removal);
      expect(rule.affectedRef, ref('w0017'));
      expect(rule.successorRef, isNull);
      expect(rule.transitionId, isNull);
      expect(rule.fromVersion, 'v1');
      expect(rule.toVersion, 'v2');
      expect(rule.note, isNotEmpty);
    });

    test('a removed variant emits a factoryVariantChange rule', () {
      final rule = onlyRuleFor(
        EntryRemoved(kind: WireIdKind.variant, affected: ref('v0001')),
      );
      expect(rule.kind, CompatKind.factoryVariantChange);
    });

    test('a replacement emits a removal rule with successor + transition', () {
      final rule = onlyRuleFor(
        EntryReplaced(
          kind: WireIdKind.widget,
          affected: ref('w0017'),
          successor: ref('w0099'),
          transitionId: 'tx0001',
        ),
      );
      expect(rule.kind, CompatKind.removal);
      expect(rule.affectedRef, ref('w0017'));
      expect(rule.successorRef, ref('w0099'));
      expect(rule.transitionId, 'tx0001');
      expect(rule.note, isNotEmpty);
    });

    test('a property type change emits a typeChange rule', () {
      final rule = onlyRuleFor(
        PropertyTypeChanged(
          affected: ref('p0001'),
          from: PropertyType.color,
          to: PropertyType.string,
        ),
      );
      expect(rule.kind, CompatKind.typeChange);
    });

    test('a token type change emits a typeChange rule', () {
      final rule = onlyRuleFor(
        TokenTypeChanged(
          affected: ref('t0001'),
          from: DesignTokenType.color,
          to: DesignTokenType.length,
        ),
      );
      expect(rule.kind, CompatKind.typeChange);
    });

    test('a required-flag tightening emits a structuralShift rule', () {
      final rule = onlyRuleFor(
        RequiredFlagChanged(
          affected: ref('p0001'),
          direction: RequiredFlagDirection.tightened,
        ),
      );
      expect(rule.kind, CompatKind.structuralShift);
    });

    test('a synthetic-strategy change emits a structuralShift rule', () {
      final rule =
          onlyRuleFor(SyntheticStrategyChanged(affected: ref('p0001')));
      expect(rule.kind, CompatKind.structuralShift);
    });

    test('a children-slot change emits a structuralShift rule', () {
      final rule = onlyRuleFor(
        WidgetChildrenSlotChanged(
          affected: ref('w0001'),
          from: ChildrenSlot.none,
          to: ChildrenSlot.single,
        ),
      );
      expect(rule.kind, CompatKind.structuralShift);
    });

    test('a discriminator change emits a structuralShift rule', () {
      final rule =
          onlyRuleFor(UnionDiscriminatorChanged(affected: ref('u0001')));
      expect(rule.kind, CompatKind.structuralShift);
    });

    test('a removed union member emits a unionMembershipChange rule', () {
      final rule = onlyRuleFor(
        UnionMemberRemoved(affected: ref('u0001'), member: ref('s0002')),
      );
      expect(rule.kind, CompatKind.unionMembershipChange);
    });

    test('a variant argument change emits a factoryVariantChange rule', () {
      final rule = onlyRuleFor(VariantArgumentsChanged(affected: ref('v0001')));
      expect(rule.kind, CompatKind.factoryVariantChange);
    });

    test('free and additive changes emit no rule', () {
      final changes = <CatalogChange>[
        EntryAdded(kind: WireIdKind.widget, affected: ref('w0001')),
        EntryRenamed(kind: WireIdKind.widget, affected: ref('w0001')),
        EntryDeprecated(kind: WireIdKind.widget, affected: ref('w0001')),
        RequiredFlagChanged(
          affected: ref('p0001'),
          direction: RequiredFlagDirection.loosened,
        ),
        PropertyDefaultChanged(affected: ref('p0001')),
        PropertyMetadataChanged(affected: ref('p0001')),
        UnionMemberAdded(affected: ref('u0001'), member: ref('s0002')),
        TokenResolverChanged(affected: ref('t0001')),
        TokenFallbackChanged(affected: ref('t0001')),
      ];
      expect(
        emitCompatRules(changes, fromVersion: 'v1', toVersion: 'v2'),
        isEmpty,
      );
    });

    test('the two structuralShift cases carry distinct notes', () {
      final tightened = onlyRuleFor(
        RequiredFlagChanged(
          affected: ref('p0001'),
          direction: RequiredFlagDirection.tightened,
        ),
      );
      final synthetic = onlyRuleFor(
        SyntheticStrategyChanged(affected: ref('p0001')),
      );
      expect(tightened.kind, CompatKind.structuralShift);
      expect(synthetic.kind, CompatKind.structuralShift);
      expect(tightened.note, isNot(equals(synthetic.note)));
    });

    test('emits only the breaking and forwarding changes from a mixed list',
        () {
      final changes = <CatalogChange>[
        EntryAdded(kind: WireIdKind.widget, affected: ref('w0001')),
        EntryRemoved(kind: WireIdKind.widget, affected: ref('w0002')),
        EntryRenamed(kind: WireIdKind.widget, affected: ref('w0003')),
        EntryReplaced(
          kind: WireIdKind.widget,
          affected: ref('w0004'),
          successor: ref('w0005'),
        ),
      ];
      final rules = emitCompatRules(
        changes,
        fromVersion: 'v1',
        toVersion: 'v2',
      );
      expect(rules, hasLength(2));
      expect(rules.map((r) => r.affectedRef), [ref('w0002'), ref('w0004')]);
    });
  });
}
