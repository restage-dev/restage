import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(rfwCatalog, contains("name: 'CatalogShowcase'"));
    expect(rfwCatalog, isNot(contains('fires:')));
    expect(rfwCatalog, contains("name: 'onChanged'"));
    expect(rfwCatalog, contains("name: 'CatalogShowcaseData'"));
    expect(
      rfwFactories,
      allOf(
        contains(
          'final _restagePresenceEnabled = '
          'RestageRfwConstructorPresence.read(\n'
          '    source,\n'
          "    <Object>['enabled'],\n"
          '  );',
        ),
        contains(
          'if (_restagePresenceEnabled.supplied)\n'
          '          #enabled: '
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
    expect(widgetbookStory, contains('final _RestageValue4 header;'));
    expect(widgetbookStory, contains('final _RestageValue5 children;'));
    expect(widgetbookStory, contains('final _RestageValue6 data;'));
    expect(widgetbookPlumbing, contains('CatalogShowcaseComponent'));
  });

  test('reviewed multi-target artifacts remain byte-identical', () async {
    const expected = <String, String>{
      'lib/components.g.dart':
          'a364cb9946a538990de0f021bddb3809b30579bfe148a629a41474aab17e7ca7',
      'lib/generated/catalog_showcase.stories.dart':
          'e3fe9e2e60b98c76f4446fa802e9308bb7b5b0426af44eed2295ece17469eb4d',
      'lib/generated/catalog_showcase.stories.g.dart':
          '0f15d14c4857f7c7531b41e80176de121fb9f059f8b3304da64460115aff5ea7',
      'lib/generated/constructor_fidelity_corpus.stories.dart':
          'c604cb30a066f14dca657c01583c80ba1d356b54aac62c2ae4a26e8767b17b10',
      'lib/generated/constructor_fidelity_corpus.stories.g.dart':
          'ba977d79636443647c64ca317569ce1b34110ee7926eb34f2f17a6b05cc802db',
      'lib/generated/constructor_fidelity_proof.stories.dart':
          '58c9846340a7db025e27cceb6a94e5edbf01ee004b6467f99e5a7646bf7857e2',
      'lib/generated/constructor_fidelity_proof.stories.g.dart':
          'e90c0925d0049681f577b2f42c42a581950e629284e137149262a23298630017',
      'lib/generated/constructor_positional_corpus.stories.dart':
          '8ae26adf6b3a62d775afb3c28d87e3af14b44040e25ece3878739de2bc61043e',
      'lib/generated/constructor_positional_corpus.stories.g.dart':
          '5970606ecfe5780fd048b8eb739cce559aa808fcad30d2969e938297c3b26412',
      'lib/generated/feature_panel.stories.dart':
          'c8672ede8cb3b564070f46233d09468fc2e23cf271b224432cb1236187817c8c',
      'lib/generated/feature_panel.stories.g.dart':
          '0d9b9c5b221751da62371fef79e39b07f59d7bfe4d1d34744f3f96ef05ac59a3',
      'lib/generated/feature_row.stories.dart':
          'c796f6865b41cb8a388bdcb9c7c20f0971526a310aa829534c57750cb6d0dfe5',
      'lib/generated/feature_row.stories.g.dart':
          'd9b6e954c9759b335d0c0e1370461a733e2210d34f7bc6880d0799e5d09f69cc',
      'lib/generated/price_badge.stories.dart':
          'ec75cdb0b73a0231f6446c730c69fd158d2a4b867e2314892d6881fae281a703',
      'lib/generated/price_badge.stories.g.dart':
          '49b03608f8280bc246812a0c3e56a548b8f2862bbac8e4b1f133a8ea6a47fc57',
      'lib/generated/stat_tile.stories.dart':
          '6d6966f26dc7fbaef6cb875c81d0d6d2d3f267671fb780b4f865449c53d49b9b',
      'lib/generated/stat_tile.stories.g.dart':
          'b45f9304c3635b76c45b86c676b2ab33a4aa3ee868535f7f021fadcc4de27bbb',
      'lib/generated/restage_a2ui_catalog.a2ui.json':
          '353251a1941bd152db190703534a5059ed606fc6b66eba1b529218cdec0385b4',
      'lib/generated/restage_a2ui_catalog.g.dart':
          'd7d7288fc8aefc3d60eb85d4285a08f711eb602323b23749d4a3479e763763ab',
      'lib/src/widget_catalog/catalog.json':
          'f74076aa38d14357542b5adce971d24714f91774beef0149289e10d1f1e717ed',
      'lib/user_catalog.g.dart':
          '19eadab846cd0f34f715defc37ef020d0d791168494f274d0457cc1dd1d0126e',
      'lib/user_factories.g.dart':
          '8ba7e30649b6f31f87eb2010769d20d9bf8acc53b0284033e8457d47fba5b7fc',
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
