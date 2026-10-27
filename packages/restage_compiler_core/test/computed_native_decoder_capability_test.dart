import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.decoder');
const _value = rfw.ArgsReference(['scalar']);
const _iconSource =
    'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData';
const _overlaySource =
    'package:flutter/src/services/system_chrome.dart#SystemUiOverlayStyle';
final _program = {
  'version': 1,
  'program': const ValueProgram(
          nodes: [ValueNode('literal', ValueType.real, value: 0.5)], root: 0)
      .encode(),
  'captures': <String, Object?>{},
};
typedef _Route = ({
  String name,
  PropertyType type,
  String? source,
  bool svg,
  Object? value
});
_Route _route(String name, PropertyType type, Object? value,
        {String? source, bool svg = false}) =>
    (name: name, type: type, source: source, svg: svg, value: value);
_Route _opaque(String name, String source, Object? value, {bool svg = false}) =>
    _route(name, PropertyType.structured, value, source: source, svg: svg);
final _routes = [
  _route('gradient stops', PropertyType.gradient, {
    'type': 'linear',
    'stops': [_value]
  }),
  _route('gradient direction', PropertyType.gradient, {
    'type': 'linear',
    'begin': {'x': _value}
  }),
  _route('gradient radius', PropertyType.gradient,
      {'type': 'radial', 'radius': _value}),
  _route('gradient angle', PropertyType.gradient,
      {'type': 'sweep', 'startAngle': _value}),
  _route('gradient tile', PropertyType.gradient,
      {'type': 'linear', 'tileMode': _value}),
  _route('uniform shape radius', PropertyType.shapeBorder,
      {'type': 'rounded', 'borderRadius': _value}),
  _route('directional shape radius', PropertyType.shapeBorder, {
    'type': 'beveled',
    'borderRadius': {'topStart': _value}
  }),
  _route('circle eccentricity', PropertyType.shapeBorder,
      {'type': 'circle', 'eccentricity': _value}),
  _route('linear edge', PropertyType.shapeBorder, {
    'type': 'linear',
    'start': {'size': _value}
  }),
  _route('star rounding', PropertyType.shapeBorder,
      {'type': 'star', 'pointRounding': _value}),
  _route('polygon rotation', PropertyType.shapeBorder,
      {'type': 'polygon', 'rotation': _value}),
  _route('decoration image opacity', PropertyType.decorationImage, {
    'image': {'kind': 'asset', 'src': 'a'},
    'opacity': _value
  }),
  _route('image provider scale', PropertyType.decorationImage, {
    'image': {'kind': 'network', 'src': 'a', 'scale': _value}
  }),
  _route('paint matrix', PropertyType.paint, {
    'colorFilter': {
      'type': 'matrix',
      'matrix': [_value, ...List.filled(19, 0.0)]
    }
  }),
  _route('paint mask', PropertyType.paint, {
    'maskFilter': {'type': 'blur', 'sigma': _value}
  }),
  _route('paint shader', PropertyType.paint, {
    'shader': {
      'type': 'linear',
      'rect': {'w': _value}
    }
  }),
  _route('box spread', PropertyType.boxShadowList, [
    {'spreadRadius': _value}
  ]),
  _route('shadow offset', PropertyType.shadowList, [
    {
      'offset': {'x': _value}
    }
  ]),
  _route('border width', PropertyType.border, [
    {'width': _value}
  ]),
  _opaque('icon lerp',
      'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData', {
    kIconThemeDataLerpKey: {
      'a': <String, Object?>{},
      'b': <String, Object?>{},
      't': _value
    }
  }),
  _opaque('icon null selectors', _iconSource,
      {'lerp': null, 'fallback': null, 'size': _value}),
  _opaque('icon fallback', _iconSource, {'fallback': _value}),
  _opaque('icon copy fields', _iconSource, {
    'fallback': true,
    'copyWith': [
      {'fallback': true, 'size': _value}
    ]
  }),
  _opaque('overlay scalar', _overlaySource, {'statusBarBrightness': _value}),
  _opaque('overlay copy color', _overlaySource, {
    'copyWith': [
      {
        'systemNavigationBarColor': {'r': _value}
      }
    ]
  }),
  _opaque(
      'SVG filter',
      'dart:ui#ColorFilter',
      {
        'kind': 'matrix',
        'matrix': [_value, ...List.filled(19, 0.0)]
      },
      svg: true),
  _opaque(
      'SVG headers',
      'dart:core#Map',
      [
        {'key': 'accept', 'value': _value}
      ],
      svg: true),
  _opaque('SVG bytes', 'dart:typed_data#Uint8List', [_value], svg: true),
  _opaque(
      'SVG loader headers',
      'package:vector_graphics/src/loader.dart#BytesLoader',
      {
        'kind': 'SvgNetworkLoader',
        'value': 'a',
        'headers': [
          {'key': 'a', 'value': _value}
        ]
      },
      svg: true),
  _opaque(
      'SVG loader bytes',
      'package:vector_graphics/src/loader.dart#BytesLoader',
      {
        'kind': 'SvgBytesLoader',
        'value': [_value]
      },
      svg: true),
  _opaque('SVG theme', 'package:flutter_svg/src/loaders.dart#SvgTheme',
      {'fontSize': _value},
      svg: true),
  _opaque(
      'text scaler',
      'package:flutter/src/painting/text_scaler.dart#TextScaler',
      {'kind': 'linear', 'factor': _value}),
  _opaque(
      'cache extent',
      'package:flutter/src/rendering/viewport.dart#ScrollCacheExtent',
      {'_s': 'pixels', 'value': _value}),
  _opaque(
      'physics',
      'package:flutter/src/widgets/scroll_physics.dart#ScrollPhysics',
      {'_s': 'BouncingScrollPhysics', 'decelerationRate': _value}),
  _opaque('size', 'dart:ui#Size', {'width': _value}),
  _opaque('grid delegate',
      'package:flutter/src/rendering/sliver_grid.dart#SliverGridDelegate', {
    '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
    'crossAxisCount': _value
  }),
  _opaque(
      'child delegate',
      'package:flutter/src/widgets/scroll_delegate.dart#SliverChildDelegate',
      {'_s': 'SliverChildBuilderDelegate', 'childCount': _value}),
];
Catalog _catalog(_Route route) {
  final owner = route.svg
      ? const WidgetLibrary.custom('restage.svg')
      : WidgetLibrary.core;
  final ref = route.source == null
      ? null
      : WireIdRef(library: owner.namespace, wireId: WireId('s0001'));
  return Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        _custom: const LibraryInfo(version: '1', capabilityVersion: 1)
      },
      widgets: [
        WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'Probe',
            library: _custom,
            category: WidgetCategory.decoration,
            description: 'Probe',
            flutterType: 'package:example/probe.dart#Probe',
            childrenSlot: ChildrenSlot.none,
            properties: [
              PropertyEntry(
                  wireId: WireId.unallocatedProperty,
                  name: 'value',
                  type: route.type,
                  description: 'Native value',
                  structuredRef: ref)
            ])
      ],
      structuredTypes: [
        if (ref != null)
          StructuredEntry(
              wireId: ref.wireId,
              name: 'Native',
              library: owner,
              description: 'Native decoder route',
              sourceType: route.source!,
              fields: const [],
              variants: const [])
      ]);
}

