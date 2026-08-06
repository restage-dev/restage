import 'dart:convert';

import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_data_builder.dart';
import 'package:restage_codegen/src/a2ui/a2ui_definition_registry.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

A2uiDartWidgetPlan _planFor(A2uiSchemaNode node) => classifyA2uiCatalogDart(
      catalogWith([
        entry(
          name: 'CarrierCard',
          properties: [
            prop('value', PropertyType.structured, required: true),
          ],
        ),
      ]),
      richShapes: {('CarrierCard', 'value'): node},
    ).widgets.single;

void main() {
  group('A2uiDefinitionRegistry node-family description reconciliation', () {
    const containerId = 'package:example/example.dart#Container';

    ObjectNode candidate({required bool withFacts}) => ObjectNode(
          defId: containerId,
          definitionDescription: 'Canonical container.',
          occurrenceDescription:
              withFacts ? 'Second container use.' : 'First container use.',
          fields: {
            'tone': EnumNode(
              members: const ['soft', 'loud'],
              dartTypeName: 'Tone',
              occurrenceDescription: withFacts ? ' Selected tone. ' : null,
            ),
            'tags': ListNode(
              occurrenceDescription: withFacts ? ' Visible tags. ' : null,
              element: ScalarNode(
                A2uiScalarType.string,
                occurrenceDescription: withFacts ? ' One tag. ' : null,
              ),
            ),
            'labels': MapNode(
              occurrenceDescription: withFacts ? ' Labels by locale. ' : null,
              valueType: EnumNode(
                members: const ['short', 'long'],
                dartTypeName: 'LabelKind',
                occurrenceDescription: withFacts ? ' One label kind. ' : null,
              ),
            ),
          },
          required: const {'tone', 'tags', 'labels'},
        );

    test('absent + present nested facts merge independent of root order', () {
      final absent = candidate(withFacts: false);
      final present = candidate(withFacts: true);
      final forward =
          A2uiDefinitionRegistry([absent, present]).definitionFor(containerId);
      final reversed =
          A2uiDefinitionRegistry([present, absent]).definitionFor(containerId);

      expect(reversed, forward);
      final container = forward as ObjectNode;
      expect(container.occurrenceDescription, isNull);
      expect(
        (container.fields['tone']! as EnumNode).occurrenceDescription,
        'Selected tone.',
      );
      final tags = container.fields['tags']! as ListNode;
      expect(tags.occurrenceDescription, 'Visible tags.');
      expect(tags.element.occurrenceDescription, 'One tag.');
      final labels = container.fields['labels']! as MapNode;
      expect(labels.occurrenceDescription, 'Labels by locale.');
      expect(labels.valueType.occurrenceDescription, 'One label kind.');

      expect(
        a2uiDataSchemaExpression(reversed),
        a2uiDataSchemaExpression(forward),
      );
      expect(
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(reversed))),
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(forward))),
      );
    });

    test('container occurrence conflicts report deterministic nested paths',
        () {
      ObjectNode withDescriptions({
        required String enumDescription,
        required String listDescription,
        required String mapDescription,
      }) =>
          ObjectNode(
            defId: containerId,
            fields: {
              'tone': EnumNode(
                members: const ['soft', 'loud'],
                dartTypeName: 'Tone',
                occurrenceDescription: enumDescription,
              ),
              'tags': ListNode(
                element: const ScalarNode(A2uiScalarType.string),
                occurrenceDescription: listDescription,
              ),
              'labels': MapNode(
                valueType: const ScalarNode(A2uiScalarType.string),
                occurrenceDescription: mapDescription,
              ),
            },
            required: const {'tone', 'tags', 'labels'},
          );

      final first = withDescriptions(
        enumDescription: 'First tone.',
        listDescription: 'Same tags.',
        mapDescription: 'Same labels.',
      );
      final second = withDescriptions(
        enumDescription: 'Second tone.',
        listDescription: 'Same tags.',
        mapDescription: 'Same labels.',
      );
      final enumConflict = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical member description for "$containerId.tone".',
      );
      expect(
        () => A2uiDefinitionRegistry([first, second]),
        throwsA(enumConflict),
      );
      expect(
        () => A2uiDefinitionRegistry([second, first]),
        throwsA(enumConflict),
      );

      final listConflict = withDescriptions(
        enumDescription: 'First tone.',
        listDescription: 'Other tags.',
        mapDescription: 'Same labels.',
      );
      expect(
        () => A2uiDefinitionRegistry([first, listConflict]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Conflicting canonical member description for '
                '"$containerId.tags".',
          ),
        ),
      );
      expect(
        () => A2uiDefinitionRegistry([listConflict, first]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Conflicting canonical member description for '
                '"$containerId.tags".',
          ),
        ),
      );

      final mapConflict = withDescriptions(
        enumDescription: 'First tone.',
        listDescription: 'Same tags.',
        mapDescription: 'Other labels.',
      );
      expect(
        () => A2uiDefinitionRegistry([first, mapConflict]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Conflicting canonical member description for '
                '"$containerId.labels".',
          ),
        ),
      );
      expect(
        () => A2uiDefinitionRegistry([mapConflict, first]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Conflicting canonical member description for '
                '"$containerId.labels".',
          ),
        ),
      );
    });

    test('nested documented carriers canonicalize order and first conflicts',
        () {
      ObjectNode documentedCandidate({
        required bool reversed,
        required String descriptionPrefix,
      }) {
        final entries = <MapEntry<String, A2uiSchemaNode>>[
          MapEntry(
            'aTone',
            EnumNode(
              members: const ['soft', 'loud'],
              dartTypeName: 'Tone',
              occurrenceDescription: '$descriptionPrefix tone.',
            ),
          ),
          MapEntry(
            'mTags',
            ListNode(
              element: const ScalarNode(A2uiScalarType.string),
              occurrenceDescription: '$descriptionPrefix tags.',
            ),
          ),
          MapEntry(
            'zLabels',
            MapNode(
              valueType: const ScalarNode(A2uiScalarType.string),
              occurrenceDescription: '$descriptionPrefix labels.',
            ),
          ),
        ];
        final ordered = reversed ? entries.reversed : entries;
        return ObjectNode(
          defId: containerId,
          occurrenceDescription:
              reversed ? 'Second container use.' : 'First container use.',
          fields: Map.fromEntries(ordered),
          required: ordered.map((entry) => entry.key).toSet(),
        );
      }

      final first = documentedCandidate(
        reversed: false,
        descriptionPrefix: 'Canonical',
      );
      final second = documentedCandidate(
        reversed: true,
        descriptionPrefix: 'Canonical',
      );
      final forwardRegistry = A2uiDefinitionRegistry([first, second]);
      final reversedRegistry = A2uiDefinitionRegistry([second, first]);
      final forward = forwardRegistry.definitionFor(containerId);
      final reversed = reversedRegistry.definitionFor(containerId);

      expect(forwardRegistry.canonicalOrderTargets, contains(containerId));
      expect(reversedRegistry.canonicalOrderTargets, contains(containerId));
      expect(
        (forward as ObjectNode).fields.keys,
        ['aTone', 'mTags', 'zLabels'],
      );
      expect(
        (reversed as ObjectNode).fields.keys,
        ['aTone', 'mTags', 'zLabels'],
      );
      expect(
        a2uiDataSchemaExpression(reversed),
        a2uiDataSchemaExpression(forward),
      );
      expect(
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(reversed))),
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(forward))),
      );

      final conflictFirst = documentedCandidate(
        reversed: false,
        descriptionPrefix: 'First',
      );
      final conflictSecond = documentedCandidate(
        reversed: true,
        descriptionPrefix: 'Second',
      );
      final expectedConflict = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical member description for '
            '"$containerId.aTone".',
      );
      expect(
        () => A2uiDefinitionRegistry([conflictFirst, conflictSecond]),
        throwsA(expectedConflict),
      );
      expect(
        () => A2uiDefinitionRegistry([conflictSecond, conflictFirst]),
        throwsA(expectedConflict),
      );
    });

    test('root use text preserves order; root definition text canonicalizes',
        () {
      ObjectNode root({String? definitionDescription}) => ObjectNode(
            defId: containerId,
            occurrenceDescription: 'This container use.',
            definitionDescription: definitionDescription,
            fields: const {
              'zeta': ScalarNode(A2uiScalarType.string),
              'alpha': ScalarNode(A2uiScalarType.integer),
            },
            required: const {'zeta', 'alpha'},
          );

      final useOnly = A2uiDefinitionRegistry([root()]);
      expect(useOnly.canonicalOrderTargets, isNot(contains(containerId)));
      expect(
        (useOnly.definitionFor(containerId) as ObjectNode).fields.keys,
        ['zeta', 'alpha'],
      );

      final canonical = A2uiDefinitionRegistry([
        root(definitionDescription: 'Canonical container.'),
      ]);
      expect(canonical.canonicalOrderTargets, contains(containerId));
      expect(
        (canonical.definitionFor(containerId) as ObjectNode).fields.keys,
        ['alpha', 'zeta'],
      );
    });

    test(
        'nested anonymous documented objects canonicalize recursively without '
        'reordering adjacent legacy subtrees', () {
      ObjectNode candidate({
        required bool reversed,
        required String descriptionPrefix,
      }) {
        final mapValueEntries = <MapEntry<String, A2uiSchemaNode>>[
          const MapEntry(
            'alpha',
            ScalarNode(A2uiScalarType.string),
          ),
          const MapEntry(
            'zeta',
            ScalarNode(A2uiScalarType.integer),
          ),
        ];
        final orderedMapValues =
            reversed ? mapValueEntries.reversed : mapValueEntries;
        final documentedEntries = <MapEntry<String, A2uiSchemaNode>>[
          MapEntry(
            'alpha',
            EnumNode(
              members: const ['soft', 'loud'],
              dartTypeName: 'Tone',
              occurrenceDescription: '$descriptionPrefix alpha.',
            ),
          ),
          MapEntry(
            'zeta',
            MapNode(
              valueType: ObjectNode(
                fields: Map.fromEntries(orderedMapValues),
                required: orderedMapValues.map((entry) => entry.key).toSet(),
              ),
              occurrenceDescription: '$descriptionPrefix zeta.',
            ),
          ),
        ];
        final ordered =
            reversed ? documentedEntries.reversed : documentedEntries;
        return ObjectNode(
          defId: containerId,
          fields: {
            'documented': ObjectNode(
              fields: Map.fromEntries(ordered),
              required: ordered.map((entry) => entry.key).toSet(),
            ),
            'legacy': ObjectNode(
              fields: const {
                'zeta': ScalarNode(A2uiScalarType.string),
                'alpha': ScalarNode(A2uiScalarType.integer),
              },
              required: const {'zeta', 'alpha'},
            ),
          },
          required: const {'documented', 'legacy'},
        );
      }

      ObjectNode subtree(A2uiSchemaNode root, String field) =>
          (root as ObjectNode).fields[field]! as ObjectNode;

      final first = candidate(
        reversed: false,
        descriptionPrefix: 'Canonical',
      );
      final second = candidate(
        reversed: true,
        descriptionPrefix: 'Canonical',
      );
      final forward =
          A2uiDefinitionRegistry([first, second]).definitionFor(containerId);
      final reversed =
          A2uiDefinitionRegistry([second, first]).definitionFor(containerId);

      expect(reversed, forward);
      for (final definition in [forward, reversed]) {
        final documented = subtree(definition, 'documented');
        expect(documented.fields.keys, ['alpha', 'zeta']);
        expect(documented.required, orderedEquals(['alpha', 'zeta']));
        final documentedMap = documented.fields['zeta']! as MapNode;
        final documentedMapValue = documentedMap.valueType as ObjectNode;
        expect(documentedMapValue.fields.keys, ['alpha', 'zeta']);
        expect(
          documentedMapValue.required,
          orderedEquals(['alpha', 'zeta']),
        );
        final legacy = subtree(definition, 'legacy');
        expect(legacy.fields.keys, ['zeta', 'alpha']);
        expect(legacy.required, orderedEquals(['zeta', 'alpha']));
      }
      expect(
        a2uiDataSchemaExpression(reversed),
        a2uiDataSchemaExpression(forward),
      );
      expect(
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(reversed))),
        jsonEncode(a2uiWidgetDataSchemaMapForPlan(_planFor(forward))),
      );

      final conflictFirst = candidate(
        reversed: false,
        descriptionPrefix: 'First',
      );
      final conflictSecond = candidate(
        reversed: true,
        descriptionPrefix: 'Second',
      );
      final expectedConflict = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical member description for '
            '"$containerId.documented.alpha".',
      );
      expect(
        () => A2uiDefinitionRegistry([conflictFirst, conflictSecond]),
        throwsA(expectedConflict),
      );
      expect(
        () => A2uiDefinitionRegistry([conflictSecond, conflictFirst]),
        throwsA(expectedConflict),
      );
    });
  });

  group('dormant UnionNode registry consistency', () {
    const unionId = 'package:example/example.dart#Result';

    UnionNode candidate({required bool withFacts}) => UnionNode(
          defId: unionId,
          discriminatorField: 'type',
          definitionDescription: withFacts ? ' Canonical result. ' : null,
          occurrenceDescription:
              withFacts ? 'Second result use.' : 'First result use.',
          variants: [
            EnumNode(
              members: const ['success', 'failure'],
              dartTypeName: 'ResultKind',
              occurrenceDescription: withFacts ? ' Result kind. ' : null,
            ),
          ],
        );

    test('registers type facts while excluding only the candidate root use',
        () {
      final absent = candidate(withFacts: false);
      final present = candidate(withFacts: true);
      final forwardRegistry = A2uiDefinitionRegistry([absent, present]);
      final forward = forwardRegistry.definitionFor(unionId);
      final reversed =
          A2uiDefinitionRegistry([present, absent]).definitionFor(unionId);

      expect(reversed, forward);
      expect(forwardRegistry.hoistTargets, contains(unionId));
      expect(forward, isA<UnionNode>());
      final union = forward as UnionNode;
      expect(union.definitionDescription, 'Canonical result.');
      expect(union.occurrenceDescription, isNull);
      expect(
        (union.variants.single as EnumNode).occurrenceDescription,
        'Result kind.',
      );
    });

    test('a nested named union keeps its use description in its parent', () {
      final result = candidate(withFacts: true);
      final container = ObjectNode(
        defId: 'package:example/example.dart#Envelope',
        fields: {'result': result},
        required: const {'result'},
      );
      final registry = A2uiDefinitionRegistry([container]);
      final envelope = registry.definitionFor(container.defId!) as ObjectNode;
      final nested = envelope.fields['result']! as UnionNode;
      final canonical = registry.definitionFor(unionId) as UnionNode;

      expect(nested.occurrenceDescription, 'Second result use.');
      expect(canonical.occurrenceDescription, isNull);
    });

    test('definition, nested occurrence, and structure conflicts are strict',
        () {
      final first = candidate(withFacts: true);
      final definitionConflict = UnionNode(
        defId: unionId,
        discriminatorField: 'type',
        definitionDescription: 'Different canonical result.',
        variants: first.variants,
      );
      final canonicalError = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical description for "$unionId".',
      );
      expect(
        () => A2uiDefinitionRegistry([first, definitionConflict]),
        throwsA(canonicalError),
      );
      expect(
        () => A2uiDefinitionRegistry([definitionConflict, first]),
        throwsA(canonicalError),
      );

      final occurrenceConflict = UnionNode(
        defId: unionId,
        discriminatorField: 'type',
        definitionDescription: 'Canonical result.',
        variants: [
          EnumNode(
            members: const ['success', 'failure'],
            dartTypeName: 'ResultKind',
            occurrenceDescription: 'Different result kind.',
          ),
        ],
      );
      final occurrenceError = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical member description for '
            '"$unionId.variants[0]".',
      );
      expect(
        () => A2uiDefinitionRegistry([first, occurrenceConflict]),
        throwsA(occurrenceError),
      );
      expect(
        () => A2uiDefinitionRegistry([occurrenceConflict, first]),
        throwsA(occurrenceError),
      );

      final structureConflict = UnionNode(
        defId: unionId,
        discriminatorField: 'type',
        definitionDescription: 'Canonical result.',
        variants: [
          EnumNode(
            members: const ['success'],
            dartTypeName: 'ResultKind',
          ),
        ],
      );
      final structureError = isA<StateError>().having(
        (error) => error.message,
        'message',
        'Conflicting canonical structure for "$unionId".',
      );
      expect(
        () => A2uiDefinitionRegistry([first, structureConflict]),
        throwsA(structureError),
      );
      expect(
        () => A2uiDefinitionRegistry([structureConflict, first]),
        throwsA(structureError),
      );
    });

    test('projection and construction remain loud with carriers populated', () {
      final union = candidate(withFacts: true);

      expect(() => a2uiDataSchemaExpression(union), throwsStateError);
      expect(
        () => A2uiDataBuilder([union]).valueExpression(union, 'raw'),
        throwsStateError,
      );
    });
  });
}
