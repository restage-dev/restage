import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:rfw_catalog_schema/constraint_validation.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  final malformed = <_ConstraintCase>[
    const _ConstraintCase(
      'minimum plus exclusiveMinimum',
      RestageConstraints(minimum: 0, exclusiveMinimum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'maximum plus exclusiveMaximum',
      RestageConstraints(maximum: 1, exclusiveMaximum: 2),
      PropertyType.real,
      '',
    ),
    for (final value in [double.nan, double.infinity, double.negativeInfinity])
      for (final bound in _nonFiniteBounds(value)) bound,
    const _ConstraintCase(
      'inclusive lower above inclusive upper',
      RestageConstraints(minimum: 2, maximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'inclusive lower above exclusive upper',
      RestageConstraints(minimum: 2, exclusiveMaximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'exclusive lower above inclusive upper',
      RestageConstraints(exclusiveMinimum: 2, maximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'exclusive lower above exclusive upper',
      RestageConstraints(exclusiveMinimum: 2, exclusiveMaximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'equal inclusive lower and exclusive upper',
      RestageConstraints(minimum: 1, exclusiveMaximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'equal exclusive lower and inclusive upper',
      RestageConstraints(exclusiveMinimum: 1, maximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'equal exclusive lower and upper',
      RestageConstraints(exclusiveMinimum: 1, exclusiveMaximum: 1),
      PropertyType.real,
      '',
    ),
    const _ConstraintCase(
      'negative minLength',
      RestageConstraints(minLength: -1),
      PropertyType.string,
      '.minLength',
    ),
    const _ConstraintCase(
      'negative maxLength',
      RestageConstraints(maxLength: -1),
      PropertyType.string,
      '.maxLength',
    ),
    const _ConstraintCase(
      'inverted lengths',
      RestageConstraints(minLength: 2, maxLength: 1),
      PropertyType.string,
      '',
    ),
    const _ConstraintCase(
      'negative minItems',
      RestageConstraints(minItems: -1),
      PropertyType.stringList,
      '.minItems',
    ),
    const _ConstraintCase(
      'negative maxItems',
      RestageConstraints(maxItems: -1),
      PropertyType.stringList,
      '.maxItems',
    ),
    const _ConstraintCase(
      'inverted item counts',
      RestageConstraints(minItems: 2, maxItems: 1),
      PropertyType.stringList,
      '',
    ),
    const _ConstraintCase(
      'empty allowedValues',
      RestageConstraints(allowedValues: []),
      PropertyType.real,
      '.allowedValues',
    ),
    const _ConstraintCase(
      'list allowed value',
      RestageConstraints(allowedValues: [<Object?>[]]),
      PropertyType.real,
      '.allowedValues[0]',
    ),
    const _ConstraintCase(
      'map allowed value',
      RestageConstraints(allowedValues: [<String, Object?>{}]),
      PropertyType.real,
      '.allowedValues[0]',
    ),
    const _ConstraintCase(
      'object allowed value',
      RestageConstraints(allowedValues: [Object()]),
      PropertyType.real,
      '.allowedValues[0]',
    ),
    for (final value in [double.nan, double.infinity, double.negativeInfinity])
      _ConstraintCase(
        'non-finite allowed value $value',
        RestageConstraints(allowedValues: [value]),
        PropertyType.real,
        '.allowedValues[0]',
      ),
    const _ConstraintCase(
      'duplicate boolean',
      RestageConstraints(allowedValues: [false, false]),
      PropertyType.boolean,
      '.allowedValues[1]',
    ),
    const _ConstraintCase(
      'duplicate mixed number',
      RestageConstraints(allowedValues: [1, 1.0]),
      PropertyType.real,
      '.allowedValues[1]',
    ),
    const _ConstraintCase(
      'duplicate signed zero',
      RestageConstraints(allowedValues: [-0.0, 0]),
      PropertyType.real,
      '.allowedValues[1]',
    ),
    const _ConstraintCase(
      'duplicate string',
      RestageConstraints(allowedValues: ['same', 'same']),
      PropertyType.string,
      '.allowedValues[1]',
    ),
    const _ConstraintCase(
      'duplicate null',
      RestageConstraints(allowedValues: [null, null]),
      PropertyType.string,
      '.allowedValues[1]',
    ),
    for (final keyword in _knownConstraintKeywords)
      _ConstraintCase(
        'extension collision $keyword',
        RestageConstraints.withExtensions(
          extensions: {keyword: true},
        ),
        PropertyType.string,
        '.extensions["$keyword"]',
      ),
    _ConstraintCase(
      'extension with non-string map key',
      RestageConstraints.withExtensions(
        extensions: const {
          'x-data': {1: true},
        },
      ),
      PropertyType.string,
      '.extensions["x-data"]',
    ),
    _ConstraintCase(
      'extension with non-JSON object',
      RestageConstraints.withExtensions(
        extensions: const {'x-data': Object()},
      ),
      PropertyType.string,
      '.extensions["x-data"]',
    ),
    _ConstraintCase(
      'extension with nested non-JSON object',
      RestageConstraints.withExtensions(
        extensions: const {
          'x-data': [
            {'nested': Object()},
          ],
        },
      ),
      PropertyType.string,
      '.extensions["x-data"][0]["nested"]',
    ),
    _ConstraintCase(
      'extension with nested non-finite number',
      RestageConstraints.withExtensions(
        extensions: const {
          'x-data': {
            'nested': [double.infinity],
          },
        },
      ),
      PropertyType.string,
      '.extensions["x-data"]["nested"][0]',
    ),
  ];

  test('one exhaustive malformed-value matrix rejects through every target',
      () {
    for (final candidate in malformed) {
      final issue = validateRestageConstraintValues(candidate.constraints);
      expect(issue, isNotNull, reason: candidate.name);
      expect(issue!.pathSuffix, candidate.pathSuffix, reason: candidate.name);
      final property = _property(candidate.type, candidate.constraints);
      final catalog = _catalog(property);

      expect(
        () => encodeCatalog(catalog),
        throwsA(isA<CatalogSchemaException>()),
        reason: 'catalog codec: ${candidate.name}',
      );
      expect(
        () => classifyA2uiCatalogDart(catalog),
        throwsA(isA<UnsupportedError>()),
        reason: 'A2UI: ${candidate.name}',
      );
      expect(
        () => validateWidgetbookConstraintApplicability(
          property,
          candidate.constraints,
          path: 'ConstraintParity.value',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Widgetbook constraints at ConstraintParity.value'),
          ),
        ),
        reason: 'Widgetbook: ${candidate.name}',
      );
    }
  });

  test('valid shared value boundaries remain accepted by every target', () {
    const valid = <_ConstraintCase>[
      _ConstraintCase(
        'equal inclusive numeric bounds',
        RestageConstraints(minimum: 1, maximum: 1),
        PropertyType.real,
        '',
      ),
      _ConstraintCase(
        'ordered exclusive numeric bounds',
        RestageConstraints(exclusiveMinimum: 1, exclusiveMaximum: 2),
        PropertyType.real,
        '',
      ),
      _ConstraintCase(
        'zero string lengths',
        RestageConstraints(minLength: 0, maxLength: 0),
        PropertyType.string,
        '',
      ),
      _ConstraintCase(
        'zero item counts',
        RestageConstraints(minItems: 0, maxItems: 0),
        PropertyType.stringList,
        '',
      ),
      _ConstraintCase(
        'boolean allowed values',
        RestageConstraints(allowedValues: [false, true]),
        PropertyType.boolean,
        '',
      ),
      _ConstraintCase(
        'integer allowed values',
        RestageConstraints(allowedValues: [1, 2]),
        PropertyType.integer,
        '',
      ),
      _ConstraintCase(
        'real allowed values',
        RestageConstraints(allowedValues: [1, 2.5]),
        PropertyType.real,
        '',
      ),
      _ConstraintCase(
        'nullable string allowed values',
        RestageConstraints(allowedValues: ['value', null]),
        PropertyType.string,
        '',
      ),
    ];

    for (final candidate in valid) {
      expect(
        validateRestageConstraintValues(candidate.constraints),
        isNull,
        reason: candidate.name,
      );
      final property = _property(candidate.type, candidate.constraints);
      expect(() => encodeCatalog(_catalog(property)), returnsNormally);
      expect(
        () => classifyA2uiCatalogDart(_catalog(property)),
        returnsNormally,
      );
      expect(
        () => validateWidgetbookConstraintApplicability(
          property,
          candidate.constraints,
          path: 'ConstraintParity.value',
        ),
        returnsNormally,
      );
    }
  });

  test('valid recursive extensions retain target-specific unknown policy', () {
    final constraints = RestageConstraints.withExtensions(
      extensions: const {
        'x-data': {
          'nested': [true, 1, 2.5, 'value', null],
        },
      },
    );
    final property = _property(PropertyType.string, constraints);
    expect(validateRestageConstraintValues(constraints), isNull);
    expect(() => encodeCatalog(_catalog(property)), returnsNormally);
    expect(
      () => validateWidgetbookConstraintApplicability(
        property,
        constraints,
        path: 'ConstraintParity.value',
      ),
      returnsNormally,
    );
    expect(
      () => classifyA2uiCatalogDart(_catalog(property)),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('cannot represent unknown constraint keywords'),
        ),
      ),
    );
  });
}

List<_ConstraintCase> _nonFiniteBounds(double value) => [
      _ConstraintCase(
        'non-finite minimum $value',
        RestageConstraints(minimum: value),
        PropertyType.real,
        '.minimum',
      ),
      _ConstraintCase(
        'non-finite exclusiveMinimum $value',
        RestageConstraints(exclusiveMinimum: value),
        PropertyType.real,
        '.exclusiveMinimum',
      ),
      _ConstraintCase(
        'non-finite maximum $value',
        RestageConstraints(maximum: value),
        PropertyType.real,
        '.maximum',
      ),
      _ConstraintCase(
        'non-finite exclusiveMaximum $value',
        RestageConstraints(exclusiveMaximum: value),
        PropertyType.real,
        '.exclusiveMaximum',
      ),
    ];

const _knownConstraintKeywords = <String>[
  'minimum',
  'exclusiveMinimum',
  'maximum',
  'exclusiveMaximum',
  'enum',
  'pattern',
  'minLength',
  'maxLength',
  'minItems',
  'maxItems',
];

final class _ConstraintCase {
  const _ConstraintCase(
    this.name,
    this.constraints,
    this.type,
    this.pathSuffix,
  );

  final String name;
  final RestageConstraints constraints;
  final PropertyType type;
  final String pathSuffix;
}

PropertyEntry _property(
  PropertyType type,
  RestageConstraints constraints,
) =>
    PropertyEntry(
      wireId: WireId('p0001'),
      name: 'value',
      type: type,
      description: 'Constraint parity value.',
      required: true,
      constraints: constraints,
    );

Catalog _catalog(PropertyEntry property) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-08-09T00:00:00.000Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '1.0.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'ConstraintParity',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: 'Constraint parity fixture.',
          flutterType: 'package:fixture/fixture.dart#ConstraintParity',
          childrenSlot: ChildrenSlot.none,
          properties: [property],
        ),
      ],
    );
