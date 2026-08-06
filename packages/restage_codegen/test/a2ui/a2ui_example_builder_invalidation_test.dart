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
    name: 'Default',
    asset: 'lib/a2ui_examples/card/default.json',
  )
  @RestageWidget(
    name: 'Card',
    library: WidgetLibrary.custom('acme.widgets'),
    category: WidgetCategory.decoration,
    description: 'A card.',
  )
  class Card {
    const Card({required this.title});
    @RestageProperty(description: 'The title.')
    final String title;
  }
''';

const _sidecarPath = 'lib/a2ui_examples/card/default.json';

Future<({bool succeeded, String logs, TestReaderWriter readerWriter})>
    _runBuilder({String? sidecar, String? movedSidecar}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/card.dart'),
    _source,
  );
  if (sidecar != null) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', _sidecarPath),
      sidecar,
    );
  }
  if (movedSidecar != null) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/a2ui_examples/card/moved.json'),
      movedSidecar,
    );
  }

  final logs = <String>[];
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    const {'apps_examples|lib/card.dart': _source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return (
    succeeded: result.succeeded,
    logs: logs.join('\n'),
    readerWriter: result.readerWriter,
  );
}

void main() {
  test('sidecar-only edits remain real tracked builder inputs', () async {
    const first = '[{"id":"root","component":"Card","title":"First"}]';
    const edited = '[{"id":"root","component":"Card","title":"Edited"}]';

    final before = await _runBuilder(sidecar: first);
    final after = await _runBuilder(sidecar: edited);
    final sidecarId = AssetId('apps_examples', _sidecarPath);

    expect(before.succeeded, isTrue);
    expect(after.succeeded, isTrue);
    expect(before.readerWriter.testing.inputsTracked, contains(sidecarId));
    expect(after.readerWriter.testing.inputsTracked, contains(sidecarId));
    expect(before.readerWriter.testing.assetsRead, contains(sidecarId));
    expect(after.readerWriter.testing.assetsRead, contains(sidecarId));
  });

  test('a deleted sidecar fails loud at its normalized asset', () async {
    final result = await _runBuilder();

    expect(result.succeeded, isFalse);
    expect(result.logs, contains('Card'));
    expect(result.logs, contains('Default'));
    expect(result.logs, contains(_sidecarPath));
    expect(result.logs, contains('does not exist'));
  });

  test('a sidecar-only move fails until the annotation is updated', () async {
    final result = await _runBuilder(
      movedSidecar: '[{"id":"root","component":"Card","title":"Moved"}]',
    );

    expect(result.succeeded, isFalse);
    expect(result.logs, contains(_sidecarPath));
    expect(result.logs, isNot(contains('moved.json does not exist')));
  });
}
