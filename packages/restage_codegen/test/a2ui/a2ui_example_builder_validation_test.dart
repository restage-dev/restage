import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _source = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;

  @RestageA2uiExample(
    name: 'Invalid count',
    asset: 'lib/a2ui_examples/card/invalid.json',
  )
  @RestageWidget(
    name: 'Card',
    library: WidgetLibrary.custom('acme.widgets'),
    category: WidgetCategory.decoration,
    description: 'A card.',
  )
  class Card {
    const Card({required this.count});
    @RestageProperty(description: 'The count.')
    final int count;
  }
''';

void main() {
  test('invalid sidecar fails before either generated output is written',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
    );
    readerWriter.testing
      ..writeString(AssetId('apps_examples', 'lib/card.dart'), _source)
      ..writeString(
        AssetId(
          'apps_examples',
          'lib/a2ui_examples/card/invalid.json',
        ),
        '[{"id":"root","component":"Card","count":"wrong"}]',
      );
    final logs = <String>[];

    final result = await testBuilder(
      const UserA2uiCatalogBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/card.dart': _source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    final diagnostic = logs.join('\n');
    expect(diagnostic, contains('Card'));
    expect(diagnostic, contains('Invalid count'));
    expect(
      diagnostic,
      contains('lib/a2ui_examples/card/invalid.json'),
    );
    expect(diagnostic, contains('component "root"'));
    expect(diagnostic, contains('component path "/0/count"'));
    expect(
      diagnostic,
      contains('schema path "/components/Card/properties/count"'),
    );
    expect(
      result.readerWriter.testing.exists(
        AssetId('apps_examples', 'lib/restage_a2ui_catalog.g.dart'),
      ),
      isFalse,
    );
    expect(
      result.readerWriter.testing.exists(
        AssetId('apps_examples', 'lib/restage_a2ui_catalog.a2ui.json'),
      ),
      isFalse,
    );
  });
}
