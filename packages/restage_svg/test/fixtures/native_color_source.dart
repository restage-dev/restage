import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'native_color_source.g.dart';

const nativeColorSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
    '<path d="M0 0h8v8H0z" fill="currentColor"/></svg>';

class Probe extends StatelessWidget {
  const Probe({required this.color, required this.swatch, super.key});
  final Map<int, Color> swatch;
  final Color color;

  @override
  Widget build(BuildContext context) => theme(context);

  Widget theme(BuildContext context) =>
      SvgPicture.string(nativeColorSvg, theme: SvgTheme(currentColor: color));

  Widget filter(BuildContext context) => SvgPicture.string(
    nativeColorSvg,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );

  Widget layout(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SvgPicture.string(
      nativeColorSvg,
      theme: SvgTheme(currentColor: color),
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
  Widget wrapped(BuildContext context) => SvgPicture.string(
    nativeColorSvg,
    // Deliberately redundant wrappers exercise the exact source boundary.
    // ignore: unnecessary_cast, dead_code
    theme: SvgTheme(currentColor: true ? (color as Color) : Colors.red),
    // ignore: unnecessary_cast
    colorFilter: ColorFilter.mode(color as Color, BlendMode.srcIn),
  );

  Widget local(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final Color tint = MaterialColor(0xff123456, swatch);
      return SvgPicture.string(
        nativeColorSvg,
        theme: SvgTheme(currentColor: tint),
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      );
    },
  );
}
