// Every framework named constant, used at a built-in catalog slot, must emit a
// value the slot's property type decodes.

import 'dart:io';

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:restage_shared/rfw_formats.dart'
    show ConstructorCall, parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Catalog _builtInCatalog() {
  final widgets = <WidgetEntry>[];
  final structuredTypes = <StructuredEntry>[];
  final unions = <UnionEntry>[];
  final libraries = <WidgetLibrary, LibraryInfo>{};
  for (final package in [
    'restage_core',
    'restage_material',
    'restage_cupertino',
  ]) {
    final catalog = requireNativeCatalog(
      decodeCatalog(
        File('../$package/lib/src/widget_catalog/catalog.json')
            .readAsStringSync(),
      ),
    );
    widgets.addAll(catalog.widgets);
    structuredTypes.addAll(catalog.structuredTypes);
    unions.addAll(catalog.unions);
    libraries.addAll(catalog.libraries);
  }
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: libraries,
    widgets: widgets,
    structuredTypes: structuredTypes,
    unions: unions,
  );
}

/// One slot: a widget source with `@` where the constant goes, the emitted
/// widget and property to read back, and its catalog property type.
final class _Slot {
  const _Slot(this.type, this.template, this.widget, this.property);

  final PropertyType type;
  final String template;
  final String widget;
  final String property;
}

const _d = 'duration: Duration(milliseconds: 1)';

const _alignment =
    _Slot(PropertyType.alignment, 'Align(alignment: @)', 'Align', 'alignment');
const _alignmentXY = _Slot(
  PropertyType.alignmentXY,
  'AnimatedScale(scale: 1.0, $_d, alignment: @)',
  'AnimatedScale',
  'alignment',
);

const _alignNames = [
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];
const _directionalNames = [
  'topStart',
  'topCenter',
  'topEnd',
  'centerStart',
  'center',
  'centerEnd',
  'bottomStart',
  'bottomCenter',
  'bottomEnd',
];

(double, double) _xy(String name) {
  final x = name.endsWith('Left') || name.endsWith('Start')
      ? -1.0
      : name.endsWith('Right') || name.endsWith('End')
          ? 1.0
          : 0.0;
  final y = name.startsWith('top')
      ? -1.0
      : name.startsWith('bottom')
          ? 1.0
          : 0.0;
  return (x, y);
}

Map<String, Object> _alignmentValue(String name, {bool directional = false}) {
  final (x, y) = _xy(name);
  return directional ? {'start': x, 'y': y} : {'x': x, 'y': y};
}

