import 'package:flutter_test/flutter_test.dart';

import 'a2ui_proof_support.dart';

/// Every authored input in the shared render graph is declared by the producer document.
void main() {
  late final Map<String, Object?> components;

  setUpAll(() {
    components =
        (readStamp()['a2uiCatalog'] as Map)['components']
            as Map<String, Object?>;
  });

  test(
    'the golden payload is authorable from the .a2ui.json schemas alone',
    () {
      for (final component in goldenLessonComponents) {
        final name = component['component'] as String;
        final schema = components[name];
        expect(
          schema,
          isNotNull,
          reason:
              'stamp is missing a schema for $name — a producer could not '
              'know the component exists',
        );
        final schemaMap = schema! as Map;
        final envelopeProperties = (schemaMap['properties'] as Map);
        final declaredProps = envelopeProperties.keys.toSet();
        final authoredProps = Map<String, Object?>.from(component)
          ..remove('id')
          ..remove('component');
        for (final key in authoredProps.keys) {
          expect(
            declaredProps,
            contains(key),
            reason:
                '$name.$key is not declared in the structural stamp — a '
                'producer could not author it from the catalog alone',
          );
        }
      }
    },
  );

  test('no PER-COMPONENT schema carries an auto-generated semantic usage '
      'field', () {
    // Honesty guard, scoped to per-component schema keys: this does not
    // assert anything about the catalog-level `instructions` list,
    // which DOES exist and DOES carry steering text today — but that text is
    // always developer-authored (from `usage`/`description`), never
    // generated/inferred by the toolchain. If a future change adds an
    // auto-generated/inferred usage KEY to a per-component schema, revisit
    // this deliberately.
    for (final schema in components.values) {
      final keys = (schema! as Map).keys.toSet();
      for (final banned in const [
        'x-usage',
        'usageRules',
        'steering',
        'x-when',
      ]) {
        expect(
          keys.contains(banned),
          isFalse,
          reason:
              'the structural stamp gained a semantic usage field '
              '"$banned" — it is not auto-generated today; adding one is a '
              'deliberate design decision, not a silent schema change',
        );
      }
    }
  });
}
