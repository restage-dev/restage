import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('customer structured discovery — R-1.1 nested data class', () {
    test(
        'a @RestageProperty typed as a customer data class lowers to '
        'PropertyType.structured + a StructuredEntry', () async {
      final result = await runWidgetVisitorOn({
        'lib/badge_card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Badge {
            const Badge({required this.label, required this.count});
            final String label;
            final int count;
          }

          @RestageWidget(
            name: 'BadgeCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card that renders a badge.',
          )
          class BadgeCard {
            const BadgeCard({required this.badge});
            @RestageProperty(description: 'The badge to render.')
            final Badge badge;
          }
        ''',
      });

      // No unsupported-type diagnostic — the data class is recognised.
      expect(
        result.issues.where((i) => i.code == IssueCode.unsupportedPropertyType),
        isEmpty,
        reason: 'a customer data class must be recognised, not rejected',
      );

      // The property lowers to a structured reference.
      final widget = result.widgets.single;
      final badge = widget.properties.firstWhere((p) => p.name == 'badge');
      expect(badge.type, PropertyType.structured);
      expect(badge.structuredRef, isNotNull);
      expect(badge.structuredRef!.library, 'acme.design_system');
      expect(badge.structuredRef!.wireId.isUnallocated, isTrue);

      // The catalog carries the discovered structured type.
      final entry = result.structuredTypes.firstWhere(
        (e) => e.name == 'Badge',
        orElse: () => throw StateError(
          'expected a StructuredEntry named Badge, got '
          '${result.structuredTypes.map((e) => e.name).toList()}',
        ),
      );
      expect(entry.library.namespace, 'acme.design_system');
      expect(entry.wireId.isUnallocated, isTrue);
      expect(entry.sourceType, endsWith('badge_card.dart#Badge'));

      final fieldNames = entry.fields.map((f) => f.name).toList();
      expect(fieldNames, containsAll(<String>['label', 'count']));
      final label = entry.fields.firstWhere((f) => f.name == 'label');
      final count = entry.fields.firstWhere((f) => f.name == 'count');
      expect(label.valueShape, isA<ScalarShape>());
      expect(
        (label.valueShape! as ScalarShape).propertyType,
        PropertyType.string,
      );
      expect(
        (count.valueShape! as ScalarShape).propertyType,
        PropertyType.integer,
      );
    });
  });

  group('customer structured discovery — R-1.2 transitive closure', () {
    test(
        'a data class that nests another data class materialises BOTH '
        '(the nested type is not warn+dropped)', () async {
      final result = await runWidgetVisitorOn({
        'lib/profile_card.dart': '''
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
            name: 'ProfileCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with nested config.',
          )
          class ProfileCard {
            const ProfileCard({required this.config});
            @RestageProperty(description: 'The nested config.')
            final Outer config;
          }
        ''',
      });

      expect(
        result.issues.where((i) => i.code == IssueCode.unsupportedPropertyType),
        isEmpty,
      );

      // Both the directly-referenced type AND its nested type are materialised.
      final names = result.structuredTypes.map((e) => e.name).toSet();
      expect(
        names,
        containsAll(<String>['Outer', 'Inner']),
        reason: 'the nested data class must be in the closure, not dropped',
      );

      // Outer carries its nested field as a structured reference (not dropped).
      final outer = result.structuredTypes.firstWhere((e) => e.name == 'Outer');
      final innerField = outer.fields.firstWhere(
        (f) => f.name == 'inner',
        orElse: () => throw StateError(
          'Outer.inner was dropped; fields: '
          '${outer.fields.map((f) => f.name).toList()}',
        ),
      );
      expect(innerField.type, PropertyType.structured);
      expect(innerField.structuredRef, isNotNull);

      // Inner is fully materialised (its own scalar field is present), not a
      // shallow empty stub.
      final inner = result.structuredTypes.firstWhere((e) => e.name == 'Inner');
      final valueField = inner.fields.firstWhere((f) => f.name == 'value');
      expect(
        (valueField.valueShape! as ScalarShape).propertyType,
        PropertyType.integer,
      );
    });

    test(
        'a List<scalar> field inside a structured type is carried (not '
        'dropped) — the parity-clean scalar-list case', () async {
      final result = await runWidgetVisitorOn({
        'lib/tag_card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class TagSet {
            const TagSet({required this.title, required this.tags});
            final String title;
            final List<String> tags;
          }

          @RestageWidget(
            name: 'TagCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with a tag set.',
          )
          class TagCard {
            const TagCard({required this.tagSet});
            @RestageProperty(description: 'The tag set.')
            final TagSet tagSet;
          }
        ''',
      });

      expect(
        result.issues.where((i) => i.code == IssueCode.unsupportedPropertyType),
        isEmpty,
      );
      final tagSet =
          result.structuredTypes.firstWhere((e) => e.name == 'TagSet');
      final tags = tagSet.fields.firstWhere(
        (f) => f.name == 'tags',
        orElse: () => throw StateError(
          'TagSet.tags (List<String>) was dropped; fields: '
          '${tagSet.fields.map((f) => f.name).toList()}',
        ),
      );
      expect(tags.valueShape, isA<ListShape>());
    });

    test(
        "a structured property required by the widget's constructor is marked "
        'required even when @RestageProperty omits it', () async {
      final result = await runWidgetVisitorOn({
        'lib/cfg_card.dart': '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          class Config {
            const Config({required this.label});
            final String label;
          }

          @RestageWidget(
            name: 'CfgCard',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.decoration,
            description: 'A card with required config.',
          )
          class CfgCard {
            const CfgCard({required this.config});
            @RestageProperty(description: 'The config.')
            final Config config;
          }
        ''',
      });

      final config = result.widgets.single.properties
          .firstWhere((p) => p.name == 'config');
      expect(config.type, PropertyType.structured);
      // The constructor requires it, so the catalog marks it required — the
      // rich-field emit needs this or it omits the field and the generated
      // reconstruction can't supply the required constructor argument.
      expect(config.required, isTrue);
    });
  });
}
