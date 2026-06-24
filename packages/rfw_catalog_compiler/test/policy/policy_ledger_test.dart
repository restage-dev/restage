// packages/rfw_catalog_compiler/test/policy/policy_ledger_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

void main() {
  group('PolicyLedger', () {
    test(
        'builtIn returns an immutable instance with all sub-policies '
        'populated', () {
      const ledger = PolicyLedger.builtIn();
      expect(ledger.denylist, isNotNull);
      expect(ledger.mutexRules, isNotNull);
      expect(ledger.stabilityRules, isNotNull);
      expect(ledger.unionRegistry, isNotNull);
      expect(ledger.themeBindingSeeds, isNotNull);
      expect(ledger.designTokenHeuristics, isNotNull);
      expect(ledger.categoryHeuristics, isNotNull);
      expect(ledger.priorityHeuristics, isNotNull);
    });

    test('PolicyLedger supports value equality', () {
      const a = PolicyLedger.builtIn();
      const b = PolicyLedger.builtIn();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test(
        'extend produces a new ledger that overrides only the named '
        'policies and preserves identity of the others', () {
      const base = PolicyLedger.builtIn();
      final extra = base.extend(
        denylist: base.denylist.extend(
          types: const {'CustomerHostType'},
        ),
      );
      expect(extra.denylist.types, contains('CustomerHostType'));
      expect(
        extra.denylist.types,
        contains('TextEditingController'),
        reason: 'base denylist types must be preserved',
      );
      expect(identical(extra.mutexRules, base.mutexRules), isTrue);
    });

    test('builtIn ledger exposes the default structured-walk policy', () {
      const ledger = PolicyLedger.builtIn();
      expect(
        ledger.structuredWalk.concreteTypes,
        contains(
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
        ),
      );
      expect(
        ledger.structuredWalk.abstractTypes,
        contains('package:flutter/src/painting/gradient.dart#Gradient'),
      );
      expect(ledger.structuredWalk.maxDepth, equals(8));
    });

    test('extend overrides structuredWalk and preserves other sub-policies',
        () {
      const base = PolicyLedger.builtIn();
      const replacement = StructuredWalkPolicy(
        concreteTypes: {'pkg:other.dart#OtherType'},
        abstractTypes: {},
        maxDepth: 3,
      );
      final extra = base.extend(structuredWalk: replacement);

      expect(extra.structuredWalk, equals(replacement));
      expect(
        extra.structuredWalk,
        isNot(equals(base.structuredWalk)),
      );
      expect(identical(extra.denylist, base.denylist), isTrue);
      expect(identical(extra.mutexRules, base.mutexRules), isTrue);
      expect(identical(extra.unionRegistry, base.unionRegistry), isTrue);
      expect(extra, isNot(equals(base)));
    });

    test('extend without structuredWalk preserves the built-in walk policy',
        () {
      const base = PolicyLedger.builtIn();
      final extra = base.extend();
      expect(extra.structuredWalk, equals(base.structuredWalk));
      expect(extra, equals(base));
    });
  });
}
