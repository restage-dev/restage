import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

import 'native_color_constants.dart' as palette;

part 'native_color_constructors.g.dart';

const Color? absentColor = null;

const localPalette = MaterialColor(0xff102030, {500: Color(0xff102030)});

class ColorConstructorSource extends StatelessWidget {
  const ColorConstructorSource({required this.swatch, super.key});
  final Map<int, Color> swatch;
  static const staticPalette =
      MaterialAccentColor(0xff102030, {100: Color(0xff102030)});

  @override
  Widget build(BuildContext context) => fresh(context);

  Widget fresh(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final color = MaterialColor(0xff102030, swatch);
        return ColoredBox(color: color);
      });

  Widget accent(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final color = MaterialAccentColor(0xff102030, swatch);
        return ColoredBox(color: color);
      });

  Widget constant(BuildContext context) => const ColoredBox(
      color: MaterialColor(0xff102030, {500: Color(0xff102030)}));

  Widget baseConstant(BuildContext context) => const ColoredBox(
      color: Color.from(alpha: 1, red: .123456789, green: .3, blue: .4));

  Widget alias(BuildContext context) => const ColoredBox(color: localPalette);

  Widget imported(BuildContext context) =>
      const ColoredBox(color: palette.importedColor);

  Widget importedStatic(BuildContext context) =>
      const ColoredBox(color: palette.Palette.color);

  // Deliberately redundant wrappers exercise the exact source boundary.
  Widget wrappedConst(BuildContext context) =>
      // ignore: dead_code
      ColoredBox(color: true ? (palette.importedColor as Color) : localPalette);

  Widget staticAlias(BuildContext context) =>
      const ColoredBox(color: ColorConstructorSource.staticPalette);

  Widget localAlias(BuildContext context) {
    const color = MaterialColor(0xff102030, {500: Color(0xff102030)});
    return const ColoredBox(color: color);
  }

  Widget layout(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final color = MaterialColor(0xff102030, swatch);
        return Row(
            children: [ColoredBox(color: color), ColoredBox(color: color)]);
      });
  Widget nullable(BuildContext context) => Container(color: absentColor);

  Widget nullableLayout(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => Container(color: absentColor));
}
