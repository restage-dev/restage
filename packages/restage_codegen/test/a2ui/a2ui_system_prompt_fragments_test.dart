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
  test('emits one reviewed catalog ID across the constant and Catalog wiring',
      () {
    final catalog = _threeWidgets();
    final registration = emitA2uiCatalog(
      catalog,
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    );
    final dart = emitA2uiCatalogDart(
      catalog,
      registration: registration,
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    );

    expect(
      dart,
      matches(
        RegExp(
          r'const String restageA2uiCatalogId =\s*'
          "'${RegExp.escape(registration.documentId)}';",
        ),
      ),
    );
    expect(
      dart,
      contains(registration.systemPromptFragments.first),
    );
    expect(dart, contains('catalogId: restageA2uiCatalogId'));

    final standalone =
        registration.toJson()['a2uiCatalog']! as Map<String, Object?>;
    expect(standalone[r'$id'], registration.documentId);
    expect(standalone['catalogId'], registration.documentId);
    expect(
      standalone['systemPromptFragments'],
      registration.systemPromptFragments,
    );
  });

  test('documents the generated identity and integration boundaries', () {
    final catalog = _threeWidgets();
    final registration = emitA2uiCatalog(catalog);
    final dart = emitA2uiCatalogDart(catalog, registration: registration);

    expect(
      dart,
      contains('/// Items for the generated custom-only catalog.'),
    );
    expect(
      dart,
      contains(
        '/// A composed Catalog must use a new application-owned catalog ID;',
      ),
    );
    expect(
      dart,
      contains(
        '/// Content address for exactly the generated custom-only catalog.',
      ),
    );
    expect(
      dart,
      contains(
        '/// Default A2A supportedCatalogIds use requires server registration',
      ),
    );
    expect(
      dart,
      contains('/// of this exact predefined catalog contract.'),
    );
    expect(
      dart,
      contains('/// GenUI 0.10.1 inline catalogs are serialization-only here;'),
    );
    expect(
      dart,
      contains('/// no end-to-end inline server interoperability is claimed.'),
    );
    expect(
      dart,
      contains(
        '/// Builds the generated custom-only GenUI catalog identified by',
      ),
    );
    expect(dart, contains('/// [restageA2uiCatalogId].'));
  });

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
    final registration = emitA2uiCatalog(
      _threeWidgets(),
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    );
    final stamp = registration.toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    expect(
      a2uiCatalog['systemPromptFragments'],
      registration.systemPromptFragments,
    );
    expect(
      registration.nonIdentitySystemPromptFragments,
      <String>['Alpha: Use Alpha for X.', 'Beta: Beta desc'],
    );
  });

  test('Dart emission rejects a registration from a different contract', () {
    final wrongSchema = emitA2uiCatalog(_noMetadataWidget());
    expect(
      () => emitA2uiCatalogDart(_threeWidgets(), registration: wrongSchema),
      throwsStateError,
    );

    final wrongPrompt = emitA2uiCatalog(
      _threeWidgets(),
      usageByWidget: const {'Alpha': 'Use Alpha for X.'},
    );
    expect(
      () => emitA2uiCatalogDart(
        _threeWidgets(),
        registration: wrongPrompt,
        usageByWidget: const {'Alpha': 'Use Alpha differently.'},
      ),
      throwsStateError,
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

  test('a catalog with no metadata carries only its identity fragment', () {
    final registration = emitA2uiCatalog(_noMetadataWidget());
    final stamp = registration.toJson();
    final a2uiCatalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    expect(registration.nonIdentitySystemPromptFragments, isEmpty);
    expect(
      a2uiCatalog['systemPromptFragments'],
      registration.systemPromptFragments,
    );
    expect(registration.systemPromptFragments, hasLength(1));
  });
}
