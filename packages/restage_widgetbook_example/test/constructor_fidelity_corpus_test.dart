import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/widgets/constructor_fidelity_corpus.dart';
  const propertyPath = '$sourcePath#ConstructorFidelityCorpus.focusNode';

  late String source;
  late String rfwCatalog;
  late String rfwFactories;
  late String a2uiCatalog;
  late String widgetbookStory;
  late String positionalStory;

  setUpAll(() async {
    source = await File(sourcePath).readAsString();
    rfwCatalog = await File('lib/user_catalog.g.dart').readAsString();
    rfwFactories = await File('lib/user_factories.g.dart').readAsString();
    a2uiCatalog = await File(
      'lib/generated/restage_a2ui_catalog.g.dart',
    ).readAsString();
    widgetbookStory = await File(
      'lib/generated/constructor_fidelity_corpus.stories.dart',
    ).readAsString();
    positionalStory = await File(
      'lib/generated/constructor_positional_corpus.stories.dart',
    ).readAsString();
  });

  test('the named corpus remains present before target assertions', () {
    expect(source, contains('class ConstructorFidelityCorpus'));
    expect(source, contains('this.focusNode'));
    expect(source, contains('@ignore this.localOnly'));

    for (final artifact in <(String, String)>[
      ('RFW catalog', rfwCatalog),
      ('RFW factories', rfwFactories),
      ('A2UI catalog', a2uiCatalog),
      ('Widgetbook story', widgetbookStory),
    ]) {
      expect(
        artifact.$2,
        contains('ConstructorFidelityCorpus'),
        reason: '${artifact.$1} must retain the widget before shape checks',
      );
    }
  });

  test('one named corpus exercises the shared accepted constructor truth', () {
    expect(
      rfwCatalog,
      allOf(<Matcher>[
        contains("name: 'ordinaryLabel'"),
        contains("name: 'requiredNamed'"),
        contains('constructorNullable: true'),
        contains("member: 'ready'"),
        contains("owner: 'ConstructorCorpusDefaults'"),
        contains("name: 'resetProof'"),
        contains("name: 'whenEnabledChanges'"),
        contains("name: 'reportCount'"),
      ]),
    );
    expect(
      rfwFactories,
      allOf(<Matcher>[
        contains('#value:'),
        contains('#ordinaryLabel:'),
        contains('#requiredNamed:'),
        contains('if (_restagePresenceNullableText.supplied)'),
        contains('if (_restagePresenceNullableSeed.supplied)'),
        contains('#resetProof:'),
        contains('#whenEnabledChanges:'),
        contains('#reportCount:'),
      ]),
    );
    expect(
      a2uiCatalog,
      allOf(<Matcher>[
        contains('.ConstructorFidelityCorpus('),
        contains('restageA2uiWriteEnabled'),
        contains('restageA2uiWriteCount'),
        contains("name: 'resetProof'"),
        contains("field: 'enabled'"),
        contains("field: 'count'"),
      ]),
    );
    expect(
      widgetbookStory,
      allOf(<Matcher>[
        contains('class ConstructorFidelityCorpusStoryInput'),
        contains('this.nullableText = null'),
        contains('this.nullableSeed = "nullable-default"'),
        contains('this.enabled = true'),
        contains('this.count = 7'),
        contains('ConstructorCorpusDefaults.publicColor'),
        contains('ConstructorCorpusDefaults.publicData'),
        contains('resetProof: () {}'),
        contains('whenEnabledChanges: (_) {}'),
        contains('reportCount: (_) {}'),
      ]),
    );
  });

  test(
    'host plumbing is target-qualified and @ignore disappears only input',
    () {
      for (final artifact in <(String, String, String, String)>[
        ("property: 'focusNode'", "target: 'rfw'", 'rfw', rfwCatalog),
        ('"property": "focusNode"', '"target": "a2ui"', 'a2ui', a2uiCatalog),
        (
          '"property": "focusNode"',
          '"target": "widgetbook"',
          'widgetbook',
          widgetbookStory,
        ),
      ]) {
        expect(artifact.$4, contains(artifact.$1), reason: artifact.$3);
        expect(artifact.$4, contains(artifact.$2), reason: artifact.$3);
        expect(artifact.$4, contains(propertyPath), reason: artifact.$3);
        expect(artifact.$4, isNot(contains('localOnly')), reason: artifact.$3);
      }
      expect(rfwFactories, isNot(contains('focusNode')));
      expect(rfwFactories, isNot(contains('localOnly')));
    },
  );

  test('the positional corpus remains present and ordered in every target', () {
    expect(source, contains('class ConstructorPositionalCorpus'));
    for (final artifact in <(String, String)>[
      ('RFW catalog', rfwCatalog),
      ('RFW factories', rfwFactories),
      ('A2UI catalog', a2uiCatalog),
      ('Widgetbook story', positionalStory),
    ]) {
      expect(
        artifact.$2,
        contains('ConstructorPositionalCorpus'),
        reason: '${artifact.$1} must retain the positional widget',
      );
    }

    expect(
      rfwFactories,
      allOf(
        contains(
          'if (_restagePresenceLeading.supplied || '
          '_restagePresenceTrailing.supplied)',
        ),
        contains(": 'leading-default'"),
        contains('if (_restagePresenceTrailing.supplied)'),
      ),
    );
    expect(
      a2uiCatalog,
      allOf(
        contains("requiredLabel ?? ''"),
        contains("leading ?? 'leading-default'"),
        contains("trailing ?? 'trailing-default'"),
      ),
    );
    expect(
      positionalStory,
      contains(
        'restage_source.ConstructorPositionalCorpus(\n'
        '    args.requiredLabel,\n'
        '    args.leading,\n'
        '    args.trailing,',
      ),
    );
  });
}
