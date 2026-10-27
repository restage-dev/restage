import 'dart:ui';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_svg/flutter_svg.dart';

const tinyColor = Color.from(
  alpha: .75,
  red: 1e-7,
  green: .4,
  blue: .8,
  colorSpace: ColorSpace.displayP3,
);
const hugeColor = Color.from(
  alpha: 1,
  red: 1e21,
  green: .4,
  blue: .6,
  colorSpace: ColorSpace.extendedSRGB,
);
const hugeTheme = SvgTheme(currentColor: hugeColor);
const hugeFilter = ColorFilter.mode(hugeColor, BlendMode.srcIn);

const fractionalOpacity = Color.fromRGBO(1, 2, 3, .1);

const argbColor = Color.fromARGB(127, 12, 34, 56);
const maskedArgbColor = Color.fromARGB(-1, 256, 257, -258);
const overflowArgbColor = Color.fromARGB(511, -1, 512, 258);

const Color importedMaterialColor = Colors.indigo;
const importedMaterialTheme = SvgTheme(currentColor: importedMaterialColor);
