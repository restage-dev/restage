// packages/rfw_catalog_compiler/test/walker/structured_type_predicate_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  const ledger = PolicyLedger.builtIn();

  group('classifyStructured', () {
    test('whitelisted concrete type → StructuredKind.concrete', () {
      final type = fakes.fakeInterfaceType(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.concrete),
      );
    });

    test('listed abstract base → StructuredKind.abstractBase', () {
      final type = fakes.fakeInterfaceType(
        'Gradient',
        libraryIdentifier: 'package:flutter/src/painting/gradient.dart',
      );
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.abstractBase),
      );
    });

    test('scalar type (String) → StructuredKind.notStructured', () {
      final type = fakes.fakeInterfaceType(
        'String',
        libraryIdentifier: 'dart:core',
      );
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.notStructured),
      );
    });

    test('List<BoxShadow> → StructuredKind.notStructured', () {
      // Lists are handled elsewhere by the walker; the predicate only
      // classifies the outer interface type and List itself is not on
      // any structured list.
      final inner = fakes.fakeInterfaceType(
        'BoxShadow',
        libraryIdentifier: 'package:flutter/src/painting/box_shadow.dart',
      );
      final listType = fakes.fakeInterfaceType(
        'List',
        libraryIdentifier: 'dart:core',
        typeArguments: [inner],
      );
      expect(
        classifyStructured(listType, ledger),
        equals(StructuredKind.notStructured),
      );
    });

    test('FunctionType → StructuredKind.notStructured', () {
      // Only InterfaceType is eligible for structured classification.
      final fn = fakes.fakeFunctionType(returnType: fakes.fakeVoidType());
      expect(
        classifyStructured(fn, ledger),
        equals(StructuredKind.notStructured),
      );
    });

    test('type alias unwraps to its underlying structured type', () {
      // The alias's target is the concrete whitelisted BoxDecoration.
      // The predicate should look through the alias and classify it
      // as concrete.
      final underlying = fakes.fakeInterfaceType(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );
      final aliasType = fakes.fakeInterfaceType(
        'MyDecoration',
        libraryIdentifier: 'package:host/types.dart',
        aliasTarget: underlying,
      );
      expect(
        classifyStructured(aliasType, ledger),
        equals(StructuredKind.concrete),
      );
    });

    test('nullable variant of a whitelisted concrete type is still concrete',
        () {
      final type = fakes.fakeInterfaceType(
        'BoxDecoration',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
        isNullable: true,
      );
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.concrete),
      );
    });

    test('non-structured interface from a structured library → notStructured',
        () {
      // Same library URI as a whitelisted type but a different class
      // name must not match — the FQN includes the class name.
      final type = fakes.fakeInterfaceType(
        'NotInTheWhitelist',
        libraryIdentifier: 'package:flutter/src/painting/box_decoration.dart',
      );
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.notStructured),
      );
    });

    test('custom ledger override surfaces a new concrete type', () {
      final custom = ledger.extend(
        structuredWalk: const StructuredWalkPolicy(
          concreteTypes: {'package:host/types.dart#MyStruct'},
          abstractTypes: {},
        ),
      );
      final type = fakes.fakeInterfaceType(
        'MyStruct',
        libraryIdentifier: 'package:host/types.dart',
      );
      expect(
        classifyStructured(type, custom),
        equals(StructuredKind.concrete),
      );
      // The built-in ledger should not classify it.
      expect(
        classifyStructured(type, ledger),
        equals(StructuredKind.notStructured),
      );
    });
  });
}
