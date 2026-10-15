import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('identifierLabel', () {
    test('sentence-cases camelCase names', () {
      expect(identifierLabel('textAlign'), 'Text align');
      expect(identifierLabel('maxLines'), 'Max lines');
      expect(identifierLabel('letterSpacing'), 'Letter spacing');
      expect(identifierLabel('softWrap'), 'Soft wrap');
      expect(identifierLabel('color'), 'Color');
      expect(identifierLabel('x'), 'X');
    });

    test('keeps acronyms', () {
      expect(
        identifierLabel('enableIMEPersonalizedLearning'),
        'Enable IME personalized learning',
      );
      expect(identifierLabel('RGBColor'), 'RGB color');
      expect(identifierLabel('colorRGB'), 'Color RGB');
    });

    test('uppercases known acronyms', () {
      expect(identifierLabel('analyticsId'), 'Analytics ID');
      expect(identifierLabel('url'), 'URL');
      expect(identifierLabel('imeAction'), 'IME action');
      expect(identifierLabel('rtlAware'), 'RTL aware');
      expect(identifierLabel('identity'), 'Identity');
    });

    test('drops a leading is', () {
      expect(identifierLabel('isScrollable'), 'Scrollable');
      expect(identifierLabel('isScrollControlled'), 'Scroll controlled');
      expect(identifierLabel('isLabelVisible'), 'Label visible');
      expect(identifierLabel('issue'), 'Issue');
    });

    test('splits digits', () {
      expect(identifierLabel('padding2x'), 'Padding 2 x');
    });
  });

  test('widgetLabel drops the Restage prefix', () {
    expect(widgetLabel('RestageShaderMask'), 'Shader mask');
    expect(widgetLabel('ShaderMask'), 'Shader mask');
    expect(widgetLabel('SizedBox'), 'Sized box');
    expect(widgetLabel('Restage'), 'Restage');
  });

  test('WidgetEntry.label derives or uses the curated label', () {
    WidgetEntry entry(String? displayLabel) => WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ClipRRect',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: 'd',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          properties: const [],
          displayLabel: displayLabel,
        );
    expect(entry(null).label, 'Clip r rect');
    expect(entry('Rounded clip').label, 'Rounded clip');
  });

  group('PropertyEntry.label', () {
    const derived = PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: 'softWrap',
      type: PropertyType.boolean,
      description: 'Whether text wraps.',
    );
    const curated = PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: 'softWrap',
      type: PropertyType.boolean,
      description: 'Whether text wraps.',
      displayLabel: 'Wrap text',
    );

    test('derives from the name, or uses the curated label', () {
      expect(derived.label, 'Soft wrap');
      expect(curated.label, 'Wrap text');
    });
  });
}
