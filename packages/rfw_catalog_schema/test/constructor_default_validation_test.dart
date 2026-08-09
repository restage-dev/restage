import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const DartTypeIdentity _intType = DartTypeIdentity(
  libraryUri: 'dart:core',
  symbolName: 'int',
);
const DartTypeIdentity _stringType = DartTypeIdentity(
  libraryUri: 'dart:core',
  symbolName: 'String',
);
const DartTypeIdentity _valueType = DartTypeIdentity(
  libraryUri: 'package:acme/value.dart',
  symbolName: 'Value',
);
const DartTypeIdentity _listOfIntType = DartTypeIdentity(
  libraryUri: 'dart:core',
  symbolName: 'List',
  typeArguments: [_intType],
);
const DartTypeIdentity _setOfIntType = DartTypeIdentity(
  libraryUri: 'dart:core',
  symbolName: 'Set',
  typeArguments: [_intType],
);
const DartTypeIdentity _mapOfStringToIntType = DartTypeIdentity(
  libraryUri: 'dart:core',
  symbolName: 'Map',
  typeArguments: [_stringType, _intType],
);

Catalog _catalog(DartConstValue constructorDefault) => Catalog(
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
              constructorDefault: constructorDefault,
            ),
          ],
        ),
      ],
    );

String _mutatedCatalog(
  DartConstValue validValue,
  void Function(Map<String, dynamic> value) mutate,
) {
  final root =
      jsonDecode(encodeCatalog(_catalog(validValue))) as Map<String, dynamic>;
  final widget =
      (root['widgets'] as List<dynamic>).single as Map<String, dynamic>;
  final property =
      (widget['properties'] as List<dynamic>).single as Map<String, dynamic>;
  mutate(property['constructorDefault'] as Map<String, dynamic>);
  return jsonEncode(root);
}

Matcher _schemaFailure(String message) => isA<CatalogSchemaException>().having(
      (error) => error.message,
      'message',
      contains(message),
    );

void _expectProgrammaticFailure(
  DartConstValue value,
  String message,
) {
  expect(
    () => encodeCatalog(_catalog(value)),
    throwsA(_schemaFailure(message)),
  );
  expect(
    () => requireNativeCatalog(_catalog(value)),
    throwsA(_schemaFailure(message)),
  );
}

void _expectDecodeFailure(
  DartConstValue validValue,
  void Function(Map<String, dynamic> value) mutate,
  String message,
) {
  expect(
    () => decodeCatalog(_mutatedCatalog(validValue, mutate)),
    throwsA(_schemaFailure(message)),
  );
}

void _expectAllEntrypointsAccept(DartConstValue value) {
  final catalog = _catalog(value);
  final encoded = encodeCatalog(catalog);
  expect(
    decodeCatalog(encoded).widgets.single.properties.single.constructorDefault,
    value,
  );
  expect(requireNativeCatalog(catalog), same(catalog));
}

