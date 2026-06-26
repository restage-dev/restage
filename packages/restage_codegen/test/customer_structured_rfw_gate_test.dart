import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A customer `@RestageWidget` whose structured (data-class) property cannot
/// yet render on the RFW path must be cleanly EXCLUDED from the RFW
/// catalog/factory build (it renders in the A2UI catalog) rather than throwing
/// — the build-safe gate. Scalar widgets in the same package are unaffected.
void main() {
  const source = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

    class Badge {
      const Badge({required this.label});
      final String label;
    }

    @RestageWidget(
      name: 'PlainButton',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.input,
      description: 'CTA.',
    )
    class PlainButton {
      const PlainButton();
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
  ''';

  group('customer-structured RFW build-safe gate', () {
    test(
        'UserCatalogBuilder excludes the structured widget, keeps the scalar '
        'one, and does not throw', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        source,
      );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'PlainButton'"),
              isNot(contains("name: 'BadgeCard'")),
              isNot(contains('WireId.unallocated')),
            ),
          ),
        },
      );
    });

    test('UserFactoryBuilder excludes the structured widget and does not throw',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        source,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('PlainButton'),
              isNot(contains('BadgeCard')),
            ),
          ),
        },
      );
    });
  });
}
