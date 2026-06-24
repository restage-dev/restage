import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../legacy_codec.dart';

final class _AcmeDesignSystem extends WidgetLibrary {
  const _AcmeDesignSystem();
  @override
  // namespace is a final field rather than a getter — `DartObject.getField`
  // (used at build time by codegen builders) only sees fields.
  // ignore: avoid_field_initializers_in_const_classes
  final String namespace = 'acme.design_system';
}

Catalog _sampleCatalog() => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-05-09T12:00:00Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        WidgetLibrary.material: const LibraryInfo(version: '0.1.0'),
        WidgetLibrary.cupertino: const LibraryInfo(version: '0.1.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'FilledButton',
          library: WidgetLibrary.material,
          category: WidgetCategory.action,
          description: 'CTA',
          flutterType: 'package:flutter/material.dart#FilledButton',
          childrenSlot: ChildrenSlot.single,
          fires: const [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'child',
              type: PropertyType.widget,
              description: 'Label.',
              required: true,
            ),
            PropertyEntry(
              wireId: WireId('p0002'),
              name: 'backgroundColor',
              type: PropertyType.color,
              description: 'Background.',
              defaultBrandToken: 'primary',
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: WireIdRef(
                library: 'restage.material',
                wireId: WireId('s0001'),
              ),
              flatProperties: {
                WireId('p0501'): WireId('p0002'),
              },
            ),
          ],
        ),
      ],
      structuredTypes: [
        StructuredEntry(
          wireId: WireId('s0001'),
          name: 'ButtonStyle',
          library: WidgetLibrary.material,
          description: 'Button style.',
          sourceType: 'package:flutter/material.dart#ButtonStyle',
          fields: [
            StructuredField(
              wireId: WireId('p0501'),
              name: 'backgroundColor',
              type: PropertyType.color,
              description: 'Background.',
            ),
          ],
          variants: const [],
        ),
      ],
    );

// Carries the legacy per-kind count keys deliberately: the decoder no longer
// requires or reads them, so this fixture also exercises the tolerate-and-
// ignore path.
Map<String, dynamic> _catalogLibraryJson() => {
      'version': '0.1.0',
      'widgetCount': 0,
      'structuredCount': 0,
      'unionCount': 0,
      'designTokenCount': 0,
    };

String _catalogJson({
  Map<String, dynamic>? library,
  List<Map<String, dynamic>> widgets = const [],
  List<Map<String, dynamic>> structuredTypes = const [],
  List<Map<String, dynamic>> unions = const [],
  List<Map<String, dynamic>> designTokens = const [],
}) {
  return jsonEncode({
    'schemaVersion': kSupportedSchemaVersion,
    'generatedAt': 'x',
    'libraries': {'restage.core': library ?? _catalogLibraryJson()},
    'widgets': widgets,
    if (structuredTypes.isNotEmpty) 'structuredTypes': structuredTypes,
    if (unions.isNotEmpty) 'unions': unions,
    if (designTokens.isNotEmpty) 'designTokens': designTokens,
  });
}

Map<String, dynamic> _widgetJson({
  String wireId = 'w0001',
  List<Map<String, dynamic>> properties = const [],
  List<Map<String, dynamic>> decomposes = const [],
}) =>
    {
      'wireId': wireId,
      'name': 'W',
      'library': 'restage.core',
      'category': 'layout',
      'description': 'd',
      'flutterType': 'x#W',
      'childrenSlot': 'none',
      'fires': const <String>[],
      'properties': properties,
      if (decomposes.isNotEmpty) 'decomposes': decomposes,
    };

Map<String, dynamic> _propertyJson({
  String wireId = 'p0001',
  List<String>? mutuallyExclusiveWith,
  Map<String, dynamic>? defaultSource,
}) =>
    {
      'wireId': wireId,
      'name': 'p',
      'type': 'string',
      'description': 'd',
      if (mutuallyExclusiveWith != null)
        'mutuallyExclusiveWith': mutuallyExclusiveWith,
      if (defaultSource != null) 'defaultSource': defaultSource,
    };

Map<String, dynamic> _decompositionJson({
  String structuredWireId = 's0001',
  Map<String, String> flatProperties = const {'p0001': 'p0002'},
  List<Map<String, dynamic>>? discriminatorValues,
}) =>
    {
      'structuredRef': {
        'library': 'restage.core',
        'wireId': structuredWireId,
      },
      'flatProperties': flatProperties,
      if (discriminatorValues != null)
        'discriminator': {
          'field': '_s',
          'values': discriminatorValues,
        },
    };

Map<String, dynamic> _structuredJson({
  String wireId = 's0001',
  List<Map<String, dynamic>> fields = const [],
  List<Map<String, dynamic>> variants = const [],
}) =>
    {
      'wireId': wireId,
      'name': 'S',
      'library': 'restage.core',
      'description': 'd',
      'sourceType': 'x#S',
      'fields': fields,
      'variants': variants,
    };

Map<String, dynamic> _structuredFieldJson({String wireId = 'p0001'}) => {
      'wireId': wireId,
      'name': 'f',
      'type': 'string',
      'description': 'd',
    };

Map<String, dynamic> _variantJson({
  String wireId = 'v0001',
  Map<String, List<String>> argMappings = const {},
}) =>
    {
      'wireId': wireId,
      'sourceKind': 'constructor',
      if (argMappings.isNotEmpty) 'argMappings': argMappings,
    };

Map<String, dynamic> _memberRefJson({String wireId = 's0001'}) => {
      'library': 'restage.core',
      'wireId': wireId,
    };