Map<String, dynamic> _jsonObjectClone(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void _reverseNamedValues(Map<String, dynamic> value) {
  final entries = (value['named'] as Map<String, dynamic>).entries.toList();
  value['named'] = <String, dynamic>{
    for (final entry in entries.reversed) entry.key: entry.value,
  };
}

void main() {
  group('recursive schema boundary', () {
    test('rejects non-importable reference libraries on every entrypoint', () {
      const valid = DartConstReference(
        libraryUri: 'package:acme/value.dart',
        owner: 'Defaults',
        member: 'value',
      );
      const path = 'constructorDefault.libraryUri';

      for (final invalidUri in <String>[
        'file:///tmp/value.dart',
        'package:/acme/value.dart',
      ]) {
        _expectProgrammaticFailure(
          DartConstReference(
            libraryUri: invalidUri,
            owner: 'Defaults',
            member: 'value',
          ),
          path,
        );
        _expectDecodeFailure(
          valid,
          (value) => value['libraryUri'] = invalidUri,
          path,
        );
      }
    });

    test('rejects private reference owners and members on every entrypoint',
        () {
      const valid = DartConstReference(
        libraryUri: 'package:acme/value.dart',
        owner: 'Defaults',
        member: 'value',
      );

      _expectProgrammaticFailure(
        const DartConstReference(
          libraryUri: 'package:acme/value.dart',
          owner: '_Defaults',
          member: 'value',
        ),
        'constructorDefault.owner',
      );
      _expectDecodeFailure(
        valid,
        (value) => value['owner'] = '_Defaults',
        'constructorDefault.owner',
      );

      _expectProgrammaticFailure(
        const DartConstReference(
          libraryUri: 'package:acme/value.dart',
          owner: 'Defaults',
          member: '_value',
        ),
        'constructorDefault.member',
      );
      _expectDecodeFailure(
        valid,
        (value) => value['member'] = '_value',
        'constructorDefault.member',
      );
    });

    test('rejects invalid invocation type identities and selectors', () {
      const valid = DartConstInvocation(
        type: _valueType,
        constructorName: 'configured',
      );

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: DartTypeIdentity(
            libraryUri: 'file:///tmp/value.dart',
            symbolName: 'Value',
          ),
        ),
        'constructorDefault.type.libraryUri',
      );
      _expectDecodeFailure(
        valid,
        (value) => (value['type'] as Map<String, dynamic>)['libraryUri'] =
            'file:///tmp/value.dart',
        'constructorDefault.type.libraryUri',
      );

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: DartTypeIdentity(
            libraryUri: 'package:acme/value.dart',
            symbolName: '_Value',
          ),
        ),
        'constructorDefault.type.symbolName',
      );
      _expectDecodeFailure(
        valid,
        (value) =>
            (value['type'] as Map<String, dynamic>)['symbolName'] = '_Value',
        'constructorDefault.type.symbolName',
      );

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: _valueType,
          constructorName: 'class',
        ),
        'constructorDefault.constructorName',
      );
      _expectDecodeFailure(
        valid,
        (value) => value['constructorName'] = 'class',
        'constructorDefault.constructorName',
      );
    });

    test('rejects invalid named argument and record-field identities', () {
      const validInvocation = DartConstInvocation(
        type: _valueType,
        named: [DartConstNamedValue('required', DartConstScalar(1))],
      );
      const invalidInvocation = DartConstInvocation(
        type: _valueType,
        named: [DartConstNamedValue('class', DartConstScalar(1))],
      );
      _expectProgrammaticFailure(
        invalidInvocation,
        'constructorDefault.named[0].name',
      );
      _expectDecodeFailure(
        validInvocation,
        (value) {
          final named = value['named'] as Map<String, dynamic>;
          final argument = named.remove('required');
          named['class'] = argument;
        },
        'constructorDefault.named[0].name',
      );

      const validRecord = DartConstRecord(
        named: [DartConstNamedValue('when', DartConstScalar(1))],
      );
      const invalidRecord = DartConstRecord(
        named: [DartConstNamedValue('class', DartConstScalar(1))],
      );
      _expectProgrammaticFailure(
        invalidRecord,
        'constructorDefault.named[0].name',
      );
      _expectDecodeFailure(
        validRecord,
        (value) {
          final named = value['named'] as Map<String, dynamic>;
          final field = named.remove('when');
          named['class'] = field;
        },
        'constructorDefault.named[0].name',
      );
    });

    test('rejects invalid and duplicate record-type fields recursively', () {
      const valid = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartRecordTypeIdentity(
              named: [DartRecordTypeNamedField('when', _intType)],
            ),
          ],
        ),
      );
      const invalidName = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartRecordTypeIdentity(
              named: [DartRecordTypeNamedField('class', _intType)],
            ),
          ],
        ),
      );
      const namePath = 'constructorDefault.type.typeArguments[0].named[0].name';
      _expectProgrammaticFailure(invalidName, namePath);
      _expectDecodeFailure(
        valid,
        (value) {
          final type = value['type'] as Map<String, dynamic>;
          final record = (type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>;
          final field =
              (record['named'] as List<dynamic>).single as Map<String, dynamic>;
          field['name'] = 'class';
        },
        namePath,
      );

      const duplicate = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartRecordTypeIdentity(
              named: [
                DartRecordTypeNamedField('value', _intType),
                DartRecordTypeNamedField('value', _stringType),
              ],
            ),
          ],
        ),
      );
      const duplicatePath =
          'constructorDefault.type.typeArguments[0].named[1].name';
      _expectProgrammaticFailure(duplicate, duplicatePath);
      _expectDecodeFailure(
        valid,
        (value) {
          final type = value['type'] as Map<String, dynamic>;
          final record = (type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>;
          (record['named'] as List<dynamic>).add({
            'name': 'when',
            'type': {
              'libraryUri': 'dart:core',
              'symbolName': 'String',
            },
          });
        },
        duplicatePath,
      );
    });

    test('rejects structural and nullable invocation outer types', () {
      const valid = DartConstInvocation(type: _valueType);

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: DartRecordTypeIdentity(positional: [_intType]),
        ),
        'constructorDefault.type: a const invocation requires a named '
        'Dart type',
      );
      _expectDecodeFailure(
        valid,
        (value) {
          (value['type'] as Map<String, dynamic>)
            ..clear()
            ..addAll({
              'kind': 'record',
              'positional': [
                {'libraryUri': 'dart:core', 'symbolName': 'int'},
              ],
            });
        },
        'constructorDefault.type: a const invocation requires a named '
        'Dart type',
      );

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: DartTypeIdentity(
            libraryUri: 'package:acme/value.dart',
            symbolName: 'Value',
            nullable: true,
          ),
        ),
        'constructorDefault.type.nullable',
      );
      _expectDecodeFailure(
        valid,
        (value) => (value['type'] as Map<String, dynamic>)['nullable'] = true,
        'constructorDefault.type.nullable',
      );
    });

    test('rejects malformed typed List, Set, and Map outer identities', () {
      const validList = DartConstList(<DartConstValue>[], type: _listOfIntType);
      const structuralList = DartConstList(
        <DartConstValue>[],
        type: DartRecordTypeIdentity(positional: [_intType]),
      );
      _expectProgrammaticFailure(
        structuralList,
        'constructorDefault.type: a typed const List requires a named',
      );
      _expectDecodeFailure(
        validList,
        (value) {
          (value['type'] as Map<String, dynamic>)
            ..clear()
            ..addAll({
              'kind': 'record',
              'positional': [
                {'libraryUri': 'dart:core', 'symbolName': 'int'},
              ],
            });
        },
        'constructorDefault.type: a typed const List requires a named',
      );

      const nullableList = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [_intType],
          nullable: true,
        ),
      );
      _expectProgrammaticFailure(
        nullableList,
        'constructorDefault.type.nullable',
      );
      _expectDecodeFailure(
        validList,
        (value) => (value['type'] as Map<String, dynamic>)['nullable'] = true,
        'constructorDefault.type.nullable',
      );

      const wrongList = DartConstList(
        <DartConstValue>[],
        type: _setOfIntType,
      );
      _expectProgrammaticFailure(
        wrongList,
        'constructorDefault.type: a typed const List requires dart:core#List',
      );
      _expectDecodeFailure(
        validList,
        (value) =>
            (value['type'] as Map<String, dynamic>)['symbolName'] = 'Set',
        'constructorDefault.type: a typed const List requires dart:core#List',
      );

      const invalidSet = DartConstSet(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'Set',
          typeArguments: [_intType, _stringType],
        ),
      );
      const validSet = DartConstSet(<DartConstValue>[], type: _setOfIntType);
      _expectProgrammaticFailure(
        invalidSet,
        'constructorDefault.type.typeArguments: dart:core#Set requires '
        'exactly 1',
      );
      _expectDecodeFailure(
        validSet,
        (value) => (value['type'] as Map<String, dynamic>)['typeArguments'] = [
          {'libraryUri': 'dart:core', 'symbolName': 'int'},
          {'libraryUri': 'dart:core', 'symbolName': 'String'},
        ],
        'constructorDefault.type.typeArguments: dart:core#Set requires '
        'exactly 1',
      );

      const wrongMapLibrary = DartConstMap(
        <DartConstMapEntry>[],
        type: DartTypeIdentity(
          libraryUri: 'package:acme/value.dart',
          symbolName: 'Map',
          typeArguments: [_stringType, _intType],
        ),
      );
      const validMap = DartConstMap(
        <DartConstMapEntry>[],
        type: _mapOfStringToIntType,
      );
      _expectProgrammaticFailure(
        wrongMapLibrary,
        'constructorDefault.type: a typed const Map requires dart:core#Map',
      );
      _expectDecodeFailure(
        validMap,
        (value) => (value['type'] as Map<String, dynamic>)['libraryUri'] =
            'package:acme/value.dart',
        'constructorDefault.type: a typed const Map requires dart:core#Map',
      );

      const invalidMapArity = DartConstMap(
        <DartConstMapEntry>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'Map',
          typeArguments: [_stringType],
        ),
      );
      _expectProgrammaticFailure(
        invalidMapArity,
        'constructorDefault.type.typeArguments: dart:core#Map requires '
        'exactly 2',
      );
      _expectDecodeFailure(
        validMap,
        (value) => (value['type'] as Map<String, dynamic>)['typeArguments'] = [
          {'libraryUri': 'dart:core', 'symbolName': 'String'},
        ],
        'constructorDefault.type.typeArguments: dart:core#Map requires '
        'exactly 2',
      );
    });

    test('rejects invalid recursively nested types and scalar values', () {
      const validType = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'void'),
          ],
        ),
      );
      const invalidType = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'void',
              nullable: true,
            ),
          ],
        ),
      );
      const typePath = 'constructorDefault.type.typeArguments[0].nullable';
      _expectProgrammaticFailure(invalidType, typePath);
      _expectDecodeFailure(
        validType,
        (value) {
          final type = value['type'] as Map<String, dynamic>;
          final argument = (type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>;
          argument['nullable'] = true;
        },
        typePath,
      );

      _expectProgrammaticFailure(
        DartConstScalar(DateTime.utc(2026)),
        'constructorDefault.value',
      );
      _expectDecodeFailure(
        const DartConstScalar('valid'),
        (value) => value['value'] = <Object?>[],
        'constructorDefault.value',
      );
      _expectProgrammaticFailure(
        const DartConstScalar(double.nan),
        'constructorDefault.value',
      );
      _expectProgrammaticFailure(
        const DartConstScalar(double.infinity),
        'constructorDefault.value',
      );
      final overflowingDouble = encodeCatalog(
        _catalog(const DartConstScalar(2.5)),
      ).replaceFirst('"value": 2.5', '"value": 1e999');
      expect(
        () => decodeCatalog(overflowingDouble),
        throwsA(_schemaFailure('constructorDefault.value')),
      );
    });

    test('recurses through positional, set, map-key, and map-value contents',
        () {
      const validReference = DartConstReference(
        libraryUri: 'package:acme/value.dart',
        owner: 'Defaults',
        member: 'value',
      );
      const invalidReference = DartConstReference(
        libraryUri: 'package:acme/value.dart',
        owner: 'Defaults',
        member: '_value',
      );

      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: _valueType,
          positional: [invalidReference],
        ),
        'constructorDefault.positional[0].member',
      );
      _expectDecodeFailure(
        const DartConstInvocation(
          type: _valueType,
          positional: [validReference],
        ),
        (value) {
          final reference = (value['positional'] as List<dynamic>).single
              as Map<String, dynamic>;
          reference['member'] = '_value';
        },
        'constructorDefault.positional[0].member',
      );

      _expectProgrammaticFailure(
        const DartConstSet([invalidReference]),
        'constructorDefault.values[0].member',
      );
      _expectDecodeFailure(
        const DartConstSet([validReference]),
        (value) {
          final reference =
              (value['values'] as List<dynamic>).single as Map<String, dynamic>;
          reference['member'] = '_value';
        },
        'constructorDefault.values[0].member',
      );

      _expectProgrammaticFailure(
        const DartConstMap([
          DartConstMapEntry(invalidReference, DartConstScalar(1)),
        ]),
        'constructorDefault.entries[0].key.member',
      );
      _expectDecodeFailure(
        const DartConstMap([
          DartConstMapEntry(validReference, DartConstScalar(1)),
        ]),
        (value) {
          final entry = (value['entries'] as List<dynamic>).single
              as Map<String, dynamic>;
          (entry['key'] as Map<String, dynamic>)['member'] = '_value';
        },
        'constructorDefault.entries[0].key.member',
      );

      _expectProgrammaticFailure(
        const DartConstMap([
          DartConstMapEntry(DartConstScalar('key'), invalidReference),
        ]),
        'constructorDefault.entries[0].value.member',
      );
      _expectDecodeFailure(
        const DartConstMap([
          DartConstMapEntry(DartConstScalar('key'), validReference),
        ]),
        (value) {
          final entry = (value['entries'] as List<dynamic>).single
              as Map<String, dynamic>;
          (entry['value'] as Map<String, dynamic>)['member'] = '_value';
        },
        'constructorDefault.entries[0].value.member',
      );

      _expectProgrammaticFailure(
        const DartConstRecord(positional: [invalidReference]),
        'constructorDefault.positional[0].member',
      );
      _expectDecodeFailure(
        const DartConstRecord(positional: [validReference]),
        (value) {
          final reference = (value['positional'] as List<dynamic>).single
              as Map<String, dynamic>;
          reference['member'] = '_value';
        },
        'constructorDefault.positional[0].member',
      );
    });

    test('reports the complete path for a deeply nested invalid value', () {
      const valid = DartConstInvocation(
        type: _valueType,
        named: [
          DartConstNamedValue(
            'options',
            DartConstRecord(
              named: [
                DartConstNamedValue(
                  'labels',
                  DartConstList([
                    DartConstReference(
                      libraryUri: 'package:acme/value.dart',
                      owner: 'Defaults',
                      member: 'label',
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      );
      const invalid = DartConstInvocation(
        type: _valueType,
        named: [
          DartConstNamedValue(
            'options',
            DartConstRecord(
              named: [
                DartConstNamedValue(
                  'labels',
                  DartConstList([
                    DartConstReference(
                      libraryUri: 'package:acme/value.dart',
                      owner: 'Defaults',
                      member: '_label',
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      );
      const nestedPath =
          'constructorDefault.named[0].value.named[0].value.values[0].member';
      const encodePath = 'widgets[0] "Probe".properties[0].$nestedPath';

      expect(
        () => encodeCatalog(_catalog(invalid)),
        throwsA(_schemaFailure(encodePath)),
      );
      expect(
        () => requireNativeCatalog(_catalog(invalid)),
        throwsA(_schemaFailure(encodePath)),
      );
      expect(
        () => decodeCatalog(
          _mutatedCatalog(valid, (value) {
            final invocationNamed = value['named'] as Map<String, dynamic>;
            final record = invocationNamed['options'] as Map<String, dynamic>;
            final recordNamed = record['named'] as Map<String, dynamic>;
            final list = recordNamed['labels'] as Map<String, dynamic>;
            final reference = (list['values'] as List<dynamic>).single
                as Map<String, dynamic>;
            reference['member'] = '_label';
          }),
        ),
        throwsA(_schemaFailure(encodePath)),
      );
    });
  });

  group('programmatic duplicate named values', () {
    test('invocation named arguments fail before map serialization', () {
      _expectProgrammaticFailure(
        const DartConstInvocation(
          type: _valueType,
          named: [
            DartConstNamedValue('value', DartConstScalar(1)),
            DartConstNamedValue('value', DartConstScalar(2)),
          ],
        ),
        'constructorDefault.named[1].name: duplicate',
      );
    });

    test('record named fields fail before map serialization', () {
      _expectProgrammaticFailure(
        const DartConstRecord(
          named: [
            DartConstNamedValue('value', DartConstScalar(1)),
            DartConstNamedValue('value', DartConstScalar(2)),
          ],
        ),
        'constructorDefault.named[1].name: duplicate',
      );
    });

    test('record type named fields fail before list serialization', () {
      _expectProgrammaticFailure(
        const DartConstList(
          <DartConstValue>[],
          type: DartTypeIdentity(
            libraryUri: 'dart:core',
            symbolName: 'List',
            typeArguments: [
              DartRecordTypeIdentity(
                named: [
                  DartRecordTypeNamedField('value', _intType),
                  DartRecordTypeNamedField('value', _stringType),
                ],
              ),
            ],
          ),
        ),
        'constructorDefault.type.typeArguments[0].named[1].name: duplicate',
      );
    });
  });

  group('const collection key eligibility', () {
    test('rejects double set elements with numeric identity intact', () {
      const valid = DartConstSet([DartConstScalar(1)]);
      const path = 'constructorDefault.values[0]: a Dart const set element '
          'must have primitive equality';

      _expectAllEntrypointsAccept(valid);
      for (final value in <double>[1, 0, -0]) {
        _expectProgrammaticFailure(
          DartConstSet([DartConstScalar(value)]),
          path,
        );
        _expectDecodeFailure(
          valid,
          (json) {
            final scalar = (json['values'] as List<dynamic>).single
                as Map<String, dynamic>;
            scalar['value'] = value;
          },
          path,
        );
      }
    });

    test('rejects double map keys with numeric identity intact', () {
      const valid = DartConstMap([
        DartConstMapEntry(DartConstScalar(1), DartConstScalar('value')),
      ]);
      const path = 'constructorDefault.entries[0].key: a Dart const map key '
          'must have primitive equality';

      _expectAllEntrypointsAccept(valid);
      for (final value in <double>[1, 0, -0]) {
        _expectProgrammaticFailure(
          DartConstMap([
            DartConstMapEntry(
              DartConstScalar(value),
              const DartConstScalar('value'),
            ),
          ]),
          path,
        );
        _expectDecodeFailure(
          valid,
          (json) {
            final entry = (json['entries'] as List<dynamic>).single
                as Map<String, dynamic>;
            (entry['key'] as Map<String, dynamic>)['value'] = value;
          },
          path,
        );
      }
    });

    test('rejects doubles recursively inside record set elements', () {
      const valid = DartConstSet([
        DartConstRecord(
          positional: [
            DartConstRecord(positional: [DartConstScalar(1)]),
          ],
        ),
      ]);
      const invalid = DartConstSet([
        DartConstRecord(
          positional: [
            DartConstRecord(positional: [DartConstScalar(-0.0)]),
          ],
        ),
      ]);
      const path = 'constructorDefault.values[0].positional[0].positional[0]: '
          'a Dart const set element must have primitive equality';

      _expectProgrammaticFailure(invalid, path);
      _expectDecodeFailure(
        valid,
        (json) {
          final outerRecord =
              (json['values'] as List<dynamic>).single as Map<String, dynamic>;
          final innerRecord = (outerRecord['positional'] as List<dynamic>)
              .single as Map<String, dynamic>;
          final scalar = (innerRecord['positional'] as List<dynamic>).single
              as Map<String, dynamic>;
          scalar['value'] = -0.0;
        },
        path,
      );
    });

    test('rejects doubles recursively inside record map keys', () {
      const valid = DartConstMap([
        DartConstMapEntry(
          DartConstRecord(
            named: [
              DartConstNamedValue(
                'nested',
                DartConstRecord(
                  named: [
                    DartConstNamedValue('value', DartConstScalar(1)),
                  ],
                ),
              ),
            ],
          ),
          DartConstScalar('value'),
        ),
      ]);
      const invalid = DartConstMap([
        DartConstMapEntry(
          DartConstRecord(
            named: [
              DartConstNamedValue(
                'nested',
                DartConstRecord(
                  named: [
                    DartConstNamedValue('value', DartConstScalar(1.0)),
                  ],
                ),
              ),
            ],
          ),
          DartConstScalar('value'),
        ),
      ]);
      const path = 'constructorDefault.entries[0].key.named[0].value.named[0]'
          '.value: a Dart const map key must have primitive equality';

      _expectProgrammaticFailure(invalid, path);
      _expectDecodeFailure(
        valid,
        (json) {
          final entry =
              (json['entries'] as List<dynamic>).single as Map<String, dynamic>;
          final outerRecord = entry['key'] as Map<String, dynamic>;
          final innerRecord = (outerRecord['named']
              as Map<String, dynamic>)['nested'] as Map<String, dynamic>;
          final scalar = (innerRecord['named'] as Map<String, dynamic>)['value']
              as Map<String, dynamic>;
          scalar['value'] = 1.0;
        },
        path,
      );
    });

    test('preserves known-valid and resolver-owned key shapes', () {
      const reference = DartConstReference(
        libraryUri: 'package:acme/value.dart',
        owner: 'Values',
        member: 'enumValue',
      );
      const record = DartConstRecord(
        positional: [DartConstScalar(1), DartConstScalar(true)],
        named: [DartConstNamedValue('label', DartConstScalar('value'))],
      );

      _expectAllEntrypointsAccept(
        const DartConstSet([
          DartConstNull(),
          DartConstScalar(1),
          DartConstScalar(true),
          DartConstScalar('value'),
          reference,
          record,
          DartConstList([DartConstScalar(1.0)]),
        ]),
      );
      _expectAllEntrypointsAccept(
        const DartConstMap([
          DartConstMapEntry(reference, DartConstScalar(1)),
          DartConstMapEntry(record, DartConstScalar(2)),
          DartConstMapEntry(
            DartConstList([DartConstScalar(1.0)]),
            DartConstScalar(3),
          ),
        ]),
      );
    });
  });

  group('known dart:core declaration arity', () {
    test('rejects nested non-generic core types with type arguments', () {
      const valid = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [_intType],
        ),
      );
      const invalid = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'int',
              typeArguments: [_stringType],
            ),
          ],
        ),
      );
      const path = 'constructorDefault.type.typeArguments[0].typeArguments: '
          'dart:core#int accepts no type arguments';

      _expectProgrammaticFailure(invalid, path);
      _expectDecodeFailure(
        valid,
        (json) {
          final type = json['type'] as Map<String, dynamic>;
          final argument = (type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>;
          argument['typeArguments'] = [
            {'libraryUri': 'dart:core', 'symbolName': 'String'},
          ];
        },
        path,
      );
    });

    test('rejects partial and over-applied generic core types recursively', () {
      const valid = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Map',
              typeArguments: [_stringType, _intType],
            ),
          ],
        ),
      );
      const partial = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Map',
              typeArguments: [_stringType],
            ),
          ],
        ),
      );
      const overApplied = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Iterable',
              typeArguments: [_stringType, _intType],
            ),
          ],
        ),
      );
      const mapPath = 'constructorDefault.type.typeArguments[0].typeArguments: '
          'dart:core#Map accepts either no type arguments or exactly 2';
      const iterablePath =
          'constructorDefault.type.typeArguments[0].typeArguments: '
          'dart:core#Iterable accepts either no type arguments or exactly 1';

      _expectProgrammaticFailure(partial, mapPath);
      _expectDecodeFailure(
        valid,
        (json) {
          final type = json['type'] as Map<String, dynamic>;
          final argument = (type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>;
          argument['typeArguments'] = [
            {'libraryUri': 'dart:core', 'symbolName': 'String'},
          ];
        },
        mapPath,
      );
      _expectProgrammaticFailure(overApplied, iterablePath);
      _expectDecodeFailure(
        valid,
        (json) {
          final type = json['type'] as Map<String, dynamic>;
          ((type['typeArguments'] as List<dynamic>).single
              as Map<String, dynamic>)
            ..['symbolName'] = 'Iterable'
            ..['typeArguments'] = [
              {'libraryUri': 'dart:core', 'symbolName': 'String'},
              {'libraryUri': 'dart:core', 'symbolName': 'int'},
            ];
        },
        iterablePath,
      );
    });

    test('accepts raw and fully applied core types and arbitrary package arity',
        () {
      _expectAllEntrypointsAccept(
        const DartConstList(
          <DartConstValue>[],
          type: DartTypeIdentity(
            libraryUri: 'dart:core',
            symbolName: 'List',
            typeArguments: [
              DartTypeIdentity(
                libraryUri: 'dart:core',
                symbolName: 'Map',
              ),
            ],
          ),
        ),
      );
      _expectAllEntrypointsAccept(
        const DartConstInvocation(
          type: DartTypeIdentity(
            libraryUri: 'package:acme/value.dart',
            symbolName: 'Value',
            typeArguments: [_intType, _stringType, _valueType],
          ),
        ),
      );
      _expectAllEntrypointsAccept(
        const DartConstList(
          <DartConstValue>[],
          type: DartTypeIdentity(
            libraryUri: 'dart:core',
            symbolName: 'List',
            typeArguments: [
              DartRecordTypeIdentity(
                positional: [
                  DartTypeIdentity(
                    libraryUri: 'dart:core',
                    symbolName: 'Map',
                    typeArguments: [_stringType, _intType],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  });

  group('const collection duplicates', () {
    test('set values fail at every schema entrypoint', () {
      const value = DartConstRecord(positional: [DartConstScalar(1)]);
      const valid = DartConstSet([value]);
      const duplicate = DartConstSet([value, value]);
      const path =
          'widgets[0] "Probe".properties[0].constructorDefault.values[1]: '
          'duplicate Dart const set value';

      _expectProgrammaticFailure(duplicate, path);
      _expectDecodeFailure(
        valid,
        (value) {
          final values = value['values'] as List<dynamic>;
          values.add(values.single);
        },
        path,
      );
    });

    test('map keys fail at every schema entrypoint', () {
      const entry = DartConstMapEntry(
        DartConstScalar('key'),
        DartConstScalar(1),
      );
      const valid = DartConstMap([entry]);
      const duplicate = DartConstMap([entry, entry]);
      const path =
          'widgets[0] "Probe".properties[0].constructorDefault.entries[1].key: '
          'duplicate Dart const map key';

      _expectProgrammaticFailure(duplicate, path);
      _expectDecodeFailure(
        valid,
        (value) {
          final entries = value['entries'] as List<dynamic>;
          entries.add(entries.single);
        },
        path,
      );
    });

    test('reordered named records fail as duplicate set values and map keys',
        () {
      const canonical = DartConstRecord(
        named: [
          DartConstNamedValue('a', DartConstScalar(1)),
          DartConstNamedValue('b', DartConstScalar(2)),
        ],
      );
      const reordered = DartConstRecord(
        named: [
          DartConstNamedValue('b', DartConstScalar(2)),
          DartConstNamedValue('a', DartConstScalar(1)),
        ],
      );
      const setPath =
          'widgets[0] "Probe".properties[0].constructorDefault.values[1]: '
          'duplicate Dart const set value';
      const mapPath =
          'widgets[0] "Probe".properties[0].constructorDefault.entries[1].key: '
          'duplicate Dart const map key';

      _expectProgrammaticFailure(
        const DartConstSet([canonical, reordered]),
        setPath,
      );
      _expectDecodeFailure(
        const DartConstSet([canonical]),
        (value) {
          final values = value['values'] as List<dynamic>;
          final duplicate = _jsonObjectClone(values.single);
          _reverseNamedValues(duplicate);
          values.add(duplicate);
        },
        setPath,
      );

      _expectProgrammaticFailure(
        const DartConstMap([
          DartConstMapEntry(canonical, DartConstScalar(1)),
          DartConstMapEntry(reordered, DartConstScalar(2)),
        ]),
        mapPath,
      );
      _expectDecodeFailure(
        const DartConstMap([
          DartConstMapEntry(canonical, DartConstScalar(1)),
        ]),
        (value) {
          final entries = value['entries'] as List<dynamic>;
          final duplicate = _jsonObjectClone(entries.single);
          _reverseNamedValues(
            duplicate['key'] as Map<String, dynamic>,
          );
          duplicate['value'] = const {'kind': 'scalar', 'value': 2};
          entries.add(duplicate);
        },
        mapPath,
      );
    });

    test(
        'reordered invocation arguments fail as duplicate set values '
        'and map keys', () {
      const canonical = DartConstInvocation(
        type: _valueType,
        named: [
          DartConstNamedValue('a', DartConstScalar(1)),
          DartConstNamedValue('b', DartConstScalar(2)),
        ],
      );
      const reordered = DartConstInvocation(
        type: _valueType,
        named: [
          DartConstNamedValue('b', DartConstScalar(2)),
          DartConstNamedValue('a', DartConstScalar(1)),
        ],
      );
      const setPath =
          'widgets[0] "Probe".properties[0].constructorDefault.values[1]: '
          'duplicate Dart const set value';
      const mapPath =
          'widgets[0] "Probe".properties[0].constructorDefault.entries[1].key: '
          'duplicate Dart const map key';

      _expectProgrammaticFailure(
        const DartConstSet([canonical, reordered]),
        setPath,
      );
      _expectDecodeFailure(
        const DartConstSet([canonical]),
        (value) {
          final values = value['values'] as List<dynamic>;
          final duplicate = _jsonObjectClone(values.single);
          _reverseNamedValues(duplicate);
          values.add(duplicate);
        },
        setPath,
      );

      _expectProgrammaticFailure(
        const DartConstMap([
          DartConstMapEntry(canonical, DartConstScalar(1)),
          DartConstMapEntry(reordered, DartConstScalar(2)),
        ]),
        mapPath,
      );
      _expectDecodeFailure(
        const DartConstMap([
          DartConstMapEntry(canonical, DartConstScalar(1)),
        ]),
        (value) {
          final entries = value['entries'] as List<dynamic>;
          final duplicate = _jsonObjectClone(entries.single);
          _reverseNamedValues(
            duplicate['key'] as Map<String, dynamic>,
          );
          duplicate['value'] = const {'kind': 'scalar', 'value': 2};
          entries.add(duplicate);
        },
        mapPath,
      );
    });
  });

  test('legal contextual identifiers survive validation and round-trip', () {
    const value = DartConstInvocation(
      type: _valueType,
      constructorName: 'new',
      named: [
        DartConstNamedValue(
          'required',
          DartConstRecord(
            named: [
              DartConstNamedValue(
                'when',
                DartConstReference(
                  libraryUri: 'package:acme/value.dart',
                  owner: 'Defaults',
                  member: 'interface',
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final catalog = _catalog(value);
    final encoded = encodeCatalog(catalog);
    expect(
      decodeCatalog(encoded)
          .widgets
          .single
          .properties
          .single
          .constructorDefault,
      value,
    );
    expect(requireNativeCatalog(catalog), same(catalog));
  });

  group('scalar identity', () {
    test('distinguishes numeric kinds and signed zero in equality and hashing',
        () {
      const intOne = DartConstScalar(1);
      const doubleOne = DartConstScalar(1.0);
      const positiveZero = DartConstScalar(0.0);
      const negativeZero = DartConstScalar(-0.0);

      expect(intOne, isNot(doubleOne));
      expect(intOne.hashCode, isNot(doubleOne.hashCode));
      expect(positiveZero, isNot(negativeZero));
      expect(positiveZero.hashCode, isNot(negativeZero.hashCode));
      expect(
        <DartConstScalar>{intOne, doubleOne, positiveZero, negativeZero},
        hasLength(4),
      );
      for (final value in <Object>[true, 1, 1.0, 'value']) {
        final left = DartConstScalar(value);
        final right = DartConstScalar(value);
        expect(left, right);
        expect(left.hashCode, right.hashCode);
      }
      final builtString = String.fromCharCodes('value'.codeUnits);
      expect(DartConstScalar(builtString), const DartConstScalar('value'));
      expect(
        DartConstScalar(builtString).hashCode,
        const DartConstScalar('value').hashCode,
      );
      expect(const DartConstScalar(-0.0).hashCode, negativeZero.hashCode);
    });

    test('round-trips exact numeric kinds and signed zero through the codec',
        () {
      const values = <DartConstScalar>[
        DartConstScalar(1),
        DartConstScalar(1.0),
        DartConstScalar(0.0),
        DartConstScalar(-0.0),
      ];

      for (final value in values) {
        final decoded = decodeCatalog(encodeCatalog(_catalog(value)))
            .widgets
            .single
            .properties
            .single
            .constructorDefault! as DartConstScalar;
        expect(decoded, value);
        expect(decoded.hashCode, value.hashCode);
        expect(decoded.value.runtimeType, value.value.runtimeType);
      }
      final decodedNegativeZero = decodeCatalog(
        encodeCatalog(_catalog(const DartConstScalar(-0.0))),
      ).widgets.single.properties.single.constructorDefault! as DartConstScalar;
      expect((decodedNegativeZero.value as double).isNegative, isTrue);
    });

    test('all supported finite scalar kinds remain valid', () {
      const values = <DartConstScalar>[
        DartConstScalar(true),
        DartConstScalar(7),
        DartConstScalar(2.5),
        DartConstScalar('value'),
      ];
      for (final value in values) {
        expect(() => encodeCatalog(_catalog(value)), returnsNormally);
      }
    });
  });

  test('valid nominal constructor-default wire bytes stay frozen', () {
    const value = DartConstReference(
      libraryUri: 'package:acme/value.dart',
      owner: 'Defaults',
      member: 'value',
    );

    expect(
      encodeCatalog(_catalog(value)),
      '''
{
  "schemaVersion": 5,
  "generatedAt": "2026-08-08T00:00:00Z",
  "libraries": {
    "acme.widgets": {
      "version": "1.0.0"
    }
  },
  "widgets": [
    {
      "wireId": "w0001",
      "name": "Probe",
      "library": "acme.widgets",
      "category": "input",
      "description": "A probe.",
      "flutterType": "package:acme/widgets.dart#Probe",
      "childrenSlot": "none",
      "properties": [
        {
          "wireId": "p0001",
          "name": "value",
          "type": "string",
          "description": "A value.",
          "constructorDefault": {
            "kind": "reference",
            "libraryUri": "package:acme/value.dart",
            "owner": "Defaults",
            "member": "value"
          }
        }
      ]
    }
  ]
}'''
          .trimLeft(),
    );
  });
}
