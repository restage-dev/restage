import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'native_color_selectors.g.dart';

const selectorSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
    '<path d="M0 0h8v8H0z" fill="currentColor"/></svg>';

class Probe extends StatelessWidget {
  const Probe({
    required this.flag,
    required this.color,
    required this.maybeColor,
    required this.other,
    super.key,
  });

  final bool flag;
  final Color color;
  final Color? maybeColor;
  final Color other;

  @override
  Widget build(BuildContext context) => conditional(context);

  Widget conditional(BuildContext context) =>
      ColoredBox(color: flag ? color : Colors.red);
  Widget alias(BuildContext context) {
    final selected = flag ? color : Colors.red;
    return ColoredBox(color: selected);
  }

  Widget borrowedBoth(BuildContext context) =>
      ColoredBox(color: flag ? color : other);
  Widget coalesce(BuildContext context) =>
      ColoredBox(color: maybeColor ?? color);
  Widget nullable(BuildContext context) =>
      Container(color: flag ? maybeColor : null);
  Widget nullableCoalesce(BuildContext context) =>
      Container(color: maybeColor ?? (flag ? color : null));
  Widget nested(BuildContext context) =>
      ColoredBox(color: !flag || maybeColor == null ? Colors.red : color);
  Widget layout(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        ColoredBox(color: flag ? color : Colors.red),
  );
  Widget svgTheme(BuildContext context) => SvgPicture.string(
    selectorSvg,
    theme: SvgTheme(currentColor: maybeColor ?? color),
  );
  Widget svgFilter(BuildContext context) => SvgPicture.string(
    selectorSvg,
    colorFilter: ColorFilter.mode(flag ? color : Colors.red, BlendMode.srcIn),
  );
  Widget svgBoth(BuildContext context) => SvgPicture.string(
    selectorSvg,
    theme: SvgTheme(currentColor: maybeColor ?? color),
    colorFilter: ColorFilter.mode(flag ? color : Colors.red, BlendMode.srcIn),
  );
}
