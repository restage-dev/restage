import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('unlabeled generic raw RFW compiles', () async {
    final output = await _compileRawPaywall();

    expect(output.blob, isNotEmpty);
    expect(output.capabilitySidecar, isNotEmpty);
  });

  test('labeled generic raw RFW fails before output writes', () async {
    const source = '''
import acme.widgets;
widget Paywall = AcmeBadge(label: "Welcome", analyticsId: "checkout.primary");
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/checkout.rfwtxt'),
      source,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
      encodeCatalog(_catalog()),
    );
    final logs = <String>[];

    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/paywalls/checkout.rfwtxt': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: const {},
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(logs.join('\n'), contains('[invalidAnalyticsId]'));
  });

  test('raw RFW rejects a nonliteral occurrence label before output writes',
      () async {
    const source = '''
import acme.widgets;
widget Paywall = AcmeBadge(label: "Welcome", analyticsId: args.label);
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/checkout.rfwtxt'),
      source,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
      encodeCatalog(_catalog()),
    );
    final logs = <String>[];

    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/paywalls/checkout.rfwtxt': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: const {},
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(logs.join('\n'), contains('[invalidAnalyticsId]'));
  });

  test('raw RFW rejects an unknown labeled call before output writes',
      () async {
    const source = '''
widget Paywall = Unknown(analyticsId: "checkout.primary");
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/checkout.rfwtxt'),
      source,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
      encodeCatalog(_catalog()),
    );
    final logs = <String>[];

    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/paywalls/checkout.rfwtxt': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: const {},
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(logs.join('\n'), contains('[invalidAnalyticsId]'));
  });

  test('customer catalog rejects a constructor field named analyticsId',
      () async {
    const source = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(library: WidgetLibrary.custom('acme.widgets'))
const restageLibrary = 0;

@RestageWidget(
  name: 'AcmeBadge',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'A badge.',
)
class AcmeBadge {
  const AcmeBadge({this.analyticsId});
  final String? analyticsId;
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/widgets/acme_badge.dart'),
      source,
    );
    final logs = <String>[];

    final result = await testBuilder(
      userCatalogJsonBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/widgets/acme_badge.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(logs.join('\n'), contains('[invalidSynthetic]'));
  });
}

Future<({List<int> blob, String capabilitySidecar})>
    _compileRawPaywall() async {
  const source = '''
import acme.widgets;
widget Paywall = AcmeBadge(label: "Welcome");
''';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: false,
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/paywalls/checkout.rfwtxt'),
    source,
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
    encodeCatalog(_catalog()),
  );

  final result = await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {'apps_examples|lib/paywalls/checkout.rfwtxt': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );

  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return (
    blob: Uint8List.fromList(
      result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/paywalls/checkout.rfw'),
      ),
    ),
    capabilitySidecar: result.readerWriter.testing.readString(
      AssetId('apps_examples', 'assets/paywalls/checkout.capability.json'),
    ),
  );
}

Catalog _catalog() {
  const library = WidgetLibrary.custom('acme.widgets');
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      library: const LibraryInfo(version: '0.1.0', capabilityVersion: 1),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'AcmeBadge',
        library: library,
        category: WidgetCategory.layout,
        description: 'A badge.',
        flutterType: 'package:acme/widgets.dart#AcmeBadge',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'label',
            type: PropertyType.string,
            description: 'Visible label.',
          ),
          analyticsIdProperty(wireId: WireId('p0002')),
        ],
      ),
    ],
  );
}
