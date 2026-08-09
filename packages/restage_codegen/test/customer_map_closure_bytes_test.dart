import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
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

void main() {
  test('a map-free customer catalog records only its constructor facts',
      () async {
    final rw =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    rw.testing.writeString(
      AssetId('apps_examples', 'lib/widgets.dart'),
      _source,
    );
    String? captured;
    await testBuilder(
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      {'apps_examples|lib/widgets.dart': _source},
      rootPackage: 'apps_examples',
      readerWriter: rw,
      outputs: {
        'apps_examples|lib/src/widget_catalog/catalog.json': decodedMatches(
          predicate<String>((value) {
            captured = value;
            return true;
          }),
        ),
      },
      onLog: (_) {},
    );
    expect(captured, isNotNull);
    final golden = File('test/fixtures/goldens/map_free_customer_catalog.json')
        .readAsStringSync();

    // This golden isolates map-value closure from constructor-fidelity facts.
    // The only constructor addition is the nullable `title` input; no map
    // shape or closure metadata may appear.
    expect(captured, golden.trimRight());
  });
}
