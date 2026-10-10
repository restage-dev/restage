// Source expectations join Dart tokens without inserting whitespace.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _hintText = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'hintText',
  type: PropertyType.string,
  description: '',
  synthetic: 'inputDecorationText',
);

const _labelText = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'labelText',
  type: PropertyType.string,
  description: '',
  synthetic: 'inputDecorationText',
);

const _border = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'border',
  type: PropertyType.string,
  description: '',
  synthetic: 'inputBorder',
  constraints: RestageConstraints(
    allowedValues: ['none', 'underline', 'outline'],
  ),
);

const _prefixIconCodepoint = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'prefixIconCodepoint',
  type: PropertyType.integer,
  description: '',
  synthetic: 'inputDecorationPrefixIcon',
);

const _prefixIconFontFamily = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'prefixIconFontFamily',
  type: PropertyType.string,
  description: '',
  synthetic: 'inputDecorationPrefixIconFontFamily',
);

const _prefixIconMatchTextDirection = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'prefixIconMatchTextDirection',
  type: PropertyType.boolean,
  description: '',
  synthetic: 'inputDecorationPrefixIconMatchTextDirection',
);

const _keyboardType = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'keyboardType',
  type: PropertyType.string,
  description: '',
  synthetic: 'textInputType',
);

const _maxLines = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'maxLines',
  type: PropertyType.integer,
  description: '',
);

WidgetEntry _textField(List<PropertyEntry> properties) => WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'TextField',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: '',
      flutterType: 'package:flutter/material.dart#TextField',
      childrenSlot: ChildrenSlot.none,
      properties: properties,
    );

void main() {
  group('text input synthetics', () {
    test('decoration text fields build one InputDecoration', () {
      final source = emitFactoryFunction(
        _textField([_hintText, _labelText, _maxLines]),
      );
      expect(source, isNotNull);
      expect(
        source,
        contains(
          'decoration: InputDecoration('
          "hintText: source.v<String>(const <Object>['hintText']), "
          "labelText: source.v<String>(const <Object>['labelText']),"
          ')',
        ),
      );
      expect(source, isNot(contains('    hintText:')));
      expect(
        source,
        contains("maxLines: source.v<int>(const <Object>['maxLines'])"),
      );
    });

    test('border decodes its closed names to Flutter input borders', () {
      final source = emitFactoryFunction(_textField([_border]));
      expect(source, isNotNull);
      expect(
        source,
        contains(
          "border: switch (source.v<String>(const <Object>['border'])) {"
          "'none' => InputBorder.none, "
          "'underline' => const UnderlineInputBorder(), "
          "'outline' => const OutlineInputBorder(), "
          '_ => null'
          '}',
        ),
      );
    });

    test('border naming a kind with no Flutter border is not emittable', () {
      const border = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'border',
        type: PropertyType.string,
        description: '',
        synthetic: 'inputBorder',
        constraints: RestageConstraints(
          allowedValues: ['none', 'dashed'],
        ),
      );
      expect(emitFactoryFunction(_textField([border])), isNull);
    });

    test('prefix icon resolves through the installed icon table', () {
      final source = emitFactoryFunction(
        _textField([
          _prefixIconCodepoint,
          _prefixIconFontFamily,
          _prefixIconMatchTextDirection,
        ]),
      );
      expect(source, isNotNull);
      expect(
        source,
        contains(
          "prefixIcon: source.v<int>(const <Object>['prefixIconCodepoint']) "
          '== null ? null : restageIcon(context, codePoint: '
          "source.v<int>(const <Object>['prefixIconCodepoint'])!, "
          "fontFamily: source.v<String>(const <Object>['prefixIconFontFamily'])"
          " ?? 'MaterialIcons', "
          'matchTextDirection: '
          "source.v<bool>(const <Object>['prefixIconMatchTextDirection'])"
          ' ?? false)',
        ),
      );
      expect(source, isNot(contains('IconData(')));
      expect(source, isNot(contains('prefixIconCodepoint:')));
      expect(source, isNot(contains('prefixIconFontFamily:')));
    });

    test('prefix icon without siblings uses the Material family', () {
      final source = emitFactoryFunction(_textField([_prefixIconCodepoint]));
      expect(
        source,
        contains(
          "source.v<int>(const <Object>['prefixIconCodepoint'])!, "
          "fontFamily: 'MaterialIcons')",
        ),
      );
    });

    test('a prefix icon family without its codepoint is not emittable', () {
      expect(emitFactoryFunction(_textField([_prefixIconFontFamily])), isNull);
      expect(
        emitFactoryFunction(_textField([_prefixIconMatchTextDirection])),
        isNull,
      );
    });

    test('a second prefix icon is not emittable', () {
      const second = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'otherIconCodepoint',
        type: PropertyType.integer,
        description: '',
        synthetic: 'inputDecorationPrefixIcon',
      );
      expect(
        emitFactoryFunction(_textField([_prefixIconCodepoint, second])),
        isNull,
      );
    });

    test('keyboardType decodes through the named keyboard table', () {
      final source = emitFactoryFunction(_textField([_keyboardType]));
      expect(source, isNotNull);
      expect(
        source,
        contains(
          'keyboardType: RestageDecoders.textInputType('
          "source, const <Object>['keyboardType'])",
        ),
      );
      expect(source, isNot(contains('InputDecoration(')));
    });

    test('the new strategies are supported', () {
      expect(
        kSupportedSyntheticStrategies,
        containsAll(<String>[
          'inputDecorationText',
          'inputBorder',
          'inputDecorationPrefixIcon',
          'inputDecorationPrefixIconFontFamily',
          'inputDecorationPrefixIconMatchTextDirection',
          'textInputType',
        ]),
      );
    });
  });
}
