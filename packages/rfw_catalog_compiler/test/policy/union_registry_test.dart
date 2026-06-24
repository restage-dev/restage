// packages/rfw_catalog_compiler/test/policy/union_registry_test.dart
import 'package:rfw_catalog_compiler/src/policy/default_content/default_union_seeds.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/policy/union_registry.dart';
import 'package:test/test.dart';

void main() {
  group('kBuiltInUnionSeeds', () {
    test('every member is a fully-qualified <library>#<Class> string', () {
      for (final entry in kBuiltInUnionSeeds.values) {
        for (final member in entry.members) {
          expect(
            member,
            matches(RegExp(r'^[a-z]+:[^#]+#[A-Z]\w+$')),
            reason: '${entry.abstractType} member "$member" must be an FQN',
          );
        }
      }
    });

    test('seeds the six built-in abstract bases', () {
      expect(kBuiltInUnionSeeds.keys, hasLength(6));
    });

    test('every entry has a non-empty description', () {
      for (final entry in kBuiltInUnionSeeds.values) {
        expect(
          entry.description,
          isNotEmpty,
          reason: '${entry.abstractType} must have a description',
        );
      }
    });
  });

  group('UnionRegistry.lookup', () {
    test('returns the entry for a registered abstract-type FQN', () {
      final registry = const PolicyLedger.builtIn().unionRegistry;
      final entry = registry.lookup(
        'package:flutter/src/painting/gradient.dart#Gradient',
      );
      expect(entry, isNotNull);
      expect(entry!.members, isNotEmpty);
    });

    test('returns null for an unregistered type', () {
      final registry = const PolicyLedger.builtIn().unionRegistry;
      expect(
        registry.lookup('package:flutter/src/widgets/basic.dart#Center'),
        isNull,
      );
    });
  });

  group('UnionRegistryEntry.of', () {
    test('throws ArgumentError when members list contains a duplicate', () {
      expect(
        () => UnionRegistryEntry.of(
          abstractType: 'package:example/example.dart#Base',
          members: const [
            'package:example/example.dart#ConcreteA',
            'package:example/example.dart#ConcreteA',
          ],
          discriminatorField: '_s',
          description: 'A union with a duplicate member.',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('unique'),
          ),
        ),
      );
    });
  });
}
