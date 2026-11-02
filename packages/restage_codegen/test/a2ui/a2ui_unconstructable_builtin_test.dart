import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Built-in widgets whose required constructor argument the built-in catalog
/// cannot provide are left out of the A2UI emit, so the merged built-in catalog
/// compiles. A same-named custom widget is not affected.
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

    test('a same-named CUSTOM widget is NOT scoped out (built-in gated)', () {
      const customLib = WidgetLibrary.custom('acme.widgets');
      final catalog = catalogWith(
        [
          entry(
            name: 'FilterChip',
            library: customLib,
            category: WidgetCategory.input,
            properties: [prop('label', PropertyType.string)],
          ),
        ],
        library: customLib,
      );

      final plan = classifyA2uiCatalogDart(catalog);
      expect(plan.widgets.any((w) => w.entry.name == 'FilterChip'), isTrue);
    });
  });
}
