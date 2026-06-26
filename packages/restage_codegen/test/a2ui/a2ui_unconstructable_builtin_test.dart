import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A contained interim guard: a small set of built-in widgets cannot be emitted
/// to a compilable A2UI catalog today — the built-in catalog marks their
/// required Flutter constructor argument (a required callback, or a decomposed
/// style/decoration) as not providable, so the merged built-in catalog would
/// not compile. They are scoped OUT of the A2UI emit (a documented gap) so the
/// shipped merged builder produces a compilable catalog; the proper fix (the 11
/// emit correctly) is tracked separately. A same-named CUSTOMER widget is not
/// affected — the guard is gated on a built-in library.
void main() {
  group('A2UI emit — unconstructable built-in scope-out', () {
    test('a known-unconstructable built-in (FilterChip) is scoped out', () {
      final catalog = catalogWith(
        [
          entry(
            name: 'FilterChip',
            library: WidgetLibrary.material,
            category: WidgetCategory.input,
            properties: [prop('onSelected', PropertyType.event)],
          ),
        ],
        library: WidgetLibrary.material,
      );

      final plan = classifyA2uiCatalogDart(catalog);
      expect(
        plan.widgets.any((w) => w.entry.name == 'FilterChip'),
        isFalse,
        reason: 'an unconstructable built-in must not be emitted',
      );
    });

    test('a structured-param built-in (DefaultTextStyle) is scoped out', () {
      final catalog = catalogWith(
        [
          entry(
            name: 'DefaultTextStyle',
            childrenSlot: ChildrenSlot.single,
            properties: [prop('child', PropertyType.widget, required: true)],
          ),
        ],
      );

      final plan = classifyA2uiCatalogDart(catalog);
      expect(
        plan.widgets.any((w) => w.entry.name == 'DefaultTextStyle'),
        isFalse,
      );
    });

    test('a same-named CUSTOMER widget is NOT scoped out (built-in gated)', () {
      const customerLib = WidgetLibrary.custom('acme.widgets');
      final catalog = catalogWith(
        [
          entry(
            name: 'FilterChip',
            library: customerLib,
            category: WidgetCategory.input,
            properties: [prop('label', PropertyType.string)],
          ),
        ],
        library: customerLib,
      );

      final plan = classifyA2uiCatalogDart(catalog);
      expect(plan.widgets.any((w) => w.entry.name == 'FilterChip'), isTrue);
    });
  });
}
