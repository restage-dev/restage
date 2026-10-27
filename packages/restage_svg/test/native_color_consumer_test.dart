import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_svg/restage_svg.dart' as restage_svg;
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/native_color_source.dart' as native;

const _color = NativeBindingContract(type: 'flutter.Color');
const _root = LibraryName(['test']);
const _xml =
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
    '<path d="M0 0h8v8H0z" fill="currentColor"/></svg>';

class _CustomColor extends Color {
  const _CustomColor() : super(0xff123456);
  @override
  ColorSpace get colorSpace => ColorSpace.displayP3;
}

void main() {
  testWidgets(
    'authored callback swatches preserve SVG color and cache behavior',
    (tester) async {
      final swatch = <int, Color>{500: Colors.red};
      final installed = native.nativeSvgColorBindings(swatch);
      final runtime = Runtime()
        ..update(
          const LibraryName(['restage', 'core']),
          buildCoreWidgetLibrary(),
        )
        ..update(
          const LibraryName(['restage', 'svg']),
          restage_svg.buildCuratedWidgetLibrary(),
        )
        ..update(
          _root,
          rfw.parseLibraryFile(
            'import restage.core; import restage.svg; widget Root = ${native.nativeSvgColorDsl};',
          ),
        );
      addTearDown(runtime.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
            bindings: installed,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent({
                'context': {
                  for (final entry in installed.entries)
                    entry.key: entry.value.contract.reference(entry.key),
                },
              }),
              widget: const FullyQualifiedWidgetName(_root, 'Root'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(RemoteWidget));
      final builder =
          native.Probe(color: Colors.black, swatch: swatch).local(context)
              as LayoutBuilder;
      final expected =
          builder.builder(context, const BoxConstraints()) as SvgPicture;
      final actual = tester.widget<SvgPicture>(find.byType(SvgPicture));
      final loader = actual.bytesLoader as SvgStringLoader;
      final expectedLoader = expected.bytesLoader as SvgStringLoader;
      final color = loader.theme!.currentColor as MaterialColor;
      final expectedColor = expectedLoader.theme!.currentColor as MaterialColor;
      expect(identical(color, expectedColor), isFalse);
      expect(color, expectedColor);
      expect(color.hashCode, expectedColor.hashCode);
      expect(actual.colorFilter, expected.colorFilter);
      expect(actual.colorFilter, ColorFilter.mode(color, BlendMode.srcIn));
      expect(loader.cacheKey(null), expectedLoader.cacheKey(null));
      swatch[500] = Colors.blue;
      expect(color[500], same(Colors.blue));
      expect(expectedColor[500], same(Colors.blue));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authored SVG colors preserve native theme filter and cache keys',
    (tester) async {
      final fixtures =
          jsonDecode(
                File(
                  'test/fixtures/native_color_sources.json',
                ).readAsStringSync(),
              )
              as Map;
      final map = <int, Color>{500: Colors.red};
      final shared = MaterialColor(0xff123456, map);
      final distinct = MaterialColor(0xff123456, map);
      expect(identical(shared, distinct), isFalse);
      for (final entry in fixtures.entries) {
        final fixture = entry.value as Map;
        final runtime = Runtime()
          ..update(
            const LibraryName(['restage', 'core']),
            buildCoreWidgetLibrary(),
          )
          ..update(
            const LibraryName(['restage', 'svg']),
            restage_svg.buildCuratedWidgetLibrary(),
          )
          ..update(
            _root,
            rfw.parseLibraryFile(
              'import restage.core; import restage.svg; '
              'widget Root = ${fixture['dsl']};',
            ),
          );
        for (final color in [
          const _CustomColor(),
          shared,
          distinct,
          MaterialAccentColor(0xff123456, map),
          Colors.blue,
        ]) {
          final withTheme = entry.key != 'filter';
          final withFilter = entry.key != 'theme';
          final native = SvgPicture.string(
            _xml,
            theme: withTheme ? SvgTheme(currentColor: color) : null,
            colorFilter: withFilter
                ? ColorFilter.mode(color, BlendMode.srcIn)
                : null,
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RestageNativeValues(
                bindings: {
                  'color': NativeBinding(contract: _color, value: color),
                },
                child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent({
                    'context': {
                      fixture['key'] as String: _color.reference('color'),
                    },
                  }),
                  widget: const FullyQualifiedWidgetName(_root, 'Root'),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final actual = tester.widget<SvgPicture>(find.byType(SvgPicture));
          final actualLoader = actual.bytesLoader as SvgStringLoader;
          final nativeLoader = native.bytesLoader as SvgStringLoader;
          if (withTheme) {
            expect(actualLoader.theme!.currentColor, same(color));
            expect(
              actualLoader.theme!.currentColor.runtimeType,
              color.runtimeType,
            );
          }
          expect(
            actual.colorFilter,
            native.colorFilter,
            reason: entry.key as String,
          );
          expect(
            actualLoader.theme,
            nativeLoader.theme,
            reason: 'theme ${entry.key}',
          );
          expect(
            actualLoader.cacheKey(null),
            nativeLoader.cacheKey(null),
            reason: 'cache ${entry.key}',
          );
          expect(
            actualLoader.cacheKey(null).hashCode,
            nativeLoader.cacheKey(null).hashCode,
          );
          if (withTheme && color is ColorSwatch<int>) {
            map[500] = Colors.green;
            expect(
              (actualLoader.theme!.currentColor as ColorSwatch<int>)[500],
              same(color[500]),
            );
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
        runtime.dispose();
      }
    },
  );
}
