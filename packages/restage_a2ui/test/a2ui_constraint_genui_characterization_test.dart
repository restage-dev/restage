import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

const _catalogId = 'constraint-characterization';

final _catalog = Catalog([
  CatalogItem(
    name: 'ConstrainedValue',
    dataSchema: S.fromMap(<String, Object?>{
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
    widgetBuilder: (_) => const SizedBox.shrink(),
  ),
], catalogId: _catalogId);

const _validProperties = <String, Object?>{
  'enumValue': 'allowed',
  'number': 5,
  'patternText': 'ABC',
  'shortText': 'abc',
  'items': <Object?>['one'],
};

void main() {
  test('real GenUI 0.9.2 rejects a non-null enum mismatch', () async {
    final error = await _validationError({
      ..._validProperties,
      'enumValue': 'rejected',
    });

    expect(error, contains('Value not in enum'));
  });

  test('real GenUI 0.9.2 accepts null before enum and type checks', () async {
    final error = await _validationError({
      ..._validProperties,
      'enumValue': null,
    });

    expect(error, isNull);
  });

  test('real GenUI 0.9.2 does not enforce primitive schema types', () async {
    final error = await _validationError({
      ..._validProperties,
      'number': 'not-a-number',
      'patternText': 7,
      'shortText': false,
      'items': 'not-a-list',
    });

    expect(error, isNull);
  });

  test('real GenUI 0.9.2 accepts representative ignored constraints', () async {
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
      expect(await _validationError(properties), isNull, reason: '$properties');
    }
  });
}

Future<String?> _validationError(Map<String, Object?> properties) async {
  final controller = SurfaceController(catalogs: [_catalog]);
  final submissions = <ChatMessage>[];
  final subscription = controller.onSubmit.listen(submissions.add);
  try {
    controller.handleMessage(
      const CreateSurface(surfaceId: 'surface', catalogId: _catalogId),
    );
    controller.handleMessage(
      UpdateComponents(
        surfaceId: 'surface',
        components: [
          Component(
            id: 'root',
            type: 'ConstrainedValue',
            properties: properties,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    if (submissions.isEmpty) return null;
    final interaction = submissions.single.parts.uiInteractionParts.single;
    final payload = jsonDecode(interaction.interaction) as Map<String, Object?>;
    final error = payload['error']! as Map<String, Object?>;
    return error['message']! as String;
  } finally {
    await subscription.cancel();
    controller.dispose();
  }
}
