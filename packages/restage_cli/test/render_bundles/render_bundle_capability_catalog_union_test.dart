import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _acme = WidgetLibrary.custom('acme.widgets');

String _catalogJson({
  required WidgetLibrary library,
  required String name,
  required String widgetWireId,
  required String propertyWireId,
  int? capabilityVersion,
  WidgetCategory? category = WidgetCategory.decoration,
}) => encodeCatalog(
  Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: <WidgetLibrary, LibraryInfo>{
      library: LibraryInfo(
        version: '1.0.0',
        capabilityVersion: capabilityVersion,
      ),
    },
    widgets: <WidgetEntry>[
      WidgetEntry(
        wireId: WireId(widgetWireId),
        name: name,
        library: library,
        category: category,
        description: '$name fixture.',
        flutterType: 'package:fixture/fixture.dart#$name',
        childrenSlot: ChildrenSlot.none,
        properties: <PropertyEntry>[
          PropertyEntry(
            wireId: WireId(propertyWireId),
            name: 'label',
            type: PropertyType.string,
            description: 'Label.',
          ),
        ],
      ),
    ],
  ),
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'render_bundle_catalog_union_',
    );
    final packages = <String, ({WidgetLibrary library, String widget})>{
      'restage_core': (library: WidgetLibrary.core, widget: 'CoreFixture'),
      'restage_material': (
        library: WidgetLibrary.material,
        widget: 'MaterialFixture',
      ),
      'restage_cupertino': (
        library: WidgetLibrary.cupertino,
        widget: 'CupertinoFixture',
      ),
    };
    var wireIndex = 1;
    for (final entry in packages.entries) {
      final catalogFile = File(
        p.join(
          root.path,
          'deps',
          entry.key,
          'lib',
          'src',
          'widget_catalog',
          'catalog.json',
        ),
      )..createSync(recursive: true);
      catalogFile.writeAsStringSync(
        _catalogJson(
          library: entry.value.library,
          name: entry.value.widget,
          widgetWireId: 'w000$wireIndex',
          propertyWireId: 'p000$wireIndex',
        ),
      );
      wireIndex += 1;
    }
    final packageConfig = File(
      p.join(root.path, '.dart_tool', 'package_config.json'),
    )..createSync(recursive: true);
    packageConfig.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final package in packages.keys)
            <String, Object?>{
              'name': package,
              'rootUri': '../deps/$package',
              'packageUri': 'lib/',
              'languageVersion': '3.8',
            },
        ],
      }),
    );
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Directory createCustomerProject() {
    final project = Directory(p.join(root.path, 'customer'))..createSync();
    File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: customer_project\n');
    File(p.join(project.path, 'lib', 'main_render_bundle.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    return project;
  }

  void setAncestorCustomerMapping(String? rootUri) {
    final ancestorConfig = File(
      p.join(root.path, '.dart_tool', 'package_config.json'),
    );
    final document =
        jsonDecode(ancestorConfig.readAsStringSync()) as Map<String, dynamic>;
    final packages = document['packages']! as List<dynamic>;
    packages.removeWhere(
      (entry) =>
          entry is Map<String, dynamic> && entry['name'] == 'customer_project',
    );
    if (rootUri != null) {
      packages.add(<String, Object?>{
        'name': 'customer_project',
        'rootUri': rootUri,
        'packageUri': 'lib/',
        'languageVersion': '3.8',
      });
    }
    ancestorConfig.writeAsStringSync(jsonEncode(document));
  }

  String customerCatalog() => _catalogJson(
    library: _acme,
    name: 'AcmeBadge',
    widgetWireId: 'w0004',
    propertyWireId: 'p0004',
  );

  test(
    'unions all runtime built-ins with the exact customer catalog',
    () async {
      final customer = _catalogJson(
        library: _acme,
        name: 'AcmeBadge',
        widgetWireId: 'w0004',
        propertyWireId: 'p0004',
        capabilityVersion: 7,
      );

      final union = decodeCatalog(
        await createRenderBundleCapabilityCatalogUnion(root, customer),
      );

      expect(union.libraries.keys.map((library) => library.namespace), <String>[
        'restage.core',
        'restage.material',
        'restage.cupertino',
        'acme.widgets',
      ]);
      expect(union.widgets.map((widget) => widget.name), <String>[
        'CoreFixture',
        'MaterialFixture',
        'CupertinoFixture',
        'AcmeBadge',
      ]);
      expect(union.libraries[_acme]!.capabilityVersion, 7);
      expect(
        union.findByName('AcmeBadge', _acme)!.properties.single.name,
        'label',
      );
    },
  );

  test('preserves a root-placement customer widget in the union', () async {
    final customer = _catalogJson(
      library: _acme,
      name: 'AcmeRoot',
      widgetWireId: 'w0004',
      propertyWireId: 'p0004',
      category: null,
    );

    final union = decodeCatalog(
      await createRenderBundleCapabilityCatalogUnion(root, customer),
    );

    expect(union.findByName('AcmeRoot', _acme)!.category, isNull);
  });

  test(
    'rejects a customer catalog that contradicts a built-in namespace',
    () async {
      final contradiction = _catalogJson(
        library: WidgetLibrary.core,
        name: 'CustomerCore',
        widgetWireId: 'w0005',
        propertyWireId: 'p0005',
      );

      await expectLater(
        createRenderBundleCapabilityCatalogUnion(root, contradiction),
        throwsStateError,
      );
    },
  );

  test('validates open event identities structurally', () async {
    final wire = jsonDecode(customerCatalog()) as Map<String, dynamic>;
    final widget = (wire['widgets']! as List).single as Map<String, dynamic>;
    final properties = widget['properties']! as List;
    properties.add({
      'wireId': 'p9999',
      'name': 'onArbitraryCustomerAction',
      'type': 'event',
      'description': 'An open callback identity.',
    });

    final valid = await createRenderBundleCapabilityCatalogUnion(
      root,
      jsonEncode(wire),
    );
    expect(
      decodeCatalog(valid)
          .findByName('AcmeBadge', _acme)!
          .properties
          .map((property) => property.name),
      contains('onArbitraryCustomerAction'),
    );

    properties.last['name'] = 'on-invalid';
    await expectLater(
      createRenderBundleCapabilityCatalogUnion(root, jsonEncode(wire)),
      throwsA(isA<CatalogSchemaException>()),
    );
  });

  test(
    'accepts an ancestor workspace config mapped to the exact project',
    () async {
      final project = createCustomerProject();
      setAncestorCustomerMapping('../customer');

      final union = decodeCatalog(
        await createRenderBundleCapabilityCatalogUnion(
          project,
          customerCatalog(),
        ),
      );

      expect(
        union.libraries.keys.map((library) => library.namespace),
        contains('acme.widgets'),
      );
    },
  );

  test('rejects an ancestor config that omits the project identity', () async {
    final project = createCustomerProject();
    setAncestorCustomerMapping(null);

    await expectLater(
      createRenderBundleCapabilityCatalogUnion(project, customerCatalog()),
      throwsStateError,
    );
  });

  test(
    'rejects an ancestor config mapping the project name elsewhere',
    () async {
      final project = createCustomerProject();
      Directory(p.join(root.path, 'sibling')).createSync();
      setAncestorCustomerMapping('../sibling');

      await expectLater(
        createRenderBundleCapabilityCatalogUnion(project, customerCatalog()),
        throwsStateError,
      );
    },
  );

  test(
    'rejects ancestor identity mismatch before scratch or process work',
    () async {
      final project = createCustomerProject();
      Directory(p.join(root.path, 'sibling')).createSync();
      setAncestorCustomerMapping('../sibling');
      var tempCreations = 0;
      var processCalls = 0;
      final builder = FlutterRenderBundleBuilder(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
            }) async {
              processCalls++;
              return ProcessResult(1, 1, '', '');
            },
        tempDirectoryCreator: (_) async {
          tempCreations++;
          return Directory(p.join(root.path, 'scratch'))..createSync();
        },
        flutterExecutable: p.join(root.path, 'flutter'),
        fontAuthority: RenderBundleFontAuthority(
          fontFile: File(p.join(root.path, 'font')),
          licenseFile: File(p.join(root.path, 'license')),
          fontSha256: 'unused',
          licenseSha256: 'unused',
        ),
      );

      await expectLater(
        builder.build(
          projectRoot: project,
          catalogJson: customerCatalog(),
          parentOrigin: Uri.parse('http://dashboard.restage.localhost:8082'),
        ),
        throwsA(
          isA<RenderBundleBuildException>().having(
            (error) => error.reason,
            'reason',
            'catalog_contract',
          ),
        ),
      );
      expect(tempCreations, 0);
      expect(processCalls, 0);
    },
  );
}
