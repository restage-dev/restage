import 'dart:async';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _coreCatalog = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.core": {"version": "0.1.0", "widgetCount": 2, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Center",
      "library": "restage.core",
      "category": "layout",
      "description": "Centers its child within itself.",
      "flutterType": "package:restage_core/src/widgets/center.dart#Center",
      "childrenSlot": "single",
      "fires": [],
      "properties": [],
      "stability": "volatile"
    },
    {
      "wireId": "w0002",
      "name": "SizedBox",
      "library": "restage.core",
      "category": "layout",
      "description": "A box with explicit dimensions.",
      "flutterType": "package:restage_core/src/widgets/sized_box.dart#SizedBox",
      "childrenSlot": "single",
      "fires": [],
      "properties": [],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

const _materialCatalog = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.material": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "FilledButton",
      "library": "restage.material",
      "category": "input",
      "description": "Material filled button.",
      "flutterType": "package:flutter/material.dart#FilledButton",
      "childrenSlot": "single",
      "fires": ["onPressed"],
      "properties": [],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

// Shadowing case. Two built-ins claiming the same name is impossible
// (the catalog generator rejects it), but a customer library *can*
// register a name that shadows a built-in — that's the case the
// translator's ambiguity diagnostic targets. This synthetic fixture
// uses two built-ins as a stand-in to prove the loader surfaces
// multiple matches; the loader doesn't care which library is built-in
// vs customer.
const _materialCatalogWithShadow = '''
{
  "schemaVersion": 4,
  "generatedAt": "2026-05-09T00:00:00Z",
  "libraries": {
    "restage.material": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Center",
      "library": "restage.material",
      "category": "layout",
      "description": "A material-flavoured Center, somehow.",
      "flutterType": "package:flutter/material.dart#MCenter",
      "childrenSlot": "single",
      "fires": [],
      "properties": [],
      "stability": "volatile"
    }
  ],
  "structuredTypes": [],
  "unions": [],
  "designTokens": []
}
''';

void main() {
  group('loadMergedCatalog', () {
    test('preserves full native graph sections from v4 catalogs', () async {
      final catalog = await _runLoaderWith({
        'restage_core': encodeCatalog(_fullGraphCoreCatalog()),
      });

      expect(catalog.schemaVersion, kSupportedSchemaVersion);
      expect(catalog.structuredTypes.map((e) => e.name), ['CoreValue']);
      expect(catalog.unions.map((e) => e.name), ['CoreValueUnion']);
      expect(catalog.designTokens.map((e) => e.name), ['brand.primary']);
      expect(catalog.compatRules, hasLength(1));
      expect(catalog.compatRules!.single.note, 'native test rule');
      expect(catalog.flutterVersion, '9.9.9');
    });

    test('merges per-package catalog.json files in priority order', () async {
      final catalog = await _runLoaderWith({
        'restage_core': _coreCatalog,
        'restage_material': _materialCatalog,
        // restage_cupertino omitted — loader tolerates missing
      });

      expect(
        catalog.widgets.map((w) => '${w.library.namespace}:${w.name}'),
        [
          'restage.core:Center',
          'restage.core:SizedBox',
          'restage.material:FilledButton',
        ],
      );
      expect(catalog.widgetsIn(WidgetLibrary.core).length, 2);
      expect(catalog.widgetsIn(WidgetLibrary.material).length, 1);
      expect(
        catalog.libraries.containsKey(WidgetLibrary.cupertino),
        isFalse,
        reason: 'libraries map omits libraries with no contributed entries',
      );
    });

    test('tolerates all per-package catalogs missing', () async {
      final catalog = await _runLoaderWith(const {});
      expect(catalog.widgets, isEmpty);
      expect(catalog.libraries, isEmpty);
    });

    test('skips widgets whose library does not match the file owner', () async {
      // Hand-crafted file: restage_core's catalog claims a widget from
      // restage.material. The loader filters such cross-library entries
      // — they would have been emitted by a different file's owner.
      const corruptCore = '''
        {
          "schemaVersion": 4,
          "generatedAt": "2026-05-09T00:00:00Z",
          "libraries": {
            "restage.core": {"version": "0.1.0", "widgetCount": 1, "structuredCount": 0, "unionCount": 0, "designTokenCount": 0}
          },
          "widgets": [
            {
              "wireId": "w0001",
              "name": "Stowaway",
              "library": "restage.material",
              "category": "layout",
              "description": "A widget in the wrong file.",
              "flutterType": "package:x/y.dart#Stowaway",
              "childrenSlot": "none",
              "fires": [],
              "properties": [],
              "stability": "volatile"
            }
          ],
          "structuredTypes": [],
          "unions": [],
          "designTokens": []
        }
      ''';
      final catalog = await _runLoaderWith({'restage_core': corruptCore});
      expect(catalog.widgets, isEmpty);
    });

    test('merges the customer catalog from the input package', () async {
      // The customer's own generated catalog (custom @RestageLibrary widgets)
      // lives at lib/src/widget_catalog/catalog.json in the package being built
      // (here the probe input package, restage_codegen). It must merge so a
      // surface referencing a custom widget validates AND the capability
      // derivation sees the custom library + its declared capabilityVersion.
      final catalog = await _runLoaderWith({
        'restage_core': _coreCatalog,
        'restage_codegen': encodeCatalog(_customCatalog()),
      });

      expect(
        catalog.widgets.map((w) => '${w.library.namespace}:${w.name}'),
        containsAll(<String>['restage.core:Center', 'acme.widgets:AcmeBanner']),
      );
      // Built-ins sort first; the custom widget is appended after them.
      expect(catalog.widgets.last.name, 'AcmeBanner');
      const customLib = WidgetLibrary.custom('acme.widgets');
      expect(catalog.libraries[customLib]?.capabilityVersion, 2);
    });
  });

  group('findWidgetsByName', () {
    test('returns one entry for a unique name', () async {
      final catalog = await _runLoaderWith({
        'restage_core': _coreCatalog,
        'restage_material': _materialCatalog,
      });
      final matches = findWidgetsByName(catalog, 'FilledButton');
      expect(matches, hasLength(1));
      expect(matches.single.library, WidgetLibrary.material);
    });

    test('returns empty for an unknown name', () async {
      final catalog = await _runLoaderWith({'restage_core': _coreCatalog});
      expect(findWidgetsByName(catalog, 'NoSuchWidget'), isEmpty);
    });

    test('returns multiple entries when a name shadows across libraries',
        () async {
      final catalog = await _runLoaderWith({
        'restage_core': _coreCatalog,
        'restage_material': _materialCatalogWithShadow,
      });
      final matches = findWidgetsByName(catalog, 'Center');
      expect(matches, hasLength(2));
      expect(
        matches.map((w) => w.library.namespace),
        containsAll(<String>['restage.core', 'restage.material']),
      );
    });
  });
}

/// Runs `loadMergedCatalog` against synthetic `catalog.json` fixtures
/// overlaid on the workspace package graph. Returns the merged [Catalog].
///
/// Bootstraps the test reader with on-disk sources from every workspace
/// package so the loader's cross-package asset reads resolve, then
/// overlays the supplied [fixtures] on top — and deletes any
/// pre-existing real `catalog.json` files for libraries that aren't in
/// [fixtures], so omitting a library from the map exercises the
/// loader's tolerance for a missing per-package file.
Future<Catalog> _runLoaderWith(Map<String, String> fixtures) async {
  const rootPackage = 'restage_codegen';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
  );

  for (final entry in fixtures.entries) {
    readerWriter.testing.writeString(
      AssetId(entry.key, 'lib/src/widget_catalog/catalog.json'),
      entry.value,
    );
  }
  const allLibraryPackages = <String>[
    'restage_core',
    'restage_material',
    'restage_cupertino',
  ];
  for (final pkg in allLibraryPackages) {
    if (fixtures.containsKey(pkg)) continue;
    readerWriter.testing.delete(
      AssetId(pkg, 'lib/src/widget_catalog/catalog.json'),
    );
  }

  // Drive a probe builder that calls loadMergedCatalog and captures the
  // result. Input asset doesn't matter — the loader reads cross-package.
  Catalog? captured;
  const probeAssetKey = '$rootPackage|lib/_probe.dart';
  readerWriter.testing.writeString(
    AssetId.parse(probeAssetKey),
    'class _Probe {}',
  );

  await testBuilder(
    _LoaderProbeBuilder(
      onCatalog: (c) => captured = c,
      probeAsset: AssetId.parse(probeAssetKey),
    ),
    {probeAssetKey: 'class _Probe {}'},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );

  if (captured == null) {
    throw StateError('loadMergedCatalog probe builder did not run');
  }
  return captured!;
}

