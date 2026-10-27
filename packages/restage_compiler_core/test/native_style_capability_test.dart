import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.widgets');
const _color = <String, Object?>{
  'a': .812345,
  'r': .234567,
  'g': .345678,
  'b': .456789,
  'colorSpace': 'displayP3',
};
final _text = WireIdRef(library: 'restage.core', wireId: WireId('s0002'));
final _overlay = WireIdRef(library: 'restage.core', wireId: WireId('s0003'));
final _icon = WireIdRef(library: 'restage.core', wireId: WireId('s0004'));
final _details = WireIdRef(library: _custom.namespace, wireId: WireId('s0001'));
final _choice = WireIdRef(library: _custom.namespace, wireId: WireId('u0001'));

PropertyEntry _p(
  String name,
  PropertyType type, {
  WireIdRef? ref,
  CatalogValueShape? shape,
  bool presence = false,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: name,
      structuredRef: ref,
      valueShape: shape,
      constructorNullable: presence,
      constructorDefault: presence ? const DartConstNull() : null,
    );

WidgetEntry _widget(
  String name,
  List<PropertyEntry> properties, {
  WidgetLibrary library = _custom,
  int floor = 1,
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: library,
      category: WidgetCategory.decoration,
      description: name,
      flutterType: 'package:fixture/native.dart#$name',
      childrenSlot: ChildrenSlot.none,
      properties: properties,
      sinceVersion: floor,
    );

StructuredEntry _structured(
  WireIdRef ref,
  String name,
  String sourceType,
  List<StructuredField> fields,
) =>
    StructuredEntry(
      wireId: ref.wireId,
      name: name,
      library: WidgetLibrary.fromNamespace(ref.library),
      description: name,
      sourceType: sourceType,
      fields: fields,
      variants: const [],
    );

Catalog _catalog() {
  final colorChoice =
      WireIdRef(library: _custom.namespace, wireId: WireId('s0005'));
  final rawChoice =
      WireIdRef(library: _custom.namespace, wireId: WireId('s0006'));
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '1'),
      _custom: const LibraryInfo(version: '1', capabilityVersion: 1),
    },
    widgets: [
      _widget(
        'ColoredBox',
        [_p('color', PropertyType.color)],
        library: WidgetLibrary.core,
        floor: 5,
      ),
      _widget(
        'Column',
        [_p('children', PropertyType.widgetList)],
        library: WidgetLibrary.core,
      ),
      _widget('ColorProbe', [
        _p('color', PropertyType.color),
        _p('weight', PropertyType.fontWeight),
        _p('decoration', PropertyType.textDecoration),
        _p('data', PropertyType.dataReference),
      ]),
      _widget(
        'PresenceProbe',
        [_p('color', PropertyType.color, presence: true)],
      ),
      _widget('PaintBox', [_p('paint', PropertyType.paint)]),
      _widget('NativeProbe', [
        _p('style', PropertyType.structured, ref: _text),
        _p('overlay', PropertyType.structured, ref: _overlay),
        _p('icon', PropertyType.structured, ref: _icon),
        _p('details', PropertyType.structured, ref: _details),
        _p('paint', PropertyType.paint),
        _p('gradient', PropertyType.gradient),
        _p('shadows', PropertyType.shadowList),
        _p('boxShadow', PropertyType.boxShadowList),
        _p('border', PropertyType.border),
        _p('shape', PropertyType.shapeBorder),
        _p('span', PropertyType.inlineSpan),
        _p(
          'choice',
          PropertyType.unknown,
          shape: UnionShape(
            propertyType: PropertyType.unknown,
            unionRef: _choice,
          ),
        ),
        _p(
          'palette',
          PropertyType.unknown,
          shape: ListShape.opaqueStructured(_details),
        ),
      ]),
    ],
    structuredTypes: [
      _structured(
        _text,
        'TextStyle',
        'package:flutter/src/painting/text_style.dart#TextStyle',
        [],
      ),
      _structured(
        _overlay,
        'SystemUiOverlayStyle',
        'package:flutter/src/services/system_chrome.dart#SystemUiOverlayStyle',
        [],
      ),
      _structured(
        _icon,
        'IconThemeData',
        'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData',
        [],
      ),
      _structured(_details, 'Details', 'package:fixture/native.dart#Details', [
        const StructuredField(
          wireId: WireId.unallocatedProperty,
          name: 'tone',
          type: PropertyType.color,
          description: 'Tone',
        ),
      ]),
      _structured(colorChoice, 'ColorChoice',
          'package:fixture/native.dart#ColorChoice', [
        const StructuredField(
          wireId: WireId.unallocatedProperty,
          name: 'color',
          type: PropertyType.color,
          description: 'Color',
        ),
      ]),
      _structured(
          rawChoice, 'RawChoice', 'package:fixture/native.dart#RawChoice', [
        const StructuredField(
          wireId: WireId.unallocatedProperty,
          name: 'color',
          type: PropertyType.dataReference,
          description: 'Raw data',
        ),
      ]),
    ],
    unions: [
      UnionEntry(
        wireId: _choice.wireId,
        name: 'Choice',
        library: _custom,
        description: 'Choice',
        sourceType: 'package:fixture/native.dart#Choice',
        memberSourceTypes: const [
          'package:fixture/native.dart#ColorChoice',
          'package:fixture/native.dart#RawChoice',
        ],
        discriminator:
            DiscriminatorSpec(field: '_s', values: [colorChoice, rawChoice]),
        members: [colorChoice, rawChoice],
      ),
    ],
  );
}

