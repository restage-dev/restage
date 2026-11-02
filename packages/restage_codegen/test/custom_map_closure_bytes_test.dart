import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _source = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  @RestageLibrary(
    library: WidgetLibrary.custom('acme.design_system'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;
  class Plan {
    const Plan({required this.name});
    final String name;
  }
  @RestageWidget(name: 'PlainCard',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration, description: 'p')
  class PlainCard {
    const PlainCard({this.title, required this.plan});
    @RestageProperty(description: 't') final String? title;
    @RestageProperty(description: 'p') final Plan plan;
  }
''';

/// Captures the original fixture through its production catalog owner.
Future<String> generateMapFreeCustomCatalog() async {
  final rw = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  rw.testing.writeString(
    AssetId('apps_examples', 'lib/widgets.dart'),
    _source,
  );
  final result = await testBuilder(
    const UserCatalogJsonBuilder(BuilderOptions.empty),
    {'apps_examples|lib/widgets.dart': _source},
    rootPackage: 'apps_examples',
    readerWriter: rw,
    flattenOutput: true,
    onLog: (_) {},
  );
  if (!result.succeeded) {
    throw StateError(
      'Map-free custom catalog build failed: '
      '${result.errors.join('\n')}',
    );
  }
  final captured = rw.testing.readString(
    AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
  );
  final factories = rw.testing.readString(
    AssetId(
      'apps_examples',
      'lib/src/widget_catalog/app_widget_factories.json',
    ),
  );
  if (captured.trim().isEmpty || factories.trim().isEmpty) {
    throw StateError('Map-free custom catalog build emitted empty outputs.');
  }
  return captured;
}

void main() {
  test(
    'a map-free custom catalog records constructor facts and synthetic metadata',
    () async {
      final captured = await generateMapFreeCustomCatalog();
      final golden = File(
        'test/fixtures/goldens/map_free_custom_catalog.json',
      ).readAsStringSync();

      // This golden isolates map-value closure from constructor-fidelity facts.
      // The nullable `title` input is the only constructor addition; analyticsId
      // is synthetic occurrence metadata, so no map shape or closure metadata
      // may appear.
      expect(captured, golden.trimRight());
    },
  );
}
