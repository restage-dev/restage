import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

void main() {
  test('admits Map<String, String>', () {
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapAdmitted>());
    final admitted = classification as MapAdmitted;
    expect(admitted.keyKind, MapKeyKind.string);
    expect(admitted.valueShape, isA<ScalarShape>());
  });

  test('admits Map<String, SomeEnum>', () {
    final enumElement = fakes.fakeEnumElement(
      'SomeEnum',
      libraryIdentifier: 'package:acme/widgets.dart',
    );
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceTypeForElement(enumElement),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapAdmitted>());
    expect(
      (classification as MapAdmitted).valueShape,
      isA<EnumShape>(),
    );
  });

  test('admits enum keys with their source-qualified type', () {
    final enumElement = fakes.fakeEnumElement(
      'SomeEnum',
      libraryIdentifier: 'package:acme/widgets.dart',
    );
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceTypeForElement(enumElement),
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapAdmitted>());
    final admitted = classification as MapAdmitted;
    expect(admitted.keyKind, MapKeyKind.enumValue);
    expect(
      admitted.keyEnumRef?.libraryUri,
      'package:acme/widgets.dart',
    );
    expect(admitted.keyEnumRef?.symbolName, 'SomeEnum');
  });

  test('admits a nested map with its nested classification', () {
    final nestedType = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
      ],
    );
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        nestedType,
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapAdmitted>());
    final nested = (classification as MapAdmitted).nestedValue;
    expect(nested, isNotNull);
    expect(nested!.valueShape, isA<ScalarShape>());
  });

  test('excludes a non-string, non-enum key and names its type', () {
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapExcluded>());
    expect((classification as MapExcluded).reason, contains('int'));
  });

  test('excludes a nullable key and names the key', () {
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType(
          'String',
          libraryIdentifier: 'dart:core',
          isNullable: true,
        ),
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapExcluded>());
    final reason = (classification as MapExcluded).reason;
    expect(reason, contains('key'));
    expect(reason, contains('String?'));
  });

  test('excludes nullable values with the absent-versus-null cause', () {
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType(
          'String',
          libraryIdentifier: 'dart:core',
          isNullable: true,
        ),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapExcluded>());
    final reason = (classification as MapExcluded).reason;
    expect(reason, contains('absent entry'));
    expect(reason, contains('authored null'));
  });

  test('excludes an unsupported value type and names it', () {
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType(
          'UnsupportedValue',
          libraryIdentifier: 'package:acme/widgets.dart',
        ),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<MapExcluded>());
    expect(
      (classification as MapExcluded).reason,
      contains('UnsupportedValue'),
    );
  });

  test('excludes direct and aliased nullable map slots', () {
    final mapType = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
      ],
    );
    final nullableTypes = [
      fakes.fakeInterfaceType(
        'Map',
        libraryIdentifier: 'dart:core',
        typeArguments: [
          fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
          fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        ],
        isNullable: true,
      ),
      fakes.fakeInterfaceType(
        'StringMap',
        aliasTarget: mapType,
        isNullable: true,
      ),
    ];

    for (final type in nullableTypes) {
      final classification = classifyMapType(
        type,
        structuredValuesAdmitted: true,
      );

      expect(classification, isA<MapExcluded>());
      expect(
        (classification as MapExcluded).reason,
        contains('nullable map slot'),
      );
    }
  });

  test('admits a recognized structured value at a widget boundary', () {
    final planElement = fakes.fakeClassElement(
      'Plan',
      libraryIdentifier: 'package:acme/widgets.dart',
      constructors: [
        fakes.fakeConstructorElement(
          null,
          returnType: fakes.fakeInterfaceTypeForElement(
            fakes.fakeClassElement(
              'Plan',
              libraryIdentifier: 'package:acme/widgets.dart',
            ),
          ),
          parameters: [
            fakes.fakeFormalParameterElement(
              'name',
              fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
            ),
          ],
        ),
      ],
    );
    final policy = const PolicyLedger.builtIn().extend(
      structuredWalk: const StructuredWalkPolicy(
        concreteTypes: {'package:acme/widgets.dart#Plan'},
        abstractTypes: <String>{},
      ),
    );
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceTypeForElement(planElement),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: true,
      library: WidgetLibrary.fromNamespace('test'),
      policy: policy,
    );

    expect(classification, isA<MapAdmitted>());
    expect(
      (classification as MapAdmitted).valueShape,
      isA<StructuredShape>(),
    );
  });

  test('defers a structured value at a data-class field boundary', () {
    final planElement = fakes.fakeClassElement(
      'Plan',
      libraryIdentifier: 'package:acme/widgets.dart',
      constructors: [
        fakes.fakeConstructorElement(
          null,
          returnType: fakes.fakeInterfaceTypeForElement(
            fakes.fakeClassElement(
              'Plan',
              libraryIdentifier: 'package:acme/widgets.dart',
            ),
          ),
          parameters: [
            fakes.fakeFormalParameterElement(
              'name',
              fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
            ),
          ],
        ),
      ],
    );
    final policy = const PolicyLedger.builtIn().extend(
      structuredWalk: const StructuredWalkPolicy(
        concreteTypes: {'package:acme/widgets.dart#Plan'},
        abstractTypes: <String>{},
      ),
    );
    final type = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceTypeForElement(planElement),
      ],
    );
    final unsupportedType = fakes.fakeInterfaceType(
      'Map',
      libraryIdentifier: 'dart:core',
      typeArguments: [
        fakes.fakeInterfaceType('String', libraryIdentifier: 'dart:core'),
        fakes.fakeInterfaceType(
          'UnsupportedValue',
          libraryIdentifier: 'package:acme/widgets.dart',
        ),
      ],
    );
    final classification = classifyMapType(
      type,
      structuredValuesAdmitted: false,
      library: WidgetLibrary.fromNamespace('test'),
      policy: policy,
    );
    final unsupportedClassification = classifyMapType(
      unsupportedType,
      structuredValuesAdmitted: false,
    );

    expect(classification, isA<MapExcluded>());
    expect(unsupportedClassification, isA<MapExcluded>());
    final reason = (classification as MapExcluded).reason;
    final unsupportedReason = (unsupportedClassification as MapExcluded).reason;
    expect(reason, contains('widget property'));
    expect(reason, isNot(equals(unsupportedReason)));
  });

  test('falls through for a non-map type', () {
    final classification = classifyMapType(
      fakes.fakeInterfaceType('int', libraryIdentifier: 'dart:core'),
      structuredValuesAdmitted: true,
    );

    expect(classification, isA<NotAMap>());
  });
}