/// (slot, constant source, expected wire value or null for type-only check).
List<(_Slot, String, Object?)> _cases() => [
      for (final n in _alignNames) ...[
        (_alignment, 'Alignment.$n', _alignmentValue(n)),
        (_alignment, 'FractionalOffset.$n', _alignmentValue(n)),
        (_alignment, 'AlignmentGeometry.$n', _alignmentValue(n)),
        (_alignmentXY, 'Alignment.$n', _alignmentValue(n)),
        (_alignmentXY, 'FractionalOffset.$n', _alignmentValue(n)),
      ],
      for (final n in _directionalNames)
        (
          _alignment,
          'AlignmentDirectional.$n',
          _alignmentValue(n, directional: true),
        ),
      for (final n in ['topStart', 'topEnd', 'centerStart', 'centerEnd'])
        (
          _alignment,
          'AlignmentGeometry.$n',
          _alignmentValue(n, directional: true),
        ),
      for (final (prefix, n) in [
        ('EdgeInsets', 'zero'),
        ('EdgeInsetsDirectional', 'zero'),
      ])
        (
          const _Slot(
            PropertyType.edgeInsets,
            'Padding(padding: @)',
            'Padding',
            'padding',
          ),
          '$prefix.$n',
          null,
        ),
      (
        const _Slot(
          PropertyType.edgeInsets,
          'Container(margin: @)',
          'Container',
          'margin',
        ),
        'EdgeInsets.zero',
        null,
      ),
      (
        const _Slot(
          PropertyType.offset,
          'AnimatedSlide(offset: @, $_d)',
          'AnimatedSlide',
          'offset',
        ),
        'Offset.zero',
        {'x': 0.0, 'y': 0.0},
      ),
      for (final (c, argb) in [
        ('Colors.red', 0xFFF44336),
        ('Colors.transparent', 0x00000000),
        ('Colors.white', 0xFFFFFFFF),
        ('Colors.black', 0xFF000000),
        ('Colors.redAccent', 0xFFFF5252),
        ('Colors.white70', 0xB3FFFFFF),
        ('Colors.black54', 0x8A000000),
        ('Colors.amber', 0xFFFFC107),
        ('Colors.blueGrey', 0xFF607D8B),
        ('CupertinoColors.white', 0xFFFFFFFF),
        ('CupertinoColors.black', 0xFF000000),
        ('CupertinoColors.transparent', 0x00000000),
      ])
        (
          const _Slot(
            PropertyType.color,
            'Container(color: @)',
            'Container',
            'color',
          ),
          c,
          argb,
        ),
      for (final c in kSupportedCurveNames)
        (
          const _Slot(
            PropertyType.curve,
            'AnimatedOpacity(opacity: 1.0, $_d, curve: @)',
            'AnimatedOpacity',
            'curve',
          ),
          'Curves.$c',
          c,
        ),
      (
        const _Slot(
          PropertyType.duration,
          'AnimatedOpacity(opacity: 1.0, duration: @)',
          'AnimatedOpacity',
          'duration',
        ),
        'Duration.zero',
        0,
      ),
      for (final (slot, constant) in [
        for (final c in ['BorderRadius.zero', 'BorderRadiusDirectional.zero'])
          for (final slot in _borderRadiusSlots) (slot, c),
        (
          const _Slot(
            PropertyType.real,
            'Container(decoration: BoxDecoration(borderRadius: '
                'BorderRadius.all(@)))',
            'Container',
            'borderRadius',
          ),
          'Radius.zero',
        ),
        (
          const _Slot(
            PropertyType.real,
            'ClipRRect(borderRadius: BorderRadius.only(topLeft: @))',
            'ClipRRect',
            'borderRadiusTopLeft',
          ),
          'Radius.zero',
        ),
      ])
        (slot, constant, 0.0),
      for (final (shape, radius, expected) in [
        ('RoundedRectangleBorder', 'BorderRadius.zero', 0.0),
        (
          'RoundedRectangleBorder',
          'BorderRadius.only(topLeft: Radius.circular(8))',
          {'topLeft': 8.0},
        ),
        (
          'ContinuousRectangleBorder',
          'BorderRadius.vertical(top: Radius.circular(4))',
          {'topLeft': 4.0, 'topRight': 4.0},
        ),
        (
          'BeveledRectangleBorder',
          'BorderRadius.horizontal(right: Radius.zero)',
          {'topRight': 0.0, 'bottomRight': 0.0},
        ),
      ])
        (
          const _Slot(
            PropertyType.shapeBorder,
            'Card(shape: @)',
            'Card',
            'shape',
          ),
          '$shape(borderRadius: $radius)',
          {
            'type': switch (shape) {
              'RoundedRectangleBorder' => 'rounded',
              'ContinuousRectangleBorder' => 'continuous',
              _ => 'beveled',
            },
            'borderRadius': expected,
          },
        ),
      for (final (enumName, members, slot) in _enumSlots)
        for (final m in members) (slot, '$enumName.$m', m),
      for (final w in [100, 200, 300, 400, 500, 600, 700, 800, 900])
        (_fontWeight, 'FontWeight.w$w', 'w$w'),
      (_fontWeight, 'FontWeight.normal', 'w400'),
      (_fontWeight, 'FontWeight.bold', 'w700'),
      for (final m in ['none', 'underline', 'overline', 'lineThrough'])
        (
          const _Slot(
            PropertyType.textDecoration,
            "Text('a', style: TextStyle(decoration: @))",
            'Text',
            'decoration',
          ),
          'TextDecoration.$m',
          m,
        ),
    ];

const _borderRadiusSlots = [
  _Slot(
    PropertyType.real,
    'Container(decoration: BoxDecoration(borderRadius: @))',
    'Container',
    'borderRadius',
  ),
  _Slot(
    PropertyType.real,
    'AnimatedContainer($_d, decoration: BoxDecoration(borderRadius: @))',
    'AnimatedContainer',
    'borderRadius',
  ),
  _Slot(
    PropertyType.real,
    'ClipRRect(borderRadius: @)',
    'ClipRRect',
    'borderRadius',
  ),
];

const _fontWeight = _Slot(
  PropertyType.fontWeight,
  "Text('a', style: TextStyle(fontWeight: @))",
  'Text',
  'fontWeight',
);

