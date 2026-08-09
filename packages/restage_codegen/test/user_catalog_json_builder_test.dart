import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // A scalar-prop custom widget (no data-class props). Whether a widget is
  // inlineable or app-backed is irrelevant to catalog emission — every
  // @RestageWidget lands in the catalog.
  const source = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    @RestageLibrary(
      library: WidgetLibrary.custom('acme.design_system'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;
    @RestageWidget(name: 'Badge',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.decoration, description: 'b')
    class Badge {
      const Badge({required this.label, this.count = 0});
      @RestageProperty(description: 'l') final String label;
      @RestageProperty(description: 'c') final int count;
    }
  ''';

  Future<Catalog> runJsonBuilder([String? src]) async {
    final s = src ?? source;
    final rw =
        await readerWriterWithFilesystemSources(rootPackage: 'restage_codegen');
    rw.testing.writeString(AssetId('apps_examples', 'lib/widgets.dart'), s);
    String? captured;
    await testBuilder(
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      {'apps_examples|lib/widgets.dart': s},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: {
        'apps_examples|lib/src/widget_catalog/catalog.json':
            decodedMatches(predicate<String>((s) {
          captured = s;
          return true;
        })),
      },
      onLog: (_) {},
    );
    expect(captured, isNotNull);
    return requireNativeCatalog(decodeCatalog(captured!));
  }

  test(
      'UserCatalogJsonBuilder emits lib/src/widget_catalog/catalog.json with '
      'allocated wire IDs', () async {
    final catalog = await runJsonBuilder();
    final badge = catalog.widgets.firstWhere((w) => w.name == 'Badge');
    expect(badge.library.namespace, 'acme.design_system');
    expect(badge.wireId.isUnallocated, isFalse);
    for (final p in badge.properties) {
      expect(p.wireId.isUnallocated, isFalse);
    }
  });

  test(
      'the emitted catalog.json carries the SAME widget/property wire IDs as '
      'user_catalog.g.dart (one deterministic allocation)', () async {
    final catalog = await runJsonBuilder();
    final badge = catalog.widgets.firstWhere((w) => w.name == 'Badge');

    final rw =
        await readerWriterWithFilesystemSources(rootPackage: 'restage_codegen');
    rw.testing
        .writeString(AssetId('apps_examples', 'lib/widgets.dart'), source);
    String? dartSource;
    await testBuilder(
      const UserCatalogBuilder(BuilderOptions.empty),
      {'apps_examples|lib/widgets.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: {
        'apps_examples|lib/user_catalog.g.dart':
            decodedMatches(predicate<String>((s) {
          dartSource = s;
          return true;
        })),
      },
      onLog: (_) {},
    );
    expect(dartSource, contains(badge.wireId.value));
    for (final p in badge.properties) {
      expect(dartSource, contains(p.wireId.value),
          reason: 'property ${p.name} wire id must match user_catalog.g.dart');
    }
  });

  test(
    'the emitted catalog.json records an optional input this target could not '
    'decode',
    () async {
      const undecodableSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;

        class Mystery {}

        @RestageWidget(name: 'Badge',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'b')
        class Badge {
          const Badge({required this.label, this.weird});
          @RestageProperty(description: 'l') final String label;
          @RestageProperty(description: 'w') final Mystery? weird;
        }
      ''';

      final catalog = await runJsonBuilder(undecodableSource);
      final badge = catalog.widgets.singleWhere(
        (widget) => widget.name == 'Badge',
      );

      // The report makes "what did this target drop" a query, not a log hunt.
      final propertyNames = badge.properties.map((property) => property.name);
      expect(propertyNames, contains('label'));
      expect(propertyNames, isNot(contains('weird')));
      expect(catalog.exclusions, hasLength(1));
      final exclusion = catalog.exclusions.single;
      expect(exclusion.widget, 'Badge');
      expect(exclusion.property, 'weird');
      expect(exclusion.target, 'rfw');
      expect(exclusion.reason, contains('Mystery'));
      expect(exclusion.location, contains('Badge.weird'));
    },
  );

  test('exclusions are emitted in a deterministic order', () async {
    const twoSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      @RestageLibrary(
        library: WidgetLibrary.custom('acme.design_system'),
        capabilityVersion: 1,
      )
      const restageLibrary = 0;

      class Mystery {}

      @RestageWidget(name: 'Zebra',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'z')
      class Zebra {
        const Zebra({required this.label, this.zed});
        @RestageProperty(description: 'l') final String label;
        @RestageProperty(description: 'z') final Mystery? zed;
      }

      @RestageWidget(name: 'Alpha',
        library: WidgetLibrary.custom('acme.design_system'),
        category: WidgetCategory.decoration, description: 'a')
      class Alpha {
        const Alpha({required this.label, this.ay});
        @RestageProperty(description: 'l') final String label;
        @RestageProperty(description: 'a') final Mystery? ay;
      }
    ''';

    final catalog = await runJsonBuilder(twoSource);

    // Byte-stable regeneration requires report order, not asset-walk order.
    expect(
      catalog.exclusions
          .map((exclusion) => '${exclusion.widget}.${exclusion.property}')
          .toList(),
      ['Alpha.ay', 'Zebra.zed'],
    );
  });
}
