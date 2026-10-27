import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_core/src/runtime/builder_context.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _displayP3 = Color.from(
  alpha: 0.812345,
  red: 0.234567,
  green: 0.345678,
  blue: 0.456789,
  colorSpace: ColorSpace.displayP3,
);
const _extended = Color.from(
  alpha: 0.923456,
  red: -0.125,
  green: 1.375,
  blue: 0.567891,
  colorSpace: ColorSpace.extendedSRGB,
);
const _srgb = Color.from(
  alpha: 0.765432,
  red: 0.123456,
  green: 0.654321,
  blue: 0.987654,
);

void main() {
  testWidgets('native context styles retain exact colors weights and masks',
      (tester) async {
    final decoration = TextDecoration.combine([
      TextDecoration.underline,
      TextDecoration.overline,
      TextDecoration.lineThrough,
    ]);
    final nativeStyle = TextStyle(
      color: _displayP3,
      backgroundColor: _extended,
      decorationColor: _srgb,
      fontWeight: const FontWeight(550),
      decoration: decoration,
    );
    final defaultStyle = nativeStyle.copyWith(
      color: _extended,
      fontWeight: const FontWeight(1000),
      decoration: TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.overline,
      ]),
    );
    final theme = ThemeData.light().copyWith(
      colorScheme: ThemeData.light().colorScheme.copyWith(primary: _displayP3),
      iconTheme: const IconThemeData(color: _extended),
      textTheme: TextTheme(bodyMedium: nativeStyle),
    );
    TextStyle? decodedStyle;
    TextStyle? decodedDefault;
    Color? decodedScheme;
    IconThemeData? decodedIcon;
    await _pumpDecode(
      tester,
      theme: theme,
      defaultStyle: defaultStyle,
      values: (context) => {
        'style': _projectStyle(context, 'textTheme.bodyMedium'),
        'default': _projectStyle(context, 'defaultTextStyle'),
        'scheme':
            readBuilderContext(context, 'context:theme:colorScheme.primary'),
        'icon': {
          'color': readBuilderContext(context, 'context:theme:iconTheme.color'),
        },
      },
      decode: (source) {
        decodedStyle = RestageDecoders.textStyle(source, ['values', 'style']);
        decodedDefault =
            RestageDecoders.textStyle(source, ['values', 'default']);
        decodedScheme = RestageDecoders.color(source, ['values', 'scheme']);
        decodedIcon = RestageDecoders.iconThemeData(source, ['values', 'icon']);
        return Text('native style', style: decodedStyle);
      },
    );
    expect(decodedStyle, nativeStyle);
    expect(decodedDefault, defaultStyle);
    expect(decodedScheme, _displayP3);
    expect(decodedIcon?.color, _extended);
    expect(tester.widget<Text>(find.text('native style')).style, nativeStyle);
  });

  testWidgets('common native decoders preserve exact color records',
      (tester) async {
    final data = _color(_extended);
    final colors = <Color?>[];
    await _pumpDecode(
      tester,
      values: (_) => {
        'color': data,
        'style': {
          'color': data,
          'backgroundColor': data,
          'decorationColor': data,
        },
        'icon': {'color': data},
        'shadows': [
          {'color': data}
        ],
        'border': {'color': data},
        'overlay': {
          'statusBarColor': data,
          'systemNavigationBarColor': data,
          'systemNavigationBarDividerColor': data,
        },
      },
      decode: (source) {
        final style = RestageDecoders.textStyle(source, ['values', 'style'])!;
        final overlay = RestageDecoders.systemUiOverlayStyle(
            source, ['values', 'overlay'])!;
        colors.addAll([
          RestageDecoders.color(source, ['values', 'color']),
          style.color,
          style.backgroundColor,
          style.decorationColor,
          RestageDecoders.iconThemeData(source, ['values', 'icon'])?.color,
          RestageDecoders.shadows(source, ['values', 'shadows'])?.single.color,
          RestageDecoders.borderSide(source, ['values', 'border'])?.color,
          overlay.statusBarColor,
          overlay.systemNavigationBarColor,
          overlay.systemNavigationBarDividerColor,
        ]);
        return const SizedBox();
      },
    );
    expect(colors, hasLength(10));
    expect(colors, everyElement(_extended));
  });

  test('exact decoders retain all weights masks and legacy inputs', () {
    for (var weight = 1; weight <= 1000; weight++) {
      expect(
          RestageDecoders.fontWeight(_Values(weight), []), FontWeight(weight));
    }
    for (var mask = 0; mask <= 7; mask++) {
      expect(
          RestageDecoders.textDecoration(_Values(mask), [])?.maskValue, mask);
    }
    for (final color in [_srgb, _extended, _displayP3]) {
      expect(RestageDecoders.color(_Values(_color(color)), []), color);
    }
    expect(RestageDecoders.color(const _Values(0xFF123456), []),
        const Color(0xFF123456));
    expect(
        RestageDecoders.fontWeight(const _Values('w700'), []), FontWeight.w700);
    expect(RestageDecoders.textDecoration(const _Values('underline'), []),
        TextDecoration.underline);
    expect(
        RestageDecoders.textDecoration(
            const _Values(['underline', 'overline']), [])?.maskValue,
        3);
    expect(
        RestageDecoders.textDecoration(const _Values([3, 'lineThrough']), [])
            ?.maskValue,
        7);
    expect(RestageDecoders.color(const _Values(null), []), isNull);
    expect(RestageDecoders.fontWeight(const _Values(null), []), isNull);
    expect(RestageDecoders.textDecoration(const _Values(null), []), isNull);
  });

  testWidgets('paint and mode filters retain native color semantics',
      (tester) async {
    const filter = ColorFilter.mode(_displayP3, BlendMode.srcIn);
    final native = Paint()
      ..color = _extended
      ..colorFilter = filter
      ..isAntiAlias = false
      ..blendMode = BlendMode.multiply;
    final wire = {
      'color': _color(_extended),
      'colorFilter': {
        'type': 'mode',
        'color': _color(_displayP3),
        'blendMode': 'srcIn',
      },
      'isAntiAlias': false,
      'blendMode': 'multiply',
    };
    final paints = <Paint?>[];
    ColorFilter? decodedFilter;
    await _pumpDecode(
      tester,
      values: (_) => {
        'paint': wire,
        'style': {'foreground': wire, 'background': wire},
      },
      decode: (source) {
        final style = RestageDecoders.textStyle(source, ['values', 'style'])!;
        paints.addAll([
          RestageDecoders.paint(source, ['values', 'paint']),
          style.foreground,
          style.background,
        ]);
        decodedFilter = RestageDecoders.colorFilter(
            source, ['values', 'paint', 'colorFilter']);
        return const SizedBox();
      },
    );
    expect(decodedFilter, filter);
    expect(paints, hasLength(3));
    for (final paint in paints) {
      expect(paint?.color, native.color);
      expect(paint?.colorFilter, native.colorFilter);
      expect(paint?.blendMode, native.blendMode);
      expect(paint?.isAntiAlias, native.isAntiAlias);
    }
    expect(RestageDecoders.paint(const _Values(null), []), isNull);
    expect(
        RestageDecoders.colorFilter(
            const _Values({'type': 'srgbToLinearGamma'}), []),
        const ColorFilter.srgbToLinearGamma());
  });

  test('malformed exact representations fail without defaults', () {
    for (final record in [
      {..._color(_displayP3)}..remove('a'),
      {..._color(_displayP3), 'r': 'invalid'},
      {..._color(_displayP3), 'colorSpace': 'unknown'},
    ]) {
      expect(() => RestageDecoders.color(_Values(record), []),
          throwsFormatException);
    }
    for (final weight in [0, 1001]) {
      expect(() => RestageDecoders.fontWeight(_Values(weight), []),
          throwsFormatException);
    }
    for (final mask in [-1, 8]) {
      expect(() => RestageDecoders.textDecoration(_Values(mask), []),
          throwsFormatException);
    }
  });

  testWidgets('gradients and box shadows retain exact colors and native fields',
      (tester) async {
    const colors = [_displayP3, _extended];
    const stops = [0.125, 0.875];
    final common = {
      'colors': [for (final color in colors) _color(color)],
      'stops': stops,
      'tileMode': 'mirror',
    };
    final gradients = <Gradient?>[];
    BoxShadow? shadow;
    await _pumpDecode(
      tester,
      values: (_) => {
        'linear': {
          ...common,
          'type': 'linear',
          'begin': {'x': -0.3, 'y': 0.4},
          'end': {'x': 0.8, 'y': -0.7},
        },
        'radial': {
          ...common,
          'type': 'radial',
          'center': {'x': 0.1, 'y': -0.2},
          'radius': 0.9,
          'focal': {'x': 0.2, 'y': 0.3},
          'focalRadius': 0.1,
        },
        'sweep': {
          ...common,
          'type': 'sweep',
          'center': {'x': 0.4, 'y': 0.5},
          'startAngle': 0.3,
          'endAngle': 2.7,
        },
        'shadow': {
          'color': _color(_displayP3),
          'offset': {'x': 3.0, 'y': 4.0},
          'blurRadius': 2.5,
          'spreadRadius': -0.5,
        },
      },
      decode: (source) {
        for (final type in ['linear', 'radial', 'sweep']) {
          gradients.add(RestageDecoders.gradient(source, ['values', type]));
        }
        shadow = RestageDecoders.boxShadow(source, ['values', 'shadow']);
        return const SizedBox();
      },
    );
    expect(gradients, const [
      LinearGradient(
        begin: Alignment(-0.3, 0.4),
        end: Alignment(0.8, -0.7),
        colors: colors,
        stops: stops,
        tileMode: TileMode.mirror,
      ),
      RadialGradient(
        center: Alignment(0.1, -0.2),
        radius: 0.9,
        focal: Alignment(0.2, 0.3),
        focalRadius: 0.1,
        colors: colors,
        stops: stops,
        tileMode: TileMode.mirror,
      ),
      SweepGradient(
        center: Alignment(0.4, 0.5),
        startAngle: 0.3,
        endAngle: 2.7,
        colors: colors,
        stops: stops,
        tileMode: TileMode.mirror,
      ),
    ]);
    expect(
        shadow,
        const BoxShadow(
          color: _displayP3,
          offset: Offset(3, 4),
          blurRadius: 2.5,
          spreadRadius: -0.5,
        ));
    for (final type in ['linear', 'radial', 'sweep']) {
      final source = _Values({
        'type': type,
        'colors': [0xFF123456, 0xFF654321]
      });
      expect(RestageDecoders.gradient(source, []),
          ArgumentDecoders.gradient(source, []));
    }
    expect(RestageDecoders.gradient(const _Values(null), []), isNull);
    expect(
        RestageDecoders.boxShadow(const _Values(null), []), const BoxShadow());
  });

  testWidgets('text theme presence distinguishes an absent style from a leaf',
      (tester) async {
    final observations = <Object?>[];
    for (final style in [
      null,
      const TextStyle(),
      const TextStyle(fontSize: 17)
    ]) {
      await tester.pumpWidget(Theme(
        data: ThemeData.light().copyWith(
          textTheme: TextTheme(bodyMedium: style),
          typography: Typography(
            englishLike: const TextTheme(),
            dense: const TextTheme(),
            tall: const TextTheme(),
          ),
        ),
        child: Builder(builder: (context) {
          expect(Theme.of(context).textTheme.bodyMedium, style);
          observations.add(readBuilderContext(
              context, r'context:theme:textTheme.bodyMedium.$present'));
          observations.add(readBuilderContext(
              context, 'context:theme:textTheme.bodyMedium.fontSize'));
          return const SizedBox();
        }),
      ));
      expect(tester.takeException(), isNull);
    }
    expect(observations, [false, null, true, null, true, 17.0]);
  });
}

