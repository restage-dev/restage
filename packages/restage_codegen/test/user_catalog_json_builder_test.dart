import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:restage_codegen/src/library_contract.dart';
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

  const namespace = 'catalog_state_visibility';
  const statePaths = {
    'widget IDs': '.restage/wire-ids.events.jsonl',
    'legacy widget IDs': 'wire_ids.events.jsonl',
    'library contract': '.restage/library-contracts/$namespace/v1.json',
  };
  for (final MapEntry(key: state, value: path) in statePaths.entries) {
    test('dependency catalog requires exposed $state state', () async {
      const package = 'restage_codegen';
      final root = (await restagePackageRoot(package))!;
      for (final fixturePath in statePaths.values) {
        final leftover = File.fromUri(root.resolve(fixturePath));
        if (leftover.existsSync()) {
          leftover.deleteSync();
        }
      }
      final fixture = source.replaceAll('acme.design_system', namespace);
      final file = File.fromUri(root.resolve(path));
      final logs = <String>[];
      Future<({bool succeeded, Catalog? catalog})> build({
        bool isRoot = false,
        bool expose = false,
      }) async {
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: package,
        );
        readerWriter.testing.writeString(
          AssetId(package, 'lib/visibility.dart'),
          fixture,
        );
        if (expose) {
          readerWriter.testing
              .writeString(AssetId(package, path), file.readAsStringSync());
        }
        logs.clear();
        final result = await testBuilder(
          UserCatalogJsonBuilder(BuilderOptions(const {}, isRoot: isRoot)),
          {
            '$package|lib/visibility.dart': fixture,
            if (expose) '$package|$path': file.readAsStringSync(),
          },
          rootPackage: package,
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.toString()),
        );
        return (
          succeeded: result.succeeded,
          catalog: result.succeeded
              ? decodeCatalog(readerWriter.testing.readString(
                  AssetId(package, 'lib/src/widget_catalog/catalog.json'),
                ))
              : null,
        );
      }

      final baseline = await build();
      expect(baseline.succeeded, isTrue, reason: logs.join('\n'));
      final contents = state == 'library contract'
          ? LibraryContractSnapshot.of(
              baseline.catalog!,
              WidgetLibrary.custom(namespace),
            )!
              .encode()
          : '{"kind":"alloc","type":"widget","id":"w0042","name":"Badge",'
              '"source":"package:$package/visibility.dart#Badge",'
              '"at":"2026-10-09T00:00:00Z","by":"test"}\n';
      file.parent.createSync(recursive: true);
      file.createSync(exclusive: true);
      try {
        file.writeAsStringSync(contents);
        final hidden = await build();
        expect(hidden.succeeded, isFalse);
        expect(
            logs.join('\n'),
            allOf([
              contains('$package must expose $path as a build input.'),
              contains('additional_public_assets: [.restage/**]'),
              contains('If the target restricts sources, '
                  'include `.restage/**` there too.'),
              if (state == 'legacy widget IDs')
                contains('Also include `wire_ids.events.jsonl`'),
            ]));
        for (final isRoot in [false, true]) {
          final visible = await build(isRoot: isRoot, expose: !isRoot);
          expect(visible.succeeded, isTrue, reason: logs.join('\n'));
          if (state != 'library contract') {
            expect(visible.catalog!.widgets.single.wireId.value, 'w0042');
          }
        }
      } finally {
        file.deleteSync();
        if (state == 'library contract') file.parent.deleteSync();
      }
    });
  }

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
        'apps_examples|lib/src/widget_catalog/catalog.json': decodedMatches(
          predicate<String>(
            (s) {
              captured = s;
              return true;
            },
          ),
        ),
        'apps_examples|lib/src/widget_catalog/app_widget_factories.json':
            anything,
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
    final analyticsId = badge.properties.singleWhere(
      (property) => property.name == kAnalyticsIdPropertyName,
    );
    expect(analyticsId.type, PropertyType.string);
    expect(analyticsId.synthetic, kAnalyticsIdSyntheticStrategy);
    expect(analyticsId.wireId.isUnallocated, isFalse);
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
        'apps_examples|lib/user_catalog.g.dart': decodedMatches(
          predicate<String>(
            (s) {
              dartSource = s;
              return true;
            },
          ),
        ),
      },
      onLog: (_) {},
    );
    expect(dartSource, contains(badge.wireId.value));
    expect(dartSource, contains("name: '$kAnalyticsIdPropertyName'"));
    expect(
      dartSource,
      contains("synthetic: '$kAnalyticsIdSyntheticStrategy'"),
    );
    for (final p in badge.properties) {
      expect(
        dartSource,
        contains(p.wireId.value),
        reason: 'property ${p.name} wire id must match user_catalog.g.dart',
      );
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
