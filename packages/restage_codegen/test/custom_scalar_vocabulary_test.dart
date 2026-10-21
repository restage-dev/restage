import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A custom `@RestageWidget` with enum and scalar-list properties builds the
/// RFW custom catalog and factories and the A2UI catalog from one source.
void main() {
  // A custom widget whose only property is a CUSTOM enum — the class where
  // the A2UI path accepts it (EnumNode); the RFW path historically
  // dropped the enum identity and `encodeCatalog` rejected it.
  const enumSource = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    @RestageLibrary(
      library: WidgetLibrary.custom('acme.widgets'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;

    enum Tone { calm, loud }

    @RestageWidget(
      name: 'Chip',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A toned chip.',
    )
    class Chip {
      const Chip({required this.tone});
      @RestageProperty(description: 'The chip tone.')
      final Tone tone;
    }
  ''';

  // A custom widget with one property per scalar-list kind.
  const scalarListSource = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    @RestageLibrary(
      library: WidgetLibrary.custom('acme.widgets'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;

    @RestageWidget(
      name: 'Bars',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A bar chart.',
    )
    class Bars {
      const Bars({
        required this.labels,
        required this.flags,
        required this.values,
        required this.weights,
        required this.ratios,
      });
      @RestageProperty(description: 'The bar labels.')
      final List<String> labels;
      @RestageProperty(description: 'Which bars are highlighted.')
      final List<bool> flags;
      @RestageProperty(description: 'The bar values.')
      final List<int> values;
      @RestageProperty(description: 'The bar weights.')
      final List<double> weights;
      @RestageProperty(description: 'The bar ratios.')
      final List<num> ratios;
    }
  ''';

  Future<TestBuilderResult> runBuilder(
    Builder builder,
    String source, {
    String assetPath = 'lib/widgets.dart',
  }) async {
    final rw =
        await readerWriterWithFilesystemSources(rootPackage: 'restage_codegen');
    rw.testing.writeString(AssetId('apps_examples', assetPath), source);
    return testBuilder(
      builder,
      {'apps_examples|$assetPath': source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      flattenOutput: true,
    );
  }

  group('custom enum property — dual-target parity', () {
    test('the RFW custom catalog.json builds green and carries enum identity',
        () async {
      final result = await runBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue,
          reason: 'RFW catalog.json build must succeed for a custom enum');
      final json = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
      );
      final catalog = decodeCatalog(json);
      final chip = catalog.widgets.firstWhere((w) => w.name == 'Chip');
      final tone = chip.properties.firstWhere((p) => p.name == 'tone');
      expect(tone.type, PropertyType.enumValue);
      final hasIdentity =
          (tone.enumType != null && tone.enumType!.isNotEmpty) ||
              tone.valueShape is EnumShape;
      expect(hasIdentity, isTrue,
          reason: 'the enum property must carry enumType or an EnumShape');
    });

    test('the RFW custom factories build green and name the custom enum',
        () async {
      final result = await runBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue,
          reason: 'RFW factory build must succeed for a custom enum');
      final dart = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );
      expect(dart, contains('enumByName<'));
      expect(dart, contains('Tone'));
    });

    test('the A2UI custom catalog still builds green (parity, no regression)',
        () async {
      final result = await runBuilder(
        UserA2uiCatalogBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue);
    });
  });

  group('custom scalar-list properties on the RFW target', () {
    test('the catalog carries each scalar-list type', () async {
      final result = await runBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        scalarListSource,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final catalog = decodeCatalog(
        result.readerWriter.testing.readString(
          AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
        ),
      );
      final bars = catalog.widgets.singleWhere((w) => w.name == 'Bars');
      expect(
        {
          for (final property in bars.properties)
            if (property.name != 'analyticsId') property.name: property.type,
        },
        {
          'labels': PropertyType.stringList,
          'flags': PropertyType.booleanList,
          'values': PropertyType.integerList,
          'weights': PropertyType.realList,
          'ratios': PropertyType.realList,
        },
      );
    });

    test('the factories decode each scalar list', () async {
      final result = await runBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        scalarListSource,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final dart = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );
      expect(
        dart,
        allOf(
          contains('RestageDecoders.stringList('),
          contains('RestageDecoders.booleanList('),
          contains('RestageDecoders.integerList('),
          contains('RestageDecoders.realList('),
        ),
      );
    });
  });
}
