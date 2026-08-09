import 'dart:convert';
import 'dart:io';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

Catalog _catalog({
  DartConstValue? constructorDefault,
  bool constructorNullable = false,
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-08-08T00:00:00Z',
      libraries: {
        const WidgetLibrary.custom('acme.widgets'):
            const LibraryInfo(version: '1.0.0'),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Probe',
          library: const WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
          description: 'A probe.',
          flutterType: 'package:acme/widgets.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId('p0001'),
              name: 'value',
              type: PropertyType.string,
              description: 'A value.',
              constructorNullable: constructorNullable,
              constructorDefault: constructorDefault,
            ),
          ],
        ),
      ],
    );

const _complexDefault = DartConstInvocation(
  type: DartTypeIdentity(
    libraryUri: 'package:acme/value.dart',
    symbolName: 'Value',
    typeArguments: [
      DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'String'),
    ],
  ),
  constructorName: 'configured',
  positional: [DartConstScalar('authored')],
  named: [
    DartConstNamedValue(
      'options',
      DartConstMap([
        DartConstMapEntry(
          DartConstScalar('modes'),
          DartConstSet([
            DartConstReference(
              libraryUri: 'package:acme/value.dart',
              owner: 'Mode',
              member: 'compact',
            ),
          ]),
        ),
      ]),
    ),
    DartConstNamedValue(
      'metadata',
      DartConstRecord(
        positional: [DartConstNull()],
        named: [
          DartConstNamedValue(
            'labels',
            DartConstList([DartConstScalar('one')]),
          ),
        ],
      ),
    ),
  ],
);

const _typedCollections = DartConstRecord(
  positional: [
    DartConstList(
      [DartConstScalar(1)],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'List',
        typeArguments: [
          DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'num'),
        ],
      ),
    ),
    DartConstSet(
      [],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'Set',
        typeArguments: [
          DartTypeIdentity(
            libraryUri: 'package:acme/value.dart',
            symbolName: 'Value',
          ),
        ],
      ),
    ),
    DartConstMap(
      [],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'Map',
        typeArguments: [
          DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'String'),
          DartTypeIdentity(
            libraryUri: 'package:acme/value.dart',
            symbolName: 'Value',
          ),
        ],
      ),
    ),
  ],
);

