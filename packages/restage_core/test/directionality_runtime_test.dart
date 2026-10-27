import 'dart:io';
import 'dart:ui' show ColorSpace;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'directionality']);

Widget _native(TextDirection direction) => Directionality(
      textDirection: direction,
      child: const Row(
        children: [
          Padding(padding: EdgeInsets.only(left: 7), child: Text('physical')),
          Padding(
            padding: EdgeInsetsDirectional.only(start: 11),
            child: Text('logical'),
          ),
        ],
      ),
    );

void main() {
  testWidgets(
      'compiled physical and logical geometry matches native across mounted direction changes',
      (tester) async {
    final compiled =
        File('test/fixtures/directionality.rfwtxt').readAsStringSync();
    final runtime = Runtime()..update(_core, buildCoreWidgetLibrary());
    final data = DynamicContent();
    addTearDown(runtime.dispose);
    final remote = RemoteWidget(
      runtime: runtime,
      data: data,
      widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
    );
    for (final direction in [
      TextDirection.rtl,
      TextDirection.ltr,
      TextDirection.rtl,
    ]) {
      runtime.update(
        _surface,
        parseLibraryFile(
          compiled.replaceAll('"rtl"', '"${direction.name}"'),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 300, child: _native(direction)),
                SizedBox(width: 300, child: remote),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final rows = find.byWidgetPredicate((widget) => widget is Row);
      expect(rows, findsNWidgets(2));
      for (final label in ['physical', 'logical']) {
        final texts = find.text(label);
        expect(texts, findsNWidgets(2));
        final native =
            tester.getRect(texts.at(0)).shift(-tester.getTopLeft(rows.at(0)));
        final delivered =
            tester.getRect(texts.at(1)).shift(-tester.getTopLeft(rows.at(1)));
        expect(delivered, native, reason: '$label under ${direction.name}');
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: texts.at(1), matching: find.byType(RichText)),
        );
        expect(paragraph.textDirection, direction);
        final padding = find
            .ancestor(
              of: texts.at(1),
              matching: find.byWidgetPredicate((widget) => widget is Padding),
            )
            .first;
        final offset =
            tester.getTopLeft(texts.at(1)).dx - tester.getTopLeft(padding).dx;
        expect(
          offset,
          label == 'physical'
              ? 7
              : direction == TextDirection.ltr
                  ? 11
                  : 0,
        );
      }
    }
  });

  testWidgets(
      'flat directional radius stays unresolved until Flutter reads direction',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
        _surface,
        parseLibraryFile('''
import restage.core;
widget Surface = ClipRRect(borderRadiusTopStart: 13.0, borderRadiusBottomEnd: 5.0, child: SizedBox(width: 40.0, height: 30.0));
'''),
      );
    addTearDown(runtime.dispose);
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: Center(
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
            ),
          ),
        ),
      );
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(
        clip.borderRadius,
        const BorderRadiusDirectional.only(
          topStart: Radius.circular(13),
          bottomEnd: Radius.circular(5),
        ),
      );
      expect(
        clip.borderRadius.resolve(direction),
        direction == TextDirection.ltr
            ? const BorderRadius.only(
                topLeft: Radius.circular(13),
                bottomRight: Radius.circular(5),
              )
            : const BorderRadius.only(
                topRight: Radius.circular(13),
                bottomLeft: Radius.circular(5),
              ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compiled nested radius aliases retain native geometry',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
        _surface,
        parseLibraryFile(
          File('test/fixtures/directional_radius_aliases.rfwtxt')
              .readAsStringSync(),
        ),
      );
    addTearDown(runtime.dispose);
    for (final widget in ['Container', 'AnimatedContainer']) {
      for (final directional in [false, true]) {
        final expected = directional
            ? const BorderRadiusDirectional.only(topStart: Radius.circular(13))
            : const BorderRadius.only(topLeft: Radius.circular(13));
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: FullyQualifiedWidgetName(
                  _surface,
                  '$widget${directional ? 'Logical' : 'Physical'}Alias',
                ),
              ),
            ),
          ),
        );
        final decoration = widget == 'AnimatedContainer'
            ? tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            : tester.widget<Container>(find.byType(Container)).decoration;
        final radius = (decoration! as BoxDecoration).borderRadius!;
        expect(radius, expected);
        for (final direction in TextDirection.values) {
          expect(radius.resolve(direction), expected.resolve(direction));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'compiled empty directional radii retain native required direction',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
        _surface,
        parseLibraryFile(
          File('test/fixtures/directional_radius_empty.rfwtxt')
              .readAsStringSync(),
        ),
      );
    addTearDown(runtime.dispose);
    const native = BorderRadiusDirectional.zero;
    expect(() => native.resolve(null), throwsAssertionError);
    for (final constructor in ['only', 'vertical', 'horizontal', 'zero']) {
      for (final nested in [false, true]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: FullyQualifiedWidgetName(
                  _surface,
                  '${nested ? 'Nested' : 'Direct'}$constructor',
                ),
              ),
            ),
          ),
        );
        final radius = nested
            ? (tester.widget<Container>(find.byType(Container)).decoration!
                    as BoxDecoration)
                .borderRadius!
            : tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius;
        expect(radius, isA<BorderRadiusDirectional>());
        expect(radius, native);
        expect(() => radius.resolve(null), throwsAssertionError);
        for (final direction in TextDirection.values) {
          expect(radius.resolve(direction), native.resolve(direction));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  test(
      'legacy inset lists retain start/end meaning and explicit maps retain subtype',
      () {
    final source = _Values({
      'legacy': [7.0, 2.0, 11.0, 3.0],
      'physical': {'left': 7, 'top': 2, 'right': 11, 'bottom': 3},
      'logical': {'start': 7, 'top': 2, 'end': 11, 'bottom': 3},
    });
    expect(
      RestageDecoders.edgeInsets(source, ['legacy']),
      const EdgeInsetsDirectional.fromSTEB(7, 2, 11, 3),
    );
    expect(
      RestageDecoders.physicalEdgeInsets(source, ['physical']),
      const EdgeInsets.fromLTRB(7, 2, 11, 3),
    );
    expect(
      RestageDecoders.directionalEdgeInsets(source, ['logical']),
      const EdgeInsetsDirectional.fromSTEB(7, 2, 11, 3),
    );
    expect(RestageDecoders.physicalEdgeInsets(source, ['logical']), isNull);
    expect(RestageDecoders.directionalEdgeInsets(source, ['physical']), isNull);
  });

  test('directional gradients retain exact native color components', () {
    const exact = Color.from(
      alpha: 0.812345,
      red: 0.234567,
      green: 0.345678,
      blue: 0.456789,
      colorSpace: ColorSpace.displayP3,
    );
    final source = _Values({
      'gradient': {
        'type': 'linear',
        'begin': {'start': -0.7, 'y': 0.2},
        'end': {'start': 0.8, 'y': -0.1},
        'colors': [
          {
            'a': exact.a,
            'r': exact.r,
            'g': exact.g,
            'b': exact.b,
            'colorSpace': exact.colorSpace.name,
          },
          0xFFFFFFFF,
        ],
        'stops': [0.125, 0.875],
        'tileMode': 'mirror',
      },
    });
    final decoded = RestageDecoders.gradient(source, ['gradient']);
    const native = LinearGradient(
      begin: AlignmentDirectional(-0.7, 0.2),
      end: AlignmentDirectional(0.8, -0.1),
      colors: [exact, Color(0xFFFFFFFF)],
      stops: [0.125, 0.875],
      tileMode: TileMode.mirror,
    );
    expect(decoded, native);
    for (final direction in TextDirection.values) {
      expect(
        (decoded! as LinearGradient).begin.resolve(direction),
        native.begin.resolve(direction),
      );
    }
  });

  test('nested shapes, gradients and images preserve directional geometry', () {
    final source = _Values({
      'shape': {
        'type': 'rounded',
        'borderRadius': {'topStart': 13.0, 'bottomEnd': 5.0},
      },
      'gradient': {
        'type': 'linear',
        'begin': {'start': -1.0, 'y': 0.0},
        'end': {'start': 1.0, 'y': 0.0},
        'colors': [0xFF000000, 0xFFFFFFFF],
      },
      'image': {
        'image': {'kind': 'asset', 'src': 'image.png'},
        'alignment': {'start': 1.0, 'y': 0.0},
      },
    });
    final shape = RestageDecoders.shapeBorder(source, ['shape'])!
        as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadiusDirectional.only(
        topStart: Radius.circular(13),
        bottomEnd: Radius.circular(5),
      ),
    );
    final gradient =
        RestageDecoders.gradient(source, ['gradient'])! as LinearGradient;
    expect(gradient.begin, AlignmentDirectional.centerStart);
    expect(gradient.end, AlignmentDirectional.centerEnd);
    for (final direction in TextDirection.values) {
      final path = shape.getOuterPath(
        const Rect.fromLTWH(0, 0, 40, 30),
        textDirection: direction,
      );
      expect(path.contains(const Offset(1, 1)), direction == TextDirection.rtl);
      expect(
        shape
            .getOuterPath(
              const Rect.fromLTWH(0, 0, 40, 30),
              textDirection: direction,
            )
            .getBounds(),
        const Rect.fromLTWH(0, 0, 40, 30),
      );
      expect(
        gradient.createShader(
          const Rect.fromLTWH(0, 0, 40, 30),
          textDirection: direction,
        ),
        isNotNull,
      );
    }
    expect(
      RestageDecoders.decorationImage(source, ['image'])!.alignment,
      AlignmentDirectional.centerEnd,
    );
  });
  testWidgets('icon direction reaches installed and delivered glyphs',
      (tester) async {
    addTearDown(InstalledIconTable.reset);
    InstalledIconTable.reset();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DeliveredIconFonts(
          fonts: const {
            'custom': LoadedIconFont(loadedFamily: 'loaded', codePoints: {42}),
          },
          child: Builder(
            builder: (context) {
              final glyph = restageIcon(
                context,
                codePoint: 42,
                fontFamily: 'custom',
                textDirection: TextDirection.rtl,
              ) as RestageDeliveredIcon;
              expect(glyph.textDirection, TextDirection.rtl);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    InstalledIconTable.add(
      RestageIconTable.fromFamilies(
        families: const {
          'custom': {42: IconData(42, fontFamily: 'custom')},
        },
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            final icon = restageIcon(
              context,
              codePoint: 42,
              fontFamily: 'custom',
              textDirection: TextDirection.rtl,
            ) as Icon;
            expect(icon.textDirection, TextDirection.rtl);
            return const SizedBox();
          },
        ),
      ),
    );
  });
}

class _Values implements DataSource {
  _Values(this.values);
  final Map<String, Object?> values;
  Object? _at(List<Object> path) {
    Object? value = values;
    for (final key in path) {
      value = value is Map
          ? value[key]
          : value is List && key is int && key < value.length
              ? value[key]
              : null;
    }
    return value;
  }

  @override
  T? v<T extends Object>(List<Object> path) {
    final value = _at(path);
    return value is T ? value : null;
  }

  @override
  bool isMap(List<Object> path) => _at(path) is Map;
  @override
  bool isList(List<Object> path) => _at(path) is List;
  @override
  int length(List<Object> path) {
    final value = _at(path);
    return value is List ? value.length : 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
