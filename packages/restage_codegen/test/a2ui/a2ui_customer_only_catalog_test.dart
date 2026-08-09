import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The customer-only invariant proof: even when built-in catalog assets are
/// present in the build graph, the generated A2UI catalog + stamp carry ONLY
/// the customer `@RestageWidget` output — no built-in widget, library,
/// structured type, union, token, or compat rule.
void main() {
  test(
      'the A2UI builder emits a customer-only catalog even when built-in '
      'catalog assets (real + a planted sentinel) are in the build graph',
      () async {
    // One customer widget — a scalar-only gauge in a custom library.
    const customerSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageLibrary(
        library: WidgetLibrary.custom('acme.widgets'),
        capabilityVersion: 1,
      )
      const restageLibrary = 0;

      @RestageWidget(
        name: 'Gauge',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'a customer gauge',
      )
      class Gauge {
        const Gauge({required this.value});
        @RestageProperty(description: 'the reading')
        final double value;
      }
    ''';

    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
    );

    // PLANT a sentinel built-in-namespace catalog asset. Clone the real core
    // catalog and append a freshly allocated widget-kind wire ID, so a
    // deterministically-named built-in widget is present to (attempt to) leak.
    final coreCatalogAsset =
        AssetId('restage_core', 'lib/src/widget_catalog/catalog.json');
    final realCoreCatalog = decodeCatalog(
      readerWriter.testing.readString(coreCatalogAsset),
    );
    var maxCoreWidgetSequence = 0;
    for (final widget in realCoreCatalog.widgets) {
      if (widget.library == WidgetLibrary.core &&
          widget.wireId.sequence > maxCoreWidgetSequence) {
        maxCoreWidgetSequence = widget.wireId.sequence;
      }
    }
    final sentinelWireId = WireId(
      'w${(maxCoreWidgetSequence + 1).toString().padLeft(4, '0')}',
    );
    final sentinelCoreCatalog = Catalog(
      schemaVersion: realCoreCatalog.schemaVersion,
      generatedAt: realCoreCatalog.generatedAt,
      libraries: realCoreCatalog.libraries,
      flutterVersion: realCoreCatalog.flutterVersion,
      widgets: [
        ...realCoreCatalog.widgets,
        WidgetEntry(
          wireId: sentinelWireId,
          name: 'LeakSentinelBuiltIn',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: 'built-in leak sentinel',
          flutterType:
              'package:flutter/src/widgets/leak_sentinel.dart#LeakSentinelBuiltIn',
          childrenSlot: ChildrenSlot.none,
          properties: const [],
        ),
      ],
      structuredTypes: realCoreCatalog.structuredTypes,
      unions: realCoreCatalog.unions,
      designTokens: realCoreCatalog.designTokens,
      compatRules: realCoreCatalog.compatRules,
    );
    readerWriter.testing.writeString(
      coreCatalogAsset,
      encodeCatalog(sentinelCoreCatalog),
    );

    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/gauge.dart'),
      customerSource,
    );

    final result = await testBuilder(
      const UserA2uiCatalogBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/gauge.dart': customerSource},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);

    final dart = String.fromCharCodes(
      result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.g.dart',
        ),
      ),
    );
    final stampJson = String.fromCharCodes(
      result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.a2ui.json',
        ),
      ),
    );
    final stamp = jsonDecode(stampJson) as Map<String, Object?>;

    // Whitelist: components + libraries are EXACTLY the customer set.
    final a2uiCatalog = stamp['a2uiCatalog']! as Map;
    final components = (a2uiCatalog['components']! as Map).keys.toSet();
    expect(components, {'Gauge'});
    final restageCapability = stamp['restageCapability']! as Map;
    final libraries = {
      for (final lib in restageCapability['availableLibraries']! as List)
        (lib as Map)['namespace'],
    };
    expect(libraries, {'acme.widgets'});

    // Blacklist: no built-in namespace, no planted sentinel, in either output.
    for (final leak in const [
      'restage.core',
      'restage.material',
      'restage.cupertino',
      'LeakSentinelBuiltIn',
    ]) {
      expect(dart.contains(leak), isFalse, reason: '.g.dart leaked $leak');
      expect(
        stampJson.contains(leak),
        isFalse,
        reason: '.a2ui.json leaked $leak',
      );
    }
  });

  test('records A2UI auto-exclusions in the generated Dart artifact', () async {
    const customerSource = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageLibrary(
        library: WidgetLibrary.custom('acme.widgets'),
        capabilityVersion: 1,
      )
      const restageLibrary = 0;

      @RestageWidget(
        name: 'Gauge',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'a customer gauge',
      )
      class Gauge {
        const Gauge({required this.value, this.hostState});
        @RestageProperty(description: 'the reading')
        final double value;
        /// State supplied only by the host application.
        final Object? hostState;
      }
    ''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/gauge.dart'),
      customerSource,
    );

    final result = await testBuilder(
      const UserA2uiCatalogBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/gauge.dart': customerSource},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);

    final dart = String.fromCharCodes(
      result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.g.dart',
        ),
      ),
    );
    expect(dart, contains(r'$RestageExclusions'));
    expect(dart, contains('"widget": "Gauge"'));
    expect(dart, contains('"property": "hostState"'));
    expect(dart, contains('"target": "a2ui"'));
    expect(dart, contains('Object?'));
  });
}
