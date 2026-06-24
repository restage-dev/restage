import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

import 'fakes/fake_dart_types.dart' as fakes;

void main() {
  group('DenylistFilter.match (pure predicate)', () {
    const ledger = PolicyLedger.builtIn();

    test('exact-match type fires denylist.types', () {
      final type = fakes.fakeInterfaceType('TextEditingController');
      final match = DenylistFilter.match(type, ledger);
      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, equals('type denylisted: TextEditingController'));
      expect(match.target, equals('TextEditingController'));
    });

    test('suffix-match type fires denylist.typeSuffixes', () {
      final type = fakes.fakeInterfaceType('AcmeButtonController');
      final match = DenylistFilter.match(type, ledger);
      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.typeSuffixes'));
      expect(
        match.reason,
        equals('type name matches denylisted suffix: '
            "'Controller' on AcmeButtonController"),
      );
    });

    test('non-denylisted type returns null', () {
      final type = fakes.fakeInterfaceType('String');
      expect(DenylistFilter.match(type, ledger), isNull);
    });

    test('nullable types are stripped before matching', () {
      final nullable =
          fakes.fakeInterfaceType('TextEditingController', isNullable: true);
      final match = DenylistFilter.match(nullable, ledger);
      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
    });

    test('generic interface base matches by element name', () {
      final type = fakes.fakeInterfaceType(
        'Future',
        libraryIdentifier: 'dart:async',
        typeArguments: [fakes.fakeVoidType()],
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.target, equals('Future'));
    });

    test('exact type entries can be library-qualified', () {
      final customLedger = ledger.extend(
        denylist: ledger.denylist.extend(
          types: {'package:acme/secret.dart#SecretSurface'},
        ),
      );
      final type = fakes.fakeInterfaceType(
        'SecretSurface',
        libraryIdentifier: 'package:acme/secret.dart',
      );

      final match = DenylistFilter.match(type, customLedger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.target, equals('package:acme/secret.dart#SecretSurface'));
    });

    test('generic interface type arguments are walked', () {
      final type = fakes.fakeInterfaceType(
        'List',
        libraryIdentifier: 'dart:core',
        typeArguments: [
          fakes.fakeInterfaceType(
            'Future',
            libraryIdentifier: 'dart:async',
            typeArguments: [fakes.fakeVoidType()],
          ),
        ],
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('type argument 1 of List'));
      expect(match.target, equals('Future'));
    });

    test('function return type is walked', () {
      final type = fakes.fakeFunctionType(
        returnType: fakes.fakeInterfaceType(
          'Future',
          libraryIdentifier: 'dart:async',
          typeArguments: [fakes.fakeVoidType()],
        ),
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('function return type'));
      expect(match.target, equals('Future'));
    });

    test('function parameter types are walked', () {
      final type = fakes.fakeFunctionType(
        returnType: fakes.fakeVoidType(),
        parameterTypes: [
          fakes.fakeInterfaceType(
            'Future',
            libraryIdentifier: 'dart:async',
            typeArguments: [fakes.fakeVoidType()],
          ),
          fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
        ],
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('function parameter p0'));
      expect(match.target, equals('Future'));
    });

    test('record fields are walked', () {
      final type = fakes.fakeRecordType(
        positional: [
          fakes.fakeInterfaceType(
            'Future',
            libraryIdentifier: 'dart:async',
            typeArguments: [fakes.fakeVoidType()],
          ),
          fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
        ],
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('record positional field 1'));
      expect(match.target, equals('Future'));
    });

    test('type aliases are unwrapped before matching', () {
      final type = fakes.fakeInterfaceType(
        'AsyncResult',
        aliasTarget: fakes.fakeInterfaceType(
          'Future',
          libraryIdentifier: 'dart:async',
          typeArguments: [fakes.fakeVoidType()],
        ),
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('type alias AsyncResult'));
      expect(match.target, equals('Future'));
    });

    test('type parameter bounds are walked', () {
      final type = fakes.fakeTypeParameterType(
        'T',
        fakes.fakeInterfaceType(
          'Future',
          libraryIdentifier: 'dart:async',
          typeArguments: [fakes.fakeVoidType()],
        ),
      );

      final match = DenylistFilter.match(type, ledger);

      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.types'));
      expect(match.reason, contains('type parameter T bound'));
      expect(match.target, equals('Future'));
    });

    test('dynamic, void, and Never are allowed', () {
      expect(DenylistFilter.match(fakes.fakeDynamicType(), ledger), isNull);
      expect(DenylistFilter.match(fakes.fakeVoidType(), ledger), isNull);
      expect(DenylistFilter.match(fakes.fakeNeverType(), ledger), isNull);
    });
  });

  group('DenylistFilter.matchWidget', () {
    const ledger = PolicyLedger.builtIn();

    test('widget FQN match fires denylist.widgets', () {
      const fqn = 'package:flutter/src/widgets/navigator.dart#Navigator';
      final match = DenylistFilter.matchWidget(fqn, ledger);
      expect(match, isNotNull);
      expect(match!.policy, equals('denylist.widgets'));
      expect(match.target, equals(fqn));
    });

    test('non-denylisted widget returns null', () {
      final match = DenylistFilter.matchWidget(
        'package:restage_core/src/widgets/restage_text.dart#RestageText',
        ledger,
      );
      expect(match, isNull);
    });
  });
}
