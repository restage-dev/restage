import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// A three-widget customer catalog: `Alpha` and `Beta` each carry a
/// description, `Gamma` carries neither — so the fragment-composition rule
/// (usage overrides description; both absent skips the widget) has one
/// widget per case.
Catalog _threeWidgets() {
  const acme = WidgetLibrary.custom('acme.widgets');
  WidgetEntry widget(String name, String description) => WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: name,
        library: acme,
        category: WidgetCategory.decoration,
        description: description,
        flutterType: 'package:acme_widgets/$name.dart#$name',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: const [],
      );
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      acme: const LibraryInfo(version: '1.0.0', capabilityVersion: 1),
    },
    widgets: [
      widget('Alpha', 'Alpha desc'),
      widget('Beta', 'Beta desc'),
      widget('Gamma', ''),
    ],
  );
}

/// A single-widget catalog with no description and no usage — every widget
/// falls into the both-absent case, so no fragment can ever be composed.
Catalog _noMetadataWidget() {
  const acme = WidgetLibrary.custom('acme.widgets');
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      acme: const LibraryInfo(version: '1.0.0', capabilityVersion: 1),
    },
    widgets: const [
      WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Gamma',
        library: acme,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:acme_widgets/Gamma.dart#Gamma',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [],
      ),
    ],
  );
}

void main() {
  test(
      'usage overrides description; description is the fallback; '
      'both-absent skips the widget', () {
    final dart = emitA2uiCatalogDart(
      _threeWidgets(),
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    );
    expect(dart, contains("'Alpha: Use Alpha for X.'"));
    expect(dart, contains("'Beta: Beta desc'"));
    expect(dart, isNot(contains('Gamma:')));
    expect(dart, contains('Catalog buildRestageCatalog()'));
    expect(
      dart,
      contains('systemPromptFragments: _restageA2uiSystemPromptFragments'),
    );
  });

  test('the same fragments land in the .a2ui.json stamp', () {
    final stamp = emitA2uiCatalog(
      _threeWidgets(),
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    ).toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    expect(
      a2uiCatalog['systemPromptFragments'],
      <String>['Alpha: Use Alpha for X.', 'Beta: Beta desc'],
    );
  });

  test(
      r'a usage containing "$", a CRLF, a single quote, and a newline '
      'emits without throwing and with the correctly-escaped fragment '
      'literal', () {
    const usage = "Costs \$5/mo\r\nDon't miss \$Widget.\nEnd.";
    final dart = emitA2uiCatalogDart(
      _threeWidgets(),
      usageByWidget: {'Alpha': usage},
    );
    expect(
      dart,
      contains(
        r"'Alpha: Costs \$5/mo\r\nDon\'t miss \$Widget.\nEnd.'",
      ),
    );
  });

  test(
      'a catalog with no usage and no descriptions omits '
      'systemPromptFragments from the stamp entirely', () {
    final stamp = emitA2uiCatalog(_noMetadataWidget()).toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    expect(a2uiCatalog.containsKey('systemPromptFragments'), isFalse);
  });
}
