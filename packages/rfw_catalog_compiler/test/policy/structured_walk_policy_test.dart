// packages/rfw_catalog_compiler/test/policy/structured_walk_policy_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

void main() {
  group('StructuredWalkPolicy', () {
    test('stores concreteTypes, abstractTypes, and maxDepth as supplied', () {
      const policy = StructuredWalkPolicy(
        concreteTypes: {'pkg:lib.dart#A', 'pkg:lib.dart#B'},
        abstractTypes: {'pkg:lib.dart#Base'},
        maxDepth: 6,
      );
      expect(
        policy.concreteTypes,
        equals({'pkg:lib.dart#A', 'pkg:lib.dart#B'}),
      );
      expect(policy.abstractTypes, equals({'pkg:lib.dart#Base'}));
      expect(policy.maxDepth, equals(6));
    });

    test('maxDepth defaults to 8 when omitted', () {
      const policy = StructuredWalkPolicy(
        concreteTypes: {},
        abstractTypes: {},
      );
      expect(policy.maxDepth, equals(8));
    });

    test('supports value-based equality for identical sets and depth', () {
      const a = StructuredWalkPolicy(
        concreteTypes: {'pkg:lib.dart#A', 'pkg:lib.dart#B'},
        abstractTypes: {'pkg:lib.dart#Base'},
        maxDepth: 4,
      );
      const b = StructuredWalkPolicy(
        // Order intentionally swapped to assert set semantics.
        concreteTypes: {'pkg:lib.dart#B', 'pkg:lib.dart#A'},
        abstractTypes: {'pkg:lib.dart#Base'},
        maxDepth: 4,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('identical-instance shortcut returns true', () {
      const policy = StructuredWalkPolicy(
        concreteTypes: {'pkg:lib.dart#A'},
        abstractTypes: {},
      );
      expect(identical(policy, policy), isTrue);
      expect(policy, equals(policy));
    });

    test('inequality on differing concreteTypes', () {
      const a = StructuredWalkPolicy(
        concreteTypes: {'pkg:lib.dart#A'},
        abstractTypes: {},
      );
      const b = StructuredWalkPolicy(
        concreteTypes: {'pkg:lib.dart#B'},
        abstractTypes: {},
      );
      expect(a, isNot(equals(b)));
    });

    test('inequality on differing abstractTypes', () {
      const a = StructuredWalkPolicy(
        concreteTypes: {},
        abstractTypes: {'pkg:lib.dart#Base'},
      );
      const b = StructuredWalkPolicy(
        concreteTypes: {},
        abstractTypes: {'pkg:lib.dart#Other'},
      );
      expect(a, isNot(equals(b)));
    });

    test('inequality on differing maxDepth', () {
      const a = StructuredWalkPolicy(
        concreteTypes: {},
        abstractTypes: {},
      );
      const b = StructuredWalkPolicy(
        concreteTypes: {},
        abstractTypes: {},
        maxDepth: 12,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
