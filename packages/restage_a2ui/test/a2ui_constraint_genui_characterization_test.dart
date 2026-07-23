import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart'
    show CreateSurfaceMessage, UpdateComponentsMessage;
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

// Characterizes the REAL genui runtime's component-schema validation. genui
// 0.10.1 performs full JSON-schema validation (enum, primitive type, and the
// numeric/string/array keyword constraints), a marked tightening over 0.9.2,
// which enforced only enum membership and ignored primitive-type and keyword
// constraints. These tests document UPSTREAM genui behavior — they are not a
// statement of any Restage guarantee. Validation is report-only: genui surfaces
// the error on `onSubmit` without rolling back the mutation, so Restage's
// pre-render check remains the fail-closed gate.
void main() {
  test('real GenUI 0.10.1 rejects a non-null enum mismatch', () async {
    final error = await _validationError({
      ..._validProperties,
      'enumValue': 'rejected',
    });

    expect(error, contains('enumValueNotAllowed'));
  });

  test(
    'real GenUI 0.10.1 now rejects null for a required typed field',
    () async {
      // 0.9.2 accepted null before enum/type checks; 0.10.1 enforces both the
      // enum membership and the declared `string` type, so null is rejected.
      final error = await _validationError({
        ..._validProperties,
        'enumValue': null,
      });

      expect(error, isNotNull);
      expect(
        error,
        anyOf(contains('enumValueNotAllowed'), contains('typeMismatch')),
      );
    },
  );

  test('real GenUI 0.10.1 now enforces primitive schema types', () async {
    // 0.9.2 did NOT enforce primitive types; 0.10.1 reports a typeMismatch for
    // each wrong-typed property.
    final error = await _validationError({
      ..._validProperties,
      'number': 'not-a-number',
      'patternText': 7,
      'shortText': false,
      'items': 'not-a-list',
    });

    expect(error, contains('typeMismatch'));
  });

  test(
    'real GenUI 0.10.1 now enforces numeric/string/array constraints',
    () async {
      // 0.9.2 ignored these keyword constraints; 0.10.1 enforces minimum,
      // pattern, maxLength, and maxItems. Each violation is reported.
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

  test('real GenUI 0.10.1 accepts a fully valid payload', () async {
    expect(await _validationError(_validProperties), isNull);
  });
}

Future<String?> _validationError(Map<String, Object?> properties) async {
  final controller = SurfaceController(catalogs: [_catalog]);
  final submissions = <ChatMessage>[];
  final subscription = controller.onSubmit.listen(submissions.add);
  try {
    controller.handleMessage(
      CreateSurfaceMessage(surfaceId: 'surface', catalogId: _catalogId),
    );
    controller.handleMessage(
      UpdateComponentsMessage(
        surfaceId: 'surface',
        components: [
          {'id': 'root', 'component': 'ConstrainedValue', ...properties},
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
