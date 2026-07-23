import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'generated/constraint_parity_catalog.g.dart';

const _documentPath = 'test/generated/constraint_parity_catalog.a2ui.json';

void main() {
  test(
    'actual emitted CatalogItem schema exactly matches the standalone twin',
    () {
      final emittedItems = buildRestageCatalogItems();
      final item = emittedItems.singleWhere(
        (candidate) => candidate.name == 'ConstraintParity',
      );
      final actual = item.dataSchema.value;
      final document =
          jsonDecode(File(_documentPath).readAsStringSync())
              as Map<String, Object?>;
      final components =
          ((document['a2uiCatalog']! as Map)['components']! as Map)
              .cast<String, Object?>();
      for (final emittedItem in emittedItems) {
        expect(
          _canonicalJson(emittedItem.dataSchema.value),
          _canonicalJson(components[emittedItem.name]),
          reason: '${emittedItem.name} real builder must match standalone',
        );
      }

      final standalone = (components[item.name]! as Map)
          .cast<String, Object?>();
      expect(_canonicalJson(actual), _canonicalJson(standalone));

      final defs = (actual[r'$defs']! as Map).cast<String, Object?>();
      final rootKey = (actual[r'$ref']! as String).split('/').last;
      final root = (defs[rootKey]! as Map).cast<String, Object?>();
      final properties = (root['properties']! as Map).cast<String, Object?>();

      final count = (properties['count']! as Map).cast<String, Object?>();
      final countArms = count['oneOf']! as List;
      expect(countArms.first, {
        'anyOf': [
          {
            'type': 'integer',
            'minimum': 0.5,
            'maximum': 9.5,
            'enum': [1, 2],
          },
          {'type': 'null'},
        ],
      });
      expect(countArms[1], isNot(contains('minimum')));
      expect(countArms[1], isNot(contains('enum')));
      expect(countArms[2], isNot(contains('maximum')));
      expect(countArms[2], isNot(contains('enum')));

      final tags = (properties['tags']! as Map).cast<String, Object?>();
      final tagArms = tags['oneOf']! as List;
      expect(tagArms.first, {
        'anyOf': [
          {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'maxItems': 3,
          },
          {'type': 'null'},
        ],
      });
      expect(tagArms[1], isNot(contains('minItems')));
      expect(tagArms[2], isNot(contains('maxItems')));

      expect(properties['ratio'], {
        'type': 'number',
        'exclusiveMinimum': 0.25,
        'exclusiveMaximum': 0.75,
      });
      expect(properties['code'], {
        'type': 'string',
        'pattern': r'^[A-Z]{2}[0-9]+$',
        'minLength': 3,
        'maxLength': 8,
      });

      final items = (properties['items']! as Map).cast<String, Object?>();
      final constrainedItems = (items['anyOf']! as List).first as Map;
      expect(constrainedItems['minItems'], 1);
      expect(constrainedItems['maxItems'], 4);
      expect(
        (constrainedItems['items']! as Map)[r'$ref'],
        r'#/$defs/ConstraintRecursiveItem',
      );
      expect(defs, contains('ConstraintRecursiveItem'));

      expect(properties['legacyCount'], {
        'type': 'number',
        'minimum': -10,
        'maximum': 10,
      });
      expect(properties['legacyMode'], {
        'type': 'string',
        'enum': ['compact', 'expanded'],
      });
      expect(properties['legacyCode'], {
        'type': 'string',
        'pattern': r'^[a-z]+$',
      });

      final serialized = jsonEncode(actual);
      expect(serialized, isNot(contains('"default"')));
      expect(serialized, isNot(contains(r'"$comment"')));
      expect(serialized, isNot(contains('Keep count within')));
      expect(serialized, isNot(contains('Choose an authored mode')));
      expect(serialized, isNot(contains('Use lowercase ASCII letters')));

      final patternItems = emittedItems
          .where((candidate) => candidate.name.startsWith('PatternCorpus'))
          .toList();
      expect(patternItems, hasLength(20));
      for (var index = 0; index < patternItems.length; index++) {
        final suffix = index.toString().padLeft(2, '0');
        final widgetName = 'PatternCorpus$suffix';
        final patternItem = emittedItems.singleWhere(
          (candidate) => candidate.name == widgetName,
        );
        final actualPatternProperties =
            (patternItem.dataSchema.value['properties']! as Map)
                .cast<String, Object?>();
        final standalonePatternProperties =
            ((components[widgetName]! as Map)['properties']! as Map)
                .cast<String, Object?>();
        final actualTyped = actualPatternProperties['typedPattern']! as Map;
        final actualLegacy = actualPatternProperties['legacyPattern']! as Map;
        final standaloneTyped =
            standalonePatternProperties['typedPattern']! as Map;
        final standaloneLegacy =
            standalonePatternProperties['legacyPattern']! as Map;

        expect(
          actualTyped['pattern'],
          standaloneTyped['pattern'],
          reason: '$widgetName typed pattern must survive the real builder',
        );
        expect(
          actualLegacy['pattern'],
          standaloneLegacy['pattern'],
          reason: '$widgetName legacy pattern must survive the real builder',
        );
        expect(
          actualTyped['pattern'],
          actualLegacy['pattern'],
          reason: 'typed/legacy accepted corpus case $index must agree',
        );
      }
    },
  );
}

String _canonicalJson(Object? node) => jsonEncode(_canonical(node));

Object? _canonical(Object? node) {
  if (node is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in node.entries) {
      // json_schema_builder 0.1.6 makes the JSON-schema default explicit on the
      // runtime `Schema.value` (`additionalProperties: true`) while the emitted
      // document omits it. Drop ONLY that default-elision; a schema-valued
      // additionalProperties stays for deep comparison.
      if (entry.key == 'additionalProperties' && entry.value == true) continue;
      sorted[entry.key as String] = _canonical(entry.value);
    }
    return sorted;
  }
  if (node is List) return [for (final element in node) _canonical(element)];
  return node;
}
