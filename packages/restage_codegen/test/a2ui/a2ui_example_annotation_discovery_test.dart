import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _library = '''
  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;
''';

const _widget = '''
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

Future<(bool succeeded, String logs)> _runBuilder(
  String body, {
  Map<String, String> sidecars = const {},
}) async {
  final source = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    $_library
    $body
  ''';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/card.dart'),
    source,
  );
  for (final entry in sidecars.entries) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', entry.key),
      entry.value,
    );
  }
  final logs = <String>[];
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    {'apps_examples|lib/card.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return (result.succeeded, logs.join('\n'));
}

void main() {
  test(
    'collects every legal canonical annotation on a RestageWidget class',
    () async {
      const body = '''
      @RestageA2uiExample(
        name: 'Default',
        asset: 'lib/a2ui_examples/card/default.json',
      )
      @RestageA2uiExample(
        name: 'Boundary',
        asset: 'lib/a2ui_examples/card/boundary.json',
      )
      $_widget
    ''';
      final (succeeded, logs) = await _runBuilder(
        body,
        sidecars: const {
          'lib/a2ui_examples/card/default.json':
              '[{"id":"root","component":"Card","title":"Default"}]',
          'lib/a2ui_examples/card/boundary.json':
              '[{"id":"root","component":"Card","title":"Boundary"}]',
        },
      );

      expect(succeeded, isTrue, reason: logs);
    },
  );

  for (final name in const ['', '   ']) {
    test(
      'rejects a blank example name ${name.isEmpty ? '<empty>' : '<space>'}',
      () async {
        final body = '''
        @RestageA2uiExample(
          name: '$name',
          asset: 'lib/a2ui_examples/card/default.json',
        )
        $_widget
      ''';
        final (succeeded, logs) = await _runBuilder(
          body,
          sidecars: const {
            'lib/a2ui_examples/card/default.json':
                '[{"id":"root","component":"Card"}]',
          },
        );

        expect(succeeded, isFalse);
        expect(logs, contains('Card'));
        expect(logs, contains('non-blank'));
        expect(logs, contains('lib/a2ui_examples/card/default.json'));
      },
    );
  }

  test('rejects duplicate names on the same catalog item', () async {
    const body = '''
      @RestageA2uiExample(
        name: 'Default',
        asset: 'lib/a2ui_examples/card/default.json',
      )
      @RestageA2uiExample(
        name: 'Default',
        asset: 'lib/a2ui_examples/card/other.json',
      )
      $_widget
    ''';
    final (succeeded, logs) = await _runBuilder(
      body,
      sidecars: const {
        'lib/a2ui_examples/card/default.json':
            '[{"id":"root","component":"Card"}]',
        'lib/a2ui_examples/card/other.json':
            '[{"id":"root","component":"Card"}]',
      },
    );

    expect(succeeded, isFalse);
    expect(logs, contains('duplicate'));
    expect(logs, contains('Default'));
    expect(logs, contains('Card'));
  });

  test('does not confuse a literal sentinel-looking name with failed eval',
      () async {
    const body = '''
      @RestageA2uiExample(
        name: '<unevaluated>',
        asset: 'lib/a2ui_examples/card/sentinel.json',
      )
      $_widget
    ''';
    final (succeeded, logs) = await _runBuilder(
      body,
      sidecars: const {
        'lib/a2ui_examples/card/sentinel.json':
            '[{"id":"root","component":"Card","title":"<unevaluated>"}]',
      },
    );

    expect(succeeded, isTrue, reason: logs);
  });

  test('collects a legal canonical const annotation alias', () async {
    const body = '''
      const aliasedExample = RestageA2uiExample(
        name: 'Aliased',
        asset: 'lib/a2ui_examples/card/aliased.json',
      );
      @aliasedExample
      $_widget
    ''';
    final (succeeded, logs) = await _runBuilder(
      body,
      sidecars: const {
        'lib/a2ui_examples/card/aliased.json':
            '[{"id":"root","component":"Card","title":"Aliased"}]',
      },
    );

    expect(succeeded, isTrue, reason: logs);
  });

  test('collects a canonical const alias with static type Object', () async {
    const body = '''
      const Object objectTypedExample = RestageA2uiExample(
        name: 'Object typed',
        asset: 'lib/a2ui_examples/card/object_typed.json',
      );
      @objectTypedExample
      $_widget
    ''';
    final (succeeded, logs) = await _runBuilder(
      body,
      sidecars: const {
        'lib/a2ui_examples/card/object_typed.json':
            '[{"id":"root","component":"Card","title":"Object typed"}]',
      },
    );

    expect(succeeded, isTrue, reason: logs);
  });

  test('rejects a canonical const annotation alias on an invalid site',
      () async {
    const body = '''
      const aliasedExample = RestageA2uiExample(
        name: 'Aliased invalid',
        asset: 'lib/a2ui_examples/card/invalid_alias.json',
      );
      @aliasedExample
      void invalidFunction() {}
      $_widget
    ''';
    final (succeeded, logs) = await _runBuilder(body);

    expect(succeeded, isFalse);
    expect(logs, contains('RestageA2uiExample'));
    expect(logs, contains('Aliased invalid'));
    expect(logs, contains('lib/a2ui_examples/card/invalid_alias.json'));
  });

  final invalidSites = <String, String>{
    'top-level function': '''
      @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
      void invalidFunction() {}
      $_widget
    ''',
    'non-class type': '''
      @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
      enum InvalidType { value }
      $_widget
    ''',
    'member': '''
      class Holder {
        @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
        void invalidMember() {}
      }
      $_widget
    ''',
    'parameter': '''
      void holder(
        @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
        String value,
      ) {}
      $_widget
    ''',
    'local': '''
      void holder() {
        @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
        final value = 1;
      }
      $_widget
    ''',
    'orphan non-widget class': '''
      @RestageA2uiExample(name: 'Invalid', asset: 'lib/invalid.json')
      class Orphan {}
      $_widget
    ''',
  };

  for (final entry in invalidSites.entries) {
    test('rejects a canonical annotation on a ${entry.key}', () async {
      final (succeeded, logs) = await _runBuilder(entry.value);

      expect(succeeded, isFalse);
      expect(logs, contains('RestageA2uiExample'));
      expect(logs, contains('Invalid'));
      expect(logs, contains('lib/invalid.json'));
    });
  }

  test('ignores a same-name local lookalike annotation', () async {
    const source = '''
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' as schema;

      class RestageA2uiExample {
        const RestageA2uiExample({required this.name, required this.asset});
        final String name;
        final String asset;
      }

      @RestageA2uiExample(name: 'Lookalike', asset: 'lib/missing.json')
      void decoratedByLookalike() {}

      @schema.RestageLibrary(
        library: schema.WidgetLibrary.custom('acme.widgets'),
        capabilityVersion: 1,
      )
      const restageLibrary = 0;

      @schema.RestageWidget(
        name: 'Card',
        library: schema.WidgetLibrary.custom('acme.widgets'),
        category: schema.WidgetCategory.decoration,
        description: 'A card.',
      )
      class Card {
        const Card({required this.title});
        @schema.RestageProperty(description: 'The title.')
        final String title;
      }
    ''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/card.dart'),
      source,
    );
    final logs = <String>[];
    final result = await testBuilder(
      const UserA2uiCatalogBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/card.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isTrue, reason: logs.join('\n'));
  });
}
