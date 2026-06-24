// packages/rfw_catalog_compiler/test/policy/denylist_policy_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

void main() {
  group('DenylistPolicy', () {
    test('empty policy is value-equal across construction', () {
      const a = DenylistPolicy(
        types: {},
        typeSuffixes: {},
        widgets: {},
        properties: {},
      );
      const b = DenylistPolicy(
        types: {},
        typeSuffixes: {},
        widgets: {},
        properties: {},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('extend unions types, suffixes, widgets, and properties', () {
      const base = DenylistPolicy(
        types: {'TextEditingController'},
        typeSuffixes: {'Controller'},
        widgets: {'package:flutter/src/widgets/navigator.dart#Navigator'},
        properties: {
          'Container': {'foregroundDecoration'},
        },
      );
      final extended = base.extend(
        types: const {'FocusNode'},
        typeSuffixes: const {'Node'},
        widgets: const {'package:flutter/src/widgets/heroes.dart#Hero'},
        properties: const {
          'Container': {'transformAlignment'},
          'Row': {'textDirection'},
        },
      );
      expect(extended.types, equals({'TextEditingController', 'FocusNode'}));
      expect(extended.typeSuffixes, equals({'Controller', 'Node'}));
      expect(extended.widgets.length, equals(2));
      expect(
        extended.properties['Container'],
        equals({'foregroundDecoration', 'transformAlignment'}),
      );
      expect(extended.properties['Row'], equals({'textDirection'}));
    });

    test('DenylistMatch carries policy + reason + optional target', () {
      const match = DenylistMatch(
        policy: 'denylist.types',
        reason: 'type denylisted: TextEditingController',
        target: 'TextEditingController',
      );
      expect(match.policy, equals('denylist.types'));
      expect(match.target, equals('TextEditingController'));
      const sameTarget = DenylistMatch(
        policy: 'denylist.types',
        reason: 'type denylisted: TextEditingController',
        target: 'TextEditingController',
      );
      expect(match, equals(sameTarget));
    });
  });
}
