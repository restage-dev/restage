import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

const _catalogId = 'constraint-characterization';

final _catalog = CatalogImplementation(
  id: _catalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ComponentImplementation(
      name: 'ConstrainedValue',
      schema: S.fromMap(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'enumValue': <String, Object?>{
            'type': 'string',
            'enum': <Object?>['allowed'],
          },
          'number': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 10,
          },
          'patternText': <String, Object?>{
            'type': 'string',
            'pattern': r'^[A-Z]+$',
          },
          'shortText': <String, Object?>{'type': 'string', 'maxLength': 3},
          'items': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'maxItems': 1,
          },
        },
        'required': <Object?>[
          'enumValue',
          'number',
          'patternText',
          'shortText',
          'items',
        ],
      }),
      builder: (_, _, _, _) => const SizedBox.shrink(),
    ),
  ],
);

const _validProperties = <String, Object?>{
  'enumValue': 'allowed',
  'number': 5,
  'patternText': 'ABC',
  'shortText': 'abc',
  'items': <Object?>['one'],
};

// The published strict v1 processor validates before committing components.
void main() {
  test('strict A2UI v1 rejects a non-null enum mismatch', () async {
    final error = await _validationError({
      ..._validProperties,
      'enumValue': 'rejected',
    });

    expect(error, contains('enum'));
  });

  test('strict A2UI v1 now rejects null for a required typed field', () async {
    final error = await _validationError({
      ..._validProperties,
      'enumValue': null,
    });

    expect(error, isNotNull);
    expect(error, anyOf(contains('enum'), contains('type')));
  });

  test('strict A2UI v1 now enforces primitive schema types', () async {
    final error = await _validationError({
      ..._validProperties,
      'number': 'not-a-number',
      'patternText': 7,
      'shortText': false,
      'items': 'not-a-list',
    });

    expect(error, contains('type'));
  });

  test(
    'strict A2UI v1 now enforces numeric/string/array constraints',
    () async {
      final violations = <Map<String, Object?>>[
        {..._validProperties, 'number': -1},
        {..._validProperties, 'patternText': 'lowercase'},
        {..._validProperties, 'shortText': 'too long'},
        {
          ..._validProperties,
          'items': <Object?>['one', 'two'],
        },
      ];

      for (final properties in violations) {
        expect(
          await _validationError(properties),
          isNotNull,
          reason: '$properties',
        );
      }
    },
  );

  test('strict A2UI v1 accepts a fully valid payload', () async {
    expect(await _validationError(_validProperties), isNull);
  });
}

Future<String?> _validationError(Map<String, Object?> properties) async {
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [_catalog],
    defaultVersion: A2uiProtocolVersion.v1_0,
    validationConfig: ValidationConfig.strict,
  );
  try {
    processor.processMessages({
      'version': '1.0',
      'createSurface': {'surfaceId': 'surface', 'catalogId': _catalogId},
    });
    try {
      processor.processMessages({
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'surface',
          'components': [
            {'id': 'root', 'component': 'ConstrainedValue', ...properties},
          ],
        },
      });
      return null;
    } on A2uiValidationError catch (error) {
      expect(
        processor.model.getSurface('surface')!.componentsModel.keys,
        isEmpty,
      );
      return error.toString();
    }
  } finally {
    processor.dispose();
  }
}
