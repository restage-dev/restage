import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Real-discovery admissibility cases — driven through the REAL
/// walker/discovery (NOT hand-populated fixtures), because the real
/// `FactoryVariantIR` carries an EMPTY `parameters` list (only `argMappings`),
/// so a lowered-catalog-only guard over `variant.parameters` is a no-op. The
/// reconstructor-soundness + duplicate-name detections must therefore live at
/// the analyzer level and are only exercised faithfully through the real path.
Future<CustomerStructuredAdmission> _admit(Map<String, String> sources) async {
  final result = await runWidgetVisitorOn(sources);
  return computeAdmission(
    widgets: result.widgets,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    localUnrenderable: result.localUnrenderable,
    widgetUnrenderable: result.widgetUnrenderable,
  );
}

void main() {
  group('reconstructor-soundness — real discovery', () {
    test(
        'a non-canonical data class (required ctor param name-matches no '
        'field) is EXCLUDED-loud, naming the param', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge({required int c}) : count = c;
            final int count;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('c'));
    });

    test(
        'a REDIRECTING unnamed ctor is skipped: the guard inspects the same '
        'variant the reconstruction uses (the enumerator drops redirecting '
        'ctors), so an unsourceable redirect target is EXCLUDED', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge({required int count}) : this.fromC(c: count);
            const Badge.fromC({required int c}) : count = c;
            final int count;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('c'));
    });

    test(
        'with NO unnamed ctor + multiple named ctors, the guard inspects the '
        'SAME ctor the reconstruction picks (first ALPHABETICAL, not first in '
        'source order) — an unsourceable alphabetical-first is EXCLUDED',
        () async {
      // Source order: zebra first, alpha second. The enumerator sorts named
      // ctors alphabetically, so the reconstruction picks `alpha`. `alpha`'s
      // required `missing` has no same-named field (only `value`), so it must
      // be excluded — a source-order guard would wrongly inspect `zebra`
      // (whose `value` IS a field, sourceable) and admit.
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge.zebra({required this.value});
            const Badge.alpha({required int missing}) : value = missing;
            final int value;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty,
          reason: 'reconstruction uses alpha (unsourceable), so exclude');
      expect(admission.excluded.single.widget.name, 'BadgeCard');
    });

    test(
        'when the selected reconstruction ctor is a FACTORY (which may '
        'transform its input, un-curated for a customer type), the type is '
        'EXCLUDED-loud even if every param name-matches a field', () async {
      // Variants sort alphabetically: factory `alpha` before generative `raw`,
      // so the reconstruction picks `alpha`. `alpha`'s `label` name-matches the
      // materialized field, but the factory rewrites it ('alpha:...') — a
      // round-trip would double it. Not faithfully reconstructable -> exclude.
      final admission = await _admit({
        'lib/card.dart': r'''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge.raw({required this.label});
            factory Badge.alpha({required String label}) =>
                Badge.raw(label: 'alpha:$label');
            final String label;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('factory'));
    });

    test(
        'an unmapped positional param BEFORE a mapped (field) positional is '
        'EXCLUDED-loud (the emitter omits the hole, shifting the field arg to '
        'the wrong slot)', () async {
      // `unused` is an optional positional that is NOT a field; `count` is an
      // optional positional that IS a field. The reconstructor omits the
      // unmapped `unused`, so reconstructing {count: 7} emits Badge(7), binding
      // 7 to `unused` and leaving count == 0. Not faithfully reconstructable.
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge([int unused = 0, this.count = 0]);
            final int count;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('positional'));
    });

    test(
        'a trailing unmapped positional (AFTER all field positionals) still '
        'ADMITS — no shift', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Badge {
            const Badge([this.count = 0, int unused = 0]);
            final int count;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted.map((w) => w.name), ['BadgeCard']);
    });

    test(
        'a SELF-REFERENTIAL (cyclic) type is EXCLUDED-loud (a cycle cannot be '
        'reconstructed by finite inline emission — A2UI-only in RFW)',
        () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Node {
            const Node({required this.value, required this.next});
            final int value;
            final Node next;
          }
          @RestageWidget(name: 'NodeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class NodeCard {
            const NodeCard({required this.node});
            @RestageProperty(description: 'b') final Node node;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'NodeCard');
      expect(admission.excluded.single.reason, contains('cyclic'));
    });

    test(
        'a DIAMOND (a type referenced by two fields, NOT cyclic) still ADMITS '
        '— the visiting set backtracks, so it is not a false cycle', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Leaf { const Leaf({required this.v}); final int v; }
          class Diamond {
            const Diamond({required this.a, required this.b});
            final Leaf a;
            final Leaf b;
          }
          @RestageWidget(name: 'DiamondCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class DiamondCard {
            const DiamondCard({required this.d});
            @RestageProperty(description: 'b') final Diamond d;
          }
        ''',
      });
      expect(admission.admitted.map((w) => w.name), ['DiamondCard']);
      expect(admission.excluded, isEmpty);
    });

    test('a canonical nested closure still ADMITS (no over-exclusion)',
        () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Inner { const Inner({required this.value}); final int value; }
          class Outer {
            const Outer({required this.title, required this.inner});
            final String title; final Inner inner;
          }
          @RestageWidget(name: 'OuterCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class OuterCard {
            const OuterCard({required this.config});
            @RestageProperty(description: 'b') final Outer config;
          }
        ''',
      });
      expect(admission.admitted.map((w) => w.name), ['OuterCard']);
      expect(admission.excluded, isEmpty);
    });
  });

  group('nameability — real discovery (compilability, not faithfulness)', () {
    test(
        'a PRIVATE enum field type is EXCLUDED-loud (the generated factory '
        'library cannot name `_Tone`)', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          enum _Tone { soft, loud }
          class Badge { const Badge({required this.tone}); final _Tone tone; }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('private'));
    });

    test(
        'a PUBLIC enum field type still ADMITS (nameable; the import closure '
        'brings its library — do NOT blanket-exclude enums)', () async {
      final admission = await _admit({
        'lib/tone.dart': 'enum Tone { soft, loud }',
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          import 'tone.dart';
          class Badge { const Badge({required this.tone}); final Tone tone; }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted.map((w) => w.name), ['BadgeCard']);
      expect(admission.excluded, isEmpty);
    });

    test('a PRIVATE nested data-class type is EXCLUDED-loud (unnameable)',
        () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class _Badge { const _Badge({required this.label}); final String label; }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final _Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.reason, contains('private'));
    });

    // H2 (reproducibility) — an OPTIONAL NON-NULLABLE field must supply its
    // ctor default on the absent branch (`<decode> ?? <default>`), reproduced
    // in the generated library. A NON-reproducible default (here a const
    // constructor — not a primitive literal or an enum constant, and the
    // generated library cannot name/qualify an arbitrary const expression)
    // cannot be faithfully emitted, so the type is EXCLUDED-loud rather than
    // silently omitted (value loss) or emitted as non-compiling code.
    test(
        'an OPTIONAL NON-NULLABLE field with a NON-reproducible default (a '
        'const constructor) is EXCLUDED-loud (never silent-omit, never '
        'uncompilable)', () async {
      final admission = await _admit({
        'lib/card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          class Inner { const Inner({this.v = 0}); final int v; }
          class Badge {
            const Badge({this.inner = const Inner()});
            final Inner inner;
          }
          @RestageWidget(name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'c')
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      expect(admission.admitted, isEmpty);
      expect(admission.excluded.single.widget.name, 'BadgeCard');
      expect(admission.excluded.single.reason, contains('default'));
    });

    // (Flutter-enum importability — a customer structured field of a
    // material/cupertino/services enum not re-exported by widgets.dart — is
    // excluded-loud by the ASYNC widgets.dart export-namespace check in the
    // WALKER, so it is exercised through the builder path in
    // customer_structured_rfw_gate_test.dart, not this discovery-level helper.)
  });

  group('duplicate-name collision — real discovery (source-inclusive keying)',
      () {
    const twoBadges = {
      'lib/a.dart': '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        class Badge { const Badge({required this.label}); final String label; }
        @RestageWidget(name: 'CardA',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'a')
        class CardA {
          const CardA({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''',
      'lib/b.dart': '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        class Badge { const Badge({required this.count}); final int count; }
        @RestageWidget(name: 'CardB',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'b')
        class CardB {
          const CardB({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''',
    };

    test(
        'both widgets are ADMITTED (a name collision is not an inherent '
        'unrenderability — source-inclusive keying disambiguates)', () async {
      final admission = await _admit(twoBadges);
      expect(admission.admitted.map((w) => w.name).toSet(), {'CardA', 'CardB'});
      expect(admission.excluded, isEmpty);
    });

    test(
        'the two same-name Badges get DISTINCT structured wire ids, and a '
        'rebuild replays cleanly (no WireIdReplayException, mints nothing)',
        () async {
      final r = await runWidgetVisitorOn(twoBadges);
      final first = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: r.widgets,
        structuredTypes: r.structuredTypes,
        slotTargets: r.slotTargets,
      );
      final badgeIds = first.catalog.structuredTypes
          .where((s) => s.name == 'Badge')
          .map((s) => s.wireId.value)
          .toSet();
      expect(badgeIds, hasLength(2), reason: 'distinct ids for the two Badges');

      // Idempotent rebuild — the seed now has two 'Badge' entries; source-keyed
      // replay must NOT throw and must mint nothing.
      final replay = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: r.widgets,
        structuredTypes: r.structuredTypes,
        slotTargets: r.slotTargets,
        existingEvents: first.newEvents,
      );
      expect(replay.newEvents, isEmpty);
    });

    test(
        'a SHARED data class imported by two widget files is discovered once '
        'per file (same sourceType twice); allocation dedupes to a single '
        'structured id and replays idempotently (no crash)', () async {
      final r = await runWidgetVisitorOn({
        'lib/model.dart': 'class Badge { const Badge({required this.label}); '
            'final String label; }',
        'lib/a.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          import 'model.dart';
          @RestageWidget(name: 'CardA',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'a')
          class CardA {
            const CardA({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
        'lib/b.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          import 'model.dart';
          @RestageWidget(name: 'CardB',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration, description: 'b')
          class CardB {
            const CardB({required this.badge});
            @RestageProperty(description: 'b') final Badge badge;
          }
        ''',
      });
      final first = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: r.widgets,
        structuredTypes: r.structuredTypes,
        slotTargets: r.slotTargets,
      );
      // A single shared type -> a single structured id (deduped by sourceType).
      expect(
        first.catalog.structuredTypes.where((s) => s.name == 'Badge'),
        hasLength(1),
      );
      final replay = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: r.widgets,
        structuredTypes: r.structuredTypes,
        slotTargets: r.slotTargets,
        existingEvents: first.newEvents,
      );
      expect(replay.newEvents, isEmpty);
    });

    test(
        'a type shared by THREE files (varying import order) dedupes to ONE '
        'id, and the deduped entry is LOSSLESS (equals a single-file '
        'discovery)', () async {
      const model = 'class Badge { const Badge({required this.label, '
          'required this.count}); final String label; final int count; }';
      String card(String name) => '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        import 'model.dart';
        @RestageWidget(name: '$name',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'x')
        class $name {
          const $name({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''';
      final shared = await runWidgetVisitorOn({
        'lib/model.dart': model,
        // Distinct file names so asset iteration order varies the discovery
        // order — first-wins must still be lossless.
        'lib/z_card.dart': card('CardZ'),
        'lib/a_card.dart': card('CardA'),
        'lib/m_card.dart': card('CardM'),
      });
      final alloc = allocateUserCatalogFromWidgets(
        package: 'apps_examples',
        widgets: shared.widgets,
        structuredTypes: shared.structuredTypes,
        slotTargets: shared.slotTargets,
      );
      final badges = alloc.catalog.structuredTypes
          .where((s) => s.name == 'Badge')
          .toList();
      expect(badges, hasLength(1), reason: 'one id for the shared type');

      // Lossless: the deduped entry carries the same fields a single-file
      // discovery of the same type would.
      final single = await runWidgetVisitorOn({
        'lib/model.dart': model,
        'lib/one.dart': card('CardOne'),
      });
      final singleBadge =
          single.structuredTypes.firstWhere((s) => s.name == 'Badge');
      expect(
        badges.single.fields.map((f) => '${f.name}:${f.type.name}').toList(),
        singleBadge.fields.map((f) => '${f.name}:${f.type.name}').toList(),
      );
    });
  });
}
