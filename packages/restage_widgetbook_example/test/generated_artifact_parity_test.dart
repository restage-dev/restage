import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('one normal build owns every screen target artifact and registration', () async {
    // Generated source stays on disk as ordinary files.
    const requiredSources = <String>[
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.restage.g.dart',
      'lib/generated/restage_a2ui_catalog.g.dart',
      'lib/generated/restage_a2ui_catalog.a2ui.json',
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.dart',
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.g.dart',
      'lib/components.g.dart',
    ];
    for (final path in requiredSources) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }

    // Delivery artifacts ship inside the package's containers rather than as
    // loose files, so ownership is checked where they actually are.
    const requiredArtifacts = <String>[
      'assets/onboarding/screens/opaque_screen_proof.rfwtxt',
      'assets/onboarding/screens/opaque_screen_proof.rfw',
      'assets/onboarding/screens/opaque_screen_proof.capability.json',
    ];
    final packaged = _packagedArtifacts();
    for (final path in requiredArtifacts) {
      expect(packaged, contains(path), reason: path);
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
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.dart',
    ).readAsString();
    final plumbing = await File(
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.g.dart',
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
    expect(story, contains('restageMetadataDescription: _RestageMetadataArg('));
    expect(story, contains('restageMetadataUsage: _RestageMetadataArg('));
    expect(plumbing, contains('Arg<String>? restageMetadataDescription'));
    expect(plumbing, contains('Arg<String>? description'));
    expect(plumbing, contains('setup: setup ?? defaults.setup!'));
    expect(registry, contains('OpaqueScreenProofComponent'));
  });

  test('a documented bare marker reaches every generated target', () async {
    final rfwCatalog = await File('lib/user_catalog.g.dart').readAsString();
    final rfwFactories = await File('lib/user_factories.g.dart').readAsString();
    final a2uiCatalog = await File(
      'lib/generated/restage_a2ui_catalog.g.dart',
    ).readAsString();
    final widgetbookStory = await File(
      'lib/widgets/restage.generated/bare_catalog_card.stories.dart',
    ).readAsString();
    final widgetbookPlumbing = await File(
      'lib/widgets/restage.generated/bare_catalog_card.stories.g.dart',
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
    expect(
      widgetbookPlumbing,
      contains("path: component.path ?? 'widgets/restage.generated'"),
    );
  });

  test('one customer source reaches RFW, A2UI, and Widgetbook', () async {
    final rfwCatalog = await File('lib/user_catalog.g.dart').readAsString();
    final rfwFactories = await File('lib/user_factories.g.dart').readAsString();
    final a2uiCatalog = await File(
      'lib/generated/restage_a2ui_catalog.g.dart',
    ).readAsString();
    final widgetbookStory = await File(
      'lib/widgets/restage.generated/catalog_showcase.stories.dart',
    ).readAsString();
    final widgetbookPlumbing = await File(
      'lib/widgets/restage.generated/catalog_showcase.stories.g.dart',
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
          '8cfc10269daf1ddfd00aeffb5ef23f3c2f223dbcfec550a301b7231ea87c0d1d',
      'lib/widgets/restage.generated/bare_catalog_card.stories.dart':
          'd3455d3c5b04b717da01974ae98c092771feef7adbf3f46339651980faba489f',
      'lib/widgets/restage.generated/bare_catalog_card.stories.g.dart':
          '3bc80fb337b376b90cc191372f75ef425a2121aacf91ee0dd6f10bef305534e7',
      'lib/widgets/restage.generated/catalog_showcase.stories.dart':
          'c36aaf102f313b3c81927eae8dd698f3c85a66624814b3389fdb33c21a2f0c7f',
      'lib/widgets/restage.generated/catalog_showcase.stories.g.dart':
          '17ac4625262b5a3aeab1d7daf0db5d9728dc9eb466ebc48d3ec595c010009f74',
      'lib/widgets/restage.generated/constructor_fidelity_corpus.stories.dart':
          'e8794adced2b139eee44e4b0581e4b6c9e2026392c2cea9d5cb717e70a19c966',
      'lib/widgets/restage.generated/constructor_fidelity_corpus.stories.g.dart':
          '186091254117d671a8173a03e5f9c7797728f19b45ba34d03b0fac5d36bfc464',
      'lib/widgets/restage.generated/constructor_fidelity_proof.stories.dart':
          'd4c7bf6d8356da191058488124c23d17d71240004f6eddd35362c09d1aed3635',
      'lib/widgets/restage.generated/constructor_fidelity_proof.stories.g.dart':
          '264d02cc8c639a2b70486d05e8e6fe7e8116ac1fe00c77efba9c12cc08a34139',
      'lib/widgets/restage.generated/constructor_positional_corpus.stories.dart':
          '228c83de986adc18ed0b016255d2bb9a85b02bc30abec70eef229ad7f2ef1391',
      'lib/widgets/restage.generated/constructor_positional_corpus.stories.g.dart':
          '34343c1866427f784a3f0c42a75d1299ac91c5b39024f1c26968426a4b9a9ff9',
      'lib/widgets/restage.generated/feature_panel.stories.dart':
          '55d41541f0294f730e9e9ee5ebc601c8adc536fc07dce91d204a8c73ecc69c7d',
      'lib/widgets/restage.generated/feature_panel.stories.g.dart':
          '50dc279b1a544b647ac3bab4dcb89f90b0c323052a6d5a1e97dc1e46010726e4',
      'lib/widgets/restage.generated/feature_row.stories.dart':
          'cb21c23ccf7b8a90392092fb724916c0ca4f6d9e06e1b1a811f14450d9644ba9',
      'lib/widgets/restage.generated/feature_row.stories.g.dart':
          '2896334f552cd9f8dd48503064cd4bafc823aaeed48a2c1158e737bb8578beb6',
      'lib/widgets/restage.generated/price_badge.stories.dart':
          '9a8bebbd5e950b3ec6c28a22c37806e540f3e5358748d2ac0f71eea475123e53',
      'lib/widgets/restage.generated/price_badge.stories.g.dart':
          '4857e21e3c3b9e9ad47e19d803fdb99d4fe122182f4a1cfa8e71306a899e1dfa',
      'lib/widgets/restage.generated/required_nullable_widget_proof.stories.dart':
          'bcec9c78205f8dfa558cc7a001d5d7e497bd7ee55ff593edeedd6c9f79b11bd9',
      'lib/widgets/restage.generated/required_nullable_widget_proof.stories.g.dart':
          'eba61dcb87d9bd63b0f2473c88b1c060b876e09822c2ced78957d2b537f2def6',
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.dart':
          'f21ef76e20a1c53ed0ca4aeaa7e1fe8e656791a52b635eab14da9614beade805',
      'lib/onboarding/screens/restage.generated/opaque_screen_proof.stories.g.dart':
          '752764a1a6f72d5ea40a54ed7e88a3cfdeaba2b6587566fb313e701c92504521',
      'lib/widgets/restage.generated/stat_tile.stories.dart':
          '5396ace7194246c9fe74d7296b1b625d1ec0537d46679c12b9fab9ecc4abfffa',
      'lib/widgets/restage.generated/stat_tile.stories.g.dart':
          'bd04dc3cc60131c8136be332505be46b36875455d8f125c8ff5de57c258dbb72',
      'lib/generated/restage_a2ui_catalog.a2ui.json':
          'd87ed0601571f76401fce3d530a60eda52df2a70100945c8fafcd1abdeea77b4',
      'lib/generated/restage_a2ui_catalog.g.dart':
          '19c99024642e1d602769998670e4f75918756f32cf8acd42abf98c1c1eea03f6',
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

/// Every logical delivery artifact this package ships, read out of the
/// deterministic containers it packages them into.
Set<String> _packagedArtifacts() {
  final bundles = Directory('assets/restage/bundles');
  if (!bundles.existsSync()) return const <String>{};
  return <String>{
    for (final file in bundles.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.rsbundle'))
        ...RestageBundleCodec.decode(
          file.readAsBytesSync(),
        ).entries.map((entry) => entry.logicalPath),
  };
}
