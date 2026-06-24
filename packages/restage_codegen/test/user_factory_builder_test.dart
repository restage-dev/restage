import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('UserFactoryBuilder', () {
    test('emits user_factories.g.dart when @RestageWidget classes are found',
        () async {
      const widgetSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeBadge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.action,
          description: 'Promo badge.',
        )
        class AcmeBadge {
          const AcmeBadge({required this.label});
          @RestageProperty(description: 'Visible label.', required: true)
          final String label;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
        widgetSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_badge.dart': widgetSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf([
              contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("import 'package:flutter/widgets.dart'"),
              contains(
                "import 'package:restage/restage.dart'",
              ),
              // Generated file does not import rfw directly — the SDK
              // re-exports DataSource / ArgumentDecoders /
              // LocalWidgetBuilder, so the customer package isn't
              // required to depend on rfw.
              isNot(contains("import 'package:rfw/rfw.dart'")),
              contains(
                "import 'package:apps_examples/widgets/acme_badge.dart'",
              ),
              contains('void registerRestageCustomerWidgets()'),
              contains("WidgetLibrary.custom('acme.design_system')"),
              contains(
                "RestageWidgetFactory(name: 'AcmeBadge', "
                'builder: _buildAcmeBadge)',
              ),
              contains(
                'Widget _buildAcmeBadge(BuildContext context, '
                'DataSource source)',
              ),
            ]),
          ),
        },
      );
    });

    test('does not emit user_factories.g.dart when no @RestageWidget classes',
        () async {
      const plainSource = '''
        class Plain { const Plain(); }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/plain.dart'),
        plainSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/plain.dart': plainSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });
  });
}