const _enumSlots = [
  (
    'TextAlign',
    ['left', 'right', 'center', 'justify', 'start', 'end'],
    _Slot(
      PropertyType.enumValue,
      "Text('a', textAlign: @)",
      'Text',
      'textAlign',
    ),
  ),
  (
    'TextOverflow',
    ['clip', 'fade', 'ellipsis', 'visible'],
    _Slot(PropertyType.enumValue, "Text('a', overflow: @)", 'Text', 'overflow'),
  ),
  (
    'FontStyle',
    ['normal', 'italic'],
    _Slot(
      PropertyType.enumValue,
      "Text('a', style: TextStyle(fontStyle: @))",
      'Text',
      'fontStyle',
    ),
  ),
  (
    'MainAxisAlignment',
    ['start', 'end', 'center', 'spaceBetween', 'spaceAround', 'spaceEvenly'],
    _Slot(
      PropertyType.enumValue,
      'Row(mainAxisAlignment: @)',
      'Row',
      'mainAxisAlignment',
    ),
  ),
  (
    'CrossAxisAlignment',
    ['start', 'end', 'center', 'stretch'],
    _Slot(
      PropertyType.enumValue,
      'Row(crossAxisAlignment: @)',
      'Row',
      'crossAxisAlignment',
    ),
  ),
  (
    'MainAxisSize',
    ['min', 'max'],
    _Slot(
      PropertyType.enumValue,
      'Row(mainAxisSize: @)',
      'Row',
      'mainAxisSize',
    ),
  ),
  (
    'StackFit',
    ['loose', 'expand', 'passthrough'],
    _Slot(PropertyType.enumValue, 'Stack(fit: @)', 'Stack', 'fit'),
  ),
  (
    'BoxFit',
    ['fill', 'contain', 'cover', 'fitWidth', 'fitHeight', 'none', 'scaleDown'],
    _Slot(
      PropertyType.enumValue,
      "Image.asset('a.png', fit: @)",
      'ImageAsset',
      'fit',
    ),
  ),
];

bool _typeAccepts(PropertyType type, Object? value) => switch (type) {
      PropertyType.alignment => value is Map &&
          value['y'] is double &&
          (value['x'] is double) != (value['start'] is double),
      PropertyType.alignmentXY ||
      PropertyType.offset =>
        value is Map && value['x'] is double && value['y'] is double,
      PropertyType.edgeInsets =>
        value is List && value.every((v) => v is double),
      PropertyType.color || PropertyType.duration => value is int,
      PropertyType.real => value is double,
      PropertyType.shapeBorder => value is Map && value['type'] is String,
      PropertyType.curve =>
        value is String && kSupportedCurveNames.contains(value),
      PropertyType.enumValue ||
      PropertyType.fontWeight ||
      PropertyType.textDecoration =>
        value is String,
      _ => false,
    };

Iterable<ConstructorCall> _calls(Object? node) sync* {
  if (node is ConstructorCall) {
    yield node;
    for (final value in node.arguments.values) {
      yield* _calls(value);
    }
  } else if (node is List) {
    for (final value in node) {
      yield* _calls(value);
    }
  } else if (node is Map) {
    for (final value in node.values) {
      yield* _calls(value);
    }
  }
}

Object? _plain(Object? value) => switch (value) {
      final Map<Object?, Object?> map =>
        map.map((k, v) => MapEntry(k, _plain(v))),
      final List<Object?> list => list.map(_plain).toList(),
      _ => value,
    };

void main() {
  final catalog = _builtInCatalog();
  final translator =
      ExpressionTranslator(catalog: catalog, helpers: HelperRegistry());

  test('named constants emit the value their catalog slot decodes', () async {
    final cases = _cases();
    final children = [
      for (final (slot, constant, _) in cases)
        slot.template.replaceFirst('@', constant),
    ];
    final source = '''
      import 'package:flutter/cupertino.dart';
      import 'package:flutter/material.dart';
      Object x() => Stack(children: [
        ${children.join(',\n        ')},
      ]);
    ''';
    final result = translator.translate(
      await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
      ),
    );
    final library = parseLibraryFile(
      'import restage.core;\nwidget Probe = ${result.dsl};',
      sourceIdentifier: 'probe',
    );
    final issues = [
      ...result.issues,
      ...validateModelAgainstCatalog(library, catalog),
    ];
    final root = library.widgets.single.root as ConstructorCall;
    final emitted = _calls(root.arguments['children']).where(
      (call) => call.name != 'SizedBox',
    );

    final failures = <String>[];
    final top = (root.arguments['children']! as List).cast<Object?>();
    expect(top, hasLength(cases.length));
    for (var i = 0; i < cases.length; i++) {
      final (slot, constant, expected) = cases[i];
      final call = _calls(top[i]).firstWhere(
        (call) => call.name == slot.widget,
        orElse: () => throw StateError('No ${slot.widget} for $constant'),
      );
      final value = _plain(call.arguments[slot.property]);
      final ok = _typeAccepts(slot.type, value) &&
          (expected == null || equals(expected).matches(value, {}));
      if (!ok) {
        failures.add(
          '${slot.type.name} ${slot.widget}.${slot.property} = $constant '
          '-> $value${expected == null ? '' : ' (expected $expected)'}',
        );
      }
    }
    expect(emitted, isNotEmpty);
    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(issues.map((issue) => issue.message), isEmpty);
  });

  test('a context-dependent colour constant is refused, not flattened',
      () async {
    final result = translator.translate(
      await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/cupertino.dart';
        Object x() => Container(color: CupertinoColors.systemBlue);
        ''',
        rootPackage: 'apps_examples',
      ),
    );
    expect(result.issues, isNotEmpty);
    expect(result.dsl, isNot(contains('0x')));
  });
}