Catalog _fullGraphCoreCatalog() {
  final structuredRef = WireIdRef(
    library: 'restage.core',
    wireId: WireId('s0001'),
  );
  final variantRef = WireIdRef(
    library: 'restage.core',
    wireId: WireId('v0001'),
  );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '2026-05-24T00:00:00Z',
    flutterVersion: '9.9.9',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '1.2.3'),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: 'CoreWidget',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: 'A full graph test widget.',
        flutterType: 'package:flutter/widgets.dart#CoreWidget',
        childrenSlot: ChildrenSlot.none,
        fires: const [],
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: 'value',
            type: PropertyType.structured,
            description: 'Structured value.',
            structuredRef: structuredRef,
            valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: structuredRef,
            ),
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: WireId('s0001'),
        name: 'CoreValue',
        library: WidgetLibrary.core,
        description: 'Structured value.',
        sourceType: 'package:flutter/widgets.dart#CoreValue',
        fields: [
          StructuredField(
            wireId: WireId('p0002'),
            name: 'label',
            type: PropertyType.string,
            description: 'Label.',
            valueShape: const ScalarShape(
              propertyType: PropertyType.string,
            ),
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: WireId('v0001'),
            parameters: [
              FactoryParameter(
                wireId: WireId('a0001'),
                name: 'label',
                kind: FactoryParameterKind.named,
                required: true,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
                valueShape: const ScalarShape(
                  propertyType: PropertyType.string,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    unions: [
      UnionEntry(
        wireId: WireId('u0001'),
        name: 'CoreValueUnion',
        library: WidgetLibrary.core,
        description: 'Value union.',
        sourceType: 'package:flutter/widgets.dart#CoreValueBase',
        memberSourceTypes: const ['package:flutter/widgets.dart#CoreValue'],
        discriminator: DiscriminatorSpec(
          field: 'kind',
          values: [structuredRef],
        ),
        members: [structuredRef],
      ),
    ],
    designTokens: [
      DesignTokenEntry(
        wireId: WireId('t0001'),
        name: 'brand.primary',
        library: WidgetLibrary.core,
        type: DesignTokenType.color,
        literalFallback: 0xff000000,
      ),
    ],
    compatRules: [
      CompatRule(
        fromVersion: '1.0.0',
        toVersion: '2.0.0',
        kind: CompatKind.factoryVariantChange,
        affectedRef: variantRef,
        note: 'native test rule',
      ),
    ],
  );
}

/// A minimal customer catalog: one custom library declaring a capability
/// version, with one widget — the shape a customer's generated
/// `lib/src/widget_catalog/catalog.json` takes.
Catalog _customCatalog() => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-06-19T00:00:00Z',
      libraries: {
        const WidgetLibrary.custom('acme.widgets'):
            const LibraryInfo(version: '0.0.0', capabilityVersion: 2),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'AcmeBanner',
          library: const WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.layout,
          description: 'A custom banner.',
          flutterType: 'package:acme/banner.dart#AcmeBanner',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: const [],
        ),
      ],
    );

class _LoaderProbeBuilder implements Builder {
  _LoaderProbeBuilder({required this.onCatalog, required this.probeAsset});

  final void Function(Catalog catalog) onCatalog;
  final AssetId probeAsset;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.noop'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId != probeAsset) return;
    final catalog = await loadMergedCatalog(step);
    onCatalog(catalog);
  }
}
