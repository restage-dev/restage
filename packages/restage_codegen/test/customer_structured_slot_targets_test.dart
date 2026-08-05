import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The customer-widget visitor must, alongside the discovered structured graph,
/// surface (a) `slotTargets` — the map from each structured slot
/// (`'<ownerFqn>.<slotName>'`) to its target structured type's sourceType FQN —
/// and (b) `localUnrenderable` — the set of structured types whose walk dropped
/// an unsupported inner field. Together they drive the recursive
/// resolve-or-exclude-loud admissibility check.
/// A map-typed inner field is dropped only when its key or value type falls
/// outside the admitted map boundary; an admitted map materializes as an opaque
/// map value shape and does not make its owner unrenderable.
void main() {
  group('customer structured slot-target + localUnrenderable capture', () {
    test(
        'captures the widget-property AND nested-field slot targets, and marks '
        'a type with a dropped (unsupported-key Map) inner field as '
        'localUnrenderable', () async {
      final result = await runWidgetVisitorOn({
        'lib/cards.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Inner {
            const Inner({required this.value, required this.data});
            final int value;
            final Map<int, String> data;
          }

          class Outer {
            const Outer({required this.title, required this.inner});
            final String title;
            final Inner inner;
          }

          @RestageWidget(
            name: 'OuterCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with nested config.',
          )
          class OuterCard {
            const OuterCard({required this.config});
            @RestageProperty(description: 'The nested config.')
            final Outer config;
          }
        ''',
      });

      // The widget property `config` targets `Outer`.
      expect(
        result.slotTargets.entries.any(
          (e) =>
              e.key.endsWith('#OuterCard.config') && e.value.endsWith('#Outer'),
        ),
        isTrue,
        reason: 'widget-property slot target for OuterCard.config -> Outer '
            'must be captured; got ${result.slotTargets}',
      );

      // The nested structured field `Outer.inner` targets `Inner`.
      expect(
        result.slotTargets.entries.any(
          (e) => e.key.endsWith('#Outer.inner') && e.value.endsWith('#Inner'),
        ),
        isTrue,
        reason: 'nested-field slot target for Outer.inner -> Inner must be '
            'captured; got ${result.slotTargets}',
      );

      // Inner carries a map whose key type is outside the admitted boundary, so
      // the structured walker warn+drops the field and Inner is locally
      // unrenderable. A map with an admitted key materializes instead — see the
      // next test.
      expect(
        result.localUnrenderable.keys.any((k) => k.endsWith('#Inner')),
        isTrue,
        reason: 'Inner (dropped unsupported-key Map field) must be '
            'localUnrenderable; got '
            '${result.localUnrenderable}',
      );

      // End-to-end: the governing invariant — OuterCard is EXCLUDED loud (its
      // closure reaches Inner, which is unrenderable), NOT admitted-with-drop.
      final admission = computeAdmission(
        widgets: result.widgets,
        structuredTypes: result.structuredTypes,
        slotTargets: result.slotTargets,
        localUnrenderable: result.localUnrenderable,
      );
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.reason, contains('Inner'));
    });

    test(
        'a data-class field carrying a map with an admitted key materializes '
        'with the map contract instead of dropping', () async {
      final result = await runWidgetVisitorOn({
        'lib/cards.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Inner {
            const Inner({required this.value, required this.data});
            final int value;
            final Map<String, int> data;
          }

          class Outer {
            const Outer({required this.title, required this.inner});
            final String title;
            final Inner inner;
          }

          @RestageWidget(
            name: 'OuterCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with nested config.',
          )
          class OuterCard {
            const OuterCard({required this.config});
            @RestageProperty(description: 'The nested config.')
            final Outer config;
          }
        ''',
      });

      // The field is no longer dropped, so its owning type is renderable.
      expect(
        result.localUnrenderable,
        isEmpty,
        reason: 'an admitted-key map field must not drop; got '
            '${result.localUnrenderable}',
      );

      // Assert the SLOT SURVIVED and carries the map contract. Asserting only
      // that nothing was marked unrenderable would also pass if the field had
      // vanished silently, which is the failure this test exists to catch.
      final inner = result.structuredTypes
          .firstWhere((entry) => entry.sourceType.endsWith('#Inner'));
      final dataFields =
          inner.fields.where((field) => field.name == 'data').toList();
      expect(
        dataFields,
        hasLength(1),
        reason: 'the map field must be materialized on Inner; got '
            '${inner.fields.map((f) => f.name).toList()}',
      );
      final data = dataFields.single;
      expect(data.type, PropertyType.unknown);
      expect(
        (data.valueShape! as ScalarShape).isOpaqueStringKeyedMap,
        isTrue,
        reason: 'the materialized field must carry the map value shape, not '
            'some other scalar shape',
      );
    });

    test(
        'a fully-renderable nested closure captures its slot targets and is '
        'admitted (no localUnrenderable entries)', () async {
      final result = await runWidgetVisitorOn({
        'lib/cards.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Inner {
            const Inner({required this.value});
            final int value;
          }

          class Outer {
            const Outer({required this.title, required this.inner});
            final String title;
            final Inner inner;
          }

          @RestageWidget(
            name: 'OuterCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with nested config.',
          )
          class OuterCard {
            const OuterCard({required this.config});
            @RestageProperty(description: 'The nested config.')
            final Outer config;
          }
        ''',
      });

      expect(result.localUnrenderable, isEmpty);
      final admission = computeAdmission(
        widgets: result.widgets,
        structuredTypes: result.structuredTypes,
        slotTargets: result.slotTargets,
        localUnrenderable: result.localUnrenderable,
      );
      expect(admission.admitted.map((w) => w.name), ['OuterCard']);
      expect(
        admission.admittedSourceTypes.map((s) => s.split('#').last),
        containsAll(<String>['Outer', 'Inner']),
      );
    });
  });
}
