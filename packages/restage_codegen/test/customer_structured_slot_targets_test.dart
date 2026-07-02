import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The customer-widget visitor must, alongside the discovered structured graph,
/// surface (a) `slotTargets` — the map from each structured slot
/// (`'<ownerFqn>.<slotName>'`) to its target structured type's sourceType FQN —
/// and (b) `localUnrenderable` — the set of structured types whose walk dropped
/// an unsupported inner field. Together they drive the recursive
/// resolve-or-exclude-loud admissibility check.
void main() {
  group('customer structured slot-target + localUnrenderable capture', () {
    test(
        'captures the widget-property AND nested-field slot targets, and marks '
        'a type with a dropped (Map) inner field as localUnrenderable',
        () async {
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

      // Inner carries a Map field the structured walker warn+drops, so Inner is
      // locally unrenderable.
      expect(
        result.localUnrenderable.keys.any((k) => k.endsWith('#Inner')),
        isTrue,
        reason: 'Inner (dropped Map field) must be localUnrenderable; got '
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
