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
    const PlainCard({required this.title, required this.plan});
    @RestageProperty(description: 't') final String title;
    @RestageProperty(description: 'p') final Plan plan;
  }
''';

void main() {
  test('a map-free customer catalog remains byte-identical', () async {
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

    // This golden was captured BEFORE the closure learned to look through a
    // map value, from this exact source. A widget with no map in it must emit
    // byte-identical bytes afterwards. If this fails, the widening reached
    // something it was scoped not to touch — regenerating the golden would
    // erase exactly the evidence this test exists to provide.
    expect(captured, golden);
  });
}
