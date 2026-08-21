import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../index_probe_helpers.dart';

void main() {
  test('syntax lookalikes declare one package output without owning it', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-output-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/first.dart').writeAsStringSync(
        _lookalikeStorySource('SameCard'),
      );
      File('${lib.path}/second.dart').writeAsStringSync(
        _lookalikeStorySource('SameCard'),
      );
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/same_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('alias-only startup discovery reserves local and imported aliases', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-alias-output-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/annotations.dart').writeAsStringSync('''
const importedCatalogWidget = Object();
''');
      File('${lib.path}/cards.dart').writeAsStringSync('''
import 'annotations.dart' as aliases;

const localCatalogWidget = Object();

@localCatalogWidget
class LocalAliasCard {}

@aliases.importedCatalogWidget
class ImportedAliasCard {}

class PlainCard {}
''');
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/imported_alias_card.stories.dart',
            'restage.generated/local_alias_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('startup discovery scans relative and package-URI parts directly', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-part-output-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/cards.dart').writeAsStringSync('''
part 'relative_card_part.dart';
part 'package:fixture/src/package_card_part.dart';
''');
      File('${lib.path}/relative_card_part.dart').writeAsStringSync('''
part of 'cards.dart';
@Deprecated('relative part')
class RelativePartCard {}
''');
      File('${lib.path}/src/package_card_part.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
part of 'package:fixture/cards.dart';
@Deprecated('package URI part')
class PackagePartCard {}
''');
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/package_part_card.stories.dart',
            'restage.generated/relative_part_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('startup ownership accepts exact LF and CRLF marker prefixes only', () {
    final cases = <({String name, String source, bool owned})>[
      (name: 'LF', source: _recognizableGeneratedManualStory, owned: true),
      (
        name: 'CRLF',
        source: _recognizableGeneratedManualStoryCrLf,
        owned: true,
      ),
      (name: 'generic', source: _foreignGeneratedManualStory, owned: false),
      (name: 'mixed', source: _mixedNewlineGeneratedManualStory, owned: false),
    ];
    for (final probe in cases) {
      final temp = Directory.systemTemp.createTempSync(
        'widgetbook-${probe.name}-ownership-',
      );
      try {
        final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
        File('${lib.path}/manual_card.dart').writeAsStringSync('''
@Deprecated('ownership probe')
class ManualCard {}
''');
        final generated = Directory('${lib.path}/restage.generated')
          ..createSync(recursive: true);
        File('${generated.path}/manual_card.stories.dart').writeAsStringSync(
          probe.source,
        );
        final outputs = createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions[r'$lib$']!;
        expect(
          outputs.contains('restage.generated/manual_card.stories.dart'),
          probe.owned,
          reason: probe.name,
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    }
  });

  test('startup declares an orphaned marked Restage story for cleanup', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-orphan-output-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      final generated = Directory('${lib.path}/restage.generated')
        ..createSync(recursive: true);
      File('${generated.path}/orphan_card.stories.dart').writeAsStringSync(
        _recognizableGeneratedManualStory,
      );
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/orphan_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('startup sentinel does not reserve a hand-authored story stem', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-manual-story-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/manual_card.dart').writeAsStringSync('''
@Deprecated('customer-authored Widgetbook story')
class ManualCard {}
''');
      File('${lib.path}/restage.generated/manual_card.stories.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_foreignGeneratedManualStory);
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': ['generated/.restage_widgetbook_story_builder'],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('startup sentinel retains a recognizable prior generated story', () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-generated-story-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/manual_card.dart').writeAsStringSync('''
@Deprecated('syntax roster probe')
class ManualCard {}
''');
      File('${lib.path}/restage.generated/manual_card.stories.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_recognizableGeneratedManualStory);
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/manual_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('mixed startup discovery reserves all annotations but no plain class',
      () {
    final temp = Directory.systemTemp.createTempSync(
      'widgetbook-mixed-output-discovery-',
    );
    try {
      final lib = Directory('${temp.path}/lib')..createSync(recursive: true);
      File('${lib.path}/cards.dart').writeAsStringSync('''
class RestageWidget {
  const RestageWidget();
}

const catalogWidget = RestageWidget();

@RestageWidget()
class DirectCard {}

@catalogWidget
class LocalAliasCard {}

@Deprecated('not a widget')
class ReservedOnlyCard {}

class PlainCard {}
''');
      expect(
        createWidgetbookStoryBuilderForLib(
          BuilderOptions.empty,
          lib,
        ).buildExtensions,
        const {
          r'$lib$': [
            'generated/.restage_widgetbook_story_builder',
            'restage.generated/direct_card.stories.dart',
            'restage.generated/local_alias_card.stories.dart',
            'restage.generated/reserved_only_card.stories.dart',
          ],
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('package tests do not mutate the process-wide working directory',
      () async {
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:restage_codegen/restage_codegen.dart'),
    );
    expect(packageLibrary, isNotNull);
    final packageRoot = File.fromUri(packageLibrary!).parent.parent;
    final mutationPattern = RegExp(
      '${'Directory'}\\.${'current'}\\s*=',
    );
    final offenders = Directory('${packageRoot.path}/test')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => mutationPattern.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList()
      ..sort();

    expect(offenders, isEmpty);
  });

  test('resolved const aliases own outputs while unrelated metadata is inert',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': [
          'restage.generated/imported_alias_card.stories.dart',
          'restage.generated/local_alias_card.stories.dart',
          'restage.generated/reserved_only_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/indirect_annotations.dart': _indirectAnnotations,
        'apps_examples|lib/indirect_alias_cards.dart': _indirectAliasCards,
        'apps_examples|lib/imported_alias_cards.dart': _importedAliasCards,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/restage.generated/imported_alias_card.stories.dart':
            decodedMatches(contains('ImportedAliasCard')),
        'apps_examples|lib/restage.generated/local_alias_card.stories.dart':
            decodedMatches(contains('LocalAliasCard')),
      },
    );
  });

  test('genuine widget fails loud without owning a hand-authored story',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['generated/.restage_widgetbook_story_builder'],
      }),
      const {
        'apps_examples|lib/manual_card.dart': _genuineManualCard,
        'apps_examples|lib/restage.generated/manual_card.stories.dart':
            _foreignGeneratedManualStory,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );

    expect(
      logs.join('\n'),
      allOf(
        contains('lib/manual_card.dart#ManualCard'),
        contains(
          'conflicts with the existing hand-authored Widgetbook story at '
          'lib/restage.generated/manual_card.stories.dart',
        ),
        contains('Move or rename the hand-authored story'),
        isNot(contains('Restart dart run build_runner watch')),
      ),
    );
  });

  test('genuine widget owns its output despite a same-stem lookalike',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['restage.generated/same_card.stories.dart'],
      }),
      {
        'apps_examples|lib/genuine.dart': _genuineSameCard,
        'apps_examples|lib/lookalike.dart': _lookalikeSameCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/restage.generated/same_card.stories.dart':
            decodedMatches(
          allOf(
            contains(
              '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
              '// GENERATED BY RESTAGE WIDGETBOOK STORY BUILDER\n'
              '// ignore_for_file: '
              'library_private_types_in_public_api, unused_import',
            ),
            contains(
              "import 'package:apps_examples/genuine.dart' show SameCard;",
            ),
            isNot(contains('lookalike.dart')),
          ),
        ),
      },
    );
  });

  test('two same-stem lookalikes emit nothing and do not fail', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['restage.generated/same_card.stories.dart'],
      }),
      {
        'apps_examples|lib/first.dart': _lookalikeSameCard,
        'apps_examples|lib/second.dart': _lookalikeSameCard,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    expect(logs.join('\n'), isNot(contains('ambiguous')));
  });

  test('two genuine same-stem owners fail with exact resolved declarations',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['restage.generated/same_card.stories.dart'],
      }),
      const {
        'apps_examples|lib/first.dart': _firstGenuineSameCard,
        'apps_examples|lib/second.dart': _secondGenuineSameCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    expect(
      logs.join('\n'),
      allOf(
        contains(
          "Widgetbook story output 'lib/restage.generated/same_card.stories.dart'",
        ),
        contains('lib/first.dart#SameCard'),
        contains('lib/second.dart#SameCard'),
        contains('genuine @RestageWidget declarations'),
      ),
    );
  });

  test('part owner paths are exact and sorted in genuine collisions', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['restage.generated/same_card.stories.dart'],
      }),
      const {
        'apps_examples|lib/part_owner.dart': _partOwnerLibrary,
        'apps_examples|lib/part_owner_piece.dart': _partOwnerPiece,
        'apps_examples|lib/source_owner.dart': _sourceOwnerSameCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    final output = logs.join('\n');
    const part = 'lib/part_owner_piece.dart#SameCard';
    const source = 'lib/source_owner.dart#SameCard';
    expect(
      output,
      allOf(
        contains(part),
        contains(source),
        isNot(contains('lib/part_owner.dart#SameCard')),
        predicate<String>(
          (value) => value.indexOf(part) < value.indexOf(source),
          'sorts exact resolved declaration paths',
        ),
      ),
    );
  });

  test('package-URI part owner paths are exact in genuine collisions',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': ['restage.generated/same_card.stories.dart'],
      }),
      const {
        'apps_examples|lib/package_part_owner.dart': _packagePartOwnerLibrary,
        'apps_examples|lib/src/package_part_piece.dart': _packagePartOwnerPiece,
        'apps_examples|lib/source_owner.dart': _sourceOwnerSameCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    final output = logs.join('\n');
    expect(
      output,
      allOf(
        contains('lib/src/package_part_piece.dart#SameCard'),
        contains('lib/source_owner.dart#SameCard'),
        isNot(contains('lib/package_part_owner.dart#SameCard')),
      ),
    );
  });

  test('one package build emits multiple genuine classes including a part',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': [
          'restage.generated/first_card.stories.dart',
          'restage.generated/second_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/cards.dart': _genuineCardsLibrary,
        'apps_examples|lib/cards_part.dart': _genuineCardsPart,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/restage.generated/first_card.stories.dart':
            decodedMatches(contains('FirstCard')),
        'apps_examples|lib/restage.generated/second_card.stories.dart':
            decodedMatches(contains('SecondCard')),
      },
    );
  });

  test(
    'Widgetbook emits a same-name widget and screen at distinct paths',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          const WidgetbookStoryBuilder({
            r'$lib$': [
              'onboarding/screens/restage.generated/shared_card.stories.dart',
              'onboarding/screens/restage.generated/shared_screen.stories.dart',
            ],
          }),
          const {
            'apps_examples|lib/onboarding/screens/shared.dart':
                _sameNameWidgetAndScreen,
            'apps_examples|pubspec.yaml': _screenSourcePubspec,
            'widgetbook|lib/widgetbook.dart': _widgetbookStub,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          outputs: {
            'apps_examples|lib/onboarding/screens/restage.generated/shared_card.stories.dart':
                decodedMatches(
              allOf(
                contains('name: "shared"'),
                contains("path: 'decoration'"),
                isNot(contains("path: 'Screens'")),
              ),
            ),
            'apps_examples|lib/onboarding/screens/restage.generated/shared_screen.stories.dart':
                decodedMatches(
              allOf(
                contains('name: "shared"'),
                contains("path: 'Screens'"),
                isNot(contains("path: 'decoration'")),
              ),
            ),
          },
        ),
      );
    },
  );

  test(
    'customer description and usage stay editable under exact Dart names',
    () async {
      const output =
          'apps_examples|lib/restage.generated/metadata_card.stories.dart';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      await testBuilder(
        const WidgetbookStoryBuilder({
          r'$lib$': ['restage.generated/metadata_card.stories.dart'],
        }),
        const {
          'apps_examples|lib/metadata_card.dart': _metadataCollisionCard,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          output: decodedMatches(
            allOf(<Matcher>[
              contains('final String restageMetadataDescription_2;'),
              contains('final String restageMetadataUsage_2;'),
              contains('final String description;'),
              contains('final String usage;'),
              contains('final String restageMetadataDescription;'),
              contains('final String restageMetadataUsage;'),
              contains("name: 'Restage description'"),
              contains("name: 'Restage usage'"),
              contains('restageMetadataDescription_2: _RestageMetadataArg('),
              contains('restageMetadataUsage_2: _RestageMetadataArg('),
              contains('description: _RestageStringArg('),
              contains('usage: _RestageStringArg('),
              contains('restageMetadataDescription: _RestageStringArg('),
              contains('restageMetadataUsage: _RestageStringArg('),
              contains('description: args.description'),
              contains('usage: args.usage'),
            ]),
          ),
        },
      );
    },
  );

  test(
    'production ScreenSource story uses exact identity and Defaults.setup',
    () async {
      const output =
          'apps_examples|lib/onboarding/screens/restage.generated/opaque_screen.stories.dart';
      const sourceRoot = 'package:apps_examples/onboarding/screens';
      const sourceUri = '$sourceRoot/opaque-screen-v1.dart';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          const WidgetbookStoryBuilder({
            r'$lib$': [
              'onboarding/screens/restage.generated/opaque_screen.stories.dart',
            ],
          }),
          const {
            'apps_examples|lib/onboarding/screens/opaque-screen-v1.dart':
                _genuineScreenSource,
            'apps_examples|pubspec.yaml': _screenSourcePubspec,
            'widgetbook|lib/widgetbook.dart': _widgetbookStub,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          outputs: {
            output: decodedMatches(
              allOf(<Matcher>[
                contains(widgetbookStoryOwnershipPrefix),
                contains("import '$sourceUri'"),
                contains('show OpaqueScreen;'),
                contains(
                  "import 'package:restage/restage.dart' as restage_runtime;",
                ),
                contains('const meta = widgetbook.Meta('),
                contains('restage_source.OpaqueScreen.new'),
                contains('name: "opaque-screen-v1"'),
                contains("path: 'Screens'"),
                contains(
                  'final previewEvents = <({String id, Object? value})>[];',
                ),
                contains('final defaults = _Defaults('),
                contains('setup: (context, child, args) =>'),
                contains('restage_runtime.RestageEventDispatcher('),
                contains('previewEvents.add((id: eventId, value: value))'),
                contains('child: child'),
                contains(
                  'builder: (context, args) => restage_source.OpaqueScreen(',
                ),
                contains('title: args.title'),
                contains('enabled: args.enabled'),
                contains('tone: switch (args.tone)'),
                contains('description: args.description'),
                contains('usage: args.usage'),
                contains("name: 'Restage description'"),
                contains("name: 'Restage usage'"),
                isNot(contains('Config.appBuilder')),
                isNot(contains('appBuilder:')),
                isNot(contains('host')),
              ]),
            ),
          },
        ),
      );
    },
  );

  test(
    'Widgetbook labels canonical native story collisions as '
    'Screen declarations',
    () async {
      const firstPath = 'lib/features/first_collision.dart';
      const secondPath = 'lib/features/second_collision.dart';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          const WidgetbookStoryBuilder({
            r'$lib$': [
              'features/restage.generated/collision_screen.stories.dart'
            ],
          }),
          const {
            'apps_examples|lib/features/first_collision.dart':
                _firstCanonicalCollisionScreen,
            'apps_examples|lib/features/second_collision.dart':
                _secondCanonicalCollisionScreen,
            'apps_examples|pubspec.yaml': _screenSourcePubspec,
            'widgetbook|lib/widgetbook.dart': _widgetbookStub,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.join('\n'),
        allOf(
          contains('@Screen declarations'),
          isNot(contains('@ScreenSource declarations')),
          contains('$firstPath#CollisionScreen'),
          contains('$secondPath#CollisionScreen'),
        ),
      );
    },
  );

  test('ScreenSource order migration is logged exactly once', () async {
    const output =
        'apps_examples|lib/onboarding/screens/restage.generated/order_screen.stories.dart';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        const WidgetbookStoryBuilder({
          r'$lib$': [
            'onboarding/screens/restage.generated/order_screen.stories.dart'
          ],
        }),
        const {
          'apps_examples|lib/onboarding/screens/order_screen.dart':
              _orderMigrationScreenSource,
          'apps_examples|pubspec.yaml': _screenSourcePubspec,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {output: decodedMatches(contains('OrderScreen'))},
        onLog: (record) => logs.add(record.message),
      ),
    );

    expect(
      logs.where((message) => message.contains('catalog properties move')),
      hasLength(1),
    );
  });

  test(
    'generated ScreenSource story compiles when its class shadows the '
    'Restage dispatcher',
    () async {
      const output = 'apps_examples|lib/onboarding/screens/restage.generated/'
          'restage_event_dispatcher.stories.dart';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      var generated = '';
      await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          const WidgetbookStoryBuilder({
            r'$lib$': [
              'onboarding/screens/restage.generated/restage_event_dispatcher.stories.dart',
            ],
          }),
          const {
            'apps_examples|lib/onboarding/screens/dispatcher_named_screen.dart':
                _dispatcherNamedScreenSource,
            'apps_examples|pubspec.yaml': _screenSourcePubspec,
            'widgetbook|lib/widgetbook.dart': _widgetbookStub,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          outputs: {
            output: decodedMatches(
              allOf(
                predicate<String>(
                  (source) {
                    generated = source;
                    return true;
                  },
                  'captures the real generated story source',
                ),
                contains(
                  "import 'package:restage/restage.dart' as restage_runtime;",
                ),
                contains('restage_runtime.RestageEventDispatcher('),
              ),
            ),
          },
        ),
      );

      await resolveSources(
        {
          'apps_examples|lib/onboarding/screens/dispatcher_named_screen.dart':
              _dispatcherNamedScreenSource,
          output: generated,
          'apps_examples|lib/onboarding/screens/restage.generated/'
                  'restage_event_dispatcher.stories.g.dart':
              _dispatcherStoryPartStub,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'apps_examples',
              'lib/onboarding/screens/restage.generated/restage_event_dispatcher.stories.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError(
              'Generated dispatcher-named story did not resolve.',
            );
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: output,
        rootPackage: 'apps_examples',
        readAllSourcesFromFilesystem: true,
      );
    },
  );

  for (final decoy in _partDirectiveDecoys.entries) {
    test(
      'Widgetbook rejects a ${decoy.key} part-directive decoy with no story',
      () async {
        final source = _screenWithPartDirectiveDecoy(decoy.value);
        const inputPath = 'lib/onboarding/screens/part_decoy.dart';
        const outputPath =
            'lib/onboarding/screens/restage.generated/part_decoy.stories.dart';
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final logs = <String>[];
        final result = await runWithNativeScreenPackageGraphForTesting(
          packageGraphSource: _screenSourcePackageGraph,
          body: () => testBuilder(
            const WidgetbookStoryBuilder({
              r'$lib$': [
                'onboarding/screens/restage.generated/part_decoy.stories.dart'
              ],
            }),
            {
              'apps_examples|$inputPath': source,
              'apps_examples|pubspec.yaml': _screenSourcePubspec,
              'widgetbook|lib/widgetbook.dart': _widgetbookStub,
            },
            rootPackage: 'apps_examples',
            readerWriter: readerWriter,
            onLog: (record) => logs.add(record.message),
            outputs: const {},
          ),
        );

        expect(result.succeeded, isFalse);
        expect(logs.join('\n'), contains('missingPartDirective'));
        expect(
          result.readerWriter.testing.exists(
            AssetId('apps_examples', outputPath),
          ),
          isFalse,
        );
      },
    );
  }

  test('Widgetbook rejects a non-Widget ScreenSource before emission',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    final result = await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        const WidgetbookStoryBuilder({
          r'$lib$': [
            'onboarding/screens/restage.generated/not_awidget_screen.stories.dart'
          ],
        }),
        const {
          'apps_examples|lib/onboarding/screens/not_a_widget_screen.dart':
              _nonWidgetScreenSource,
          'apps_examples|pubspec.yaml': _screenSourcePubspec,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
      ),
    );

    expect(result.succeeded, isFalse);
    expect(
      logs.join('\n'),
      allOf(
        contains('Flow screens must extend StatelessWidget'),
        contains(
          'lib/onboarding/screens/not_a_widget_screen.dart#NotAWidgetScreen',
        ),
      ),
    );
  });

  test('ScreenSource output membership changes retain the restart rule',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        const WidgetbookStoryBuilder({
          r'$lib$': ['generated/.restage_widgetbook_story_builder'],
        }),
        const {
          'apps_examples|lib/onboarding/screens/opaque-screen-v1.dart':
              _genuineScreenSource,
          'apps_examples|pubspec.yaml': _screenSourcePubspec,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
      ),
    );

    expect(
      logs.join('\n'),
      allOf(
        contains(
          'lib/onboarding/screens/opaque-screen-v1.dart#OpaqueScreen',
        ),
        contains(
            'lib/onboarding/screens/restage.generated/opaque_screen.stories.dart'),
        contains('Restart dart run build_runner watch'),
      ),
    );
  });

  test('rejects legacy auxiliary authoring options', () {
    expect(
      () => createWidgetbookStoryBuilder(
        const BuilderOptions(
          {
            'hosts': {
              'package:example/widget.dart#Widget':
                  'package:example/host.dart#host',
            },
            'suppress': ['package:example/widget.dart#Widget'],
          },
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('no per-widget authoring options'),
            contains('hosts'),
            contains('suppress'),
          ),
        ),
      ),
    );
  });

  test('preserves public callback defaults through production story output',
      () async {
    const output =
        'apps_examples|lib/restage.generated/callback_default_card.stories.dart';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    var generated = '';
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': [
          'restage.generated/callback_default_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/callback_defaults.dart': _publicCallbackDefaults,
        'apps_examples|lib/callback_default_card.dart': _callbackDefaultCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        output: decodedMatches(
          allOf(<Matcher>[
            predicate<String>(
              (source) {
                generated = source;
                return true;
              },
              'captures generated story source',
            ),
            contains(
              "import 'package:apps_examples/callback_defaults.dart' "
              'as restage_native_0;',
            ),
            contains('this.onTap = true'),
            contains('this.onChanged = true'),
            contains('this.onSubmitted = true'),
            contains('this.onDismissed = false'),
            contains(
              'onTap: restage_native_0.topLevelCallback',
            ),
            matches(
              RegExp(
                r'onChanged: args\.onChanged\s*\?\s*'
                r'restage_native_0\.PublicCallbacks\.staticCallback\s*:\s*null',
              ),
            ),
            contains('onSubmitted: (_) {}'),
            contains('onDismissed: args.onDismissed ? () {} : null'),
            contains(
              'onTap: _RestageEventArg(\n'
              '      true,',
            ),
            contains(
              'onSubmitted: _RestageEventArg(\n'
              '      true,',
            ),
            contains(
              'onChanged: _RestageBoolArg(\n'
              '      true,',
            ),
            contains(
              'onDismissed: _RestageBoolArg(\n'
              '      false,',
            ),
            contains(
              'final class _RestageEventArg extends widgetbook.Arg<bool>\n'
              '    with widgetbook.NoFields<bool>',
            ),
          ]),
        ),
      },
    );

    await resolveSources(
      {
        'apps_examples|lib/callback_defaults.dart': _publicCallbackDefaults,
        'apps_examples|lib/callback_default_card.dart': _callbackDefaultCard,
        output: generated,
        'apps_examples|lib/restage.generated/callback_default_card.stories.g.dart':
            _storyPartStub,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId(
            'apps_examples',
            'lib/restage.generated/callback_default_card.stories.dart',
          ),
        );
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError('Generated callback-default story did not resolve.');
        }
        final errors = [
          for (final unit in resolved.units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error)
                diagnostic.problemMessage.messageText(includeUrl: false),
        ];
        expect(errors, isEmpty, reason: generated);
      },
      resolverFor: output,
      rootPackage: 'apps_examples',
      readAllSourcesFromFilesystem: true,
    );
  });

  test('rejects a private callback default at its constructor-default path',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final logs = <String>[];
    await testBuilder(
      const WidgetbookStoryBuilder({
        r'$lib$': [
          'restage.generated/private_callback_card.stories.dart',
        ],
      }),
      const {
        'apps_examples|lib/private_callback_card.dart': _privateCallbackCard,
        'widgetbook|lib/widgetbook.dart': _widgetbookStub,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
    );
    expect(
      logs.join('\n'),
      allOf(
        contains('/constructorDefaults/onTap'),
        contains('_privateCallback'),
      ),
    );
  });

  test('emits ComponentMeta with explicit root or category placement',
      () async {
    for (final fixture in <({String arguments, Matcher matcher})>[
      (
        arguments: '',
        matcher: allOf(
          contains('const meta = widgetbook.Meta('),
          contains('const component = widgetbook.ComponentMeta('),
          contains("path: ''"),
          isNot(contains("name: 'RootCard'")),
        ),
      ),
      (
        arguments: 'category: WidgetCategory.action,',
        matcher: allOf(
          contains('const component = widgetbook.ComponentMeta('),
          contains("path: 'action'"),
          isNot(contains("name: 'RootCard'")),
        ),
      ),
      (
        arguments: "name: 'CatalogRootCard',",
        matcher: allOf(
          contains('const component = widgetbook.ComponentMeta('),
          contains('name: "CatalogRootCard"'),
          contains("path: ''"),
        ),
      ),
    ]) {
      final source = _metadataStorySource(fixture.arguments);
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      await testBuilder(
        const WidgetbookStoryBuilder({
          r'$lib$': [
            'restage.generated/root_card.stories.dart',
          ],
        }),
        {
          'apps_examples|lib/root_card.dart': source,
          'widgetbook|lib/widgetbook.dart': _widgetbookStub,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/restage.generated/root_card.stories.dart':
              decodedMatches(fixture.matcher),
        },
      );
    }
  });
}

String _metadataStorySource(String arguments) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(library: WidgetLibrary.custom('fixture.widgets'))
const restageLibrary = 0;

/// A root-level customer card.
@RestageWidget($arguments)
class RootCard extends StatelessWidget {
  const RootCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _publicCallbackDefaults = '''
void topLevelCallback() {}

class PublicCallbacks {
  static void staticCallback(String value) {}
}
''';

const _callbackDefaultCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'callback_defaults.dart';

@RestageWidget(
  name: 'CallbackDefaultCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.input,
  description: 'Callback constructor-default probe.',
)
class CallbackDefaultCard extends StatelessWidget {
  const CallbackDefaultCard({
    required this.onSubmitted,
    this.onTap = topLevelCallback,
    this.onChanged = PublicCallbacks.staticCallback,
    this.onDismissed,
  });

  /// Invoked for taps.
  final VoidCallback onTap;

  /// Invoked when the value changes.
  final ValueChanged<String>? onChanged;

  /// Invoked when a value is submitted.
  final ValueChanged<String> onSubmitted;

  /// Invoked when the card is dismissed.
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _screenSourcePubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';

final String _screenSourcePackageGraph = nativeScreenPackageGraph(
  const {'flutter', 'restage', 'rfw_catalog_schema'},
);

String _screenWithPartDirectiveDecoy(String decoy) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

$decoy

@ScreenSource(id: 'part_decoy')
final class PartDecoyScreen extends StatelessWidget {
  const PartDecoyScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _partDirectiveDecoys = <String, String>{
  'comment': "// part 'restage.generated/part_decoy.restage.g.dart';",
  'string':
      "const partDirectiveText = \"part 'restage.generated/part_decoy.restage.g.dart';\";",
};

const _dispatcherNamedScreenSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

part 'restage.generated/dispatcher_named_screen.restage.g.dart';

@restage.ScreenSource(id: 'dispatcher_named_screen')
final class RestageEventDispatcher extends StatelessWidget {
  const RestageEventDispatcher({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _nonWidgetScreenSource = '''
import 'package:restage/restage.dart' as restage;

part 'restage.generated/not_a_widget_screen.restage.g.dart';

@restage.ScreenSource(id: 'not_a_widget_screen')
final class NotAWidgetScreen {
  const NotAWidgetScreen();
}
''';

const _genuineScreenSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

part 'restage.generated/opaque-screen-v1.restage.g.dart';

enum ScreenTone { calm, urgent }

/// An opaque native screen.
///
/// Its real class must remain the typed Widgetbook story result.
@ScreenSource(id: 'opaque-screen-v1')
class OpaqueScreen extends StatelessWidget {
  const OpaqueScreen({
    super.key,
    required this.title,
    this.enabled = true,
    this.tone = ScreenTone.calm,
    this.description = 'Customer description',
    this.usage = 'Customer usage',
  });

  /// Visible screen title.
  final String title;

  /// Whether the screen is enabled.
  @wb.Config.values([false])
  final bool enabled;

  /// Visual state selected for the preview.
  @wb.Config.allValues()
  final ScreenTone tone;

  /// Editable customer description.
  final String description;

  /// Editable customer usage.
  final String usage;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _firstCanonicalCollisionScreen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_collision.restage.g.dart';

@Screen(id: 'first-collision', surface: Surface.general)
final class CollisionScreen extends StatelessWidget {
  const CollisionScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _secondCanonicalCollisionScreen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/second_collision.restage.g.dart';

@Screen(id: 'second-collision', surface: Surface.general)
final class CollisionScreen extends StatelessWidget {
  const CollisionScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _orderMigrationScreenSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/order_screen.restage.g.dart';

@ScreenSource(id: 'order_screen')
class OrderScreen extends StatelessWidget {
  const OrderScreen({
    super.key,
    @Ignore({EmitTarget.a2ui, EmitTarget.widgetbook}) this.hidden = '',
    this.first = '',
    this.second = '',
  });

  final String hidden;

  @RestageProperty(description: 'Second field.')
  final String second;

  @RestageProperty(description: 'First field.')
  final String first;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _metadataCollisionCard = r'''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config.usage('Generated usage metadata.')
@RestageWidget(
  name: 'MetadataCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Generated description metadata.',
)
class MetadataCard extends StatelessWidget {
  const MetadataCard({
    required this.description,
    required this.usage,
    required this.restageMetadataDescription,
    required this.restageMetadataUsage,
  });

  /// Editable customer description.
  final String description;

  /// Editable customer usage.
  final String usage;

  /// Customer property sharing the preferred description implementation name.
  final String restageMetadataDescription;

  /// Customer property sharing the preferred usage implementation name.
  final String restageMetadataUsage;

  @override
  Widget build(BuildContext context) => Text(
    '$description|$usage|'
    '$restageMetadataDescription|$restageMetadataUsage',
  );
}
''';

const _privateCallbackCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

void _privateCallback() {}

@RestageWidget(
  name: 'PrivateCallbackCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.input,
  description: 'Private callback constructor-default probe.',
)
class PrivateCallbackCard extends StatelessWidget {
  const PrivateCallbackCard({this.onTap = _privateCallback});

  /// Invoked for taps.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _indirectAnnotations = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const importedCatalogWidget = RestageWidget(
  name: 'ImportedAliasCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'An imported-alias customer card.',
);
''';

const _indirectAliasCards = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const localCatalogWidget = RestageWidget(
  name: 'LocalAliasCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A local-alias customer card.',
);

@localCatalogWidget
class LocalAliasCard extends StatelessWidget {
  const LocalAliasCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Deprecated('not a Restage widget')
class ReservedOnlyCard {}

class PlainCard {}
''';

/// The imported-alias card, in a file of its own that spells no annotation
/// name at all.
///
/// It used to share a file with the local alias above, whose declaration
/// happens to name `RestageWidget` — so the file was scanned for that reason
/// and this card came along with it. Split out, it is a real test of whether
/// an alias declared in another file is followed.
const _importedAliasCards = '''
import 'package:flutter/widgets.dart';

import 'indirect_annotations.dart' as aliases;

@aliases.importedCatalogWidget
class ImportedAliasCard extends StatelessWidget {
  const ImportedAliasCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _genuineManualCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'ManualCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A genuine card colliding with a manual Widgetbook story.',
)
class ManualCard extends StatelessWidget {
  const ManualCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _foreignGeneratedManualStory = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: library_private_types_in_public_api, unused_import

import 'package:widgetbook/widgetbook.dart';

part 'manual_card.stories.g.dart';

const meta = Meta(Object.new);
''';

const _recognizableGeneratedManualStory = r'''
// GENERATED CODE - DO NOT MODIFY BY HAND
// GENERATED BY RESTAGE WIDGETBOOK STORY BUILDER
// ignore_for_file: library_private_types_in_public_api, unused_import

part 'manual_card.stories.g.dart';

final $RestageCatalog = _Story(args: _Args());
''';

final String _recognizableGeneratedManualStoryCrLf =
    _recognizableGeneratedManualStory.replaceAll('\n', '\r\n');

const _mixedNewlineGeneratedManualStory =
    '// GENERATED CODE - DO NOT MODIFY BY HAND\r\n'
    '// GENERATED BY RESTAGE WIDGETBOOK STORY BUILDER\n'
    '// ignore_for_file: library_private_types_in_public_api, unused_import\r\n';

const _widgetbookStub = '''
class Meta {
  const Meta(Object constructor, {required Object argsType});
}

class ComponentMeta {
  const ComponentMeta({this.name, this.path});
  final String? name;
  final String? path;
}

class Arg<T> {
  Arg(this.value, {this.name});
  final T value;
  final String? name;
  String? get description => null;
}

mixin NoFields<T> on Arg<T> {}

class BoolArg extends Arg<bool> {
  BoolArg(super.value, {super.name});
}
''';

const _storyPartStub = '''
part of 'callback_default_card.stories.dart';

typedef _Defaults = CallbackDefaultCardDefaults;
typedef _Story = CallbackDefaultCardStory;
typedef _Args = CallbackDefaultCardArgs;

typedef CallbackDefaultCardBuilder = restage_source.CallbackDefaultCard
    Function(Object? context, CallbackDefaultCardStoryInput args);

final class CallbackDefaultCardDefaults {
  CallbackDefaultCardDefaults({required this.builder});
  final CallbackDefaultCardBuilder builder;
}

final class CallbackDefaultCardStory {
  CallbackDefaultCardStory({required this.args});
  final CallbackDefaultCardArgs args;
}

final class CallbackDefaultCardArgs {
  CallbackDefaultCardArgs({
    required Object restageMetadataDescription,
    required Object restageMetadataUsage,
    required Object onTap,
    required Object onChanged,
    required Object onSubmitted,
    required Object onDismissed,
  });
}
''';

const _dispatcherStoryPartStub = '''
part of 'restage_event_dispatcher.stories.dart';

typedef _Defaults = RestageEventDispatcherDefaults;
typedef _Story = RestageEventDispatcherStory;
typedef _Args = RestageEventDispatcherArgs;

final class RestageEventDispatcherDefaults {
  RestageEventDispatcherDefaults({
    required Object builder,
    Object? setup,
  });
}

final class RestageEventDispatcherStory {
  RestageEventDispatcherStory({required Object args});
}

final class RestageEventDispatcherArgs {
  RestageEventDispatcherArgs({
    required Object restageMetadataDescription,
    required Object restageMetadataUsage,
  });
}
''';

String _lookalikeStorySource(String className) => '''
class RestageWidget {
  const RestageWidget();
}

@RestageWidget()
class $className {}
''';

const _lookalikeSameCard = '''
class RestageWidget {
  const RestageWidget();
}

@RestageWidget()
class SameCard {}
''';

const _genuineSameCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A genuine same-stem card.
@RestageWidget(
  name: 'GenuineSameCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'A genuine same-stem card.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _firstGenuineSameCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The first genuine same-stem card.
@RestageWidget(
  name: 'FirstSameCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'The first genuine same-stem card.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _secondGenuineSameCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The second genuine same-stem card.
@RestageWidget(
  name: 'SecondSameCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'The second genuine same-stem card.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _genuineCardsLibrary = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'cards_part.dart';

/// The first card in a multi-widget library.
@RestageWidget(
  name: 'FirstCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'The first card in a multi-widget library.',
)
class FirstCard extends StatelessWidget {
  const FirstCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _genuineCardsPart = '''
part of 'cards.dart';

/// The second card in a part file.
@RestageWidget(
  name: 'SecondCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'The second card in a part file.',
)
class SecondCard extends StatelessWidget {
  const SecondCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _sameNameWidgetAndScreen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/shared.restage.g.dart';

/// A customer widget under its ordinary Widgetbook path.
@RestageWidget(
  name: 'shared',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A customer widget under its ordinary Widgetbook path.',
)
class SharedCard extends StatelessWidget {
  const SharedCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A native screen under Widgetbook's reserved Screens path.
@ScreenSource(id: 'shared')
class SharedScreen extends StatelessWidget {
  const SharedScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _partOwnerLibrary = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'part_owner_piece.dart';
''';

const _partOwnerPiece = '''
part of 'part_owner.dart';

/// A genuine same-stem card declared in a part.
@RestageWidget(
  name: 'PartOwnerSameCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'A genuine same-stem card declared in a part.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _packagePartOwnerLibrary = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'package:apps_examples/src/package_part_piece.dart';
''';

const _packagePartOwnerPiece = '''
part of 'package:apps_examples/package_part_owner.dart';

@RestageWidget(
  name: 'PackagePartOwner',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A package URI part owner.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _sourceOwnerSameCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A genuine same-stem card declared in a library.
@RestageWidget(
  name: 'SourceOwnerSameCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  description: 'A genuine same-stem card declared in a library.',
)
class SameCard extends StatelessWidget {
  const SameCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
