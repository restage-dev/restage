import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'fixtures/pre_constraints_v4/published_v1_1_0_property_projection.dart';

void main() {
  test('fixture pins the published pre-constraint source and field order', () {
    expect(publishedPackageVersion, '1.1.0');
    expect(
      publishedReleaseCommit,
      '185c4abea6802a9893914881d957c9bc7b734a9a',
    );
    expect(
      publishedArchiveSha256,
      'dbfeaf0d900d66620354f0fd5749be2a35e5e0a669556619e52201c7510d78e5',
    );
    expect(
      publishedCatalogCodecSha256,
      '08ce94e815b375368dafc53a1c70cb89e60c0e3288c44e8e15c8c7cc961ffd81',
    );
    expect(
      publishedPropertyEntrySha256,
      '3794858798b4b6e3f6a1109cc26a1d4b3e28b93c171aeb2a38d424aed124d939',
    );
    expect(publishedAt, '2026-07-13T01:17:44.597072Z');
    expect(publishedPropertyFieldOrder, [
      'wireId',
      'name',
      'type',
      'description',
      'required',
      'synthetic',
      'positional',
      'enumType',
      'widgetType',
      'callbackSignature',
      'firesAs',
      'defaultSource',
      'mutuallyExclusiveWith',
      'requiresAncestor',
      'category',
      'priority',
      'validationRule',
      'deprecated',
      'structuredRef',
      'valueShape',
    ]);
    expect(publishedPropertyFieldOrder, isNot(contains('constraints')));
  });

  test('frozen projection emits every recognized field in published order', () {
    final source = <String, dynamic>{
      'constraints': {'minimum': 1},
      'valueShape': {'kind': 'scalar', 'propertyType': 'integer'},
      'wireId': 'p0001',
      'name': 'count',
      'type': 'integer',
      'description': 'Count.',
      'required': true,
      'synthetic': 'fixture',
      'positional': true,
      'enumType': 'Count',
      'widgetType': 'Widget',
      'callbackSignature': 'ValueChanged<int>',
      'firesAs': 'onChanged',
      'defaultSource': {'kind': 'literal', 'value': 1},
      'mutuallyExclusiveWith': ['p0002'],
      'requiresAncestor': 'Material',
      'category': 'data',
      'priority': 'primary',
      'validationRule': {'expression': 'range(1, 5)', 'message': 'Range.'},
      'deprecated': {
        'catalog': {'reason': 'Fixture.', 'at': '1.0.0'},
      },
      'structuredRef': {'library': 'fixture', 'wireId': 's0001'},
    };

    final projected = PublishedV110Property.fromJson(source).toJson();
    expect(projected.keys, publishedPropertyFieldOrder);
    expect(projected, isNot(contains('constraints')));
  });

  test('published v1.1.0 round trip loses exactly constraints and nothing else',
      () {
    final source = encodeCatalog(
      Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-07-19T00:00:00.000Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '1.0.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'LegacyTransformFixture',
            library: WidgetLibrary.core,
            category: WidgetCategory.input,
            description: 'Legacy transform fixture.',
            flutterType: 'package:fixture/fixture.dart#LegacyTransformFixture',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'count',
                type: PropertyType.integer,
                description: 'Count.',
                constraints: RestageConstraints.withExtensions(
                  minimum: 1,
                  maximum: 5,
                  allowedValues: const [1, 3, 5],
                  extensions: const {'x-future': true},
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final oldRoundTrip = publishedV110PropertyRoundTrip(source);
    final sourceJson = jsonDecode(source) as Map<String, dynamic>;
    final expectedJson = jsonDecode(source) as Map<String, dynamic>;
    final sourceProperty = _singleProperty(sourceJson);
    final expectedProperty = _singleProperty(expectedJson);
    final removedConstraints = expectedProperty.remove('constraints');

    expect(sourceJson['schemaVersion'], 4);
    expect(removedConstraints, {
      'minimum': 1,
      'maximum': 5,
      'enum': [1, 3, 5],
      'x-future': true,
    });
    expect(
      sourceProperty.keys.where((key) => !expectedProperty.containsKey(key)),
      ['constraints'],
      reason: 'The exact property diff must contain one removed key.',
    );
    expect(
      jsonDecode(oldRoundTrip),
      expectedJson,
      reason: 'The pre-constraint transformation may lose only constraints.',
    );
    expect(
      oldRoundTrip,
      const JsonEncoder.withIndent('  ').convert(expectedJson),
      reason: 'The loss characterization is byte-exact after canonical encode.',
    );
    expect(oldRoundTrip, isNot(source));
  });
}

Map<String, dynamic> _singleProperty(Map<String, dynamic> catalog) {
  final widgets =
      (catalog['widgets']! as List<Object?>).cast<Map<String, dynamic>>();
  final properties = (widgets.single['properties']! as List<Object?>)
      .cast<Map<String, dynamic>>();
  return properties.single;
}
