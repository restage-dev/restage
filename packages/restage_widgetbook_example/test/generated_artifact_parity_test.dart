import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'one normal build owns every screen target artifact and registration',
    () async {
      const requiredPaths = <String>[
        'lib/onboarding/screens/opaque_screen_proof.rsscreen.g.dart',
        'assets/onboarding/screens/opaque_screen_proof.rfwtxt',
        'assets/onboarding/screens/opaque_screen_proof.rfw',
        'assets/onboarding/screens/opaque_screen_proof.capability.json',
        'lib/generated/restage_a2ui_catalog.g.dart',
        'lib/generated/restage_a2ui_catalog.a2ui.json',
        'lib/generated/opaque_screen_proof.stories.dart',
        'lib/generated/opaque_screen_proof.stories.g.dart',
        'lib/components.g.dart',
      ];
      for (final path in requiredPaths) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }

      final a2uiDart = await File(
        'lib/generated/restage_a2ui_catalog.g.dart',
      ).readAsString();
      final a2uiDocument =
          jsonDecode(
                await File(
                  'lib/generated/restage_a2ui_catalog.a2ui.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      final a2uiCatalog = a2uiDocument['a2uiCatalog']! as Map<String, Object?>;
      final components = a2uiCatalog['components']! as Map<String, Object?>;
      const expectedCustomerComponents = <String>{
        'BareCatalogCard',
        'CatalogShowcase',
        'ConstructorFidelityCorpus',
        'ConstructorFidelityProof',
        'ConstructorPositionalCorpus',
        'FeaturePanel',
        'FeatureRow',
        'PriceBadge',
        'RequiredNullableWidgetProof',
        'StatTile',
        'opaque_screen_proof',
      };
      expect(components.keys.toSet(), expectedCustomerComponents);
      expect(a2uiDart, contains("name: 'opaque_screen_proof'"));
      expect(a2uiDart, contains(RegExp(r'\bp\d+\.OpaqueScreenProof\(')));

      final story = await File(
        'lib/generated/opaque_screen_proof.stories.dart',
      ).readAsString();
      final plumbing = await File(
        'lib/generated/opaque_screen_proof.stories.g.dart',
      ).readAsString();
      final registry = await File('lib/components.g.dart').readAsString();
      expect(story, contains("path: 'Screens'"));
      expect(story, contains('restage_runtime.RestageSurfaceEventDispatcher('));
      expect(story, contains('final String restageMetadataDescription;'));
      expect(story, contains('final String restageMetadataUsage;'));
      expect(story, contains('final String description;'));
      expect(story, contains('final String usage;'));
      expect(story, contains("name: 'Restage description'"));
      expect(story, contains("name: 'Restage usage'"));
      expect(
        story,
        contains('restageMetadataDescription: _RestageMetadataArg('),
      );
      expect(story, contains('restageMetadataUsage: _RestageMetadataArg('));
      expect(plumbing, contains('Arg<String>? restageMetadataDescription'));
      expect(plumbing, contains('Arg<String>? description'));
      expect(plumbing, contains('setup: setup ?? defaults.setup!'));
      expect(registry, contains('OpaqueScreenProofComponent'));
    },
  );

  test('a documented bare marker reaches every generated target', () async {
    final rfwCatalog = await File('lib/user_catalog.g.dart').readAsString();
    final rfwFactories = await File('lib/user_factories.g.dart').readAsString();
    final a2uiCatalog = await File(
      'lib/generated/restage_a2ui_catalog.g.dart',
    ).readAsString();
    final widgetbookStory = await File(
      'lib/generated/bare_catalog_card.stories.dart',
    ).readAsString();
    final widgetbookPlumbing = await File(
      'lib/generated/bare_catalog_card.stories.g.dart',
    ).readAsString();

    expect(rfwCatalog, contains("name: 'BareCatalogCard'"));
    expect(rfwCatalog, contains('category: null,'));
    expect(rfwFactories, contains('RestageWidgetFactory('));
    expect(rfwFactories, contains("name: 'BareCatalogCard'"));
    expect(a2uiCatalog, contains("name: 'BareCatalogCard'"));
    expect(widgetbookStory, contains('class BareCatalogCardStoryInput'));
    expect(
      widgetbookStory,
      contains('const component = widgetbook.ComponentMeta('),
    );
    expect(widgetbookStory, contains("path: ''"));
    expect(widgetbookPlumbing, contains('BareCatalogCardComponent'));
    expect(widgetbookPlumbing, contains("path: component.path ?? 'generated'"));
  });

  test('one customer source reaches RFW, A2UI, and Widgetbook', () async {
    final rfwCatalog = await File('lib/user_catalog.g.dart').readAsString();
    final rfwFactories = await File('lib/user_factories.g.dart').readAsString();
    final a2uiCatalog = await File(
      'lib/generated/restage_a2ui_catalog.g.dart',
    ).readAsString();
    final widgetbookStory = await File(
      'lib/generated/catalog_showcase.stories.dart',
    ).readAsString();
    final widgetbookPlumbing = await File(
      'lib/generated/catalog_showcase.stories.g.dart',
    ).readAsString();
    final normalizedRfwFactories = rfwFactories.replaceAll(RegExp(r'\s+'), ' ');
    final showcaseEntryStart = rfwCatalog.indexOf("name: 'CatalogShowcase'");
    final showcasePropertiesStart = rfwCatalog.indexOf(
      'properties: [',
      showcaseEntryStart,
    );

    expect(rfwCatalog, contains("name: 'CatalogShowcase'"));
    expect(showcaseEntryStart, isNonNegative);
    expect(showcasePropertiesStart, greaterThan(showcaseEntryStart));
    expect(
      rfwCatalog.substring(showcaseEntryStart, showcasePropertiesStart),
      contains('category: WidgetCategory.input,'),
    );
    expect(rfwCatalog, isNot(contains('fires:')));
    expect(rfwCatalog, contains("name: 'onChanged'"));
    expect(rfwCatalog, contains("name: 'CatalogShowcaseData'"));
    expect(
      normalizedRfwFactories,
      allOf(
        contains(
          'final _restagePresenceEnabled = '
          "RestageRfwConstructorPresence.read( source, <Object>['enabled'], );",
        ),
        contains(
          'if (_restagePresenceEnabled.supplied) #enabled: '
          'source.v<bool>(_restagePresenceEnabled.valuePath),',
        ),
        isNot(contains("source.v<bool>(<Object>['enabled']) ?? true")),
      ),
    );
    expect(a2uiCatalog, contains('restageA2uiWriteEnabled'));
    expect(a2uiCatalog, contains('enabled: enabled ?? true'));
    expect(
      a2uiCatalog,
      contains(
        'CatalogShowcase: Use to verify a customer catalog across RFW, '
        'A2UI, and Widgetbook.',
      ),
    );
    expect(widgetbookStory, contains('class CatalogShowcaseStoryInput'));
    expect(widgetbookStory, contains('final bool enabled;'));
    expect(widgetbookStory, contains('this.enabled = true'));
    expect(widgetbookStory, contains('final _RestageChoice2 status;'));
    expect(widgetbookStory, contains(r'final $RestageCatalog'));
    expect(widgetbookStory, contains(r'final $EnabledFalse'));
    expect(widgetbookStory, contains(r'final $StatusProcessing'));
    expect(widgetbookStory, contains('final _RestageValue4 hero;'));
    expect(widgetbookStory, contains('final _RestageValue5 details;'));
    expect(widgetbookStory, contains('final _RestageValue6 footer;'));
    expect(widgetbookStory, contains('final _RestageValue7 data;'));
    expect(widgetbookStory, contains("ComponentMeta(path: 'input')"));
    expect(widgetbookPlumbing, contains('CatalogShowcaseComponent'));
    expect(
      widgetbookPlumbing,
      contains(r"$EnabledFalse..$generatedName = 'EnabledFalse'"),
    );
    expect(
      widgetbookPlumbing,
      contains(r"$StatusProcessing..$generatedName = 'StatusProcessing'"),
    );
  });

  test('reviewed multi-target artifacts remain byte-identical', () async {
    const expected = <String, String>{
      'lib/components.g.dart':
          'f9440584e67aa2874501f953f3609beb0576233642c8829b69c54fbca8155c93',
      'lib/generated/bare_catalog_card.stories.dart':
          'd3455d3c5b04b717da01974ae98c092771feef7adbf3f46339651980faba489f',
      'lib/generated/bare_catalog_card.stories.g.dart':
          '9d1d0279d72c86bf074ee4ff532e3ec50ea545106b18a252de0cdc9adc096ee5',
      'lib/generated/catalog_showcase.stories.dart':
          'c36aaf102f313b3c81927eae8dd698f3c85a66624814b3389fdb33c21a2f0c7f',
      'lib/generated/catalog_showcase.stories.g.dart':
          '5fb8391fb085a49e2e9a5ee6aff5c5e04eba7907b91afd23e0139ad2531817c8',
      'lib/generated/constructor_fidelity_corpus.stories.dart':
          'e8794adced2b139eee44e4b0581e4b6c9e2026392c2cea9d5cb717e70a19c966',
      'lib/generated/constructor_fidelity_corpus.stories.g.dart':
          '5054c7b54ab2909d7fb1f3577455ff8015962fd23643a7bf3f0818734782c975',
      'lib/generated/constructor_fidelity_proof.stories.dart':
          'd4c7bf6d8356da191058488124c23d17d71240004f6eddd35362c09d1aed3635',
      'lib/generated/constructor_fidelity_proof.stories.g.dart':
          'a4f73f6fda7b89d44aab07cb4d1b7c8809db216d11f5c6e9ef9341326b38cfd2',
      'lib/generated/constructor_positional_corpus.stories.dart':
          '228c83de986adc18ed0b016255d2bb9a85b02bc30abec70eef229ad7f2ef1391',
      'lib/generated/constructor_positional_corpus.stories.g.dart':
          'b79c6aa3ae8b4590fef866354805abc97e56ee5266670afc5c88ebebbad63bdc',
      'lib/generated/feature_panel.stories.dart':
          '55d41541f0294f730e9e9ee5ebc601c8adc536fc07dce91d204a8c73ecc69c7d',
      'lib/generated/feature_panel.stories.g.dart':
          '1965620a8f92484dfa2ab3576471b276e34fd8edd0fca9048ce5b1e60f32fc00',
      'lib/generated/feature_row.stories.dart':
          'cb21c23ccf7b8a90392092fb724916c0ca4f6d9e06e1b1a811f14450d9644ba9',
      'lib/generated/feature_row.stories.g.dart':
          '11f50884baf6d849801e7ad8e2f0f98e8f1eeb19d9c222a4dfddf15f45effbab',
      'lib/generated/price_badge.stories.dart':
          '9a8bebbd5e950b3ec6c28a22c37806e540f3e5358748d2ac0f71eea475123e53',
      'lib/generated/price_badge.stories.g.dart':
          '770e32a0044e272ce252ff1180a8c8a01ddf5fe58748bf9561a50a728ca46e7a',
      'lib/generated/required_nullable_widget_proof.stories.dart':
          'bcec9c78205f8dfa558cc7a001d5d7e497bd7ee55ff593edeedd6c9f79b11bd9',
      'lib/generated/required_nullable_widget_proof.stories.g.dart':
          '7991b8a28677fb22cdc3eca4cb476e32f8594cd7f921f6afca1b53ecebe74eb0',
      'lib/generated/opaque_screen_proof.stories.dart':
          'f21ef76e20a1c53ed0ca4aeaa7e1fe8e656791a52b635eab14da9614beade805',
      'lib/generated/opaque_screen_proof.stories.g.dart':
          '4eb3ac7232788f2e2289ba2e4509f90b97d410b6cd97aac16fd65373db728156',
      'lib/generated/stat_tile.stories.dart':
          '5396ace7194246c9fe74d7296b1b625d1ec0537d46679c12b9fab9ecc4abfffa',
      'lib/generated/stat_tile.stories.g.dart':
          'de665a7375935c82dcc010b79228552eb5e62f2e5f79df52f6cde108d68f0357',
      'lib/generated/restage_a2ui_catalog.a2ui.json':
          'd87ed0601571f76401fce3d530a60eda52df2a70100945c8fafcd1abdeea77b4',
      'lib/generated/restage_a2ui_catalog.g.dart':
          'b10bf858b9d5e86e2a0d4b9b49598b4ac8dbcd319784e35ad4236d2e6a6da4a5',
      'lib/src/widget_catalog/catalog.json':
          '5c4aca8207e886e4016c3e77e18ee52244a2b09985ea936ed6e557272e2b77d3',
      'lib/user_catalog.g.dart':
          '02e26b85571e5b423d107dc7217446b962054d0a8e28769d92dce15936af9ea7',
      'lib/user_factories.g.dart':
          'd6a2a6aaa61c7c761ba871ea611ced2a62ad03dccda7c27e509843c7e31fd317',
    };

    for (final entry in expected.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: 'missing ${entry.key}');
      expect(
        sha256.convert(await file.readAsBytes()).toString(),
        entry.value,
        reason:
            '${entry.key} drifted; review the target-specific delta before '
            'updating the reviewed artifact manifest',
      );
    }
  });
}
