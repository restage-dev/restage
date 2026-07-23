import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A customer `@RestageWidget` with an enum property must
/// build the RFW customer catalog + factories AND the A2UI catalog from one
/// source (dual-target parity); an A2UI-admissible scalar-list property that the
/// RFW path cannot carry must fail LOUD with a target-boundary diagnostic that
/// names the widget + property and the remedies.
void main() {
  // A customer widget whose only property is a CUSTOMER enum — the class where
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

  // A customer widget with a direct List<int> property — supported on the A2UI
  // target but not carried by the RFW customer catalog vocabulary.
  const intListSource = '''
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
      const Bars({required this.values});
      @RestageProperty(description: 'The bar values.')
      final List<int> values;
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

  group('customer enum property — dual-target parity', () {
    test('the RFW customer catalog.json builds green and carries enum identity',
        () async {
      final result = await runBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue,
          reason: 'RFW catalog.json build must succeed for a customer enum');
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

    test('the RFW customer factories build green and name the customer enum',
        () async {
      final result = await runBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue,
          reason: 'RFW factory build must succeed for a customer enum');
      final dart = result.readerWriter.testing.readString(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      );
      expect(dart, contains('enumValue<'));
      expect(dart, contains('Tone'));
    });

    test('the A2UI customer catalog still builds green (parity, no regression)',
        () async {
      final result = await runBuilder(
        const UserA2uiCatalogBuilder(BuilderOptions.empty),
        enumSource,
      );
      expect(result.succeeded, isTrue);
    });
  });

  group('RFW scalar-list rejection — target-boundary diagnostic', () {
    test(
        'the RFW rejection of an A2UI-admissible scalar list names the widget, '
        'property, target boundary, and remedies', () async {
      final visited =
          await runWidgetVisitorOn({'lib/widgets.dart': intListSource});
      final rejection = visited.issues.firstWhere(
        (i) => i.code == IssueCode.unsupportedPropertyType,
        orElse: () =>
            fail('expected an unsupportedPropertyType issue for List<int>'),
      );
      final message = rejection.message;
      // Names the widget + property.
      expect(message, contains('Bars.values'));
      // States the target boundary: supported on A2UI, not carried by RFW.
      expect(message, contains('A2UI'));
      expect(message, contains('RFW'));
      // Names a remedy the customer can act on.
      expect(message.toLowerCase(), contains('restrict'));
    });

    test('the RFW build still fails loud on the scalar-list property',
        () async {
      final result = await runBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        intListSource,
      );
      expect(result.succeeded, isFalse,
          reason: 'fail-loud semantics on the RFW path are unchanged');
    });
  });
}
