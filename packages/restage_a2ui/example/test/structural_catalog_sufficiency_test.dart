import 'package:flutter_test/flutter_test.dart';

import 'a2ui_proof_support.dart';

/// The standalone `.a2ui.json` structural catalog is sufficient for a
/// producer to author the golden payload — every component the payload
/// references has a schema, and every property the payload sets on each
/// component is declared in that component's schema. So a producer reading ONLY
/// the structural stamp (no source, no side channel) could author this payload.
///
/// The authorable-property set is DERIVED from [goldenLessonComponents] (the
/// same golden the render proof feeds to genui) rather than a hand-maintained
/// mirror, so the two proofs cannot drift.
///
/// Honest scope: this test scans PER-COMPONENT schema keys only — the
/// catalog-level `systemPromptFragments` list (developer-authored steering
/// text, sourced from `usage`/`description`) is out of its scope and asserted
/// elsewhere. The invariant this guards is narrower than "no steering text at
/// all": no per-component schema key carries AUTO-generated or inferred usage
/// rules. Every fragment that does exist is developer-authored, never
/// generated/inferred from the schema, so that invariant still holds; this
/// test asserts nothing about `systemPromptFragments` and guards that no
/// per-component semantic usage KEY silently appears (which would need a
/// deliberate design decision, not a silent add).
void main() {
  late final Map<String, Object?> components;

  setUpAll(() {
    components =
        (readStamp()['a2uiCatalog'] as Map)['components']
            as Map<String, Object?>;
  });

  test('the golden payload is authorable from the .a2ui.json schemas alone', () {
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
      final props = ((schema! as Map)['properties'] as Map).keys.toSet();
      // Every property the golden payload SETS (scalars + slot refs) must be a
      // declared property a producer could find in the stamp. `id`/`component`
      // are the envelope discriminators, not authorable schema properties.
      for (final key in component.keys) {
        if (key == 'id' || key == 'component') continue;
        expect(
          props,
          contains(key),
          reason:
              '$name.$key is not declared in the structural stamp — a '
              'producer could not author it from the catalog alone',
        );
      }
      // Every schema carries the `component` discriminator a producer must set.
      expect(props, contains('component'));
    }
  });

  test('no PER-COMPONENT schema carries an auto-generated semantic usage '
      'field', () {
    // Honesty guard, scoped to per-component schema keys: this does not
    // assert anything about the catalog-level `systemPromptFragments` list,
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