Map<String, dynamic> _unionJson({
  String wireId = 'u0001',
  List<Map<String, dynamic>>? discriminatorValues,
  List<Map<String, dynamic>>? members,
}) =>
    {
      'wireId': wireId,
      'name': 'U',
      'library': 'restage.core',
      'description': 'd',
      'sourceType': 'package:test/test.dart#U',
      'memberSourceTypes': const ['package:test/test.dart#UMember'],
      'discriminator': {
        'field': '_s',
        'values': discriminatorValues ?? [_memberRefJson()],
      },
      'members': members ?? [_memberRefJson()],
    };

Map<String, dynamic> _designTokenJson({String wireId = 't0001'}) => {
      'wireId': wireId,
      'name': 'token',
      'library': 'restage.core',
      'type': 'color',
    };

Catalog _catalogWith({
  List<WidgetEntry> widgets = const [],
  List<StructuredEntry> structuredTypes = const [],
  List<UnionEntry> unions = const [],
  List<DesignTokenEntry> designTokens = const [],
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: 'x',
      libraries: {
        WidgetLibrary.core: LibraryInfo(version: '0.1.0'),
      },
      widgets: widgets,
      structuredTypes: structuredTypes,
      unions: unions,
      designTokens: designTokens,
    );

WidgetEntry _widgetEntry({
  WireId? wireId,
  List<PropertyEntry> properties = const [],
  List<DecompositionRecipe> decomposes = const [],
}) =>
    WidgetEntry(
      wireId: wireId ?? WireId('w0001'),
      name: 'W',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'd',
      flutterType: 'x#W',
      childrenSlot: ChildrenSlot.none,
      fires: const [],
      properties: properties,
      decomposes: decomposes,
    );

PropertyEntry _propertyEntry({
  WireId? wireId,
  List<WireId>? mutuallyExclusiveWith,
  DefaultValueSource? defaultSource,
}) =>
    PropertyEntry(
      wireId: wireId ?? WireId('p0001'),
      name: 'p',
      type: PropertyType.string,
      description: 'd',
      mutuallyExclusiveWith: mutuallyExclusiveWith,
      defaultSource: defaultSource,
    );

StructuredEntry _structuredEntry({
  WireId? wireId,
  List<StructuredField> fields = const [],
  List<FactoryVariant> variants = const [],
}) =>
    StructuredEntry(
      wireId: wireId ?? WireId('s0001'),
      name: 'S',
      library: WidgetLibrary.core,
      description: 'd',
      sourceType: 'x#S',
      fields: fields,
      variants: variants,
    );

StructuredField _structuredField({WireId? wireId}) => StructuredField(
      wireId: wireId ?? WireId('p0001'),
      name: 'f',
      type: PropertyType.string,
      description: 'd',
    );

FactoryVariant _variant({
  WireId? wireId,
  Map<String, ArgMapping> argMappings = const {},
}) =>
    ConstructorVariant(
      wireId: wireId ?? WireId('v0001'),
      argMappings: argMappings,
    );

WireIdRef _memberRef({WireId? wireId}) => WireIdRef(
      library: 'restage.core',
      wireId: wireId ?? WireId('s0001'),
    );

UnionEntry _unionEntry({
  WireId? wireId,
  DiscriminatorSpec? discriminator,
  List<WireIdRef>? members,
}) =>
    UnionEntry(
      wireId: wireId ?? WireId('u0001'),
      name: 'U',
      library: WidgetLibrary.core,
      description: 'd',
      sourceType: 'package:test/test.dart#U',
      memberSourceTypes: const ['package:test/test.dart#UMember'],
      discriminator: discriminator ??
          DiscriminatorSpec(field: '_s', values: [_memberRef()]),
      members: members ?? [_memberRef()],
    );

DesignTokenEntry _designTokenEntry({WireId? wireId}) => DesignTokenEntry(
      wireId: wireId ?? WireId('t0001'),
      name: 'token',
      library: WidgetLibrary.core,
      type: DesignTokenType.color,
    );

void main() {
  Matcher throwsCatalogSchemaExceptionContaining(String fragment) {
    return throwsA(
      isA<CatalogSchemaException>().having(
        (e) => e.message,
        'message',
        contains(fragment),
      ),
    );
  }

  group('v4 canonical codec', () {
    test('encodeCatalog produces JSON with wire IDs and envelope counts', () {
      final json =
          jsonDecode(encodeCatalog(_sampleCatalog())) as Map<String, dynamic>;
      final libraries = json['libraries']! as Map<String, dynamic>;
      final material = libraries['restage.material']! as Map<String, dynamic>;
      final widgets = json['widgets']! as List<dynamic>;
      final firstWidget = widgets.first as Map<String, dynamic>;
      final firstProperties = firstWidget['properties']! as List<dynamic>;
      final childProperty = firstProperties[0] as Map<String, dynamic>;
      final decomposes = firstWidget['decomposes']! as List<dynamic>;
      final buttonStyle = decomposes.first as Map<String, dynamic>;

      expect(json['schemaVersion'], kSupportedSchemaVersion);
      // The library envelope carries only version — per-kind counts are
      // computed off the entry lists, not serialized.
      expect(material['version'], '0.1.0');
      expect(material.containsKey('widgetCount'), isFalse);
      // Wire IDs on every widget + property.
      expect(firstWidget['wireId'], 'w0001');
      expect(firstWidget['name'], 'FilledButton');
      expect(firstWidget['library'], 'restage.material');
      expect(
        firstWidget['flutterType'],
        'package:flutter/material.dart#FilledButton',
      );
      expect(firstWidget['fires'], ['onPressed']);
      expect(childProperty['wireId'], 'p0001');
      expect(childProperty['type'], 'widget');
      // Canonical decomposition is wire-ID-keyed.
      final structuredRef =
          buttonStyle['structuredRef']! as Map<String, dynamic>;
      expect(structuredRef['library'], 'restage.material');
      expect(structuredRef['wireId'], 's0001');
      expect(
        (buttonStyle['flatProperties']! as Map)['p0501'],
        'p0002',
      );
      // Legacy projection fields do NOT appear in v4 emission.
      expect(buttonStyle.containsKey('structuredType'), isFalse);
      expect(childProperty.containsKey('defaultBrandToken'), isFalse);
    });

    test('encodeCatalog omits decomposes when empty', () {
      final noDecomposes = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-09T12:00:00Z',
        libraries: const {},
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'SizedBox',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'Fixed-dimension box.',
            flutterType: 'package:flutter/widgets.dart#SizedBox',
            childrenSlot: ChildrenSlot.single,
            fires: const [],
            properties: const [],
          ),
        ],
      );
      final json =
          jsonDecode(encodeCatalog(noDecomposes)) as Map<String, dynamic>;
      final firstWidget =
          (json['widgets']! as List<dynamic>).first as Map<String, dynamic>;
      expect(firstWidget.containsKey('decomposes'), isFalse);
    });

    test('encodeCatalog rejects internal sentinel wire IDs', () {
      final unresolved = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-09T12:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [
          WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'W',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'd',
            flutterType: 'x#W',
            childrenSlot: ChildrenSlot.none,
            fires: [],
            properties: [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'p',
                type: PropertyType.string,
                description: 'd',
              ),
            ],
          ),
        ],
      );

      expect(
        () => encodeCatalog(unresolved),
        throwsCatalogSchemaExceptionContaining('unallocated sentinel'),
      );
    });

    test('encodeCatalog rejects wrong-kind wire IDs by context', () {
      final cases = <String, Catalog>{
        'widget wire ID': _catalogWith(
          widgets: [_widgetEntry(wireId: WireId('p0001'))],
        ),
        'property wire ID': _catalogWith(
          widgets: [
            _widgetEntry(properties: [_propertyEntry(wireId: WireId('w0001'))]),
          ],
        ),
        'mutuallyExclusiveWith reference': _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [
                _propertyEntry(mutuallyExclusiveWith: [WireId('w0001')]),
              ],
            ),
          ],
        ),
        'decomposition structuredRef': _catalogWith(
          widgets: [
            _widgetEntry(
              decomposes: [
                DecompositionRecipe(
                  structuredRef: WireIdRef(
                    library: 'restage.core',
                    wireId: WireId('p0001'),
                  ),
                  flatProperties: const {},
                ),
              ],
            ),
          ],
        ),
        'decomposition flatProperties key': _catalogWith(
          widgets: [
            _widgetEntry(
              decomposes: [
                DecompositionRecipe(
                  structuredRef: WireIdRef(
                    library: 'restage.core',
                    wireId: WireId('s0001'),
                  ),
                  flatProperties: {WireId('w0001'): WireId('p0001')},
                ),
              ],
            ),
          ],
        ),
        'decomposition flatProperties value': _catalogWith(
          widgets: [
            _widgetEntry(
              decomposes: [
                DecompositionRecipe(
                  structuredRef: WireIdRef(
                    library: 'restage.core',
                    wireId: WireId('s0001'),
                  ),
                  flatProperties: {WireId('p0001'): WireId('w0001')},
                ),
              ],
            ),
          ],
        ),
        'structured wire ID': _catalogWith(
          structuredTypes: [_structuredEntry(wireId: WireId('w0001'))],
        ),
        'structured field wire ID': _catalogWith(
          structuredTypes: [
            _structuredEntry(
              fields: [_structuredField(wireId: WireId('s0002'))],
            ),
          ],
        ),
        'factory variant wire ID': _catalogWith(
          structuredTypes: [
            _structuredEntry(variants: [_variant(wireId: WireId('s0002'))]),
          ],
        ),
        'factory variant target field': _catalogWith(
          structuredTypes: [
            _structuredEntry(
              variants: [
                _variant(
                  argMappings: {
                    'x': ArgMapping(targetFields: [WireId('w0001')]),
                  },
                ),
              ],
            ),
          ],
        ),
        'union wire ID': _catalogWith(
          unions: [_unionEntry(wireId: WireId('w0001'))],
        ),
        'union member': _catalogWith(
          unions: [
            _unionEntry(members: [_memberRef(wireId: WireId('w0001'))]),
          ],
        ),
        'union discriminator value': _catalogWith(
          unions: [
            _unionEntry(
              discriminator: DiscriminatorSpec(
                field: '_s',
                values: [_memberRef(wireId: WireId('w0001'))],
              ),
            ),
          ],
        ),
        'design token wire ID': _catalogWith(
          designTokens: [_designTokenEntry(wireId: WireId('w0001'))],
        ),
        'tokenRef default': _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [
                _propertyEntry(
                  defaultSource: TokenRefDefault(
                    WireIdRef(
                      library: 'restage.core',
                      wireId: WireId('w0001'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      };

      for (final entry in cases.entries) {
        expect(
          () => encodeCatalog(entry.value),
          throwsCatalogSchemaExceptionContaining('expected'),
          reason: entry.key,
        );
      }
    });

    test('decodeCatalog round-trips through encode', () {
      final sample = _sampleCatalog();
      final decoded = decodeCatalog(encodeCatalog(sample));
      expect(decoded.schemaVersion, kSupportedSchemaVersion);
      expect(decoded.widgets.length, sample.widgets.length);
      expect(decoded.widgets.first.wireId, sample.widgets.first.wireId);
      expect(decoded.widgets.first.name, sample.widgets.first.name);
      expect(
        decoded.widgets.first.flutterType,
        sample.widgets.first.flutterType,
      );
      expect(decoded.widgets.first.fires, sample.widgets.first.fires);
      final recipe = decoded.widgets.first.decomposes.first;
      expect(recipe.structuredRef.wireId, WireId('s0001'));
      expect(recipe.flatProperties[WireId('p0501')], WireId('p0002'));
      expect(decoded.libraries.keys, sample.libraries.keys);
    });

    test('decodeCatalog yields a custom library for unknown namespaces', () {
      const customJson = '{"schemaVersion":4,"generatedAt":"2026-05-09",'
          '"libraries":{"acme.design_system":{"version":"1.0.0",'
          '"widgetCount":0,"structuredCount":0,"unionCount":0,'
          '"designTokenCount":0}},"widgets":[]}';
      final decoded = decodeCatalog(customJson);
      final lib = decoded.libraries.keys.single;
      expect(lib.namespace, 'acme.design_system');
      expect(WidgetLibrary.builtInByNamespace('acme.design_system'), isNull);
    });

    test('decodeCatalog rejects non-current wire shapes', () {
      expect(
        () => decodeCatalog(
          '{"schemaVersion": 2, "generatedAt": "x", '
          '"libraries": {}, "widgets": []}',
        ),
        throwsA(
          isA<CatalogSchemaException>()
              .having(
                (error) => error.message,
                'message',
                contains('Unsupported catalog schemaVersion 2'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('decodeCatalogCompat')),
              ),
        ),
      );
    });

    test('decodeCatalog throws on missing required fields', () {
      expect(
        () => decodeCatalog('{"schemaVersion": 4}'),
        throwsA(isA<CatalogSchemaException>()),
      );
    });

    test('decodeCatalog rejects widgets missing wireId', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"name":"W","library":"restage.core","category":"layout",'
          '"description":"d","flutterType":"x#W","childrenSlot":"none",'
          '"fires":[],"properties":[]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('wireId'),
      );
    });

    test('decodeCatalog rejects properties missing wireId', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0001","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","flutterType":"x#W",'
          '"childrenSlot":"none","fires":[],'
          '"properties":[{"name":"p","type":"string","description":"d"}]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('wireId'),
      );
    });

    test('decodeCatalog rejects sentinel widget wire IDs', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0000","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","flutterType":"x#W",'
          '"childrenSlot":"none","fires":[],"properties":[]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('Sequence 0'),
      );
    });

    test('decodeCatalog rejects sentinel property wire IDs', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0001","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","flutterType":"x#W",'
          '"childrenSlot":"none","fires":[],'
          '"properties":[{"wireId":"p0000","name":"p","type":"string",'
          '"description":"d"}]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('Sequence 0'),
      );
    });

    test('decodeCatalog rejects sentinel wire ID references', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0001","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","flutterType":"x#W",'
          '"childrenSlot":"none","fires":[],"properties":[],'
          '"decomposes":[{"structuredRef":{"library":"restage.core",'
          '"wireId":"s0000"},"flatProperties":{}}]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('Sequence 0'),
      );
    });

    test(
        'decodeCatalog throws CatalogSchemaException when widget is missing '
        'name', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"library":"restage.core","category":"layout",'
          '"description":"d","flutterType":"x#Y","childrenSlot":"none",'
          '"fires":[],"properties":[]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('name'),
      );
    });

    test(
        'decodeCatalog throws CatalogSchemaException when widget is missing '
        'flutterType', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0001","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","childrenSlot":"none",'
          '"fires":[],"properties":[]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('flutterType'),
      );
    });

    test('decodeCatalog throws when library entry is missing version', () {
      const json = '{"schemaVersion":4,"generatedAt":"x",'
          '"libraries":{"restage.core":{"widgetCount":0}},"widgets":[]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('version'),
      );
    });

    test('decodeCatalog accepts a library entry with only version', () {
      const json = '{"schemaVersion":4,"generatedAt":"x",'
          '"libraries":{"restage.core":{"version":"0.1.0"}},"widgets":[]}';
      final catalog = decodeCatalog(json);
      expect(catalog.libraries[WidgetLibrary.core]!.version, '0.1.0');
    });

    test('decodeCatalog tolerates and ignores legacy per-kind count keys', () {
      // `_catalogLibraryJson()` still carries widgetCount/structuredCount/etc.
      // The decoder no longer requires or reads them — counts are derived
      // from the entry lists, so legacy keys are simply ignored.
      final catalog = decodeCatalog(_catalogJson());
      expect(catalog.libraries[WidgetLibrary.core]!.version, '0.1.0');
    });

    test('decodeCatalog rejects wrong-kind wire IDs by context', () {
      final cases = <String, String>{
        'widget wire ID': _catalogJson(
          widgets: [_widgetJson(wireId: 'p0001')],
        ),
        'property wire ID': _catalogJson(
          widgets: [
            _widgetJson(properties: [_propertyJson(wireId: 'w0001')]),
          ],
        ),
        'mutuallyExclusiveWith reference': _catalogJson(
          widgets: [
            _widgetJson(
              properties: [
                _propertyJson(mutuallyExclusiveWith: ['w0001']),
              ],
            ),
          ],
        ),
        'decomposition structuredRef': _catalogJson(
          widgets: [
            _widgetJson(
              decomposes: [_decompositionJson(structuredWireId: 'p0001')],
            ),
          ],
        ),
        'decomposition flatProperties key': _catalogJson(
          widgets: [
            _widgetJson(
              decomposes: [
                _decompositionJson(flatProperties: {'w0001': 'p0002'}),
              ],
            ),
          ],
        ),
        'decomposition flatProperties value': _catalogJson(
          widgets: [
            _widgetJson(
              decomposes: [
                _decompositionJson(flatProperties: {'p0001': 'w0001'}),
              ],
            ),
          ],
        ),
        'structured wire ID': _catalogJson(
          structuredTypes: [_structuredJson(wireId: 'w0001')],
        ),
        'structured field wire ID': _catalogJson(
          structuredTypes: [
            _structuredJson(fields: [_structuredFieldJson(wireId: 's0002')]),
          ],
        ),
        'factory variant wire ID': _catalogJson(
          structuredTypes: [
            _structuredJson(variants: [_variantJson(wireId: 's0002')]),
          ],
        ),
        'factory variant target field': _catalogJson(
          structuredTypes: [
            _structuredJson(
              variants: [
                _variantJson(
                  argMappings: {
                    'x': ['w0001'],
                  },
                ),
              ],
            ),
          ],
        ),
        'union wire ID': _catalogJson(
          unions: [_unionJson(wireId: 'w0001')],
        ),
        'union member': _catalogJson(
          unions: [
            _unionJson(members: [_memberRefJson(wireId: 'w0001')]),
          ],
        ),
        'union discriminator value': _catalogJson(
          unions: [
            _unionJson(
              discriminatorValues: [_memberRefJson(wireId: 'w0001')],
            ),
          ],
        ),
        'design token wire ID': _catalogJson(
          designTokens: [_designTokenJson(wireId: 'w0001')],
        ),
        'tokenRef default': _catalogJson(
          widgets: [
            _widgetJson(
              properties: [
                _propertyJson(
                  defaultSource: {
                    'kind': 'tokenRef',
                    'token': {
                      'library': 'restage.core',
                      'wireId': 'w0001',
                    },
                  },
                ),
              ],
            ),
          ],
        ),
      };

      for (final entry in cases.entries) {
        expect(
          () => decodeCatalog(entry.value),
          throwsCatalogSchemaExceptionContaining('expected'),
          reason: entry.key,
        );
      }
    });

    test('decoded catalog map keys round-trip into typed-subclass lookups', () {
      // Author the catalog with a typed customer-library subclass; encode +
      // decode (which always produces _CustomLibrary); the namespace-based
      // equality from WidgetLibrary makes the typed subclass valid as a key
      // for retrieving entries the decoder put under _CustomLibrary.
      const acme = _AcmeDesignSystem();
      final authored = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: 'x',
        libraries: {
          acme: const LibraryInfo(version: '1.0.0'),
        },
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'AcmeButton',
            library: const _AcmeDesignSystem(),
            category: WidgetCategory.input,
            description: 'CTA',
            flutterType: 'package:acme/button.dart#AcmeButton',
            childrenSlot: ChildrenSlot.none,
            fires: const [WidgetEventName.onPressed],
            properties: const [],
          ),
        ],
      );

      final decoded = decodeCatalog(encodeCatalog(authored));
      expect(decoded.libraries[acme]?.version, '1.0.0');
      expect(decoded.widgetsIn(acme), hasLength(1));
      expect(decoded.findByName('AcmeButton', acme)?.name, 'AcmeButton');
    });

    test(
        'decodeCatalog throws eagerly when flatProperties has non-string '
        'values', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[{"wireId":"w0001","name":"W","library":"restage.core",'
          '"category":"layout","description":"d","flutterType":"x#W",'
          '"childrenSlot":"none","fires":[],"properties":[],'
          '"decomposes":[{"structuredRef":{"library":"restage.core",'
          '"wireId":"s0001"},"flatProperties":{"p0001":42}}]}]}';
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('flatProperties'),
      );
    });

    test(
        'decodeCatalog rejects unknown defaultSource kind with helpful '
        'message', () {
      final json = _catalogJson(
        widgets: [
          _widgetJson(
            properties: [
              _propertyJson(
                defaultSource: {'kind': 'experimental'},
              ),
            ],
          ),
        ],
      );
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('unknown defaultSource kind'),
      );
    });

    test('decodeCatalog rejects unknown stability with helpful message', () {
      final widget = _widgetJson()..['stability'] = 'experimental';
      final json = _catalogJson(widgets: [widget]);
      expect(
        () => decodeCatalog(json),
        throwsCatalogSchemaExceptionContaining('unknown stability'),
      );
    });

    test(
        'decodeCatalog falls back to PropertyType.unknown on unrecognized '
        'property type name (forward-compat)', () {
      // A payload with a type name the current build doesn't know
      // (`"type": "fromTheFuture"`). Older builds must still decode the
      // surrounding catalog so a newer-schema deploy doesn't crash the
      // decoder.
      final json = _catalogJson(
        widgets: [
          _widgetJson(
            properties: [
              {
                'wireId': 'p0001',
                'name': 'p',
                'type': 'fromTheFuture',
                'description': 'd',
              },
            ],
          ),
        ],
      );
      final decoded = decodeCatalog(json);
      expect(
        decoded.widgets.single.properties.single.type,
        PropertyType.unknown,
      );
    });

    test('decodeCatalog still decodes known PropertyType names strictly', () {
      // Sanity: the forward-compat fallback does not change the
      // behavior for known names.
      final json = _catalogJson(
        widgets: [
          _widgetJson(
            properties: [
              {
                'wireId': 'p0001',
                'name': 'p',
                'type': 'color',
                'description': 'd',
              },
            ],
          ),
        ],
      );
      final decoded = decodeCatalog(json);
      expect(
        decoded.widgets.single.properties.single.type,
        PropertyType.color,
      );
    });

    test(
        'decodeCatalog falls back to PropertyType.unknown on unrecognized '
        'structured-field type name (forward-compat)', () {
      // Same forward-compat behavior for the type field on a
      // StructuredField — the second site that consumes a JSON
      // PropertyType name.
      final json = _catalogJson(
        structuredTypes: [
          _structuredJson(
            fields: [
              {
                'wireId': 'p0001',
                'name': 'f',
                'type': 'fromTheFuture',
                'description': 'd',
              },
            ],
            variants: [_variantJson()],
          ),
        ],
      );
      final decoded = decodeCatalog(json);
      expect(
        decoded.structuredTypes.single.fields.single.type,
        PropertyType.unknown,
      );
    });

    test(
        'encodeCatalog + decodeCatalog round-trips a PropertyEntry with '
        'PropertyType.structured + structuredRef losslessly', () {
      final sample = _catalogWith(
        widgets: [
          _widgetEntry(
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'decoration',
                type: PropertyType.structured,
                description: 'Decoration applied to the box.',
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0001'),
                ),
              ),
            ],
          ),
        ],
        structuredTypes: [_structuredEntry()],
      );
      final encoded = encodeCatalog(sample);
      final decoded = decodeCatalog(encoded);
      final property = decoded.widgets.single.properties.single;
      expect(property.type, PropertyType.structured);
      expect(property.structuredRef, isNotNull);
      expect(property.structuredRef!.library, 'restage.core');
      expect(property.structuredRef!.wireId, WireId('s0001'));
    });

    test(
        'encodeCatalog + decodeCatalog round-trips a StructuredField with '
        'PropertyType.structured + structuredRef losslessly', () {
      final sample = _catalogWith(
        structuredTypes: [
          _structuredEntry(
            wireId: WireId('s0001'),
            fields: [
              StructuredField(
                wireId: WireId('p0001'),
                name: 'borderRadius',
                type: PropertyType.structured,
                description: 'Corner radii.',
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0002'),
                ),
              ),
            ],
          ),
          _structuredEntry(wireId: WireId('s0002')),
        ],
      );
      final encoded = encodeCatalog(sample);
      final decoded = decodeCatalog(encoded);
      final field = decoded.structuredTypes.first.fields.single;
      expect(field.type, PropertyType.structured);
      expect(field.structuredRef, isNotNull);
      expect(field.structuredRef!.library, 'restage.core');
      expect(field.structuredRef!.wireId, WireId('s0002'));
    });

    test(
        'encodeCatalog omits structuredRef for properties that do not '
        'declare one', () {
      final sample = _catalogWith(
        widgets: [
          _widgetEntry(
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'label',
                type: PropertyType.string,
                description: 'A label.',
              ),
            ],
          ),
        ],
      );
      final encoded = encodeCatalog(sample);
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final widget = (json['widgets']! as List).first as Map<String, dynamic>;
      final property =
          (widget['properties']! as List).first as Map<String, dynamic>;
      expect(property.containsKey('structuredRef'), isFalse);
    });

    test(
        'encodeCatalog rejects structuredRef pointing at a '
        'non-structured wire ID kind', () {
      final sample = _catalogWith(
        widgets: [
          _widgetEntry(
            properties: [
              PropertyEntry(
                wireId: WireId('p0001'),
                name: 'broken',
                type: PropertyType.structured,
                description: 'Bad ref kind.',
                // p* wire IDs are property-kind, not structured-kind.
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('p0002'),
                ),
              ),
            ],
          ),
        ],
      );
      expect(
        () => encodeCatalog(sample),
        throwsCatalogSchemaExceptionContaining('structured wire ID'),
      );
    });
  });

  group('v2 legacy codec', () {
    test('round-trips through encodeLegacyCatalogV2 / decodeLegacyCatalogV2',
        () {
      final canonical = _sampleCatalog();
      final legacyJson = encodeLegacyCatalogV2(canonical);
      final json = jsonDecode(legacyJson) as Map<String, dynamic>;
      expect(json['schemaVersion'], 2);
      final material = (json['libraries']! as Map)['restage.material']!
          as Map<String, dynamic>;
      // v2 envelope: only version + widgetCount, no envelope-count extensions.
      expect(material.keys.toSet(), {'version', 'widgetCount'});
      final firstWidget =
          (json['widgets']! as List).first as Map<String, dynamic>;
      // v2 emission has no wireId on widgets or properties.
      expect(firstWidget.containsKey('wireId'), isFalse);
      final properties = firstWidget['properties']! as List<dynamic>;
      expect(
        (properties.first as Map).containsKey('wireId'),
        isFalse,
      );
      final colorProperty = properties[1] as Map<String, dynamic>;
      // Legacy projection of defaultBrandToken is preserved.
      expect(colorProperty['defaultBrandToken'], 'primary');
      // Legacy decomposition shape uses string keys.
      final recipe =
          (firstWidget['decomposes']! as List).first as Map<String, dynamic>;
      expect(recipe['structuredType'], 'ButtonStyle');
      expect(
        (recipe['flatProperties']! as Map)['backgroundColor'],
        'backgroundColor',
      );

      final decoded = decodeLegacyCatalogV2(legacyJson);
      // Decoded v2 JSON stays in a legacy projection instead of pretending to
      // be a canonical Catalog with duplicate unresolved wire IDs.
      expect(decoded.schemaVersion, 2);
      expect(decoded.widgets.single, isA<LegacyWidgetEntry>());
      final decodedRecipe = decoded.widgets.single.decomposes.single;
      expect(decodedRecipe.structuredType, 'ButtonStyle');
      expect(decodedRecipe.flatProperties, {
        'backgroundColor': 'backgroundColor',
      });

      final transitional = decoded.toCatalogWithInternalPlaceholders();
      expect(transitional.widgets.single.wireId.isUnallocated, isTrue);
      expect(
        () => encodeCatalog(transitional),
        throwsCatalogSchemaExceptionContaining('schemaVersion 2'),
      );
    });

    test(
        'encodeLegacyCatalogV2 fails when a recipe is missing its legacy '
        'projection slots', () {
      final canonical = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: 'x',
        libraries: const {},
        widgets: [
          WidgetEntry(
            wireId: WireId('w0001'),
            name: 'W',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: 'd',
            flutterType: 'x#W',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: const [],
            decomposes: [
              DecompositionRecipe(
                structuredRef: WireIdRef(
                  library: 'restage.core',
                  wireId: WireId('s0001'),
                ),
                flatProperties: {
                  WireId('p0501'): WireId('p0001'),
                },
              ),
            ],
          ),
        ],
      );
      expect(
        () => encodeLegacyCatalogV2(canonical),
        throwsCatalogSchemaExceptionContaining('property wire ID'),
      );
    });

    test(
        'decodeLegacyCatalogV2 rejects canonical catalogs with a helpful '
        'message', () {
      const json = '{"schemaVersion":4,"generatedAt":"x","libraries":{},'
          '"widgets":[]}';
      expect(
        () => decodeLegacyCatalogV2(json),
        throwsCatalogSchemaExceptionContaining('decodeCatalog'),
      );
    });

    test('decodeLegacyCatalogV2 throws eagerly on non-string flatProperties',
        () {
      const json = '{"schemaVersion":2,"generatedAt":"x","libraries":{},'
          '"widgets":[{"name":"W","library":"restage.core","category":"layout",'
          '"description":"d","flutterType":"x#W","childrenSlot":"none",'
          '"fires":[],"properties":[],'
          '"decomposes":[{"structuredType":"S","flatProperties":{"a":42}}]}]}';
      expect(
        () => decodeLegacyCatalogV2(json),
        throwsCatalogSchemaExceptionContaining('flatProperties'),
      );
    });

    test(
        'decodeLegacyCatalogV2 round-trips the additive structured / union / '
        'designToken sections symmetrically', () {
      // Build a catalog with a non-empty structured-type section. The v2
      // encoder projects each structured entry to a v2-shape map and emits
      // the section as an additive top-level key. The decoder must read
      // back the same surface — without symmetry, any v2 reader sees a
      // different surface than the writer produced.
      final canonical = _catalogWith(
        structuredTypes: [
          _structuredEntry(
            wireId: WireId('s0001'),
            fields: [_structuredField(wireId: WireId('p0001'))],
            variants: [_variant(wireId: WireId('v0001'))],
          ),
        ],
      );
      final legacyJson = encodeLegacyCatalogV2(canonical);
      final decoded = decodeLegacyCatalogV2(legacyJson);

      // Full round-trip identity: the decoded sections must equal the
      // exact arrays the encoder emitted. Asserting against the encoded
      // JSON (rather than a count + spot-check) means a future codec
      // change that drops or mutates any structured-type field is
      // caught — a count-only assertion would stay green through such a
      // regression.
      final encodedRoot = jsonDecode(legacyJson) as Map<String, dynamic>;
      expect(decoded.structuredTypes, equals(encodedRoot['structuredTypes']));
      expect(decoded.unions, equals(encodedRoot['unions'] ?? const []));
      expect(
        decoded.designTokens,
        equals(encodedRoot['designTokens'] ?? const []),
      );

      // Sanity-check the section is genuinely non-empty so the identity
      // assertion above isn't vacuously satisfied by an empty array.
      expect(decoded.structuredTypes, hasLength(1));
    });

    test(
        'decodeLegacyCatalogV2 defaults additive sections to empty for '
        'pre-extension v2 blobs', () {
      // A v2 blob authored before the additive sections existed omits
      // the keys entirely. The decoder must accept that shape and emit
      // empty lists — backward-compat is the load-bearing property.
      const json = '{"schemaVersion":2,"generatedAt":"x","libraries":{},'
          '"widgets":[]}';
      final decoded = decodeLegacyCatalogV2(json);
      expect(decoded.structuredTypes, isEmpty);
      expect(decoded.unions, isEmpty);
      expect(decoded.designTokens, isEmpty);
    });

    test(
        'decodeLegacyCatalogV2 falls back to PropertyType.unknown on '
        'unrecognized property type name (forward-compat)', () {
      // Same forward-compat policy applies to the legacy reader path
      // — a v2 payload carrying a newer property type name must not
      // explode older decoder builds.
      const json = '{"schemaVersion":2,"generatedAt":"x","libraries":{},'
          '"widgets":[{"name":"W","library":"restage.core","category":"layout",'
          '"description":"d","flutterType":"x#W","childrenSlot":"none",'
          '"fires":[],"properties":['
          '{"name":"p","type":"fromTheFuture","description":"d"}],'
          '"decomposes":[]}]}';
      final decoded = decodeLegacyCatalogV2(json);
      expect(
        decoded.widgets.single.properties.single.type,
        PropertyType.unknown,
      );
    });

    test(
        'encodeLegacyCatalogV2 emits the unions array with one entry per '
        'discriminated union in the catalog', () {
      // Build a catalog containing one UnionEntry for the abstract Gradient
      // type with three concrete member FQNs. Encoding via the legacy codec
      // must populate the top-level `unions` key rather than leaving it empty.
      const gradientFqn = 'package:flutter/src/painting/gradient.dart#Gradient';
      const linearFqn =
          'package:flutter/src/painting/gradient.dart#LinearGradient';
      const radialFqn =
          'package:flutter/src/painting/gradient.dart#RadialGradient';
      const sweepFqn =
          'package:flutter/src/painting/gradient.dart#SweepGradient';

      final catalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '2026-05-16T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
        },
        widgets: const [],
        unions: [
          UnionEntry(
            wireId: WireId('u0001'),
            name: 'Gradient',
            library: WidgetLibrary.core,
            description: 'An abstract gradient type.',
            sourceType: gradientFqn,
            memberSourceTypes: const [linearFqn, radialFqn, sweepFqn],
            discriminator: DiscriminatorSpec(
              field: '_s',
              values: [
                WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
                WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
                WireIdRef(library: 'restage.core', wireId: WireId('s0003')),
              ],
            ),
            members: [
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
              WireIdRef(library: 'restage.core', wireId: WireId('s0003')),
            ],
          ),
        ],
      );

      final legacyJson = encodeLegacyCatalogV2(catalog);
      final root = jsonDecode(legacyJson) as Map<String, dynamic>;
      final unions = root['unions']! as List<dynamic>;

      expect(unions, hasLength(1));
      final entry = unions.first as Map<String, dynamic>;

      // Identity fields.
      expect(entry['name'], 'Gradient');
      expect(entry['library'], 'restage.core');
      expect(entry['description'], 'An abstract gradient type.');
      expect(entry['sourceType'], gradientFqn);

      // Members are identified by FQN, not by wire ID.
      final members = entry['members'] as List<dynamic>;
      expect(members, [linearFqn, radialFqn, sweepFqn]);

      // Discriminator carries the field name.
      final discriminator = entry['discriminator'] as Map<String, dynamic>;
      expect(discriminator['field'], '_s');
      // Legacy shape carries the field name only; wire IDs omitted.
      expect(discriminator.keys, ['field']);
    });

    group('additive defaultSource', () {
      // The v2 codec carries the discriminated default source as an
      // additive transitional field so the codegen factory builder — which
      // decodes the v2 baseline — can observe a materialized
      // ThemeBindingDefault / FlutterCtorDefault. Each variant must survive
      // the encode / decode round-trip intact.

      LegacyPropertyEntry roundTrippedProperty(
        DefaultValueSource defaultSource,
      ) {
        final canonical = _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [_propertyEntry(defaultSource: defaultSource)],
            ),
          ],
        );
        final legacyJson = encodeLegacyCatalogV2(canonical);
        return decodeLegacyCatalogV2(legacyJson)
            .widgets
            .single
            .properties
            .single;
      }

      test('round-trips a ThemeBindingDefault', () {
        const source =
            ThemeBindingDefault(ThemeBindingPath.path('iconTheme.color'));
        expect(roundTrippedProperty(source).defaultSource, source);
      });

      test('round-trips a FlutterCtorDefault', () {
        const source = FlutterCtorDefault();
        expect(roundTrippedProperty(source).defaultSource, source);
      });

      test('round-trips a LiteralDefault alongside the legacy defaultValue',
          () {
        const source = LiteralDefault(42);
        final canonical = _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [
                PropertyEntry(
                  wireId: WireId('p0001'),
                  name: 'p',
                  type: PropertyType.string,
                  description: 'd',
                  // Authored via the canonical default source; the flattened
                  // legacy `defaultValue` is a computed projection of it.
                  defaultSource: source,
                ),
              ],
            ),
          ],
        );
        final legacyJson = encodeLegacyCatalogV2(canonical);

        // The flattened legacy `defaultValue` is still emitted verbatim,
        // unaffected by the additive `defaultSource` key.
        final encodedWidget = ((jsonDecode(legacyJson)
                as Map<String, dynamic>)['widgets']! as List)
            .single as Map<String, dynamic>;
        final encodedProperty = (encodedWidget['properties']! as List).single
            as Map<String, dynamic>;
        expect(encodedProperty['defaultValue'], 42);
        expect(encodedProperty.containsKey('defaultSource'), isTrue);

        final decoded =
            decodeLegacyCatalogV2(legacyJson).widgets.single.properties.single;
        expect(decoded.defaultValue, 42);
        expect(decoded.defaultSource, source);
      });

      test(
          'a TokenRefDefault survives the round-trip alongside the legacy '
          'defaultBrandToken', () {
        final source = TokenRefDefault(
          WireIdRef(library: 'restage.core', wireId: WireId('t0001')),
        );
        final canonical = _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [
                PropertyEntry(
                  wireId: WireId('p0001'),
                  name: 'p',
                  type: PropertyType.color,
                  description: 'd',
                  defaultBrandToken: 'primary',
                  defaultSource: source,
                ),
              ],
            ),
          ],
        );
        final legacyJson = encodeLegacyCatalogV2(canonical);
        final encodedWidget = ((jsonDecode(legacyJson)
                as Map<String, dynamic>)['widgets']! as List)
            .single as Map<String, dynamic>;
        final encodedProperty = (encodedWidget['properties']! as List).single
            as Map<String, dynamic>;
        // Legacy brand-token projection is preserved verbatim.
        expect(encodedProperty['defaultBrandToken'], 'primary');

        final decoded =
            decodeLegacyCatalogV2(legacyJson).widgets.single.properties.single;
        expect(decoded.defaultBrandToken, 'primary');
        expect(decoded.defaultSource, source);
      });

      test('the materialized defaultSource reaches the transitional Catalog',
          () {
        const source =
            ThemeBindingDefault(ThemeBindingPath.path('iconTheme.color'));
        final canonical = _catalogWith(
          widgets: [
            _widgetEntry(
              properties: [_propertyEntry(defaultSource: source)],
            ),
          ],
        );
        final legacyJson = encodeLegacyCatalogV2(canonical);
        final transitional = decodeLegacyCatalogV2(legacyJson)
            .toCatalogWithInternalPlaceholders();
        // The codegen path consumes this projection — the default source
        // must survive into the PropertyEntry it builds.
        expect(
          transitional.widgets.single.properties.single.defaultSource,
          source,
        );
      });

      test('a v2 blob omitting the defaultSource key decodes as null', () {
        // Backward-compat: older v2 blobs authored before the additive key
        // existed must still decode cleanly, leaving defaultSource null.
        const json = '{"schemaVersion":2,"generatedAt":"x","libraries":{},'
            '"widgets":[{"name":"W","library":"restage.core",'
            '"category":"layout","description":"d","flutterType":"x#W",'
            '"childrenSlot":"none","fires":[],"properties":['
            '{"name":"p","type":"string","description":"d"}],'
            '"decomposes":[]}]}';
        final decoded = decodeLegacyCatalogV2(json);
        expect(
          decoded.widgets.single.properties.single.defaultSource,
          isNull,
        );
      });
    });
  });
}
