import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('emits an immutable ordered registry and CatalogItem callbacks', () {
    final catalog = catalogWith([
      entry(
        name: 'Card',
        properties: [prop('title', PropertyType.string)],
      ),
    ]);

    final source = emitA2uiCatalogDartWithExampleRegistry(
      catalog,
      exampleRegistry: const {
        'Card': {
          'Zulu': '[{"component":"Card","id":"root","title":"Last"}]',
          'Alpha': '[{"component":"Card","id":"root","title":"First"}]',
        },
      },
    );

    expect(
      source,
      contains(
        'const Map<String, Map<String, String>> '
        'restageA2uiExampleRegistry',
      ),
    );
    expect(source, contains("'Card': <String, String>{"));
    expect(
      source.indexOf("'Alpha':"),
      lessThan(source.indexOf("'Zulu':")),
    );
    expect(
      source.indexOf("['Alpha']!"),
      lessThan(source.indexOf("['Zulu']!")),
    );
    expect(source, contains('exampleData: <ExampleBuilderCallback>['));
    expect(source, isNot(contains('widgetbook')));
  });

  test('ordinary emission omits example-only output', () {
    final source = emitA2uiCatalogDart(
      catalogWith([
        entry(
          name: 'Card',
          properties: [prop('title', PropertyType.string)],
        ),
      ]),
    );

    expect(source, isNot(contains('restageA2uiExampleRegistry')));
    expect(source, isNot(contains('exampleData:')));
  });
}