rfw.RemoteWidgetLibrary _library(String name, Map<String, Object?> args) =>
    rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration('Root', null, rfw.ConstructorCall(name, args)),
    ]);
SurfaceCapabilityDerivation _derive(String name, Map<String, Object?> args) =>
    deriveSurfaceCapability(_library(name, args), _catalog());

BlobRenderVerdict _gate(
  SurfaceCapabilityDerivation required, {
  int builtIn = 19,
  int generated = 3,
}) =>
    BlobRenderCapabilityGate.evaluate(
      required: CapabilityManifest(
        builtInFloor: required.builtInFloor,
        requiredLibraries: required.requiredLibraries,
      ),
      installed: InstalledCapability(
        builtInCatalogVersion: builtIn,
        installedLibraries: [
          InstalledLibrary(
            namespace: _custom.namespace,
            version: 1,
            generated: generated,
          ),
        ],
      ),
    );

void main() {
  test('canonical colors require capability24 only in typed native fields', () {
    const material = {..._color, 'material': 'red'};
    expect(_derive('ColoredBox', {'color': material}).builtInFloor, 24);
    expect(_derive('ColorProbe', {'data': material}).builtInFloor, 1);
    expect(
        _derive('ColorProbe', {
          'color': {..._color, 'material': ''}
        }).builtInFloor,
        19);
    expect(
        () => _derive('ColorProbe', {
              'color': {..._color, 'material': 'custom'}
            }),
        throwsFormatException);
    final required = _derive('ColorProbe', {'color': material});
    expect(_gate(required, builtIn: 23).accepted, isFalse);
    expect(_gate(required, builtIn: 24).accepted, isTrue);
    for (final args in <Map<String, Object?>>[
      {
        'paint': {'color': material}
      },
      {
        'paint': {
          'colorFilter': {'type': 'mode', 'color': material}
        }
      },
      {
        'style': {'color': material}
      },
      {
        'span': {
          'children': [
            {
              'style': {'color': material}
            }
          ]
        }
      },
      {
        'gradient': {
          'type': 'linear',
          'colors': [material, 0xff000000]
        }
      },
      {
        'overlay': {'statusBarColor': material}
      },
    ]) {
      expect(_derive('NativeProbe', args).builtInFloor, 24, reason: '$args');
    }
    final local = rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root', null, rfw.ConstructorCall('Forward', {'color': material})),
      rfw.WidgetDeclaration(
          'Forward',
          null,
          rfw.ConstructorCall('ColoredBox', {
            'color': const rfw.ArgsReference(['color'])
          })),
    ]);
    expect(deriveSurfaceCapability(local, _catalog()).builtInFloor, 24);
  });
  test('installed core catalog gates direct exact Color at capability19', () {
    final file = File(
      Directory('packages/restage_core').existsSync()
          ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
          : '../restage_core/lib/src/widget_catalog/catalog.json',
    );
    final catalog = decodeCatalog(file.readAsStringSync());
    final exact = deriveSurfaceCapability(
      _library('ColoredBox', {'color': _color}),
      catalog,
    );
    final legacy = deriveSurfaceCapability(
      _library('ColoredBox', {'color': 0xff123456}),
      catalog,
    );
    expect(exact.builtInFloor, 19);
    expect(_gate(exact, builtIn: 18).accepted, isFalse);
    expect(_gate(exact).accepted, isTrue);
    expect(legacy.builtInFloor, lessThan(19));
    expect(_gate(legacy, builtIn: legacy.builtInFloor).accepted, isTrue);
  });

  test('direct exact color requires capability19 and current custom factories',
      () {
    expect(_derive('ColoredBox', {'color': _color}).builtInFloor, 19);
    expect(
      _gate(_derive('ColoredBox', {'color': _color}), builtIn: 5).accepted,
      isFalse,
    );
    expect(
      _derive('ColoredBox', {
        'color': {..._color, 'colorSpace': 'sRGB'},
      }).builtInFloor,
      19,
    );
    final custom = _derive('ColorProbe', {'color': _color});
    expect(custom.builtInFloor, 19);
    expect(custom.requiredLibraries.single.minGenerated, 3);
  });

  test('local scopes survive every typed native descent and map forwarding',
      () {
    const arg = rfw.ArgsReference(['color']);
    for (final (name, args, generated) in <(String, Map<String, Object?>, int)>[
      (
        'PaintBox',
        {
          'paint': {'color': arg},
        },
        3
      ),
      (
        'NativeProbe',
        {
          'span': {
            'style': {'color': arg},
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'span': {
            'children': [
              {
                'style': {'color': arg},
              }
            ],
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'paint': {'color': arg},
        },
        3
      ),
      (
        'NativeProbe',
        {
          'paint': {
            'colorFilter': {'type': 'mode', 'color': arg},
          },
        },
        3
      ),
      (
        'NativeProbe',
        {
          'style': {
            'foreground': {'color': arg},
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'details': {'tone': arg},
        },
        3
      ),
      (
        'NativeProbe',
        {
          'palette': [
            {'tone': arg},
          ],
        },
        3
      ),
      (
        'NativeProbe',
        {
          'choice': {'_s': 'ColorChoice', 'color': arg},
        },
        3
      ),
      (
        'NativeProbe',
        {
          'gradient': {
            'type': 'linear',
            'colors': [arg],
          },
        },
        3
      ),
      (
        'NativeProbe',
        {
          'shadows': [
            const rfw.Loop([1], {'color': arg}),
          ],
        },
        2
      ),
      (
        'NativeProbe',
        {
          'shadows': [
            const rfw.Loop([
              1,
            ], [
              {'color': arg},
            ]),
          ],
        },
        2
      ),
      (
        'NativeProbe',
        {
          'border': [
            {'color': arg},
          ],
        },
        2
      ),
      (
        'NativeProbe',
        {
          'shape': {
            'type': 'circle',
            'side': {'color': arg},
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'overlay': {
            'copyWith': [
              {'statusBarColor': arg},
            ],
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'icon': {
            'lerp': {
              'a': {'color': arg},
              'b': null,
              't': .5,
            },
          },
        },
        2
      ),
      (
        'NativeProbe',
        {
          'icon': {
            'lerp': const rfw.ArgsReference(['empty']),
            'fallback': const rfw.ArgsReference(['empty']),
            'color': arg,
          },
        },
        2,
      ),
      (
        'PresenceProbe',
        {
          'color': {
            RfwConstructorPresenceProtocol.markerKey:
                const rfw.ArgsReference(['marker']),
            RfwConstructorPresenceProtocol.valueKey: arg,
          },
        },
        3
      ),
    ]) {
      for (final forwardMap in [false, true]) {
        final library = rfw.RemoteWidgetLibrary(const [], [
          rfw.WidgetDeclaration(
            'Link',
            null,
            rfw.ConstructorCall(
              name,
              forwardMap
                  ? {
                      for (final key in args.keys)
                        key: rfw.ArgsReference([key]),
                    }
                  : args,
            ),
          ),
          if (forwardMap)
            rfw.WidgetDeclaration(
              'Mid',
              null,
              rfw.ConstructorCall('Link', args),
            ),
          rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall(
              forwardMap ? 'Mid' : 'Link',
              const {'color': _color, 'empty': null, 'marker': 1},
            ),
          ),
        ]);
        final result = deriveSurfaceCapability(library, _catalog());
        expect(
          (result.builtInFloor, result.requiredLibraries.single.minGenerated),
          (19, generated),
          reason: '$name $args forwardMap=$forwardMap',
        );
        expect(_gate(result, builtIn: 18).accepted, isFalse);
        expect(_gate(result, generated: generated).accepted, isTrue);
        if (generated == 3) {
          expect(_gate(result, generated: 2).accepted, isFalse);
        }
      }
    }
  });

  test('installed inline span style retains its calling scope', () {
    final file = File(
      Directory('packages/restage_core').existsSync()
          ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
          : '../restage_core/lib/src/widget_catalog/catalog.json',
    );
    final core = decodeCatalog(file.readAsStringSync());
    const color = '{a: 0.8, r: 0.2, g: 0.3, b: 0.4, colorSpace: "displayP3"}';
    for (final source in [
      '''
widget Link = TextRich(textSpan: {text: "A", style: {color: args.color}});
widget Root = Link(color: $color);
''',
      '''
widget Link = TextRich(textSpan: args.span);
widget Mid = Link(span: {text: "A", style: {color: args.color}});
widget Root = Mid(color: $color);
''',
    ]) {
      final result =
          deriveSurfaceCapability(rfw.parseLibraryFile(source), core);
      expect(result.builtInFloor, 19);
      expect(_gate(result, builtIn: 18).accepted, isFalse);
    }
  });

  for (final exhaust in [false, true]) {
    for (final custom in [false, true]) {
      test(
          'typed native floors after '
          "${exhaust ? 'exhausted expansion' : 'finite recursion'} "
          "${custom ? 'custom factory' : 'built-in'}", () {
        const color =
            '{a: 0.8, r: 0.2, g: 0.3, b: 0.4, colorSpace: "displayP3"}';
        final filler = [
          'widget Layer0 = ColoredBox(color: 0);',
          for (var i = 1; i <= 13; i++)
            '''
widget Layer$i = Column(children: [Layer${i - 1}(), Layer${i - 1}()]);
''',
        ].join('\n');
        final terminal = custom
            ? 'PaintBox(paint: args.value)'
            : 'ColoredBox(color: args.value)';
        final legacy = custom ? '{color: 0}' : '0';
        final exact = custom ? '{color: $color}' : color;
        final result = deriveSurfaceCapability(
          rfw.parseLibraryFile('''
${exhaust ? filler : ''}
widget Link = switch args.more {
  false: $terminal,
  default: Link(more: args.next.more, value: args.next.value, next: args.next.next)
};
widget Root = Link(more: true, value: $legacy, next: {more: false, value: $exact});
'''),
          _catalog(),
        );
        expect(
          (
            result.builtInFloor,
            custom ? result.requiredLibraries.single.minGenerated : null
          ),
          (19, custom ? 3 : null),
          reason: 'custom=$custom exhaust=$exhaust',
        );
        expect(_gate(result, builtIn: 18).accepted, isFalse);
        if (custom) {
          expect(result.requiredLibraries.single.minGenerated, 3);
          expect(_gate(result, generated: 2).accepted, isFalse);
        }
        expect(_gate(result).accepted, isTrue);
      });
    }
  }

  test('recursive legacy arguments retain their proven native floors', () {
    for (final (terminal, value, floor) in [
      ('ColoredBox(color: args.value)', '0', 5),
      ('PaintBox(paint: args.value)', '{color: 0}', 1),
    ]) {
      final result = deriveSurfaceCapability(
        rfw.parseLibraryFile('''
widget Link = switch args.more {
  false: $terminal,
  default: Link(more: args.next.more, value: args.next.value, next: args.next.next)
};
widget Root = Link(more: true, value: $value, next: {more: false, value: $value});
'''),
        _catalog(),
      );
      expect(result.builtInFloor, floor);
      if (result.requiredLibraries.isNotEmpty) {
        expect(result.requiredLibraries.single.minGenerated, 1);
      }
    }
  });

  test('bounded fallback preserves literal legacy and unrelated map exclusions',
      () {
    const color = '{a: 0.8, r: 0.2, g: 0.3, b: 0.4, colorSpace: "displayP3"}';
    for (final terminal in [
      'ColoredBox(color: 0)',
      'PaintBox(paint: {color: 0})',
      'NativeProbe(details: {ignored: $color})',
      'NativeProbe(choice: {_s: "RawChoice", color: $color})',
      'NativeProbe(span: {text: "plain", recognizer: null})',
    ]) {
      final result = deriveSurfaceCapability(
        rfw.parseLibraryFile('''
widget Link = switch args.more {false: $terminal, default: Link(more: args.next.more, next: args.next.next)};
widget Root = Link(more: true, next: {more: false});
'''),
        _catalog(),
      );
      expect(result.builtInFloor, lessThan(19), reason: terminal);
      if (result.requiredLibraries.isNotEmpty) {
        expect(
          result.requiredLibraries.single.minGenerated,
          lessThan(3),
          reason: terminal,
        );
      }
    }
  });

  test('integer weights and decoration masks require their actual decoder use',
      () {
    for (final args in [
      <String, Object?>{'weight': 1},
      {'weight': 550},
      {'weight': 1000},
      {'decoration': 0},
      {'decoration': 7},
      {
        'decoration': ['underline', 2],
      }
    ]) {
      final required = _derive('ColorProbe', args);
      expect(required.builtInFloor, 19, reason: '$args');
      expect(
        required.requiredLibraries.single.minGenerated,
        args.containsKey('weight') ? 3 : 1,
        reason: '$args',
      );
    }
  });

  test('nested native decoder forms retain exact style requirements', () {
    for (final args in <Map<String, Object?>>[
      {
        'style': {'color': _color},
      },
      {
        'style': {'fontWeight': 550},
      },
      {
        'style': {'decoration': 3},
      },
      {
        'style': {'backgroundColor': _color},
      },
      {
        'style': {'decorationColor': _color},
      },
      {
        'style': {
          'foreground': {'color': _color},
        },
      },
      {
        'style': {
          'background': {
            'colorFilter': {'type': 'mode', 'color': _color},
          },
        },
      },
      {
        'style': {
          'shadows': [
            {'color': _color},
          ],
        },
      },
      {
        'paint': {'color': _color},
      },
      {
        'paint': {
          'colorFilter': {'type': 'mode', 'color': _color},
        },
      },
      {
        'gradient': {
          'type': 'linear',
          'colors': [0xff000000, _color],
        },
      },
      {
        'gradient': {
          'type': 'radial',
          'colors': [_color, 0xff000000],
        },
      },
      {
        'gradient': {
          'type': 'sweep',
          'colors': [_color, 0xff000000],
        },
      },
      {
        'shadows': [
          {'color': _color},
        ],
      },
      {
        'boxShadow': [
          {'color': _color},
        ],
      },
      {
        'border': [
          {'color': _color},
        ],
      },
      {
        'shape': {
          'type': 'rounded',
          'side': {'color': _color},
        },
      },
      {
        'span': {
          'text': 'Hi',
          'children': [
            {
              'style': {'fontWeight': 550, 'color': _color},
            }
          ],
        },
      },
      {
        'details': {'tone': _color},
      },
      {
        'choice': {'_s': 'ColorChoice', 'color': _color},
      },
      {
        'palette': [
          {'tone': _color},
        ],
      },
      {
        'overlay': {
          'copyWith': [
            {'systemNavigationBarColor': _color},
          ],
        },
      },
      {
        'icon': {
          'lerp': {
            'a': {'color': _color},
            'b': {'color': 0xff000000},
            't': .5,
          },
        },
      },
      {
        'icon': {
          'copyWith': [
            {
              'shadows': [
                {'color': _color},
              ],
            }
          ],
        },
      },
      {
        'icon': {
          'copyWith': [
            {'fallback': true, 'color': _color},
          ],
        },
      },
    ]) {
      final required = _derive('NativeProbe', args);
      expect(required.builtInFloor, 19, reason: '${args.keys}');
      final changedFactory = const {
        'paint',
        'gradient',
        'boxShadow',
        'details',
        'choice',
        'palette',
      }.contains(args.keys.single);
      expect(
        required.requiredLibraries.single.minGenerated,
        changedFactory ? 3 : 2,
        reason: '${args.keys}',
      );
    }
  });

  test('presence, switches and loop templates retain typed direct forms', () {
    final present = _derive('PresenceProbe', {
      'color': {
        RfwConstructorPresenceProtocol.markerKey: 1,
        RfwConstructorPresenceProtocol.valueKey: _color,
      },
    });
    expect(present.builtInFloor, 19);
    expect(present.requiredLibraries.single.minGenerated, 3);
    expect(
      _derive('ColorProbe', {
        'color': const rfw.Switch(
          rfw.DataReference(['flag']),
          {true: _color, false: 0xff000000},
        ),
      }).builtInFloor,
      19,
    );
    expect(
      _derive('NativeProbe', {
        'shadows': [
          const rfw.Loop([1], {'color': _color}),
        ],
      }).builtInFloor,
      19,
    );
  });

  test('old clients and old generated custom factories reject exact forms', () {
    final required = _derive('ColorProbe', {'color': _color});
    expect(
      (_gate(required, builtIn: 18) as BlobRenderRejected).reason,
      BlobRenderRejectionReason.capabilityFloorRaised,
    );
    expect(
      (_gate(required, generated: 2) as BlobRenderRejected).reason,
      BlobRenderRejectionReason.requiredLibraryUnsatisfied,
    );
    expect(_gate(required).accepted, isTrue);
  });

  test('unchanged decoder call routes retain existing generated requirements',
      () {
    final style = _derive('NativeProbe', {
      'style': {'color': _color, 'fontWeight': 550, 'decoration': 7},
    });
    expect(style.builtInFloor, 19);
    expect(style.requiredLibraries.single.minGenerated, 2);
    expect(_gate(style, generated: 2).accepted, isTrue);
    expect(_gate(style, builtIn: 18, generated: 2).accepted, isFalse);
    final mask = _derive('ColorProbe', {'decoration': 7});
    expect(mask.requiredLibraries.single.minGenerated, 1);
    expect(_gate(mask, generated: 1).accepted, isTrue);
    final paint = _derive('NativeProbe', {
      'paint': {'color': _color},
    });
    expect(paint.requiredLibraries.single.minGenerated, 3);
    expect(_gate(paint, generated: 2).accepted, isFalse);
  });

  test('legacy colors weights and string/list decorations keep their floors',
      () {
    expect(_derive('ColoredBox', {'color': 0xff123456}).builtInFloor, 5);
    expect(
      _gate(_derive('ColoredBox', {'color': 0xff123456}), builtIn: 5).accepted,
      isTrue,
    );
    for (final args in [
      <String, Object?>{'color': 0xff123456},
      {'weight': 'w400'},
      {'decoration': 'underline'},
      {
        'decoration': ['underline', 'overline'],
      }
    ]) {
      final required = _derive('ColorProbe', args);
      expect(required.builtInFloor, 1);
      expect(required.requiredLibraries.single.minGenerated, 1);
      expect(_gate(required, builtIn: 1, generated: 1).accepted, isTrue);
    }
    final nested = _derive('NativeProbe', {
      'style': {
        'color': 0xff123456,
        'fontWeight': 'w400',
        'decoration': ['underline'],
      },
    });
    expect(nested.builtInFloor, 1);
    expect(nested.requiredLibraries.single.minGenerated, 2);
    for (final args in <Map<String, Object?>>[
      {
        'gradient': {
          'type': 'linear',
          'colors': [0xff000000, 0xffffffff],
        },
      },
      {
        'paint': {
          'color': 0xff000000,
          'colorFilter': {'type': 'mode', 'color': 0xffffffff},
        },
      },
      {
        'shadows': [
          {'color': 0xff000000},
        ],
      },
      {
        'boxShadow': [
          {'color': 0xff000000},
        ],
      },
      {
        'border': [
          {'color': 0xff000000},
        ],
      },
      {
        'shape': {
          'type': 'rounded',
          'side': {'color': 0xff000000},
        },
      },
      {
        'span': {
          'children': [
            {
              'style': {
                'color': 0xff000000,
                'fontWeight': 'w400',
                'decoration': ['underline'],
              },
            }
          ],
        },
      },
      {
        'overlay': {
          'copyWith': [
            {'systemNavigationBarColor': 0xff000000},
          ],
        },
      },
      {
        'icon': {
          'lerp': {
            'a': {'color': 0xff000000},
            'b': {'color': 0xffffffff},
            't': .5,
          },
        },
      },
    ]) {
      final legacy = _derive('NativeProbe', args);
      expect(legacy.builtInFloor, 1, reason: '${args.keys}');
      expect(
        legacy.requiredLibraries.single.minGenerated,
        2,
        reason: '${args.keys}',
      );
    }
  });

  test('unrelated maps ignored fields and unused declarations do not upgrade',
      () {
    final data = _derive('ColorProbe', {'data': _color});
    expect(data.builtInFloor, 1);
    expect(data.requiredLibraries.single.minGenerated, 1);
    expect(_derive('ColorProbe', {}).builtInFloor, 1);
    expect(_derive('ColorProbe', {}).requiredLibraries.single.minGenerated, 1);
    for (final args in <Map<String, Object?>>[
      {
        'choice': {'_s': 'RawChoice', 'color': _color},
      },
      {
        'paint': {'metadata': _color},
      },
      {
        'style': {'metadata': _color},
      },
      {
        'style': {
          'copyWith': [
            {'color': _color},
          ],
        },
      },
      {
        'icon': {'fallback': true, 'color': _color},
      },
      {
        'icon': {
          'copyWith': [
            {
              'lerp': {
                'a': {'color': _color},
                'b': {'color': _color},
                't': .5,
              },
            }
          ],
        },
      },
      {
        'shape': {
          'type': 'box',
          'side': {'color': _color},
        },
      },
    ]) {
      expect(_derive('NativeProbe', args).builtInFloor, 1, reason: '$args');
    }
  });
}