Map<String, Object?> _projectStyle(BuildContext context, String path) => {
      for (final field in [
        'color',
        'backgroundColor',
        'decorationColor',
        'fontWeight',
        'decoration',
      ])
        field: readBuilderContext(context, 'context:theme:$path.$field'),
    };

Map<String, Object?> _color(Color color) => {
      'a': color.a,
      'r': color.r,
      'g': color.g,
      'b': color.b,
      'colorSpace': color.colorSpace.name,
    };

Future<void> _pumpDecode(
  WidgetTester tester, {
  required Map<String, Object?> Function(BuildContext) values,
  required Widget Function(DataSource) decode,
  ThemeData? theme,
  TextStyle defaultStyle = const TextStyle(),
}) async {
  const local = LibraryName(['local']);
  const remote = LibraryName(['test']);
  final runtime = Runtime()
    ..update(
        local,
        LocalWidgetLibrary({
          'Probe': (_, source) => decode(source),
        }))
    ..update(remote, rfw.parseLibraryFile('''
import local;
widget Root = Probe(values: data.values);
'''));
  addTearDown(runtime.dispose);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Theme(
      data: theme ?? ThemeData.light(),
      child: DefaultTextStyle(
        style: defaultStyle,
        child: Builder(builder: (context) {
          return RemoteWidget(
            runtime: runtime,
            widget: const FullyQualifiedWidgetName(remote, 'Root'),
            data: DynamicContent({'values': values(context)}),
          );
        }),
      ),
    ),
  ));
  expect(tester.takeException(), isNull);
}

final class _Values implements DataSource {
  const _Values(this.root);
  final Object? root;

  Object? _read(List<Object> path) {
    Object? value = root;
    for (final part in path) {
      value = switch ((value, part)) {
        (Map<String, Object?> map, String key) => map[key],
        (List<Object?> list, int index)
            when index >= 0 && index < list.length =>
          list[index],
        _ => null,
      };
    }
    return value;
  }

  @override
  T? v<T extends Object>(List<Object> path) {
    final value = _read(path);
    return value is T ? value : null;
  }

  @override
  bool isMap(List<Object> path) => _read(path) is Map<String, Object?>;

  @override
  bool isList(List<Object> path) => _read(path) is List<Object?>;

  @override
  int length(List<Object> path) {
    final value = _read(path);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
