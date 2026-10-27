import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' show buildCoreWidgetLibrary;
import 'package:restage_svg/restage_svg.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';
import 'fixtures/exact_colors.dart' as native;

void main() {
  test('native color constructor arguments evaluate in source order', () {
    expect(() => native.argbDivisionFirst(0), throwsA(isA<UnsupportedError>()));
    expect(() => native.argbClampFirst(0), throwsArgumentError);
    expect(() => native.rgboDivisionFirst(0), throwsA(isA<UnsupportedError>()));
    expect(() => native.rgboClampFirst(0), throwsArgumentError);
  });
  testWidgets(
    'authored exact Color aliases and exponents match native SVG values',
    (tester) async {
      const surface = LibraryName(['exact', 'colors']);
      final runtime = Runtime()
        ..update(
          const LibraryName(['restage', 'core']),
          buildCoreWidgetLibrary(),
        )
        ..update(
          const LibraryName(['restage', 'svg']),
          buildCuratedWidgetLibrary(),
        )
        ..update(
          surface,
          parseLibraryFile(
            File('test/fixtures/exact_colors.rfwtxt').readAsStringSync(),
          ),
        );
      addTearDown(runtime.dispose);
      for (final (name, build) in <(String, Widget Function())>[
        ('materialShade', native.materialShade),
        ('materialDirect', native.materialDirect),
        ('materialAliasFixture', native.materialAliasFixture),
        ('materialPrefixed', native.materialPrefixed),
        ('materialImported', native.materialImported),
        ('materialNested', native.materialNested),
        ('accentBuilder', native.accentBuilder),
        ('baseBuilder', native.baseBuilder),
        ('nestedMaterialBuilder', native.nestedMaterialBuilder),
        ('subtypeRefused', native.subtypeRefused),
        ('direct', native.direct),
        ('local', native.local),
        ('imported', native.imported),
        ('prefixed', native.prefixed),
        ('nested', native.nested),
        ('builderDirect', native.builderDirect),
        ('builderAliases', native.builderAliases),
        ('fractional', native.fractional),
        ('argbDirect', native.argbDirect),
        ('argbAliases', native.argbAliases),
        ('argbMaskedDirect', native.argbMaskedDirect),
        ('argbMaskedAliases', native.argbMaskedAliases),
        ('builderArgbDirect', native.builderArgbDirect),
        ('builderArgbAliases', native.builderArgbAliases),
        ('builderArgbMaskedDirect', native.builderArgbMaskedDirect),
        ('builderArgbMaskedAliases', native.builderArgbMaskedAliases),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Expanded(child: build()),
                Expanded(
                  child: RemoteWidget(
                    runtime: runtime,
                    data: DynamicContent(),
                    widget: FullyQualifiedWidgetName(surface, name),
                  ),
                ),
              ],
            ),
          ),
        );
        final pictures = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .toList();
        expect(pictures, hasLength(2), reason: name);
        final expected =
            (pictures.first.bytesLoader as SvgStringLoader).theme!.currentColor;
        final actual =
            (pictures.last.bytesLoader as SvgStringLoader).theme!.currentColor;
        expect(actual.runtimeType, expected.runtimeType, reason: name);
        expect(actual == expected, isTrue, reason: name);
        expect(expected == actual, isTrue, reason: name);
        if (expected is MaterialColor || expected is MaterialAccentColor) {
          expect(actual, same(expected), reason: name);
          expect(actual.hashCode, expected.hashCode, reason: name);
          final swatch = actual as ColorSwatch<int>;
          final expectedSwatch = expected as ColorSwatch<int>;
          for (final shade in [
            50,
            100,
            200,
            300,
            400,
            500,
            600,
            700,
            800,
            900,
          ]) {
            expect(swatch[shade], same(expectedSwatch[shade]), reason: name);
          }
          expect(swatch[777], isNull, reason: name);
        }
        expect(
          [actual.a, actual.r, actual.g, actual.b, actual.colorSpace],
          [expected.a, expected.r, expected.g, expected.b, expected.colorSpace],
          reason: name,
        );
        expect(
          pictures.last.colorFilter,
          pictures.first.colorFilter,
          reason: name,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