Object? _replace(Object? value, Object? scalar) => switch (value) {
      rfw.ArgsReference() => scalar,
      Map() => {
          for (final entry in value.entries)
            entry.key: _replace(entry.value, scalar)
        },
      List() => [for (final item in value) _replace(item, scalar)],
      _ => value,
    };
SurfaceCapabilityDerivation _derive(_Route route,
    {int depth = 0, bool computed = true}) {
  final value = depth == 0
      ? _replace(route.value, computed ? _program : 0.5)
      : route.value;
  return deriveSurfaceCapability(
      rfw.RemoteWidgetLibrary(const [], [
        if (depth == 0)
          rfw.WidgetDeclaration(
              'Root', null, rfw.ConstructorCall('Probe', {'value': value}))
        else ...[
          rfw.WidgetDeclaration(
              'Root',
              null,
              rfw.ConstructorCall(
                  'Local0', {'scalar': computed ? _program : 0.5})),
          for (var i = 0; i < depth; i++)
            rfw.WidgetDeclaration(
                'Local$i',
                null,
                rfw.ConstructorCall(i + 1 == depth ? 'Probe' : 'Local${i + 1}',
                    i + 1 == depth ? {'value': value} : {'scalar': _value})),
        ]
      ]),
      _catalog(route));
}

bool _acceptsOldFactory(SurfaceCapabilityDerivation result) =>
    BlobRenderCapabilityGate.evaluate(
        required: CapabilityManifest(
            builtInFloor: result.builtInFloor,
            requiredLibraries: result.requiredLibraries),
        installed: InstalledCapability(
            builtInCatalogVersion: 23,
            installedLibraries: [
              InstalledLibrary(
                  namespace: _custom.namespace, version: 1, generated: 2)
            ])).accepted;
