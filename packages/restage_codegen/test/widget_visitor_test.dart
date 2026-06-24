import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('visitRestageWidgets', () {
    test('finds a single @RestageWidget class with no properties', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo();
          }
        ''',
      });

      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      final w = result.widgets.single;
      expect(w.name, 'Foo');
      expect(w.library.namespace, 'acme.design_system');
      expect(w.category, WidgetCategory.layout);
      expect(w.description, 'A foo widget.');
      expect(w.childrenSlot, ChildrenSlot.none);
      expect(w.fires, isEmpty);
    });

    test('skips classes without the annotation', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          class Plain { const Plain(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('emits missingAnnotationField when description is missing', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: null,
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.missingAnnotationField);
    });

    test('captures @RestageProperty fields with description and required',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Widget {}

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
            fires: [WidgetEventName.onPressed],
            childrenSlot: ChildrenSlot.single,
          )
          class Btn {
            const Btn({required this.child, this.onPressed});
            @RestageProperty(description: 'Label', required: true)
            final Widget child;
            @RestageProperty(description: 'Tap')
            final void Function()? onPressed;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      final w = result.widgets.single;
      expect(w.fires, [WidgetEventName.onPressed]);
      expect(w.childrenSlot, ChildrenSlot.single);
      expect(w.properties, hasLength(2));
      final child = w.properties.firstWhere((p) => p.name == 'child');
      expect(child.required, isTrue);
      expect(child.type, PropertyType.widget);
      final tap = w.properties.firstWhere((p) => p.name == 'onPressed');
      expect(tap.required, isFalse);
      expect(tap.type, PropertyType.event);
    });

    test('emits unsupportedPropertyType for an unknown static type', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Mystery {}

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo {
            const Foo({required this.weird});
            @RestageProperty(description: 'Weird thing.')
            final Mystery weird;
          }
        ''',
      });

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unsupportedPropertyType),
      );
      // The widget itself still produces an entry — only the bad property
      // is dropped — so a single typo doesn't hide the whole widget from
      // the catalog.
      expect(result.widgets, hasLength(1));
      expect(result.widgets.single.properties, isEmpty);
    });

    test('synthesizes flutterType from the class library URI + class name',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets.single.flutterType, endsWith('foo.dart#Foo'));
    });

    test(
        'emits duplicateWidgetName when two @RestageWidget classes share a '
        'name in the same library', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Same',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'one',
          )
          class A { const A(); }

          @RestageWidget(
            name: 'Same',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'two',
          )
          class B { const B(); }
        ''',
      });

      final issue = result.issues
          .firstWhere((i) => i.code == IssueCode.duplicateWidgetName);
      expect(issue.message, contains('A'));
      expect(issue.message, contains('B'));
      expect(issue.message, contains('acme.design_system'));
      expect(issue.message, contains('Same'));
    });

    test('rejects abstract @RestageWidget classes', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'AbstractWidget',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'never instantiable',
          )
          abstract class AbstractWidget {}
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.invalidWidgetClass),
      );
    });

    test('rejects private @RestageWidget classes', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Private',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'private to this file',
          )
          class _Private { const _Private(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.invalidWidgetClass),
      );
    });

    test('const-eval failure produces an actionable diagnostic', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: null,
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.widgets, isEmpty);
      final issue = result.issues
          .firstWhere((i) => i.code == IssueCode.missingAnnotationField);
      expect(issue.message, contains('Foo'));
      expect(issue.message.toLowerCase(), contains('compile-time constant'));
    });

    test('extracts deprecatedSince marker', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.layout,
            description: 'A foo widget.',
            deprecatedSince: '2.0.0',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.widgets.single.deprecatedSince, '2.0.0');
    });

    test('decodes literal defaultValue and defaultBrandToken on properties',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
          )
          class Btn {
            const Btn({this.label = 'Buy', this.color, this.padding = 12});
            @RestageProperty(description: 'Label.', defaultValue: 'Buy')
            final String label;
            @RestageProperty(description: 'Color.', defaultBrandToken: 'primary')
            final String? color;
            @RestageProperty(description: 'Padding.', defaultValue: 12)
            final int padding;
          }
        ''',
      });
      expect(result.issues, isEmpty);
      final byName = {
        for (final p in result.widgets.single.properties) p.name: p,
      };
      expect(byName['label']!.defaultValue, 'Buy');
      expect(byName['color']!.defaultBrandToken, 'primary');
      expect(byName['padding']!.defaultValue, 12);
    });

    test('decodes @RestageProperty defaultSource', () async {
      final result = await runWidgetVisitorOn({
        'lib/btn.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Btn',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'CTA.',
          )
          class Btn {
            const Btn({this.label, this.tokenColor});
            @RestageProperty(
              description: 'Label.',
              defaultSource: LiteralDefault('Buy'),
            )
            final String? label;
            @RestageProperty(
              description: 'Token color.',
              defaultSource: TokenRefDefault(
                WireIdRef(
                  library: 'acme.design_system',
                  wireId: WireId.unallocatedDesignToken,
                ),
              ),
            )
            final String? tokenColor;
          }
        ''',
      });

      expect(result.issues, isEmpty);
      final byName = {
        for (final p in result.widgets.single.properties) p.name: p,
      };
      expect(byName['label']!.defaultSource, const LiteralDefault('Buy'));
      expect(byName['label']!.defaultValue, 'Buy');
      expect(
        byName['tokenColor']!.defaultSource,
        const TokenRefDefault(
          WireIdRef(
            library: 'acme.design_system',
            wireId: WireId.unallocatedDesignToken,
          ),
        ),
      );
    });

    test(
        'typed singleton WidgetLibrary.core resolves to its built-in '
        'namespace', () async {
      final result = await runWidgetVisitorOn({
        'lib/foo.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          @RestageWidget(
            name: 'Foo',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'A foo widget.',
          )
          class Foo { const Foo(); }
        ''',
      });
      expect(result.issues, isEmpty);
      expect(result.widgets.single.library.namespace, 'restage.core');
    });
  });
}
