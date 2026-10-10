// A TextField's InputDecoration, keyboard and input action lower to the
// catalog's flat text-field properties.
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

PropertyEntry _synthetic(
  String name,
  PropertyType type,
  String strategy, {
  List<String>? allowedValues,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: '',
      synthetic: strategy,
      constraints: allowedValues == null
          ? RestageConstraints.empty
          : RestageConstraints(allowedValues: allowedValues),
    );

const _keyboards = [
  'text',
  'multiline',
  'number',
  'phone',
  'emailAddress',
  'url',
  'name',
];

final Catalog _catalog = catalogWith([
  entry(
    name: 'TextField',
    flutterType: 'package:flutter/src/material/text_field.dart#TextField',
    properties: [
      _synthetic('hintText', PropertyType.string, 'inputDecorationText'),
      _synthetic('labelText', PropertyType.string, 'inputDecorationText'),
      _synthetic('helperText', PropertyType.string, 'inputDecorationText'),
      _synthetic(
        'prefixIconCodepoint',
        PropertyType.integer,
        'inputDecorationPrefixIcon',
      ),
      _synthetic(
        'prefixIconFontFamily',
        PropertyType.string,
        'inputDecorationPrefixIconFontFamily',
      ),
      _synthetic(
        'prefixIconMatchTextDirection',
        PropertyType.boolean,
        'inputDecorationPrefixIconMatchTextDirection',
      ),
      _synthetic(
        'border',
        PropertyType.string,
        'inputBorder',
        allowedValues: const ['none', 'underline', 'outline'],
      ),
      _synthetic(
        'keyboardType',
        PropertyType.string,
        'textInputType',
        allowedValues: _keyboards,
      ),
      prop('maxLines', PropertyType.integer),
      const PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'textInputAction',
        type: PropertyType.enumValue,
        description: '',
        enumType: 'TextInputAction',
      ),
    ],
  ),
  entry(
    name: 'CupertinoTextField',
    flutterType:
        'package:flutter/src/cupertino/text_field.dart#CupertinoTextField',
    properties: [
      prop('placeholder', PropertyType.string),
      _synthetic(
        'keyboardType',
        PropertyType.string,
        'textInputType',
        allowedValues: _keyboards,
      ),
    ],
  ),
]);

Future<TranslationResult> _translate(String body) async =>
    ExpressionTranslator(catalog: _catalog, helpers: HelperRegistry())
        .translate(
      await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/cupertino.dart';
        import 'package:flutter/material.dart';
        Object x() => $body;
        ''',
        rootPackage: 'apps_examples',
      ),
    );

void main() {
  test('the decoration, keyboard and prefix icon lower flat', () async {
    final result = await _translate('''
      TextField(
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Anything else?',
          labelText: 'Note',
          helperText: 'Optional',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.edit),
        ),
      )
    ''');

    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      allOf([
        contains('hintText: "Anything else?"'),
        contains('labelText: "Note"'),
        contains('helperText: "Optional"'),
        contains('border: "outline"'),
        contains('prefixIconCodepoint: $_iconsEdit'),
        contains('keyboardType: "multiline"'),
        contains('textInputAction: "done"'),
      ]),
    );
    expect(result.dsl, isNot(contains('prefixIconFontFamily')));
    expect(
      result.iconReferences.map((icon) => icon.codePoint),
      contains(_iconsEdit),
    );
  });

  test('each border form lowers to its name', () async {
    for (final (border, name) in [
      ('InputBorder.none', 'none'),
      ('UnderlineInputBorder()', 'underline'),
      ('const OutlineInputBorder()', 'outline'),
    ]) {
      final result = await _translate(
        'TextField(decoration: InputDecoration(border: $border))',
      );
      expect(result.issues, isEmpty, reason: border);
      expect(result.dsl, contains('border: "$name"'), reason: border);
    }
  });

  test('a Cupertino prefix icon carries its font family', () async {
    final result = await _translate('''
      TextField(
        decoration: InputDecoration(prefixIcon: Icon(CupertinoIcons.search)),
      )
    ''');
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('prefixIconFontFamily: "CupertinoIcons"'));
    expect(
      result.iconReferences.map((icon) => icon.fontFamily),
      contains('CupertinoIcons'),
    );
  });

  test('a CupertinoTextField keyboard lowers by name', () async {
    final result = await _translate('''
      CupertinoTextField(
        placeholder: 'Phone',
        keyboardType: TextInputType.phone,
      )
    ''');
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('keyboardType: "phone"'));
  });

  test('unsupported decoration forms are refused by name', () async {
    for (final (source, fragment) in [
      (
        'TextField(decoration: InputDecoration(suffixIcon: Icon(Icons.add)))',
        'suffixIcon',
      ),
      (
        'TextField(decoration: InputDecoration( '
            'border: OutlineInputBorder(gapPadding: 2)))',
        'border',
      ),
      (
        'TextField(decoration: InputDecoration( '
            'prefixIcon: Icon(Icons.add, size: 12)))',
        'prefixIcon',
      ),
      (
        'TextField(keyboardType: TextInputType.numberWithOptions())',
        'keyboardType',
      ),
    ]) {
      final result = await _translate(source);
      expect(
        result.issues.map((issue) => issue.message),
        contains(contains(fragment)),
        reason: source,
      );
    }
  });
}

// Icons.edit in the Material icon font.
const _iconsEdit = 0xe21a;