const _recordTypedCollections = DartConstRecord(
  positional: [
    DartConstList(
      [],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'List',
        typeArguments: [
          DartRecordTypeIdentity(
            named: [
              DartRecordTypeNamedField(
                'value',
                DartTypeIdentity(
                  libraryUri: 'package:acme/value.dart',
                  symbolName: 'Value',
                  nullable: true,
                ),
              ),
              DartRecordTypeNamedField(
                'labels',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'List',
                  typeArguments: [
                    DartTypeIdentity(
                      libraryUri: 'dart:core',
                      symbolName: 'String',
                      nullable: true,
                    ),
                  ],
                  nullable: true,
                ),
              ),
              DartRecordTypeNamedField(
                'anything',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'dynamic',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    DartConstSet(
      [],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'Set',
        typeArguments: [
          DartRecordTypeIdentity(
            positional: [
              DartTypeIdentity(
                libraryUri: 'package:acme/value.dart',
                symbolName: 'Value',
                nullable: true,
              ),
              DartTypeIdentity(
                libraryUri: 'dart:core',
                symbolName: 'int',
              ),
            ],
            nullable: true,
          ),
        ],
      ),
    ),
    DartConstMap(
      [],
      type: DartTypeIdentity(
        libraryUri: 'dart:core',
        symbolName: 'Map',
        typeArguments: [
          DartTypeIdentity(
            libraryUri: 'dart:core',
            symbolName: 'String',
          ),
          DartRecordTypeIdentity(
            positional: [
              DartTypeIdentity(
                libraryUri: 'package:acme/value.dart',
                symbolName: 'Value',
              ),
            ],
            named: [
              DartRecordTypeNamedField(
                'enabled',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'bool',
                  nullable: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ],
);

void main() {
  test('constructor constant structure round-trips without flattening', () {
    final encoded = encodeCatalog(
      _catalog(
        constructorDefault: _complexDefault,
        constructorNullable: true,
      ),
    );
    final property = decodeCatalog(encoded).widgets.single.properties.single;

    expect(property.constructorNullable, isTrue);
    expect(property.constructorDefault, _complexDefault);
  });

  test('collection type identity round-trips and re-encodes canonically', () {
    final encoded = encodeCatalog(
      _catalog(constructorDefault: _typedCollections),
    );
    final decoded = decodeCatalog(encoded);

    expect(
      decoded.widgets.single.properties.single.constructorDefault,
      _typedCollections,
    );
    expect(jsonDecode(encodeCatalog(decoded)), jsonDecode(encoded));

    final root = jsonDecode(encoded) as Map<String, dynamic>;
    final property = ((root['widgets'] as List<dynamic>).single
        as Map<String, dynamic>)['properties'] as List<dynamic>;
    final record = (property.single
        as Map<String, dynamic>)['constructorDefault'] as Map<String, dynamic>;
    final collections = record['positional'] as List<dynamic>;
    expect(
      collections.map((value) => (value as Map<String, dynamic>)['type']),
      everyElement(isA<Map<String, dynamic>>()),
    );
  });

  test('record type identity round-trips in canonical name order', () {
    final encoded = encodeCatalog(
      _catalog(constructorDefault: _recordTypedCollections),
    );
    final decoded = decodeCatalog(encoded);

    expect(
      decoded.widgets.single.properties.single.constructorDefault,
      _recordTypedCollections,
    );
    expect(jsonDecode(encodeCatalog(decoded)), jsonDecode(encoded));

    final root = jsonDecode(encoded) as Map<String, dynamic>;
    final widget =
        (root['widgets'] as List<dynamic>).single as Map<String, dynamic>;
    final property =
        (widget['properties'] as List<dynamic>).single as Map<String, dynamic>;
    final record = property['constructorDefault'] as Map<String, dynamic>;
    final collections = record['positional'] as List<dynamic>;
    final listType = (collections[0] as Map<String, dynamic>)['type']
        as Map<String, dynamic>;
    final recordType = (listType['typeArguments'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(recordType['kind'], 'record');
    expect(
      (recordType['named'] as List<dynamic>)
          .map((field) => (field as Map<String, dynamic>)['name']),
      ['anything', 'labels', 'value'],
    );
  });

  test('legacy v4 and v5 collections without type identity stay accepted', () {
    for (final wireVersion in [4, 5]) {
      final root = jsonDecode(
        encodeCatalog(_catalog(constructorDefault: _typedCollections)),
      ) as Map<String, dynamic>;
      root['schemaVersion'] = wireVersion;
      final widget =
          (root['widgets'] as List<dynamic>).single as Map<String, dynamic>;
      if (wireVersion == 4) widget['fires'] = <Object?>[];
      final property = (widget['properties'] as List<dynamic>).single
          as Map<String, dynamic>;
      final record = property['constructorDefault'] as Map<String, dynamic>;
      final collections = record['positional'] as List<dynamic>;
      for (final value in collections) {
        (value as Map<String, dynamic>).remove('type');
      }

      final decoded = decodeCatalog(jsonEncode(root));
      final decodedRecord = decoded.widgets.single.properties.single
          .constructorDefault! as DartConstRecord;
      expect(
        decodedRecord.positional.map(
          (value) => switch (value) {
            DartConstList(:final type) ||
            DartConstSet(:final type) ||
            DartConstMap(:final type) =>
              type,
            _ => fail('expected a collection, got $value'),
          },
        ),
        everyElement(isNull),
        reason: 'wire v$wireVersion',
      );

      final reencoded =
          jsonDecode(encodeCatalog(decoded)) as Map<String, dynamic>;
      expect(reencoded['schemaVersion'], kSupportedSchemaVersion);
      final reencodedWidget = (reencoded['widgets'] as List<dynamic>).single
          as Map<String, dynamic>;
      final reencodedProperty = (reencodedWidget['properties'] as List<dynamic>)
          .single as Map<String, dynamic>;
      final reencodedRecord =
          reencodedProperty['constructorDefault'] as Map<String, dynamic>;
      expect(
        (reencodedRecord['positional'] as List<dynamic>).map(
          (value) => (value as Map<String, dynamic>).containsKey('type'),
        ),
        everyElement(isFalse),
        reason: 'wire v$wireVersion',
      );
    }
  });

  test('collection type identity participates in equality', () {
    const intType = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'int',
    );
    const stringType = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'String',
    );
    const intList = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'List',
      typeArguments: [intType],
    );
    const stringList = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'List',
      typeArguments: [stringType],
    );
    const intSet = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'Set',
      typeArguments: [intType],
    );
    const stringSet = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'Set',
      typeArguments: [stringType],
    );
    const intMap = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'Map',
      typeArguments: [stringType, intType],
    );
    const stringMap = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'Map',
      typeArguments: [stringType, stringType],
    );

    expect(
      const DartConstList([], type: intList),
      isNot(const DartConstList([], type: stringList)),
    );
    expect(
      const DartConstSet([], type: intSet),
      isNot(const DartConstSet([], type: stringSet)),
    );
    expect(
      const DartConstMap([], type: intMap),
      isNot(const DartConstMap([], type: stringMap)),
    );
  });

  test('named record type identity is canonical by field name', () {
    const intType = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'int',
    );
    const stringType = DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'String',
    );

    expect(
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('count', intType),
          DartRecordTypeNamedField('label', stringType),
        ],
      ),
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('count', intType),
          DartRecordTypeNamedField('label', stringType),
        ],
      ),
    );
    expect(
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('count', intType),
          DartRecordTypeNamedField('label', stringType),
        ],
      ),
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('label', stringType),
          DartRecordTypeNamedField('count', intType),
        ],
      ),
    );
    expect(
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('count', intType),
          DartRecordTypeNamedField('label', stringType),
        ],
      ).hashCode,
      const DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField('label', stringType),
          DartRecordTypeNamedField('count', intType),
        ],
      ).hashCode,
    );
    expect(
      const DartRecordTypeIdentity(positional: [intType, stringType]),
      isNot(
        const DartRecordTypeIdentity(positional: [stringType, intType]),
      ),
    );
  });

  test('record and invocation named values are canonical by name', () {
    const type = DartTypeIdentity(
      libraryUri: 'package:acme/value.dart',
      symbolName: 'Value',
    );
    const canonical = [
      DartConstNamedValue('a', DartConstScalar(1)),
      DartConstNamedValue('b', DartConstScalar(2)),
    ];
    const reordered = [
      DartConstNamedValue('b', DartConstScalar(2)),
      DartConstNamedValue('a', DartConstScalar(1)),
    ];

    expect(
      const DartConstRecord(named: canonical),
      const DartConstRecord(named: reordered),
    );
    expect(
      const DartConstRecord(named: canonical).hashCode,
      const DartConstRecord(named: reordered).hashCode,
    );
    expect(
      const DartConstInvocation(type: type, named: canonical),
      const DartConstInvocation(type: type, named: reordered),
    );
    expect(
      const DartConstInvocation(type: type, named: canonical).hashCode,
      const DartConstInvocation(type: type, named: reordered).hashCode,
    );
    expect(
      const DartConstInvocation(
        type: type,
        positional: [DartConstScalar(1), DartConstScalar(2)],
      ),
      isNot(
        const DartConstInvocation(
          type: type,
          positional: [DartConstScalar(2), DartConstScalar(1)],
        ),
      ),
    );
  });

  test('named type fields and const values have deterministic wire order', () {
    const canonical = DartConstInvocation(
      type: DartTypeIdentity(
        libraryUri: 'package:acme/value.dart',
        symbolName: 'Value',
        typeArguments: [
          DartRecordTypeIdentity(
            named: [
              DartRecordTypeNamedField(
                'a',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'int',
                ),
              ),
              DartRecordTypeNamedField(
                'b',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'String',
                ),
              ),
            ],
          ),
        ],
      ),
      named: [
        DartConstNamedValue(
          'a',
          DartConstRecord(
            named: [
              DartConstNamedValue('a', DartConstScalar(1)),
              DartConstNamedValue('b', DartConstScalar(2)),
            ],
          ),
        ),
        DartConstNamedValue('b', DartConstScalar(3)),
      ],
    );
    const reordered = DartConstInvocation(
      type: DartTypeIdentity(
        libraryUri: 'package:acme/value.dart',
        symbolName: 'Value',
        typeArguments: [
          DartRecordTypeIdentity(
            named: [
              DartRecordTypeNamedField(
                'b',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'String',
                ),
              ),
              DartRecordTypeNamedField(
                'a',
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'int',
                ),
              ),
            ],
          ),
        ],
      ),
      named: [
        DartConstNamedValue('b', DartConstScalar(3)),
        DartConstNamedValue(
          'a',
          DartConstRecord(
            named: [
              DartConstNamedValue('b', DartConstScalar(2)),
              DartConstNamedValue('a', DartConstScalar(1)),
            ],
          ),
        ),
      ],
    );

    final canonicalBytes = encodeCatalog(
      _catalog(constructorDefault: canonical),
    );
    expect(
      encodeCatalog(_catalog(constructorDefault: reordered)),
      canonicalBytes,
    );

    final noncanonical = jsonDecode(canonicalBytes) as Map<String, dynamic>;
    final widget = (noncanonical['widgets'] as List<dynamic>).single
        as Map<String, dynamic>;
    final property =
        (widget['properties'] as List<dynamic>).single as Map<String, dynamic>;
    final invocation = property['constructorDefault'] as Map<String, dynamic>;
    final type = invocation['type'] as Map<String, dynamic>;
    final recordType =
        (type['typeArguments'] as List<dynamic>).single as Map<String, dynamic>;
    recordType['named'] =
        (recordType['named'] as List<dynamic>).reversed.toList();
    final invocationNamed = invocation['named'] as Map<String, dynamic>;
    invocation['named'] = <String, dynamic>{
      for (final entry in invocationNamed.entries.toList().reversed)
        entry.key: entry.value,
    };
    final record = (invocation['named'] as Map<String, dynamic>)['a']
        as Map<String, dynamic>;
    final recordNamed = record['named'] as Map<String, dynamic>;
    record['named'] = <String, dynamic>{
      for (final entry in recordNamed.entries.toList().reversed)
        entry.key: entry.value,
    };

    final decoded = decodeCatalog(jsonEncode(noncanonical));
    final decodedInvocation = decoded.widgets.single.properties.single
        .constructorDefault! as DartConstInvocation;
    final decodedType = decodedInvocation.type as DartNamedTypeIdentity;
    final decodedRecordType =
        decodedType.typeArguments.single as DartRecordTypeIdentity;
    final decodedRecord =
        decodedInvocation.named.first.value as DartConstRecord;
    expect(decodedRecordType.named.map((field) => field.name), ['a', 'b']);
    expect(decodedInvocation.named.map((field) => field.name), ['a', 'b']);
    expect(decodedRecord.named.map((field) => field.name), ['a', 'b']);
    expect(decodedInvocation, canonical);
    expect(encodeCatalog(decoded), canonicalBytes);
  });

  test('legacy properties omit constructor fields and keep stable shape', () {
    final encoded = encodeCatalog(_catalog());
    final property = ((jsonDecode(encoded) as Map<String, dynamic>)['widgets']
            as List<dynamic>)
        .single as Map<String, dynamic>;
    final propertyJson = (property['properties'] as List<dynamic>).single
        as Map<String, dynamic>;

    expect(propertyJson, isNot(contains('constructorDefault')));
    expect(propertyJson, isNot(contains('constructorNullable')));
  });

  test('wrong-typed top-level and nested fields fail through schema errors',
      () {
    final raw = jsonDecode(
      encodeCatalog(
        _catalog(
          constructorDefault: _complexDefault,
          constructorNullable: true,
        ),
      ),
    ) as Map<String, dynamic>;

    final wrongFlutter = Map<String, dynamic>.from(raw)
      ..['flutterVersion'] = 42;
    expect(
      () => decodeCatalog(jsonEncode(wrongFlutter)),
      throwsA(isA<CatalogSchemaException>()),
    );

    final nested = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    final property = ((nested['widgets'] as List<dynamic>).single
        as Map<String, dynamic>)['properties'] as List<dynamic>;
    final constructor = (property.single
        as Map<String, dynamic>)['constructorDefault'] as Map<String, dynamic>;
    final type = constructor['type'] as Map<String, dynamic>;
    type['typeArguments'] = 'not-a-list';
    expect(
      () => decodeCatalog(jsonEncode(nested)),
      throwsA(isA<CatalogSchemaException>()),
    );
  });

  test(
    'lossy unknown re-encode guard survives AOT assertion stripping',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'restage-unknown-reencode-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final executable = '${temporary.path}/probe';
      final compile = await Process.run(
        Platform.resolvedExecutable,
        [
          'compile',
          'exe',
          'test/fixtures/unknown_reencode_probe.dart',
          '-o',
          executable,
        ],
      );
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );

      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(run.stdout, contains('CatalogSchemaException'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