void main() {
  test('native shader direction reads retain the constructor argument scope',
      () {
    final route = _route('shader root direction', PropertyType.paint, {
      'shader': {'type': 'linear'}
    });
    final direction = {
      'version': 1,
      'program': const ValueProgram(
              nodes: [ValueNode('literal', ValueType.string, value: 'rtl')],
              root: 0)
          .encode(),
      'captures': <String, Object?>{},
    };
    for (final local in [false, true]) {
      final result = deriveSurfaceCapability(
          rfw.RemoteWidgetLibrary(const [], [
            if (local)
              rfw.WidgetDeclaration('Root', null,
                  rfw.ConstructorCall('Local', {'direction': direction})),
            rfw.WidgetDeclaration(
                local ? 'Local' : 'Root',
                null,
                rfw.ConstructorCall('Probe', {
                  'value': route.value,
                  'textDirection': local
                      ? const rfw.ArgsReference(['direction'])
                      : direction,
                }))
          ]),
          _catalog(route));
      expect(result.requiredLibraries.single.minGenerated, 3);
      expect(_acceptsOldFactory(result), isFalse);
    }
  });

  test(
      'installed native scalar reads require current factories through direct local and bounded paths',
      () {
    for (final route in _routes) {
      for (final depth in [0, 1, 70]) {
        final result = _derive(route, depth: depth);
        expect(result.requiredLibraries.single.minGenerated, 3,
            reason: '${route.name}, depth $depth');
        expect(_acceptsOldFactory(result), isFalse, reason: route.name);
      }
      for (final depth in [0, 1]) {
        final result = _derive(route, depth: depth, computed: false);
        expect(result.requiredLibraries.single.minGenerated, lessThan(3),
            reason: 'static ${route.name}');
        expect(_acceptsOldFactory(result), isTrue, reason: route.name);
      }
    }
  });
  test(
      'native decoders ignore unrelated fields and respect branch and owner boundaries',
      () {
    final ignored = [
      _route('gradient transform', PropertyType.gradient,
          {'type': 'linear', 'transform': _value}),
      _route('paint stroke', PropertyType.paint,
          {'strokeWidth': _value, 'invertColors': _value}),
      _route('box blur style', PropertyType.boxShadowList, [
        {'blurStyle': _value}
      ]),
      _route('border stroke alignment', PropertyType.border, [
        {'strokeAlign': _value}
      ]),
      _route('fifth border side', PropertyType.border, [
        <String, Object?>{},
        <String, Object?>{},
        <String, Object?>{},
        <String, Object?>{},
        {'width': _value}
      ]),
      _route(
          'inset kind', PropertyType.edgeInsets, {'kind': _value, 'top': 1.0}),
      _route(
          'fifth inset', PropertyType.edgeInsets, [1.0, 1.0, 1.0, 1.0, _value]),
      _route('locale map', PropertyType.locale, {'languageCode': _value}),
      _route('circle ignores corners', PropertyType.shapeBorder,
          {'type': 'circle', 'borderRadius': _value}),
      _route('span ignored label', PropertyType.inlineSpan,
          {'text': 'inert', 'semanticsLabel': _value}),
      _opaque('ordinary map', 'dart:core#Map', [
        {'key': 'a', 'value': _value}
      ]),
      _opaque('ordinary bytes', 'dart:typed_data#Uint8List', [_value]),
      _opaque('icon fallback ignores base', _iconSource,
          {'fallback': true, 'size': _value}),
      _opaque('icon lerp ignores base', _iconSource,
          {'lerp': <Object?>[], 'size': _value}),
      _opaque('icon copy ignores lerp', _iconSource, {
        'copyWith': [
          {
            'lerp': {'t': _value}
          }
        ]
      }),
      _opaque('icon ignores shadow fields', _iconSource, {
        'offset': {'x': _value},
        'strokeAlign': _value
      }),
      _opaque(
          'SVG wrong discriminator',
          'dart:ui#ColorFilter',
          {
            'type': 'matrix',
            'matrix': [_value, ...List.filled(19, 0.0)]
          },
          svg: true),
      _opaque(
          'SVG string ignores headers',
          'package:vector_graphics/src/loader.dart#BytesLoader',
          {
            'kind': 'SvgStringLoader',
            'value': 'a',
            'headers': [
              {'key': 'a', 'value': _value}
            ]
          },
          svg: true),
      _opaque(
          'clamping ignores deceleration',
          'package:flutter/src/widgets/scroll_physics.dart#ScrollPhysics',
          {'_s': 'ClampingScrollPhysics', 'decelerationRate': _value}),
    ];
    for (final route in ignored) {
      for (final depth in [0, 1]) {
        final result = _derive(route, depth: depth);
        expect(result.requiredLibraries.single.minGenerated, lessThan(3),
            reason: '${route.name}, depth $depth');
        expect(_acceptsOldFactory(result), isTrue, reason: route.name);
      }
    }
  });

  test('SVG native theme color retains its owner and loader boundaries', () {
    const themeSource = 'package:flutter_svg/src/loaders.dart#SvgTheme';
    const loaderSource = 'package:vector_graphics/src/loader.dart#BytesLoader';
    const theme = {
      'currentColor': {
        'a': 1.0,
        'r': .2,
        'g': .3,
        'b': .4,
        'colorSpace': 'displayP3'
      }
    };
    for (final svg in [false, true]) {
      final themeResult =
          _derive(_opaque('theme', themeSource, theme, svg: svg));
      expect(themeResult.builtInFloor, svg ? 19 : 1);
      for (final kind in ['SvgStringLoader', 'unknown']) {
        final loader = _derive(_opaque(
            'loader', loaderSource, {'kind': kind, 'theme': theme},
            svg: svg));
        expect(loader.builtInFloor, svg && kind == 'SvgStringLoader' ? 19 : 1);
      }
    }
  });
}
