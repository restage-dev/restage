import 'dart:ui' show ColorSpace;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_svg/restage_svg.dart' as svg;
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/native_color_selectors.dart' as source;

class _CustomColor extends Color {
  const _CustomColor() : super(0xff123456);
  @override
  double get r => .123456789;
  @override
  ColorSpace get colorSpace => ColorSpace.displayP3;
}

typedef _Bindings =
    Map<String, NativeBinding<Object?>> Function({
      required bool flag,
      required Color color,
      required Color? maybeColor,
      required Color other,
    });

void main() {
  final cases =
      <
        (String, String, _Bindings, Widget Function(source.Probe, BuildContext))
      >[
        (
          'conditional',
          source.nativeSelectorDslconditional,
          source.nativeSelectorBindingsconditional,
          (probe, context) => probe.conditional(context),
        ),
        (
          'alias',
          source.nativeSelectorDslalias,
          source.nativeSelectorBindingsalias,
          (probe, context) => probe.alias(context),
        ),
        (
          'borrowedBoth',
          source.nativeSelectorDslborrowedBoth,
          source.nativeSelectorBindingsborrowedBoth,
          (probe, context) => probe.borrowedBoth(context),
        ),
        (
          'coalesce',
          source.nativeSelectorDslcoalesce,
          source.nativeSelectorBindingscoalesce,
          (probe, context) => probe.coalesce(context),
        ),
        (
          'nullable',
          source.nativeSelectorDslnullable,
          source.nativeSelectorBindingsnullable,
          (probe, context) => probe.nullable(context),
        ),
        (
          'nullableCoalesce',
          source.nativeSelectorDslnullableCoalesce,
          source.nativeSelectorBindingsnullableCoalesce,
          (probe, context) => probe.nullableCoalesce(context),
        ),
        (
          'nested',
          source.nativeSelectorDslnested,
          source.nativeSelectorBindingsnested,
          (probe, context) => probe.nested(context),
        ),
        (
          'layout',
          source.nativeSelectorDsllayout,
          source.nativeSelectorBindingslayout,
          (probe, context) => probe.layout(context),
        ),
        (
          'svgTheme',
          source.nativeSelectorDslsvgTheme,
          source.nativeSelectorBindingssvgTheme,
          (probe, context) => probe.svgTheme(context),
        ),
        (
          'svgFilter',
          source.nativeSelectorDslsvgFilter,
          source.nativeSelectorBindingssvgFilter,
          (probe, context) => probe.svgFilter(context),
        ),
        (
          'svgBoth',
          source.nativeSelectorDslsvgBoth,
          source.nativeSelectorBindingssvgBoth,
          (probe, context) => probe.svgBoth(context),
        ),
      ];

  for (final (name, dsl, bind, build) in cases) {
    testWidgets(
      '$name retains native selection and replaced constructor inputs',
      (tester) async {
        final map = <int, Color>{500: Colors.blue, 100: Colors.green};
        final material = MaterialColor(0xff123456, map);
        final accent = MaterialAccentColor(0xff123456, map);
        final replacementMap = <int, Color>{500: Colors.purple};
        final replacement = MaterialColor(0xff123456, replacementMap);
        const custom = _CustomColor();
        final inputs = <(bool, Color, Color?, Color)>[
          (true, material, null, accent),
          (false, custom, material, accent),
          (true, accent, custom, material),
          (false, replacement, null, custom),
          (true, replacement, material, accent),
        ];
        Map<String, NativeBinding<Object?>> bindings(
          (bool, Color, Color?, Color) input,
        ) => bind(
          flag: input.$1,
          color: input.$2,
          maybeColor: input.$3,
          other: input.$4,
        );
        const root = LibraryName(['selector']);
        final runtime = Runtime()
          ..update(
            const LibraryName(['restage', 'core']),
            buildCoreWidgetLibrary(),
          )
          ..update(
            const LibraryName(['restage', 'svg']),
            svg.buildCuratedWidgetLibrary(),
          )
          ..update(
            root,
            rfw.parseLibraryFile(
              'import restage.core; import restage.svg; widget Root = $dsl;',
            ),
          );
        final installed = bindings(inputs.first);
        // The same remote child survives every constructor-input replacement.
        final remote = RemoteWidget(
          runtime: runtime,
          data: DynamicContent({
            'context': {
              for (final entry in installed.entries)
                entry.key: entry.value.contract.reference(entry.key),
            },
          }),
          widget: const FullyQualifiedWidgetName(root, 'Root'),
        );
        for (final input in inputs) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RestageNativeValues(
                bindings: bindings(input),
                child: remote,
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final context = tester.element(find.byType(RemoteWidget));
          final probe = source.Probe(
            flag: input.$1,
            color: input.$2,
            maybeColor: input.$3,
            other: input.$4,
          );
          var expected = build(probe, context);
          if (expected is LayoutBuilder) {
            expected = expected.builder(context, const BoxConstraints());
          }
          Color? selected;
          Color? oracle;
          if (expected is SvgPicture) {
            final actual = tester.widget<SvgPicture>(find.byType(SvgPicture));
            final loader = actual.bytesLoader as SvgStringLoader;
            final nativeLoader = expected.bytesLoader as SvgStringLoader;
            selected = loader.theme?.currentColor;
            oracle = nativeLoader.theme?.currentColor;
            expect(actual.colorFilter, expected.colorFilter);
            expect(loader.theme, nativeLoader.theme);
            expect(loader.cacheKey(null), nativeLoader.cacheKey(null));
            expect(
              loader.cacheKey(null).hashCode,
              nativeLoader.cacheKey(null).hashCode,
            );
          } else if (expected is ColoredBox) {
            selected = tester.widget<ColoredBox>(find.byType(ColoredBox)).color;
            oracle = expected.color;
          } else if (expected is Container) {
            final actual = tester.widget<Container>(find.byType(Container));
            // The catalog's Container recipe carries color in BoxDecoration.
            selected = (actual.decoration! as BoxDecoration).color;
            oracle = expected.color;
          } else {
            fail('Unexpected native oracle ${expected.runtimeType}');
          }
          expect(selected, same(oracle));
          if (selected != null) {
            expect(selected.runtimeType, oracle.runtimeType);
            expect(
              [
                selected.a,
                selected.r,
                selected.g,
                selected.b,
                selected.colorSpace,
              ],
              [oracle!.a, oracle.r, oracle.g, oracle.b, oracle.colorSpace],
            );
            expect(selected.hashCode, oracle.hashCode);
            if (selected is ColorSwatch<int>) {
              map[500] = Colors.orange;
              replacementMap[500] = Colors.yellow;
              expect(selected[500], same((oracle as ColorSwatch<int>)[500]));
            }
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        runtime.dispose();
      },
    );
  }
}
