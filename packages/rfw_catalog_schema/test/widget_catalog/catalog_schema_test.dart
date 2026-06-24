import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('catalog schema types', () {
    test('WidgetLibrary.builtInLibraries lists core, material, cupertino', () {
      expect(WidgetLibrary.builtInLibraries, [
        WidgetLibrary.core,
        WidgetLibrary.material,
        WidgetLibrary.cupertino,
      ]);
    });

    test('WidgetLibrary.namespace returns dotted-namespace strings', () {
      expect(WidgetLibrary.core.namespace, 'restage.core');
      expect(WidgetLibrary.material.namespace, 'restage.material');
      expect(WidgetLibrary.cupertino.namespace, 'restage.cupertino');
    });

    test('WidgetLibrary.custom carries its namespace', () {
      const lib = WidgetLibrary.custom('acme.design_system');
      expect(lib.namespace, 'acme.design_system');
    });

    test('WidgetLibrary const-canonicalizes by namespace', () {
      const a = WidgetLibrary.custom('acme.design_system');
      const b = WidgetLibrary.custom('acme.design_system');
      expect(identical(a, b), isTrue);
      expect(a.namespace, b.namespace);
    });

    test('WidgetLibrary equality is namespace-based across construction forms',
        () {
      const viaCustom = WidgetLibrary.custom('acme.design_system');
      final fromDecode = WidgetLibrary.fromNamespace('acme.design_system');
      expect(viaCustom == fromDecode, isTrue);
      expect(viaCustom.hashCode, fromDecode.hashCode);
    });

    test('different namespaces compare unequal', () {
      const a = WidgetLibrary.custom('acme.design_system');
      const b = WidgetLibrary.custom('beta.design_system');
      expect(a == b, isFalse);
    });

    test('Map<WidgetLibrary, X> lookup works across construction forms', () {
      final map = <WidgetLibrary, String>{
        const WidgetLibrary.custom('acme.design_system'): 'acme',
      };
      final keyFromDecode = WidgetLibrary.fromNamespace('acme.design_system');
      expect(map[keyFromDecode], 'acme');
    });

    test('WidgetLibrary built-in singletons are stable across reads', () {
      expect(identical(WidgetLibrary.core, WidgetLibrary.core), isTrue);
      expect(identical(WidgetLibrary.material, WidgetLibrary.material), isTrue);
      expect(
        identical(WidgetLibrary.cupertino, WidgetLibrary.cupertino),
        isTrue,
      );
    });

    test('WidgetLibrary.fromNamespace returns built-ins for known namespaces',
        () {
      expect(WidgetLibrary.fromNamespace('restage.core'), WidgetLibrary.core);
      expect(
        WidgetLibrary.fromNamespace('restage.material'),
        WidgetLibrary.material,
      );
      expect(
        WidgetLibrary.fromNamespace('restage.cupertino'),
        WidgetLibrary.cupertino,
      );
    });

    test('WidgetLibrary.fromNamespace yields a custom library for unknown', () {
      final lib = WidgetLibrary.fromNamespace('acme.design_system');
      expect(lib.namespace, 'acme.design_system');
      expect(lib, isA<WidgetLibrary>());
      expect(WidgetLibrary.builtInByNamespace('acme.design_system'), isNull);
    });

    test('WidgetLibrary.builtInByNamespace returns null for unknown', () {
      expect(WidgetLibrary.builtInByNamespace('acme.design_system'), isNull);
    });

    test('WidgetCategory has layout, input, decoration, paywall', () {
      expect(WidgetCategory.values.toSet(), {
        WidgetCategory.layout,
        WidgetCategory.input,
        WidgetCategory.decoration,
        WidgetCategory.action,
      });
    });

    test('ChildrenSlot has none, single, list', () {
      expect(ChildrenSlot.values.toSet(), {
        ChildrenSlot.none,
        ChildrenSlot.single,
        ChildrenSlot.list,
      });
    });

    test('PropertyType covers spec property type system', () {
      expect(
        PropertyType.values.toSet().containsAll([
          PropertyType.widget,
          PropertyType.widgetList,
          PropertyType.color,
          PropertyType.length,
          PropertyType.edgeInsets,
          PropertyType.alignment,
          PropertyType.fontWeight,
          PropertyType.duration,
          PropertyType.curve,
          PropertyType.boolean,
          PropertyType.integer,
          PropertyType.real,
          PropertyType.string,
          PropertyType.event,
          PropertyType.dataReference,
          PropertyType.enumValue,
        ]),
        isTrue,
      );
    });

    test('WidgetEventName covers v0 event names referenced by widgets', () {
      expect(
        WidgetEventName.values.toSet().containsAll([
          WidgetEventName.onPressed,
          WidgetEventName.onTap,
          WidgetEventName.onChanged,
          WidgetEventName.onEnd,
        ]),
        isTrue,
      );
    });
  });
}
